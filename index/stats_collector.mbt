// 统计收集器模块
//
// 收集索引统计信息：基数、碎片率、命中率、内存占用
// 定期自动收集，支持指标暴露

///|
/// 统计收集器结构体
pub struct StatsCollector {
  /// 索引管理器引用
  mut manager : IndexManager?
  /// 收集间隔（秒）
  mut collect_interval : Int
  /// 上次收集时间
  mut last_collect_time : Int
  /// 统计信息缓存
  mut stats_cache : Map[String, IndexStats]
  /// 是否启用自动收集
  mut auto_collect : Bool
  /// 查询计数器
  mut query_count : Int
  /// 命中计数器
  mut hit_count : Int
}

///|
/// 默认收集间隔（1 小时）
pub const DEFAULT_COLLECT_INTERVAL : Int = 3600

///|
/// 创建统计收集器
pub fn StatsCollector::new() -> StatsCollector {
  {
    manager: None,
    collect_interval: DEFAULT_COLLECT_INTERVAL,
    last_collect_time: 0,
    stats_cache: Map([]),
    auto_collect: true,
    query_count: 0,
    hit_count: 0,
  }
}

///|
/// 设置索引管理器
pub fn StatsCollector::set_manager(
  self : StatsCollector,
  manager : IndexManager?,
) -> Unit {
  self.manager = manager
}

///|
/// 收集统计信息
/// - index_name 为 None 时收集所有索引，并返回第一个索引的统计
pub fn StatsCollector::collect_stats(
  self : StatsCollector,
  index_name : String?,
) -> Result[IndexStats, IndexError] {
  let manager = match self.manager {
    Some(m) => m
    None => return Err(Internal_Error("Index manager not set"))
  }

  match index_name {
    Some(name) => self.collect_single_stats(name, manager)
    None => self.collect_all_stats(manager)
  }
}

///|
/// 收集单个索引的统计（内部方法）
fn StatsCollector::collect_single_stats(
  self : StatsCollector,
  name : String,
  manager : IndexManager,
) -> Result[IndexStats, IndexError] {
  let def = match manager.indices.get(name) {
    Some(d) => d
    None => return Err(Index_Not_Found)
  }

  let storage = match def.storage {
    Some(s) => s
    None => return Err(Internal_Error("Index storage not initialized"))
  }

  let total_entries = storage.size()
  let memory_usage = storage.memory_usage()
  let cardinality = self.estimate_cardinality(storage)
  let fragmentation_rate = self.estimate_fragmentation(storage)
  let hit_rate = if self.query_count == 0 {
    1.0
  } else {
    self.hit_count.to_double() / self.query_count.to_double()
  }
  let query_latency_p99 = self.estimate_query_latency(storage)
  let update_latency_p99 = 50

  let stats = {
    name,
    cardinality,
    total_entries,
    memory_usage,
    fragmentation_rate,
    hit_rate,
    query_latency_p99,
    update_latency_p99,
  }

  self.stats_cache.set(name, stats)
  self.last_collect_time = self.get_current_time()

  Ok(stats)
}

///|
/// 收集所有索引的统计（内部方法）
fn StatsCollector::collect_all_stats(
  self : StatsCollector,
  manager : IndexManager,
) -> Result[IndexStats, IndexError] {
  if manager.indices.length() == 0 {
    return Err(Internal_Error("No indices found"))
  }

  let mut last : IndexStats? = None
  for name, _ in manager.indices {
    match self.collect_single_stats(name, manager) {
      Ok(stats) => last = Some(stats)
      Err(_) => ()
    }
  }

  match last {
    Some(stats) => Ok(stats)
    None => Err(Internal_Error("No indices found"))
  }
}

///|
/// 获取索引统计信息
pub fn StatsCollector::get_index_stats(
  self : StatsCollector,
  index_name : String,
) -> IndexStats? {
  self.stats_cache.get(index_name)
}

///|
/// 获取所有统计信息
pub fn StatsCollector::get_all_stats(
  self : StatsCollector,
) -> Array[IndexStats] {
  let result : Array[IndexStats] = []
  for _, stats in self.stats_cache {
    result.push(stats)
  }
  result
}

///|
/// 估算基数（简化实现：返回条目数；后续可替换为 HyperLogLog）
fn StatsCollector::estimate_cardinality(
  self : StatsCollector,
  storage : IndexStorageHandle,
) -> Int {
  let _ = self
  storage.size()
}

///|
/// 估算碎片率（简化实现）
fn StatsCollector::estimate_fragmentation(
  self : StatsCollector,
  storage : IndexStorageHandle,
) -> Double {
  let _ = self
  let _ = storage
  0.1
}

///|
/// 估算查询延迟（内部方法）
fn StatsCollector::estimate_query_latency(
  self : StatsCollector,
  storage : IndexStorageHandle,
) -> Int {
  let _ = self
  match storage.index_type() {
    Hash => 10
    BTree => 30
    Fulltext => 50
    Composite => 20
  }
}

///|
/// 获取当前时间（逻辑时钟，秒）
fn StatsCollector::get_current_time(self : StatsCollector) -> Int {
  match self.manager {
    Some(manager) =>
      match manager.db {
        Some(db) => db.clock()
        None => 0
      }
    None => 0
  }
}

///|
/// 检查是否需要收集统计信息
pub fn StatsCollector::should_collect(self : StatsCollector) -> Bool {
  if !self.auto_collect {
    return false
  }
  let current_time = self.get_current_time()
  current_time - self.last_collect_time >= self.collect_interval
}

///|
/// 记录查询
pub fn StatsCollector::record_query(
  self : StatsCollector,
  hit_cache : Bool,
) -> Unit {
  self.query_count = self.query_count + 1
  if hit_cache {
    self.hit_count = self.hit_count + 1
  }
}

///|
/// 设置收集间隔
pub fn StatsCollector::set_collect_interval(
  self : StatsCollector,
  interval : Int,
) -> Unit {
  if interval > 0 {
    self.collect_interval = interval
  }
}

///|
/// 启用/禁用自动收集
pub fn StatsCollector::set_auto_collect(
  self : StatsCollector,
  auto : Bool,
) -> Unit {
  self.auto_collect = auto
}

///|
/// 清除缓存
pub fn StatsCollector::clear_cache(self : StatsCollector) -> Unit {
  self.stats_cache = Map([])
}

///|
/// 暴露指标（Prometheus 文本格式）
pub fn StatsCollector::expose_metrics(self : StatsCollector) -> String {
  let mut metrics = ""

  for (name, stats) in self.stats_cache {
    metrics = metrics +
      "index_query_latency_p99{index=\"" +
      name +
      "\"} " +
      stats.query_latency_p99.to_string() +
      "\n"
    metrics = metrics +
      "index_update_latency_p99{index=\"" +
      name +
      "\"} " +
      stats.update_latency_p99.to_string() +
      "\n"
    metrics = metrics +
      "index_memory_usage{index=\"" +
      name +
      "\"} " +
      stats.memory_usage.to_string() +
      "\n"
    metrics = metrics +
      "index_hit_rate{index=\"" +
      name +
      "\"} " +
      stats.hit_rate.to_string() +
      "\n"
    metrics = metrics +
      "index_cardinality{index=\"" +
      name +
      "\"} " +
      stats.cardinality.to_string() +
      "\n"
    metrics = metrics +
      "index_total_entries{index=\"" +
      name +
      "\"} " +
      stats.total_entries.to_string() +
      "\n"
    metrics = metrics +
      "index_fragmentation_rate{index=\"" +
      name +
      "\"} " +
      stats.fragmentation_rate.to_string() +
      "\n"
  }

  metrics
}
