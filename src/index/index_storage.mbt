// 索引存储接口模块
//
// MoonBit 不支持 trait object，因此使用枚举分发（IndexStorageHandle）
// 统一承载 Hash/BTree/Fulltext/Composite 四种索引存储。

///|
/// 索引存储句柄：所有具体索引引擎的枚举分发。
pub(all) enum IndexStorageHandle {
  /// Hash 索引
  Hash(HashIndex)
  /// B+树索引
  BTree(BTreeIndex)
  /// 前缀树索引
  Fulltext(FulltextIndex)
  /// 复合索引
  Composite(CompositeIndex)
}

///|
/// 插入索引条目
pub fn IndexStorageHandle::insert(
  self : IndexStorageHandle,
  value : @realtime_db.Value,
  key : String,
) -> Bool {
  match self {
    Hash(h) => h.insert(value, key)
    BTree(h) => h.insert(value, key)
    Fulltext(h) => h.insert(value, key)
    Composite(h) => h.insert(value, key)
  }
}

///|
/// 删除索引条目
pub fn IndexStorageHandle::delete(
  self : IndexStorageHandle,
  value : @realtime_db.Value,
  key : String,
) -> Bool {
  match self {
    Hash(h) => h.delete(value, key)
    BTree(h) => h.delete(value, key)
    Fulltext(h) => h.delete(value, key)
    Composite(h) => h.delete(value, key)
  }
}

///|
/// 等值查询
pub fn IndexStorageHandle::query(
  self : IndexStorageHandle,
  value : @realtime_db.Value,
) -> Array[String] {
  match self {
    Hash(h) => h.query(value)
    BTree(h) => h.query(value)
    Fulltext(h) => h.query(value)
    Composite(h) => h.query(value)
  }
}

///|
/// 范围查询。include_start/include_end 为 None 时按 true（含边界）处理。
pub fn IndexStorageHandle::range_query(
  self : IndexStorageHandle,
  start : @realtime_db.Value?,
  end : @realtime_db.Value?,
  include_start : Bool?,
  include_end : Bool?,
) -> Array[String] {
  let inc_s = match include_start {
    Some(b) => b
    None => true
  }
  let inc_e = match include_end {
    Some(b) => b
    None => true
  }
  match self {
    Hash(h) => h.range_query(start, end, Some(inc_s), Some(inc_e))
    BTree(h) => h.range_query(start, end, Some(inc_s), Some(inc_e))
    Fulltext(h) => h.range_query(start, end, Some(inc_s), Some(inc_e))
    Composite(h) => h.range_query(start, end, Some(inc_s), Some(inc_e))
  }
}

///|
/// 前缀查询
pub fn IndexStorageHandle::prefix_query(
  self : IndexStorageHandle,
  prefix : String,
) -> Array[String] {
  match self {
    Hash(h) => h.prefix_query(prefix)
    BTree(h) => h.prefix_query(prefix)
    Fulltext(h) => h.prefix_query(prefix)
    Composite(h) => h.prefix_query(prefix)
  }
}

///|
/// 获取索引内存占用
pub fn IndexStorageHandle::memory_usage(self : IndexStorageHandle) -> Int {
  match self {
    Hash(h) => h.memory_usage()
    BTree(h) => h.memory_usage()
    Fulltext(h) => h.memory_usage()
    Composite(h) => h.memory_usage()
  }
}

///|
/// 获取索引条目数
pub fn IndexStorageHandle::size(self : IndexStorageHandle) -> Int {
  match self {
    Hash(h) => h.size()
    BTree(h) => h.size()
    Fulltext(h) => h.size()
    Composite(h) => h.size()
  }
}

///|
/// 清空索引
pub fn IndexStorageHandle::clear(self : IndexStorageHandle) -> Unit {
  match self {
    Hash(h) => h.clear()
    BTree(h) => h.clear()
    Fulltext(h) => h.clear()
    Composite(h) => h.clear()
  }
}

///|
/// 获取索引类型
pub fn IndexStorageHandle::index_type(self : IndexStorageHandle) -> IndexType {
  match self {
    Hash(h) => h.index_type()
    BTree(h) => h.index_type()
    Fulltext(h) => h.index_type()
    Composite(h) => h.index_type()
  }
}

///|
/// 批量更新索引
pub fn IndexStorageHandle::batch_update(
  self : IndexStorageHandle,
  inserts : Array[(@realtime_db.Value, String)],
  deletes : Array[(@realtime_db.Value, String)],
) -> BatchUpdateResult {
  match self {
    Hash(h) => h.batch_update(inserts, deletes)
    BTree(h) => h.batch_update(inserts, deletes)
    Fulltext(h) => h.batch_update(inserts, deletes)
    Composite(h) => h.batch_update(inserts, deletes)
  }
}

///|
/// 批量索引更新结果
pub(all) struct BatchUpdateResult {
  /// 成功插入数
  inserted : Int
  /// 成功删除数
  deleted : Int
  /// 失败数
  failed : Int
}

///|
/// 值比较辅助函数：-1/0/1
fn compare_values(a : @realtime_db.Value, b : @realtime_db.Value) -> Int {
  match (a, b) {
    (@realtime_db.Int(ai), @realtime_db.Int(bi)) =>
      if ai < bi {
        -1
      } else if ai > bi {
        1
      } else {
        0
      }
    (@realtime_db.Float(af), @realtime_db.Float(bf)) =>
      if af < bf {
        -1
      } else if af > bf {
        1
      } else {
        0
      }
    (@realtime_db.Str(as_), @realtime_db.Str(bs_)) =>
      if as_ < bs_ {
        -1
      } else if as_ > bs_ {
        1
      } else {
        0
      }
    (@realtime_db.Bool(ab), @realtime_db.Bool(bb)) =>
      if ab == bb {
        0
      } else if ab {
        1
      } else {
        -1
      }
    _ => 0
  }
}

///|
/// 将 Value 编码为带类型前缀的唯一字符串键。
/// Value 未实现 Hash，无法直接作为 Map 键，用类型前缀消除
/// 不同变体之间的歧义（如 Int(1) 与 Str("1")）。
fn value_key(v : @realtime_db.Value) -> String {
  match v {
    @realtime_db.Str(s) => "s:" + s
    @realtime_db.Int(i) => "i:" + i.to_string()
    @realtime_db.Float(f) => "f:" + f.to_string()
    @realtime_db.Bool(b) => if b { "b:1" } else { "b:0" }
    @realtime_db.Null => "n"
    @realtime_db.Arr(_) => "a:" + v.to_string()
    @realtime_db.Map(_) => "m:" + v.to_string()
  }
}

///|
/// 数组区间复制（Array 无内建 subarray）
fn[T] subarray(arr : Array[T], start : Int, end : Int) -> Array[T] {
  let lo = if start < 0 {
    0
  } else if start > arr.length() {
    arr.length()
  } else {
    start
  }
  let hi = if end < lo {
    lo
  } else if end > arr.length() {
    arr.length()
  } else {
    end
  }
  let out : Array[T] = []
  let mut i = lo
  while i < hi {
    out.push(arr[i])
    i = i + 1
  }
  out
}

///|
/// 数组是否包含某元素
fn[T : Eq] array_contains(arr : Array[T], item : T) -> Bool {
  for x in arr {
    if x == item {
      return true
    }
  }
  false
}
