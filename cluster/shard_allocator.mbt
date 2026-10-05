// 分片分配器模块
//
// 实现分片分配策略、一致性哈希算法

///|
/// 分片分配策略枚举
pub(all) enum AllocationStrategy {
  /// 轮询策略
  RoundRobin
  /// 最低负载策略
  LowestLoad
  /// 标签匹配策略
  LabelMatch
}

///|
impl Eq for AllocationStrategy with fn equal(self, other) -> Bool {
  match (self, other) {
    (RoundRobin, RoundRobin) => true
    (LowestLoad, LowestLoad) => true
    (LabelMatch, LabelMatch) => true
    _ => false
  }
}

///|
pub extend AllocationStrategy with Eq::{equal, not_equal}

///|
/// 分片分配器
pub(all) struct ShardAllocator {
  /// 节点管理器
  node_manager : NodeManager
  /// 分配策略
  mut strategy : AllocationStrategy
  /// 副本因子
  replica_factor : Int
  /// 分片总数
  total_shards : Int
  /// 轮询索引
  mut round_robin_index : Int
}

///|
/// 创建分片分配器
pub fn ShardAllocator::new(
  node_manager : NodeManager,
  config : ClusterConfig,
) -> ShardAllocator {
  {
    node_manager,
    strategy: RoundRobin,
    replica_factor: config.replica_factor,
    total_shards: config.total_shards,
    round_robin_index: 0,
  }
}

///|
/// 设置分配策略
pub fn ShardAllocator::set_strategy(
  self : ShardAllocator,
  strategy : AllocationStrategy,
) -> Unit {
  self.strategy = strategy
}

///|
/// 分配分片副本
pub fn ShardAllocator::allocate_replicas(
  self : ShardAllocator,
  _shard_id : String,
  exclude_nodes : Array[String],
) -> Result[Array[String], ClusterError] {
  // 获取可用节点
  let available_nodes = self.node_manager.get_available_nodes()
  if available_nodes.length() < self.replica_factor {
    return Err(Resource_Exhausted)
  }

  // 过滤排除的节点
  let candidates : Array[NodeInfo] = []
  for node in available_nodes {
    let mut excluded = false
    for ex in exclude_nodes {
      if node.id == ex {
        excluded = true
        break
      }
    }
    if !excluded {
      candidates.push(node)
    }
  }

  if candidates.length() < self.replica_factor {
    return Err(Resource_Exhausted)
  }

  // 根据策略选择节点
  let mut selected_nodes : Array[String] = []
  match self.strategy {
    RoundRobin => selected_nodes = self.select_by_round_robin(candidates)
    LowestLoad => selected_nodes = self.select_by_lowest_load(candidates)
    LabelMatch => selected_nodes = self.select_by_label_match(candidates)
  }

  // 确保副本数不超过候选节点数
  let replica_count = if selected_nodes.length() < self.replica_factor {
    selected_nodes.length()
  } else {
    self.replica_factor
  }

  let result : Array[String] = []
  for i in 0..<replica_count {
    result.push(selected_nodes[i])
  }

  Ok(result)
}

///|
/// 轮询选择
fn ShardAllocator::select_by_round_robin(
  self : ShardAllocator,
  candidates : Array[NodeInfo],
) -> Array[String] {
  let result : Array[String] = []
  let n = candidates.length()

  for i in 0..<self.replica_factor {
    let idx = (self.round_robin_index + i) % n
    result.push(candidates[idx].id)
  }

  self.round_robin_index = (self.round_robin_index + 1) % n

  result
}

///|
/// 最低负载选择
fn ShardAllocator::select_by_lowest_load(
  self : ShardAllocator,
  candidates : Array[NodeInfo],
) -> Array[String] {
  // 按负载分数排序（升序）
  let sorted : Array[NodeInfo] = []
  for node in candidates {
    sorted.push(node)
  }

  // 简化排序：使用冒泡排序
  let n = sorted.length()
  let mut i = 0
  while i < n - 1 {
    let mut j = 0
    while j < n - 1 - i {
      if sorted[j].load_score > sorted[j + 1].load_score {
        let temp = { ..sorted[j], }
        sorted[j] = { ..sorted[j + 1], }
        sorted[j + 1] = temp
      }
      j = j + 1
    }
    i = i + 1
  }

  let result : Array[String] = []
  for i in 0..<self.replica_factor {
    if i < sorted.length() {
      result.push(sorted[i].id)
    }
  }

  result
}

///|
/// 标签匹配选择
fn ShardAllocator::select_by_label_match(
  self : ShardAllocator,
  candidates : Array[NodeInfo],
) -> Array[String] {
  // 简化实现：返回前 replica_factor 个节点
  let result : Array[String] = []
  for i in 0..<self.replica_factor {
    if i < candidates.length() {
      result.push(candidates[i].id)
    }
  }
  result
}

///|
/// 一致性哈希算法
pub(all) struct ConsistentHash {
  /// 虚拟节点数
  virtual_nodes : Int
  /// 哈希环
  mut hash_ring : Map[Int, String]
  /// 节点映射
  mut node_map : Map[String, Array[Int]]
  /// 总分片数
  total_shards : Int
}

///|
/// 默认虚拟节点数
pub const DEFAULT_VIRTUAL_NODES : Int = 100

///|
/// 创建一致性哈希
pub fn ConsistentHash::new(total_shards : Int) -> ConsistentHash {
  {
    virtual_nodes: DEFAULT_VIRTUAL_NODES,
    hash_ring: Map([]),
    node_map: Map([]),
    total_shards,
  }
}

///|
/// 指定虚拟节点数创建一致性哈希
pub fn ConsistentHash::with_virtual_nodes(
  total_shards : Int,
  virtual_nodes : Int,
) -> ConsistentHash {
  { virtual_nodes, hash_ring: Map([]), node_map: Map([]), total_shards, }
}

///|
/// 添加节点
pub fn ConsistentHash::add_node(
  self : ConsistentHash,
  node_id : String,
) -> Unit {
  let virtual_hashes : Array[Int] = []

  for i in 0..<self.virtual_nodes {
    let hash = self.hash(node_id.to_string() + "_" + i.to_string())
    self.hash_ring.set(hash % self.total_shards, node_id.to_string())
    virtual_hashes.push(hash % self.total_shards)
  }

  self.node_map.set(node_id, virtual_hashes)
}

///|
/// 移除节点
pub fn ConsistentHash::remove_node(
  self : ConsistentHash,
  node_id : String,
) -> Unit {
  match self.node_map.get(node_id.to_string()) {
    Some(hashes) =>
      for h in hashes {
        self.hash_ring.remove(h)
      }
    None => ()
  }

  self.node_map.remove(node_id)
}

///|
/// 获取分片对应的节点
pub fn ConsistentHash::get_node(self : ConsistentHash, key : String) -> String? {
  let hash = self.hash(key)
  let shard_id = hash % self.total_shards

  // 查找哈希环
  let mut node_id : String? = self.hash_ring.get(shard_id)

  // 如果没找到，找下一个节点
  if node_id is None {
    let mut min_hash = 2147483647
    for (h, n) in self.hash_ring {
      if h > shard_id && h < min_hash {
        min_hash = h
        node_id = Some(n.to_string())
      }
    }

    // 如果还是没找到，返回第一个节点
    if node_id is None {
      for (_, n) in self.hash_ring {
        node_id = Some(n.to_string())
        break
      }
    }
  }

  node_id
}

///|
/// 获取分片对应的所有节点（包括副本）
pub fn ConsistentHash::get_nodes_for_shard(
  self : ConsistentHash,
  shard_id : Int,
) -> Array[String] {
  let _ = shard_id
  let result : Array[String] = []
  for (_, node_id) in self.hash_ring {
    if !result.contains(node_id) {
      result.push(node_id.to_string())
    }
  }
  result
}

///|
/// 哈希函数（FNV-1a 思想的简化版，限制在正 Int 范围内避免溢出）
fn ConsistentHash::hash(self : ConsistentHash, key : String) -> Int {
  let _ = self
  let mut hash = 5381
  for b in key.to_array() {
    hash = ((hash ^ b.to_int()) * 3) & 0x1FFFFFFF
  }
  hash
}

///|
/// 分片键映射函数
pub fn map_key_to_shard(key : String, total_shards : Int) -> Int {
  let mut hash = 5381
  for b in key.to_array() {
    hash = ((hash ^ b.to_int()) * 3) & 0x1FFFFFFF
  }
  hash % total_shards
}

///|
/// 创建分片分配器
pub fn create_shard_allocator(
  node_manager : NodeManager,
  config : ClusterConfig,
) -> ShardAllocator {
  ShardAllocator::new(node_manager, config)
}

///|
/// 创建一致性哈希
pub fn create_consistent_hash(total_shards : Int) -> ConsistentHash {
  ConsistentHash::new(total_shards)
}
