// 分片代理层模块
//
// 实现查询路由、结果聚合、分片代理

///|
/// 查询路由器
pub(all) struct QueryRouter {
  /// 路由表服务
  routing_service : RoutingTableService
  /// 一致性哈希
  consistent_hash : ConsistentHash
  /// 路由缓存
  mut route_cache : Map[String, RoutingEntry]
}

///|
/// 创建查询路由器
pub fn QueryRouter::new(
  routing_service : RoutingTableService,
  total_shards : Int32,
) -> QueryRouter {
  {
    routing_service,
    consistent_hash: ConsistentHash::new(total_shards),
    route_cache: Map([]),
  }
}

///|
/// 路由查询
pub fn QueryRouter::route(
  self : QueryRouter,
  key : String,
) -> Result[RoutingEntry, ClusterError] {
  // 先查缓存
  match self.route_cache.get(key.to_string()) {
    Some(entry) => return Ok(entry)
    None => ()
  }

  // 查询路由表
  match self.routing_service.get_route(key.to_string()) {
    Ok(entry) => {
      self.route_cache.set(key, { ..entry, })
      Ok(entry)
    }
    Err(e) => Err(e)
  }
}

///|
/// 路由批量查询
pub fn QueryRouter::route_batch(
  self : QueryRouter,
  keys : Array[String],
) -> Array[Result[RoutingEntry, ClusterError]] {
  let result : Array[Result[RoutingEntry, ClusterError]] = []
  for key in keys {
    result.push(self.route(key))
  }
  result
}

///|
/// 清除缓存
pub fn QueryRouter::clear_cache(self : QueryRouter) -> Unit {
  self.route_cache = Map([])
}

///|
/// 结果聚合器
pub(all) struct ResultAggregator {
  /// 聚合策略
  strategy : AggregationStrategy
  /// 结果列表
  mut results : Array[@realtime_db.Value]
}

///|
/// 聚合策略枚举
pub(all) enum AggregationStrategy {
  /// 合并所有结果
  MergeAll
  /// 去重
  Distinct
  /// 排序
  Sorted
}

///|
/// 创建结果聚合器
pub fn ResultAggregator::new(
  strategy : AggregationStrategy,
) -> ResultAggregator {
  { strategy, results: [], }
}

///|
/// 添加结果
pub fn ResultAggregator::add_result(
  self : ResultAggregator,
  result : @realtime_db.Value,
) -> Unit {
  self.results.push(result)
}

///|
/// 聚合结果
pub fn ResultAggregator::aggregate(
  self : ResultAggregator,
) -> @realtime_db.Value {
  match self.strategy {
    MergeAll => @realtime_db.Arr(self.results)
    Distinct => {
      let unique : Array[@realtime_db.Value] = []
      for r in self.results {
        if !unique.contains(r) {
          unique.push(r)
        }
      }
      @realtime_db.Arr(unique)
    }
    Sorted =>
      // 简化排序
      @realtime_db.Arr(self.results)
  }
}

///|
/// 清空结果
pub fn ResultAggregator::clear(self : ResultAggregator) -> Unit {
  self.results = []
}

///|
/// 分片代理
pub(all) struct ShardProxy {
  /// 查询路由器
  router : QueryRouter
  /// 节点管理器
  node_manager : NodeManager
  /// 读写分离标志
  mut read_write_splitting : Bool
  /// 强一致性读取
  mut strong_consistency : Bool
}

///|
/// 创建分片代理
pub fn ShardProxy::new(
  router : QueryRouter,
  node_manager : NodeManager,
) -> ShardProxy {
  {
    router,
    node_manager,
    read_write_splitting: true,
    strong_consistency: false,
  }
}

///|
/// 处理读请求
pub fn ShardProxy::handle_read(
  self : ShardProxy,
  key : String,
) -> Result[@realtime_db.Value, ClusterError] {
  // 路由查询
  let route = match self.router.route(key) {
    Ok(route) => route
    Err(e) => return Err(e)
  }

  // 选择节点
  let node_addr = if self.read_write_splitting && !self.strong_consistency {
    // 选择副本节点
    if route.replica_addrs.length() > 0 {
      route.replica_addrs[0].to_string()
    } else {
      route.primary_addr
    }
  } else {
    route.primary_addr
  }

  // 简化实现：返回节点地址
  Ok(@realtime_db.Str(node_addr))
}

///|
/// 处理写请求
pub fn ShardProxy::handle_write(
  self : ShardProxy,
  key : String,
  _value : @realtime_db.Value,
) -> Result[@realtime_db.Value, ClusterError] {
  // 路由查询
  let route = match self.router.route(key) {
    Ok(route) => route
    Err(e) => return Err(e)
  }

  // 写请求总是发送到主节点
  let node_addr = route.primary_addr

  // 简化实现：返回节点地址
  Ok(@realtime_db.Str(node_addr))
}

///|
/// 处理批量读请求
pub fn ShardProxy::handle_batch_read(
  self : ShardProxy,
  keys : Array[String],
) -> Result[Array[@realtime_db.Value], ClusterError] {
  let result : Array[@realtime_db.Value] = []

  for key in keys {
    match self.handle_read(key) {
      Ok(value) => result.push(value)
      Err(e) => return Err(e)
    }
  }

  Ok(result)
}

///|
/// 处理批量写请求
pub fn ShardProxy::handle_batch_write(
  self : ShardProxy,
  pairs : Array[(String, @realtime_db.Value)],
) -> Result[Array[@realtime_db.Value], ClusterError] {
  let result : Array[@realtime_db.Value] = []

  for (key, value) in pairs {
    match self.handle_write(key, value) {
      Ok(res) => result.push(res)
      Err(e) => return Err(e)
    }
  }

  Ok(result)
}

///|
/// 设置读写分离
pub fn ShardProxy::set_read_write_splitting(
  self : ShardProxy,
  enabled : Bool,
) -> Unit {
  self.read_write_splitting = enabled
}

///|
/// 设置强一致性
pub fn ShardProxy::set_strong_consistency(
  self : ShardProxy,
  enabled : Bool,
) -> Unit {
  self.strong_consistency = enabled
}

///|
/// 创建查询路由器
pub fn create_query_router(
  routing_service : RoutingTableService,
  total_shards : Int32,
) -> QueryRouter {
  QueryRouter::new(routing_service, total_shards)
}

///|
/// 创建结果聚合器
pub fn create_result_aggregator(
  strategy : AggregationStrategy,
) -> ResultAggregator {
  ResultAggregator::new(strategy)
}

///|
/// 创建分片代理
pub fn create_shard_proxy(
  router : QueryRouter,
  node_manager : NodeManager,
) -> ShardProxy {
  ShardProxy::new(router, node_manager)
}
