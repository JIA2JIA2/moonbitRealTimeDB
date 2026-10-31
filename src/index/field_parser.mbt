// 字段路径解析器模块
//
// 实现嵌套字段路径的解析与值提取能力
// 支持格式：`user.profile.age`, `items[0].name`

///|
/// 字段路径段
pub(all) enum PathSegment {
  /// 键访问（如 `user`）
  Key(String)
  /// 索引访问（如 `[0]`）
  Index(Int32)
}

///|
pub impl Eq for PathSegment with fn equal(self, other) -> Bool {
  match (self, other) {
    (Key(a), Key(b)) => a == b
    (Index(a), Index(b)) => a == b
    _ => false
  }
}

///|
pub extend PathSegment with Eq::{equal, not_equal}

///|
pub impl Debug for PathSegment with fn to_repr(self) -> Repr {
  match self {
    Key(k) => Repr::ctor("Key", [(None, Repr(k))])
    Index(i) => Repr::ctor("Index", [(None, Repr(i))])
  }
}

///|
pub extend PathSegment with Debug::{to_repr}

///|
/// 字段路径解析器
pub struct FieldParser {
  /// 路径解析缓存：原始路径 -> 解析后的段数组
  mut cache : Map[String, Array[PathSegment]]
  /// 缓存最大容量
  max_cache_size : Int32
  /// 累计查询次数（含命中与未命中）
  mut total_lookups : Int32
  /// 缓存命中次数
  mut cache_hits : Int32
}

///|
/// 默认缓存大小
pub const DEFAULT_CACHE_SIZE : Int32 = 1000

///|
/// 创建字段路径解析器
pub fn FieldParser::new() -> FieldParser {
  {
    cache: Map([]),
    max_cache_size: DEFAULT_CACHE_SIZE,
    total_lookups: 0,
    cache_hits: 0,
  }
}

///|
/// 创建指定缓存大小的字段路径解析器
pub fn FieldParser::with_cache_size(max_size : Int32) -> FieldParser {
  { cache: Map([]), max_cache_size: max_size, total_lookups: 0, cache_hits: 0, }
}

///|
/// 解析非负整数字符串，非法输入返回 None
fn parse_non_negative_int(s : String) -> Int32? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut value = 0
  for ch in chars {
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
/// 解析字段路径为段数组
/// 支持格式：`user.profile.age`, `items[0].name`, `data.users[1].score`
pub fn FieldParser::parse_path(
  self : FieldParser,
  path : String,
) -> Result[Array[PathSegment], String] {
  self.total_lookups = self.total_lookups + 1
  // 检查缓存
  match self.cache.get(path) {
    Some(segments) => {
      self.cache_hits = self.cache_hits + 1
      return Ok(segments)
    }
    None => ()
  }

  let segments : Array[PathSegment] = []
  let chars = path.to_array()
  let mut i = 0
  let n = chars.length()

  while i < n {
    let ch = chars[i]
    if ch == '.' {
      i = i + 1
      continue
    }

    if ch == '[' {
      // 解析索引访问 [0], [123]
      i = i + 1
      let start = i
      while i < n && chars[i] != ']' {
        i = i + 1
      }
      if i >= n {
        return Err("Unclosed bracket in path: " + path)
      }
      let index_str = path[start:i].to_owned()
      match parse_non_negative_int(index_str) {
        Some(idx) => {
          segments.push(PathSegment::Index(idx))
          i = i + 1 // 跳过 ']'
        }
        None => return Err("Invalid index in path: " + index_str)
      }
    } else {
      // 解析键访问
      let start = i
      while i < n && chars[i] != '.' && chars[i] != '[' {
        i = i + 1
      }
      let key = path[start:i].to_owned()
      if key.length() > 0 {
        segments.push(PathSegment::Key(key))
      }
    }
  }

  // 更新缓存
  if self.cache.length() < self.max_cache_size {
    self.cache.set(path, segments)
  }

  Ok(segments)
}

///|
/// 从 Value 中提取指定路径的字段值
pub fn FieldParser::extract_value(
  self : FieldParser,
  value : @realtime_db.Value,
  path : String,
) -> @realtime_db.Value? {
  match self.parse_path(path) {
    Ok(segments) => self.extract_by_segments(value, segments)
    Err(_) => None
  }
}

///|
/// 从 Value 中按段提取字段值（内部方法）
fn FieldParser::extract_by_segments(
  self : FieldParser,
  value : @realtime_db.Value,
  segments : Array[PathSegment],
) -> @realtime_db.Value? {
  let _ = self
  let mut current = value
  for seg in segments {
    match seg {
      PathSegment::Key(k) =>
        match current {
          @realtime_db.Map(m) =>
            match m.get(k) {
              Some(v) => current = v
              None => return None
            }
          _ => return None
        }
      PathSegment::Index(idx) =>
        match current {
          @realtime_db.Arr(arr) =>
            if idx >= 0 && idx < arr.length() {
              current = arr[idx]
            } else {
              return None
            }
          _ => return None
        }
    }
  }
  Some(current)
}

///|
/// 批量提取多个字段路径的值（用于复合索引）
pub fn FieldParser::extract_fields(
  self : FieldParser,
  value : @realtime_db.Value,
  paths : Array[String],
) -> Array[@realtime_db.Value?] {
  let results : Array[@realtime_db.Value?] = []
  for path in paths {
    results.push(self.extract_value(value, path))
  }
  results
}

///|
/// 清空缓存
pub fn FieldParser::clear_cache(self : FieldParser) -> Unit {
  self.cache = Map([])
  self.total_lookups = 0
  self.cache_hits = 0
}

///|
/// 获取缓存命中率（命中次数 / 总解析次数）
pub fn FieldParser::cache_hit_rate(self : FieldParser) -> Double {
  if self.total_lookups == 0 {
    0.0
  } else {
    self.cache_hits.to_double() / self.total_lookups.to_double()
  }
}
