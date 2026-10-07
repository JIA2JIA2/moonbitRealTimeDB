// 查询引擎模块
//
// 实现索引查询执行与结果合并
// 支持等值查询、范围查询、前缀匹配、复合查询

///|
/// 查询结果
pub(all) struct QueryResult {
  /// 匹配的键数组
  keys : Array[String]
  /// 查询耗时（微秒）
  latency_us : Int
  /// 是否命中缓存
  hit_cache : Bool
  /// 使用的索引名称
  index_used : String
}

///|
/// 查询引擎结构体
pub struct QueryEngine {
  /// 数据库引用
  mut db : @realtime_db.DB?
  /// 索引管理器引用
  mut manager : IndexManager?
  /// 索引选择器引用
  mut selector : IndexSelector?
  /// 查询超时时间（微秒）
  mut timeout_us : Int
  /// 是否启用缓存
  mut enable_cache : Bool
  /// 查询缓存
  mut cache : Map[String, QueryResult]
  /// 缓存查询总次数
  mut cache_lookups : Int
  /// 缓存命中次数
  mut cache_hits : Int
}

///|
/// 默认查询超时时间（1 秒 = 1,000,000 微秒）
pub const DEFAULT_QUERY_TIMEOUT_US : Int = 1_000_000

///|
/// 默认查询缓存大小
pub const DEFAULT_QUERY_CACHE_SIZE : Int = 1000

///|
/// 创建查询引擎
pub fn QueryEngine::new() -> QueryEngine {
  {
    db: None,
    manager: None,
    selector: None,
    timeout_us: DEFAULT_QUERY_TIMEOUT_US,
    enable_cache: true,
    cache: Map([]),
    cache_lookups: 0,
    cache_hits: 0,
  }
}

///|
pub fn QueryEngine::set_db(self : QueryEngine, db : @realtime_db.DB?) -> Unit {
  self.db = db
}

///|
pub fn QueryEngine::set_manager(
  self : QueryEngine,
  manager : IndexManager?,
) -> Unit {
  self.manager = manager
}

///|
pub fn QueryEngine::set_selector(
  self : QueryEngine,
  selector : IndexSelector?,
) -> Unit {
  self.selector = selector
}

///|
/// 等值查询
pub fn QueryEngine::index_query(
  self : QueryEngine,
  index_name : String?,
  field_path : String,
  value : @realtime_db.Value,
  limit : Int?,
  offset : Int?,
) -> Result[QueryResult, QueryError] {
  let start_time = self.get_time_us()

  let manager = match self.manager {
    Some(m) => m
    None => return Err(Internal_Error("Index manager not set"))
  }

  // 自动选择索引
  let chosen = match index_name {
    Some(name) => name
    None => {
      let conditions = [{ field_path, value: Some(value), query_type: Equal, }]
      match self.selector {
        Some(selector) =>
          match selector.select_index(conditions) {
            Some(name) => name
            None => return Err(Internal_Error("No suitable index found"))
          }
        None => return Err(Internal_Error("Index selector not set"))
      }
    }
  }

  // 先查缓存
  let cache_key = chosen +
    "|" +
    field_path +
    "|eq|" +
    value.to_string() +
    "|" +
    option_int_to_string(limit) +
    "|" +
    option_int_to_string(offset)
  if self.enable_cache {
    self.cache_lookups = self.cache_lookups + 1
    match self.cache.get(cache_key) {
      Some(cached) => {
        self.cache_hits = self.cache_hits + 1
        return Ok({
          keys: cached.keys.copy(),
          latency_us: 0,
          hit_cache: true,
          index_used: chosen,
        })
      }
      None => ()
    }
  }

  let storage = match manager.get_index_storage(chosen) {
    Some(s) => s
    None => return Err(Index_Not_Found)
  }

  let keys = paginate(storage.query(value), offset, limit)

  let latency = self.get_time_us() - start_time
  if latency > self.timeout_us {
    return Err(Query_Timeout)
  }

  let result = {
    keys,
    latency_us: latency,
    hit_cache: false,
    index_used: chosen,
  }
  if self.enable_cache && self.cache.length() < DEFAULT_QUERY_CACHE_SIZE {
    self.cache.set(cache_key, {
      keys: result.keys.copy(),
      latency_us: latency,
      hit_cache: true,
      index_used: chosen,
    })
  }

  Ok(result)
}

///|
/// 范围查询
pub fn QueryEngine::index_range(
  self : QueryEngine,
  index_name : String?,
  field_path : String,
  start : @realtime_db.Value?,
  end : @realtime_db.Value?,
  include_start : Bool?,
  include_end : Bool?,
  limit : Int?,
  offset : Int?,
) -> Result[QueryResult, QueryError] {
  let _ = field_path
  let start_time = self.get_time_us()

  let manager = match self.manager {
    Some(m) => m
    None => return Err(Internal_Error("Index manager not set"))
  }

  let chosen = match index_name {
    Some(name) => name
    None => {
      let conditions = [{ field_path: "", value: start, query_type: Range, }]
      match self.selector {
        Some(selector) =>
          match selector.select_index(conditions) {
            Some(name) => name
            None => return Err(Internal_Error("No suitable index found"))
          }
        None => return Err(Internal_Error("Index selector not set"))
      }
    }
  }

  let storage = match manager.get_index_storage(chosen) {
    Some(s) => s
    None => return Err(Index_Not_Found)
  }

  let keys = storage.range_query(start, end, include_start, include_end)
  let keys = paginate(keys, offset, limit)

  let latency = self.get_time_us() - start_time
  if latency > self.timeout_us {
    return Err(Query_Timeout)
  }

  Ok({ keys, latency_us: latency, hit_cache: false, index_used: chosen, })
}

///|
/// 前缀匹配查询
pub fn QueryEngine::index_prefix(
  self : QueryEngine,
  index_name : String?,
  field_path : String,
  prefix : String,
  limit : Int?,
) -> Result[QueryResult, QueryError] {
  let start_time = self.get_time_us()

  let manager = match self.manager {
    Some(m) => m
    None => return Err(Internal_Error("Index manager not set"))
  }

  let chosen = match index_name {
    Some(name) => name
    None => {
      let conditions = [
        {
          field_path,
          value: Some(@realtime_db.Str(prefix)),
          query_type: Prefix,
        },
      ]
      match self.selector {
        Some(selector) =>
          match selector.select_index(conditions) {
            Some(name) => name
            None => return Err(Internal_Error("No suitable index found"))
          }
        None => return Err(Internal_Error("Index selector not set"))
      }
    }
  }

  let storage = match manager.get_index_storage(chosen) {
    Some(s) => s
    None => return Err(Index_Not_Found)
  }

  let keys = paginate(storage.prefix_query(prefix), None, limit)

  let latency = self.get_time_us() - start_time
  if latency > self.timeout_us {
    return Err(Query_Timeout)
  }

  Ok({ keys, latency_us: latency, hit_cache: false, index_used: chosen, })
}

///|
/// 复合索引查询
pub fn QueryEngine::composite_query(
  self : QueryEngine,
  index_name : String,
  conditions : Array[@realtime_db.Value?],
  limit : Int?,
) -> Result[QueryResult, QueryError] {
  let start_time = self.get_time_us()

  let manager = match self.manager {
    Some(m) => m
    None => return Err(Internal_Error("Index manager not set"))
  }

  let def = match manager.indices.get(index_name) {
    Some(d) => d
    None => return Err(Index_Not_Found)
  }

  if def.field_paths.length() <= 1 {
    return Err(Internal_Error("Not a composite index"))
  }

  let storage = match def.storage {
    Some(s) => s
    None => return Err(Internal_Error("Index storage not initialized"))
  }

  let keys = match storage {
    IndexStorageHandle::Composite(c) => c.composite_query(conditions, limit)
    _ => return Err(Type_Mismatch)
  }

  let latency = self.get_time_us() - start_time
  if latency > self.timeout_us {
    return Err(Query_Timeout)
  }

  Ok({ keys, latency_us: latency, hit_cache: false, index_used: index_name, })
}

///|
/// 回表查询（获取完整数据）
pub fn QueryEngine::fetch_full_data(
  self : QueryEngine,
  keys : Array[String],
) -> Array[(String, @realtime_db.Value)] {
  let db = match self.db {
    Some(d) => d
    None => return []
  }

  let result : Array[(String, @realtime_db.Value)] = []
  for key in keys {
    match db.get(key) {
      Some(value) => result.push((key, value))
      None => ()
    }
  }
  result
}

///|
/// 分页辅助：先偏移后截断
fn paginate(keys : Array[String], offset : Int?, limit : Int?) -> Array[String] {
  let off = match offset {
    Some(o) => if o < 0 { 0 } else { o }
    None => 0
  }
  let start = if off > keys.length() { keys.length() } else { off }
  match limit {
    Some(l) => subarray(keys, start, start + l)
    None => subarray(keys, start, keys.length())
  }
}

///|
/// 可选整数转字符串（缓存键用）
fn option_int_to_string(v : Int?) -> String {
  match v {
    Some(i) => i.to_string()
    None => "-"
  }
}

///|
/// 获取时间（微秒）——使用逻辑时钟
fn QueryEngine::get_time_us(self : QueryEngine) -> Int {
  match self.db {
    Some(db) => db.clock()
    None => 0
  }
}

///|
/// 清空缓存
pub fn QueryEngine::clear_cache(self : QueryEngine) -> Unit {
  self.cache = Map([])
  self.cache_lookups = 0
  self.cache_hits = 0
}

///|
/// 设置查询超时时间
pub fn QueryEngine::set_timeout(self : QueryEngine, timeout_us : Int) -> Unit {
  if timeout_us > 0 {
    self.timeout_us = timeout_us
  }
}

///|
/// 启用/禁用缓存
pub fn QueryEngine::set_enable_cache(self : QueryEngine, enable : Bool) -> Unit {
  self.enable_cache = enable
  if !enable {
    self.cache = Map([])
  }
}

///|
/// 获取缓存命中率
pub fn QueryEngine::cache_hit_rate(self : QueryEngine) -> Double {
  if self.cache_lookups == 0 {
    0.0
  } else {
    self.cache_hits.to_double() / self.cache_lookups.to_double()
  }
}
