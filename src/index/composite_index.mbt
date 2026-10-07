// 复合索引模块
//
// 实现多字段复合索引，支持最左前缀匹配
// 例如索引 (a, b, c) 支持查询 a、a AND b、a AND b AND c
//
// 插入的值必须是 Arr（按字段顺序排列的值数组），
// 每个字段对应一个子索引（IndexStorageHandle）。

///|
/// 复合索引条目
pub(all) struct CompositeEntry {
  /// 值数组（按字段顺序）
  values : Array[@realtime_db.Value]
  /// 键
  key : String
}

///|
/// 复合索引结构体
pub(all) struct CompositeIndex {
  /// 索引名称
  name : String
  /// 字段路径数组
  field_paths : Array[String]
  /// 子索引数组（每个字段一个索引）
  /// 第一个索引是主索引，后续是辅助索引
  mut sub_indices : Array[IndexStorageHandle]
  /// 键到值的映射
  mut key_to_values : Map[String, Array[@realtime_db.Value]]
  /// 条目总数（按数据键计数）
  mut total_entries : Int
  /// 内存占用估算
  mut memory_bytes : Int
}

///|
/// 创建复合索引
pub fn CompositeIndex::new(
  name : String,
  field_paths : Array[String],
) -> CompositeIndex {
  {
    name,
    field_paths,
    sub_indices: [],
    key_to_values: Map([]),
    total_entries: 0,
    memory_bytes: 0,
  }
}

///|
/// 设置子索引（在创建后调用）
pub fn CompositeIndex::set_sub_indices(
  self : CompositeIndex,
  indices : Array[IndexStorageHandle],
) -> Unit {
  self.sub_indices = indices
}

///|
/// 插入索引条目。
/// value 必须是 Arr，长度与字段数一致。
/// 同一数据键重复插入时先移除旧值，条目数不重复计数。
pub fn CompositeIndex::insert(
  self : CompositeIndex,
  value : @realtime_db.Value,
  key : String,
) -> Bool {
  match value {
    @realtime_db.Arr(values) => {
      // 键已存在时先删除旧条目
      let is_new_key = match self.key_to_values.get(key) {
        Some(old_values) => {
          self.remove_from_sub_indices(old_values, key)
          false
        }
        None => true
      }

      // 插入每个子索引
      let mut i = 0
      while i < values.length() {
        if i < self.sub_indices.length() {
          let _ = self.sub_indices[i].insert(values[i], key)
        }
        i = i + 1
      }
      // 更新键到值的映射
      self.key_to_values.set(key, values)
      if is_new_key {
        self.total_entries = self.total_entries + 1
      }
      self.update_memory_estimate(is_new_key)
      true
    }
    _ => false
  }
}

///|
/// 从所有子索引中移除一个旧条目
fn CompositeIndex::remove_from_sub_indices(
  self : CompositeIndex,
  values : Array[@realtime_db.Value],
  key : String,
) -> Unit {
  let mut i = 0
  while i < values.length() {
    if i < self.sub_indices.length() {
      let _ = self.sub_indices[i].delete(values[i], key)
    }
    i = i + 1
  }
}

///|
/// 删除索引条目
pub fn CompositeIndex::delete(
  self : CompositeIndex,
  _value : @realtime_db.Value,
  key : String,
) -> Bool {
  match self.key_to_values.get(key) {
    Some(values) => {
      self.remove_from_sub_indices(values, key)
      self.key_to_values.remove(key)
      self.total_entries = self.total_entries - 1
      self.update_memory_estimate(false)
      true
    }
    None => false
  }
}

///|
/// 等值查询：使用第一个子索引
pub fn CompositeIndex::query(
  self : CompositeIndex,
  value : @realtime_db.Value,
) -> Array[String] {
  if self.sub_indices.length() > 0 {
    self.sub_indices[0].query(value)
  } else {
    []
  }
}

///|
/// 范围查询：使用第一个子索引
pub fn CompositeIndex::range_query(
  self : CompositeIndex,
  start : @realtime_db.Value?,
  end : @realtime_db.Value?,
  include_start : Bool?,
  include_end : Bool?,
) -> Array[String] {
  if self.sub_indices.length() > 0 {
    self.sub_indices[0].range_query(start, end, include_start, include_end)
  } else {
    []
  }
}

///|
/// 前缀查询：使用第一个子索引
pub fn CompositeIndex::prefix_query(
  self : CompositeIndex,
  prefix : String,
) -> Array[String] {
  if self.sub_indices.length() > 0 {
    self.sub_indices[0].prefix_query(prefix)
  } else {
    []
  }
}

///|
pub fn CompositeIndex::memory_usage(self : CompositeIndex) -> Int {
  self.memory_bytes
}

///|
pub fn CompositeIndex::size(self : CompositeIndex) -> Int {
  self.total_entries
}

///|
pub fn CompositeIndex::clear(self : CompositeIndex) -> Unit {
  for idx in self.sub_indices {
    idx.clear()
  }
  self.key_to_values = Map([])
  self.total_entries = 0
  self.memory_bytes = 0
}

///|
pub fn CompositeIndex::index_type(self : CompositeIndex) -> IndexType {
  let _ = self
  IndexType::Composite
}

///|
/// 复合查询（支持最左前缀匹配）
///
/// - conditions: 查询条件数组，按字段顺序，None 表示该字段不参与
/// - limit: 可选，返回结果数量上限
pub fn CompositeIndex::composite_query(
  self : CompositeIndex,
  conditions : Array[@realtime_db.Value?],
  limit : Int?,
) -> Array[String] {
  if conditions.length() == 0 {
    return []
  }

  // 找到第一个 None 条件的位置
  let mut used_fields = 0
  for cond in conditions {
    if cond is None {
      break
    }
    used_fields = used_fields + 1
  }

  if used_fields == 0 || self.sub_indices.length() == 0 {
    return []
  }

  // 使用第一个子索引进行初始查询
  let first_value = match conditions[0] {
    Some(v) => v
    None => return []
  }
  let mut result = self.sub_indices[0].query(first_value)

  // 与后续字段的结果取交集
  let mut i = 1
  while i < used_fields && i < self.sub_indices.length() {
    match conditions[i] {
      Some(v) => {
        let next_keys = self.sub_indices[i].query(v)
        result = intersect_arrays(result, next_keys)
      }
      None => ()
    }
    i = i + 1
  }

  // 应用 limit
  match limit {
    Some(l) => if result.length() > l { result = subarray(result, 0, l) }
    None => ()
  }

  result
}

///|
/// 计算两个数组的交集（保持 a 的顺序与去重语义）
fn intersect_arrays(a : Array[String], b : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for item in a {
    if array_contains(b, item) && !array_contains(result, item) {
      result.push(item)
    }
  }
  result
}

///|
/// 检查是否支持最左前缀匹配
pub fn CompositeIndex::supports_prefix_match(
  self : CompositeIndex,
  field_count : Int,
) -> Bool {
  field_count > 0 && field_count <= self.sub_indices.length()
}

///|
/// 获取字段数量
pub fn CompositeIndex::field_count(self : CompositeIndex) -> Int {
  self.field_paths.length()
}

///|
/// 获取字段路径
pub fn CompositeIndex::get_field_paths(self : CompositeIndex) -> Array[String] {
  self.field_paths
}

///|
/// 更新内存估算（内部方法）
fn CompositeIndex::update_memory_estimate(
  self : CompositeIndex,
  is_add : Bool,
) -> Unit {
  let entry_size = 120
  if is_add {
    self.memory_bytes = self.memory_bytes + entry_size
  } else {
    self.memory_bytes = self.memory_bytes - entry_size
  }
}

///|
/// 批量操作
pub fn CompositeIndex::batch_update(
  self : CompositeIndex,
  inserts : Array[(@realtime_db.Value, String)],
  deletes : Array[(@realtime_db.Value, String)],
) -> BatchUpdateResult {
  let mut inserted = 0
  let mut deleted = 0
  let mut failed = 0

  for (value, key) in deletes {
    if self.delete(value, key) {
      deleted = deleted + 1
    } else {
      failed = failed + 1
    }
  }
  for (value, key) in inserts {
    if self.insert(value, key) {
      inserted = inserted + 1
    } else {
      failed = failed + 1
    }
  }

  { inserted, deleted, failed, }
}
