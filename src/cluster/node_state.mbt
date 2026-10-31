// 节点状态管理模块
//
// 实现节点状态机、状态转换、标签匹配

///|
/// 节点状态机
pub(all) struct NodeState {
  /// 节点信息
  info : NodeInfo
  /// 当前状态
  mut status : NodeStatus
  /// 状态转换历史
  mut state_history : Array[(Int32, NodeStatus)]
  /// 状态转换锁
  mut is_transitioning : Bool
}

///|
/// 创建节点状态机
pub fn NodeState::new(info : NodeInfo) -> NodeState {
  { info, status: Joining, state_history: [], is_transitioning: false, }
}

///|
/// 转换状态
pub fn NodeState::transition_to(
  self : NodeState,
  new_status : NodeStatus,
) -> Result[Unit, ClusterError] {
  if self.is_transitioning {
    return Err(Node_Invalid_State)
  }

  if !self.status.can_transition_to(new_status) {
    return Err(Node_Invalid_State)
  }

  self.is_transitioning = true
  self.state_history.push((0, new_status))
  self.status = new_status
  self.is_transitioning = false

  // 更新节点活跃时间
  if new_status == Active {
    self.info.last_active_at = 0 // 使用实际时钟
  }

  Ok(())
}

///|
/// 获取当前状态
pub fn NodeState::get_status(self : NodeState) -> NodeStatus {
  self.status
}

///|
/// 获取节点信息
pub fn NodeState::get_info(self : NodeState) -> NodeInfo {
  self.info
}

///|
/// 更新心跳时间
pub fn NodeState::update_heartbeat(self : NodeState) -> Unit {
  self.info.last_active_at = 0
  self.info.heartbeat_timeouts = 0
}

///|
/// 增加心跳超时计数
pub fn NodeState::increment_heartbeat_timeout(self : NodeState) -> Int32 {
  self.info.heartbeat_timeouts = self.info.heartbeat_timeouts + 1
  self.info.heartbeat_timeouts
}

///|
/// 重置心跳超时计数
pub fn NodeState::reset_heartbeat_timeout(self : NodeState) -> Unit {
  self.info.heartbeat_timeouts = 0
}

///|
/// 获取心跳超时次数
pub fn NodeState::get_heartbeat_timeouts(self : NodeState) -> Int32 {
  self.info.heartbeat_timeouts
}

///|
/// 判断是否活跃
pub fn NodeState::is_active(self : NodeState) -> Bool {
  self.status == Active
}

///|
/// 判断是否健康
pub fn NodeState::is_healthy(self : NodeState) -> Bool {
  self.status.is_healthy()
}

///|
/// 更新负载分数
pub fn NodeState::update_load_score(self : NodeState, score : Double) -> Unit {
  self.info.load_score = score
}

///|
/// 增加分片计数
pub fn NodeState::increment_shard_count(self : NodeState) -> Unit {
  self.info.shard_count = self.info.shard_count + 1
}

///|
/// 减少分片计数
pub fn NodeState::decrement_shard_count(self : NodeState) -> Unit {
  if self.info.shard_count > 0 {
    self.info.shard_count = self.info.shard_count - 1
  }
}

///|
/// 获取分片计数
pub fn NodeState::get_shard_count(self : NodeState) -> Int32 {
  self.info.shard_count
}

///|
/// 节点标签匹配
pub(all) struct NodeLabelMatcher {}

///|
/// 创建标签匹配器
pub fn NodeLabelMatcher::new() -> NodeLabelMatcher {
  NodeLabelMatcher::{ }
}

///|
/// 检查节点是否匹配标签选择器
pub fn NodeLabelMatcher::matches(
  self : NodeLabelMatcher,
  node_labels : Map[String, String],
  selector : Map[String, String],
) -> Bool {
  let _ = self
  for (key, value) in selector {
    match node_labels.get(key) {
      Some(v) => if v != value { return false }
      None => return false
    }
  }
  true
}

///|
/// 检查节点是否匹配区域标签
pub fn NodeLabelMatcher::match_region(
  self : NodeLabelMatcher,
  node_labels : Map[String, String],
  region : String,
) -> Bool {
  let _ = self
  match node_labels.get("region") {
    Some(r) => r == region
    None => false
  }
}

///|
/// 检查节点是否匹配类型标签
pub fn NodeLabelMatcher::match_type(
  self : NodeLabelMatcher,
  node_labels : Map[String, String],
  node_type : String,
) -> Bool {
  let _ = self
  match node_labels.get("type") {
    Some(t) => t == node_type
    None => false
  }
}

///|
/// 节点管理器
pub(all) struct NodeManager {
  /// 节点映射：节点ID -> 节点状态
  mut nodes : Map[String, NodeState]
  /// 节点地址映射：节点ID -> 地址
  mut node_addrs : Map[String, String]
  /// 配置
  config : ClusterConfig
  /// 标签匹配器
  label_matcher : NodeLabelMatcher
  /// 下一个节点 ID
  mut next_id : Int32
}

///|
/// 创建节点管理器
pub fn NodeManager::new(config : ClusterConfig) -> NodeManager {
  {
    nodes: Map([]),
    node_addrs: Map([]),
    config,
    label_matcher: NodeLabelMatcher::new(),
    next_id: 0,
  }
}

///|
/// 注册节点
pub fn NodeManager::register_node(
  self : NodeManager,
  node_id : String,
  addr : String,
  labels : Map[String, String],
) -> Result[String, ClusterError] {
  // 校验节点 ID 格式
  if !self.validate_node_id(node_id) {
    return Err(Invalid_Node_Id)
  }

  // 检查节点是否已存在
  if self.nodes.contains(node_id) {
    // 更新心跳时间
    match self.nodes.get(node_id) {
      Some(state) => state.update_heartbeat()
      None => ()
    }
    return Ok(node_id)
  }

  // 创建节点信息
  let info = NodeInfo::{
    id: node_id.to_string(),
    addr: addr.to_string(),
    status: Joining,
    labels,
    shard_count: 0,
    load_score: 0.0,
    joined_at: 0,
    last_active_at: 0,
    heartbeat_timeouts: 0,
  }

  // 创建节点状态
  let state = NodeState::new(info)
  self.nodes.set(node_id.to_string(), state)
  self.node_addrs.set(node_id.to_string(), addr)

  // 转换到 Active 状态
  match self.nodes.get(node_id) {
    Some(state) => {
      let _ = state.transition_to(Active)
    }
    None => ()
  }

  Ok(node_id)
}

///|
/// 注销节点
pub fn NodeManager::deregister_node(
  self : NodeManager,
  node_id : String,
) -> Result[Unit, ClusterError] {
  if !self.nodes.contains(node_id) {
    return Err(Node_Not_Found)
  }

  // 检查节点状态
  match self.nodes.get(node_id) {
    Some(state) => {
      if state.get_status() == Active {
        // 先转换到 Leaving 状态
        let _ = state.transition_to(Leaving)
      }

      // 转换到 Left 状态
      let _ = state.transition_to(Left)
    }
    None => return Err(Node_Not_Found)
  }

  // 移除节点
  self.nodes.remove(node_id.to_string())
  self.node_addrs.remove(node_id)

  Ok(())
}

///|
/// 获取节点状态
pub fn NodeManager::get_node_state(
  self : NodeManager,
  node_id : String,
) -> NodeState? {
  self.nodes.get(node_id)
}

///|
/// 获取节点信息
pub fn NodeManager::get_node_info(
  self : NodeManager,
  node_id : String,
) -> NodeInfo? {
  match self.nodes.get(node_id) {
    Some(state) => Some(state.get_info())
    None => None
  }
}

///|
/// 获取所有节点
pub fn NodeManager::get_all_nodes(self : NodeManager) -> Array[NodeInfo] {
  let result : Array[NodeInfo] = []
  for (_, state) in self.nodes {
    result.push(state.get_info())
  }
  result
}

///|
/// 获取活跃节点
pub fn NodeManager::get_active_nodes(self : NodeManager) -> Array[NodeInfo] {
  let result : Array[NodeInfo] = []
  for (_, state) in self.nodes {
    if state.is_active() {
      result.push(state.get_info())
    }
  }
  result
}

///|
/// 获取可用节点
pub fn NodeManager::get_available_nodes(self : NodeManager) -> Array[NodeInfo] {
  let result : Array[NodeInfo] = []
  for (_, state) in self.nodes {
    if state.is_healthy() {
      result.push(state.get_info())
    }
  }
  result
}

///|
/// 根据标签选择节点
pub fn NodeManager::select_nodes_by_label(
  self : NodeManager,
  selector : Map[String, String],
) -> Array[NodeInfo] {
  let result : Array[NodeInfo] = []
  for (_, state) in self.nodes {
    if state.is_healthy() &&
      self.label_matcher.matches(state.get_info().labels, selector) {
      result.push(state.get_info())
    }
  }
  result
}

///|
/// 更新节点心跳
pub fn NodeManager::update_heartbeat(
  self : NodeManager,
  node_id : String,
) -> Result[Unit, ClusterError] {
  let state = match self.nodes.get(node_id) {
    Some(s) => s
    None => return Err(Node_Not_Found)
  }

  state.update_heartbeat()
  Ok(())
}

///|
/// 标记节点心跳超时
pub fn NodeManager::mark_heartbeat_timeout(
  self : NodeManager,
  node_id : String,
) -> Result[Unit, ClusterError] {
  let state = match self.nodes.get(node_id) {
    Some(s) => s
    None => return Err(Node_Not_Found)
  }

  let timeouts = state.increment_heartbeat_timeout()

  // 连续 3 次超时标记为 Suspect
  if timeouts >= self.config.heartbeat_timeout_count {
    let _ = state.transition_to(Suspect)
  }

  Ok(())
}

///|
/// 标记节点为 Suspect
pub fn NodeManager::mark_suspect(
  self : NodeManager,
  node_id : String,
) -> Result[Unit, ClusterError] {
  let state = match self.nodes.get(node_id) {
    Some(s) => s
    None => return Err(Node_Not_Found)
  }

  state.transition_to(Suspect)
}

///|
/// 标记节点为 Dead
pub fn NodeManager::mark_dead(
  self : NodeManager,
  node_id : String,
) -> Result[Unit, ClusterError] {
  let state = match self.nodes.get(node_id) {
    Some(s) => s
    None => return Err(Node_Not_Found)
  }

  state.transition_to(Dead)
}

///|
/// 恢复节点为 Active
pub fn NodeManager::recover_node(
  self : NodeManager,
  node_id : String,
) -> Result[Unit, ClusterError] {
  let state = match self.nodes.get(node_id) {
    Some(s) => s
    None => return Err(Node_Not_Found)
  }

  state.reset_heartbeat_timeout()
  state.transition_to(Active)
}

///|
/// 获取节点数量
pub fn NodeManager::node_count(self : NodeManager) -> Int32 {
  self.nodes.length()
}

///|
/// 获取活跃节点数量
pub fn NodeManager::active_node_count(self : NodeManager) -> Int32 {
  let mut count = 0
  for (_, state) in self.nodes {
    if state.is_active() {
      count = count + 1
    }
  }
  count
}

///|
/// 校验节点 ID
fn NodeManager::validate_node_id(self : NodeManager, node_id : String) -> Bool {
  let _ = self
  // 简化校验：长度 1-64
  node_id.length() > 0 && node_id.length() <= 64
}

///|
/// 获取节点地址
pub fn NodeManager::get_node_addr(
  self : NodeManager,
  node_id : String,
) -> String? {
  self.node_addrs.get(node_id)
}

///|
/// 检查节点是否存在
pub fn NodeManager::node_exists(self : NodeManager, node_id : String) -> Bool {
  self.nodes.contains(node_id)
}

///|
/// 创建节点管理器
pub fn create_node_manager(config : ClusterConfig) -> NodeManager {
  NodeManager::new(config)
}

///|
/// 创建默认节点管理器
pub fn create_default_node_manager() -> NodeManager {
  NodeManager::new(ClusterConfig::default())
}
