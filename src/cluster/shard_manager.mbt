// 分片管理器模块
//
// 实现分片创建、删除、状态管理

///|
/// 分片管理器
pub(all) struct ShardManager {
  /// 节点管理器
  node_manager : NodeManager
  /// 分片分配器
  allocator : ShardAllocator
  /// 分片映射：分片ID -> 分片信息
  mut shards : Map[String, ShardInfo]
  /// 分片状态映射：分片ID -> 分片状态
  mut shard_states : Map[String, ShardStatus]
  /// 副本因子
  replica_factor : Int
  /// 分片总数
  total_shards : Int
  /// 版本号
  mut version : Int
}

///|
/// 创建分片管理器
pub fn ShardManager::new(
  node_manager : NodeManager,
  allocator : ShardAllocator,
  config : ClusterConfig,
) -> ShardManager {
  {
    node_manager,
    allocator,
    shards: Map([]),
    shard_states: Map([]),
    replica_factor: config.replica_factor,
    total_shards: config.total_shards,
    version: 0,
  }
}

///|
/// 创建分片
pub fn ShardManager::create_shard(
  self : ShardManager,
  shard_id : String,
  key_range : ShardKeyRange,
) -> Result[ShardInfo, ClusterError] {
  // 检查分片是否已存在
  if self.shards.contains(shard_id.to_string()) {
    return Err(Shard_Already_Exists)
  }

  // 分配副本节点
  let replica_nodes = match
    self.allocator.allocate_replicas(shard_id.to_string(), []) {
    Ok(nodes) => nodes
    Err(e) => return Err(e)
  }

  if replica_nodes.length() < 1 {
    return Err(Resource_Exhausted)
  }

  // 创建副本列表
  let replicas : Array[Replica] = []
  for i in 0..<replica_nodes.length() {
    let role = if i == 0 { Primary } else { Secondary }
    replicas.push(Replica::{
      id: shard_id.to_string() + "_replica_" + i.to_string(),
      node_id: replica_nodes[i].to_string(),
      role,
      latency_ms: 0,
      is_healthy: true,
      last_heartbeat: 0,
    })
  }

  // 创建分片信息
  let info = ShardInfo::{
    id: shard_id.to_string(),
    replicas,
    primary_node_id: replica_nodes[0].to_string(),
    status: Creating,
    version: 1,
    key_range,
    size_bytes: 0,
    created_at: 0,
    updated_at: 0,
  }

  // 保存分片
  self.shards.set(shard_id.to_string(), { ..info, })
  self.shard_states.set(shard_id.to_string(), Creating)
  self.version = self.version + 1

  // 转换到 Active 状态
  self.shard_states.set(shard_id, Active)

  Ok(info)
}

///|
/// 删除分片
pub fn ShardManager::delete_shard(
  self : ShardManager,
  shard_id : String,
) -> Result[Unit, ClusterError] {
  // 检查分片是否存在
  if !self.shards.contains(shard_id.to_string()) {
    return Err(Shard_Not_Found)
  }

  // 获取分片状态
  let status = match self.shard_states.get(shard_id.to_string()) {
    Some(s) => s
    None => return Err(Shard_Not_Found)
  }

  // 检查状态转换
  if !status.can_transition_to(Deleting) {
    return Err(Shard_Invalid_State)
  }

  // 更新状态
  self.shard_states.set(shard_id.to_string(), Deleting)
  self.version = self.version + 1

  // 移除分片
  self.shards.remove(shard_id.to_string())
  self.shard_states.remove(shard_id)

  Ok(())
}

///|
/// 获取分片信息
pub fn ShardManager::get_shard_info(
  self : ShardManager,
  shard_id : String,
) -> ShardInfo? {
  self.shards.get(shard_id)
}

///|
/// 获取分片状态
pub fn ShardManager::get_shard_status(
  self : ShardManager,
  shard_id : String,
) -> ShardStatus? {
  self.shard_states.get(shard_id)
}

///|
/// 获取所有分片
pub fn ShardManager::get_all_shards(self : ShardManager) -> Array[ShardInfo] {
  let result : Array[ShardInfo] = []
  for (_, info) in self.shards {
    result.push(info)
  }
  result
}

///|
/// 获取活跃分片
pub fn ShardManager::get_active_shards(self : ShardManager) -> Array[ShardInfo] {
  let result : Array[ShardInfo] = []
  for (shard_id, info) in self.shards {
    match self.shard_states.get(shard_id) {
      Some(Active) => result.push(info)
      _ => ()
    }
  }
  result
}

///|
/// 获取分片数量
pub fn ShardManager::shard_count(self : ShardManager) -> Int {
  self.shards.length()
}

///|
/// 更新分片状态
pub fn ShardManager::update_shard_status(
  self : ShardManager,
  shard_id : String,
  new_status : ShardStatus,
) -> Result[Unit, ClusterError] {
  let current_status = match self.shard_states.get(shard_id) {
    Some(s) => s
    None => return Err(Shard_Not_Found)
  }

  if !current_status.can_transition_to(new_status) {
    return Err(Shard_Invalid_State)
  }

  self.shard_states.set(shard_id, new_status)
  self.version = self.version + 1

  Ok(())
}

///|
/// 迁移分片
pub fn ShardManager::migrate_shard(
  self : ShardManager,
  shard_id : String,
  from_node : String,
  to_node : String,
) -> Result[Unit, ClusterError] {
  let _ = from_node
  let _ = to_node
  // 检查分片是否存在
  let info = match self.shards.get(shard_id.to_string()) {
    Some(i) => i
    None => return Err(Shard_Not_Found)
  }

  // 检查分片状态
  if info.status != Active {
    return Err(Shard_Invalid_State)
  }

  // 更新分片状态为 Moving
  self.shard_states.set(shard_id.to_string(), Moving)

  // 更新分片信息
  info.status = Moving
  info.version = info.version + 1
  self.version = self.version + 1

  // 简化实现：实际需要执行数据迁移
  // 迁移完成后更新状态为 Active
  self.shard_states.set(shard_id, Active)
  info.status = Active

  Ok(())
}

///|
/// 获取节点上的分片
pub fn ShardManager::get_shards_by_node(
  self : ShardManager,
  node_id : String,
) -> Array[ShardInfo] {
  let result : Array[ShardInfo] = []
  for (_, info) in self.shards {
    for replica in info.replicas {
      if replica.node_id == node_id {
        result.push(info)
        break
      }
    }
  }
  result
}

///|
/// 获取主分片
pub fn ShardManager::get_primary_shard(
  self : ShardManager,
  shard_id : String,
) -> ShardInfo? {
  match self.shards.get(shard_id) {
    Some(info) if info.primary_node_id != "" => Some(info)
    _ => None
  }
}

///|
/// 获取版本号
pub fn ShardManager::get_version(self : ShardManager) -> Int {
  self.version
}

///|
/// 路由表服务
pub(all) struct RoutingTableService {
  /// 路由表
  mut routing_table : RoutingTable
  /// 分片管理器
  shard_manager : ShardManager
  /// 一致性哈希
  consistent_hash : ConsistentHash
  /// 路由缓存
  mut route_cache : Map[String, RoutingEntry]
}

///|
/// 创建路由表服务
pub fn RoutingTableService::new(
  shard_manager : ShardManager,
  total_shards : Int,
) -> RoutingTableService {
  {
    routing_table: RoutingTable::new(),
    shard_manager,
    consistent_hash: ConsistentHash::new(total_shards),
    route_cache: Map([]),
  }
}

///|
/// 获取路由
pub fn RoutingTableService::get_route(
  self : RoutingTableService,
  key : String,
) -> Result[RoutingEntry, ClusterError] {
  // 先查缓存
  match self.route_cache.get(key) {
    Some(entry) => return Ok(entry)
    None => ()
  }

  // 计算分片 ID
  let shard_id = match self.consistent_hash.get_node(key.to_string()) {
    Some(id) => id
    None => return Err(Route_Not_Found)
  }

  // 查询路由表
  match self.routing_table.get_entry(shard_id) {
    Some(entry) => {
      // 更新缓存
      self.route_cache.set(key, { ..entry, })
      Ok(entry)
    }
    None => Err(Route_Not_Found)
  }
}

///|
/// 更新路由表
pub fn RoutingTableService::update_routing_table(
  self : RoutingTableService,
) -> Result[Unit, ClusterError] {
  // 获取所有分片
  let shards = self.shard_manager.get_all_shards()

  // 更新路由表
  for shard in shards {
    let entry = RoutingEntry::{
      shard_id: shard.id,
      primary_addr: shard.primary_node_id,
      replica_addrs: [],
      version: shard.version,
    }

    for replica in shard.replicas {
      entry.replica_addrs.push(replica.node_id)
    }

    self.routing_table.add_entry(entry)
  }

  Ok(())
}

///|
/// 获取路由表
pub fn RoutingTableService::get_routing_table(
  self : RoutingTableService,
) -> RoutingTable {
  self.routing_table
}

///|
/// 获取路由表版本
pub fn RoutingTableService::get_version(self : RoutingTableService) -> Int {
  self.routing_table.get_version()
}

///|
/// 清除缓存
pub fn RoutingTableService::clear_cache(self : RoutingTableService) -> Unit {
  self.route_cache = Map([])
}

///|
/// 创建分片管理器
pub fn create_shard_manager(
  node_manager : NodeManager,
  allocator : ShardAllocator,
  config : ClusterConfig,
) -> ShardManager {
  ShardManager::new(node_manager, allocator, config)
}

///|
/// 创建路由表服务
pub fn create_routing_table_service(
  shard_manager : ShardManager,
  total_shards : Int,
) -> RoutingTableService {
  RoutingTableService::new(shard_manager, total_shards)
}
