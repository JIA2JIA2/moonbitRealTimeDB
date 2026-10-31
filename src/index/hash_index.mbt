// Hash 索引模块
//
// 提供等值查询 O(1) 的索引实现
// 使用 Map[Value, Array[String]] 存储值到键集合的映射

///|
/// Hash 索引结构体
pub(all) struct HashIndex {
  /// 索引名称
  name : String
  /// 索引桶：值的规范化编码 -> 键集合
  mut buckets : Map[String, Array[String]]
  /// 键到值的映射（用于快速删除）
  mut key_to_value : Map[String, @realtime_db.Value]
  /// 条目总数（按数据键计数）
  mut total_entries : Int32
  /// 内存占用估算
  mut memory_bytes : Int32
}

///|
/// 创建 Hash 索引
pub fn HashIndex::new(name : String) -> HashIndex {
  {
    name,
    buckets: Map([]),
    key_to_value: Map([]),
    total_entries: 0,
    memory_bytes: 0,
  }
}

///|
/// 插入索引条目。
/// 同一数据键重复插入时先移除旧映射，条目数不重复计数。
pub fn HashIndex::insert(
  self : HashIndex,
  value : @realtime_db.Value,
  key : String,
) -> Bool {
  // 检查是否已存在该键
  let is_new_key = match self.key_to_value.get(key) {
    Some(old_value) => {
      // 值未变化，幂等插入，直接失败
      if old_value == value {
        return false
      }
      // 值发生变化，先删除旧的映射
      self.remove_from_bucket(old_value, key)
      false
    }
    None => true
  }

  // 添加到桶中
  self.add_to_bucket(value, key)
  // 更新键到值的映射
  self.key_to_value.set(key, value)
  if is_new_key {
    self.total_entries = self.total_entries + 1
    self.update_memory_estimate(true)
  }
  true
}

///|
/// 删除索引条目
pub fn HashIndex::delete(
  self : HashIndex,
  _value : @realtime_db.Value,
  key : String,
) -> Bool {
  // 检查键是否存在
  match self.key_to_value.get(key) {
    Some(old_value) => {
      // 从桶中移除
      self.remove_from_bucket(old_value, key)
      // 移除键到值的映射
      self.key_to_value.remove(key)
      self.total_entries = self.total_entries - 1
      self.update_memory_estimate(false)
      true
    }
    None => false
  }
}

///|
/// 等值查询
pub fn HashIndex::query(
  self : HashIndex,
  value : @realtime_db.Value,
) -> Array[String] {
  match self.buckets.get(value_key(value)) {
    Some(keys) => keys.copy()
    None => []
  }
}

///|
/// 范围查询（Hash 索引不支持，返回空数组）
pub fn HashIndex::range_query(
  self : HashIndex,
  _start : @realtime_db.Value?,
  _end : @realtime_db.Value?,
  _include_start : Bool?,
  _include_end : Bool?,
) -> Array[String] {
  let _ = self
  []
}

///|
/// 前缀查询（Hash 索引不支持，返回空数组）
pub fn HashIndex::prefix_query(
  self : HashIndex,
  _prefix : String,
) -> Array[String] {
  let _ = self
  []
}

///|
/// 获取索引内存占用
pub fn HashIndex::memory_usage(self : HashIndex) -> Int32 {
  self.memory_bytes
}

///|
/// 获取索引条目数
pub fn HashIndex::size(self : HashIndex) -> Int32 {
  self.total_entries
}

///|
/// 清空索引
pub fn HashIndex::clear(self : HashIndex) -> Unit {
  self.buckets = Map([])
  self.key_to_value = Map([])
  self.total_entries = 0
  self.memory_bytes = 0
}

///|
/// 获取索引类型
pub fn HashIndex::index_type(self : HashIndex) -> IndexType {
  let _ = self
  Hash
}

///|
/// 添加到桶中（内部方法）
fn HashIndex::add_to_bucket(
  self : HashIndex,
  value : @realtime_db.Value,
  key : String,
) -> Unit {
  let code = value_key(value)
  match self.buckets.get(code) {
    Some(keys) => if !array_contains(keys, key) { keys.push(key) }
    None => self.buckets.set(code, [key])
  }
}

///|
/// 从桶中移除（内部方法）
fn HashIndex::remove_from_bucket(
  self : HashIndex,
  value : @realtime_db.Value,
  key : String,
) -> Unit {
  let code = value_key(value)
  match self.buckets.get(code) {
    Some(keys) => {
      let new_keys : Array[String] = []
      for k in keys {
        if k != key {
          new_keys.push(k)
        }
      }
      if new_keys.length() == 0 {
        self.buckets.remove(code)
      } else {
        self.buckets.set(code, new_keys)
      }
    }
    None => ()
  }
}

///|
/// 更新内存估算（内部方法）
fn HashIndex::update_memory_estimate(self : HashIndex, is_add : Bool) -> Unit {
  // 估算每个条目的内存占用：
  // - key 字符串：平均 32 字节
  // - value 值：平均 16 字节
  // - Map 开销：平均 8 字节
  let entry_size = 56
  if is_add {
    self.memory_bytes = self.memory_bytes + entry_size
  } else {
    self.memory_bytes = self.memory_bytes - entry_size
  }
}

///|
/// 批量操作
pub fn HashIndex::batch_update(
  self : HashIndex,
  inserts : Array[(@realtime_db.Value, String)],
  deletes : Array[(@realtime_db.Value, String)],
) -> BatchUpdateResult {
  let mut inserted = 0
  let mut deleted = 0
  let mut failed = 0

  // 处理删除
  for (value, key) in deletes {
    if self.delete(value, key) {
      deleted = deleted + 1
    } else {
      failed = failed + 1
    }
  }

  // 处理插入
  for (value, key) in inserts {
    if self.insert(value, key) {
      inserted = inserted + 1
    } else {
      failed = failed + 1
    }
  }

  { inserted, deleted, failed, }
}

///|
/// 获取所有键（用于测试和调试）
pub fn HashIndex::keys(self : HashIndex) -> Array[String] {
  let all_keys : Array[String] = []
  for _, keys in self.buckets {
    for k in keys {
      all_keys.push(k)
    }
  }
  all_keys
}

///|
/// 获取所有值（用于测试和调试）
pub fn HashIndex::values(self : HashIndex) -> Array[@realtime_db.Value] {
  let all_values : Array[@realtime_db.Value] = []
  for _, v in self.key_to_value {
    if !array_contains(all_values, v) {
      all_values.push(v)
    }
  }
  all_values
}

///|
/// 获取桶数量（用于统计）
pub fn HashIndex::bucket_count(self : HashIndex) -> Int32 {
  self.buckets.length()
}

///|
/// 获取平均桶深度（用于性能分析）
pub fn HashIndex::avg_bucket_depth(self : HashIndex) -> Double {
  let bucket_count = self.buckets.length()
  if bucket_count == 0 {
    0.0
  } else {
    self.total_entries.to_double() / bucket_count.to_double()
  }
}
