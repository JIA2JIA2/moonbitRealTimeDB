// 心跳服务模块
//
// 实现心跳发送、接收、超时检测

///|
/// 心跳消息
pub(all) struct HeartbeatMessage {
  /// 节点 ID
  node_id : String
  /// 时间戳
  timestamp : Int
  /// 节点状态
  status : NodeStatus
  /// 分片数量
  shard_count : Int
  /// 负载分数
  load_score : Double
  /// 路由表版本
  route_version : Int
}

///|
/// 心跳响应
pub(all) struct HeartbeatResponse {
  /// 是否成功
  success : Bool
  /// 集群状态
  cluster_status : String
  /// 路由表版本
  route_version : Int
  /// 时间戳
  timestamp : Int
  /// 错误信息
  error_message : String
}

///|
/// 心跳服务
pub(all) struct HeartbeatService {
  /// 节点管理器
  node_manager : NodeManager
  /// 心跳间隔（毫秒）
  heartbeat_interval_ms : Int
  /// 心跳超时次数阈值
  timeout_threshold : Int
  /// 疑似故障超时（毫秒）
  suspect_timeout_ms : Int
  /// 上次心跳时间映射
  mut last_heartbeat_times : Map[String, Int]
  /// 是否在运行
  mut is_running : Bool
}

///|
/// 创建心跳服务
pub fn HeartbeatService::new(
  node_manager : NodeManager,
  config : ClusterConfig,
) -> HeartbeatService {
  {
    node_manager,
    heartbeat_interval_ms: config.heartbeat_interval_ms,
    timeout_threshold: config.heartbeat_timeout_count,
    suspect_timeout_ms: config.suspect_timeout_ms,
    last_heartbeat_times: Map([]),
    is_running: false,
  }
}

///|
/// 发送心跳
pub fn HeartbeatService::send_heartbeat(
  self : HeartbeatService,
  node_id : String,
  status : NodeStatus,
  shard_count : Int,
  load_score : Double,
  route_version : Int,
) -> HeartbeatMessage {
  let _ = self
  HeartbeatMessage::{
    node_id,
    timestamp: 0, // 使用实际时钟
    status,
    shard_count,
    load_score,
    route_version,
  }
}

///|
/// 接收心跳
pub fn HeartbeatService::receive_heartbeat(
  self : HeartbeatService,
  msg : HeartbeatMessage,
) -> HeartbeatResponse {
  // 检查节点是否存在
  if !self.node_manager.node_exists(msg.node_id.to_string()) {
    return HeartbeatResponse::{
      success: false,
      cluster_status: "unknown".to_string(),
      route_version: 0,
      timestamp: 0,
      error_message: "Node not found".to_string(),
    }
  }

  // 更新心跳时间
  self.last_heartbeat_times.set(msg.node_id.to_string(), msg.timestamp)

  // 更新节点状态
  match self.node_manager.get_node_state(msg.node_id.to_string()) {
    Some(state) => {
      state.update_heartbeat()

      // 如果节点是 Suspect 状态，恢复为 Active
      if state.get_status() == Suspect {
        let _ = self.node_manager.recover_node(msg.node_id)
      }
    }
    None => ()
  }

  HeartbeatResponse::{
    success: true,
    cluster_status: "healthy".to_string(),
    route_version: msg.route_version,
    timestamp: 0,
    error_message: "".to_string(),
  }
}

///|
/// 检查心跳超时
pub fn HeartbeatService::check_timeouts(
  self : HeartbeatService,
  current_time : Int,
) -> Array[String] {
  let timed_out_nodes : Array[String] = []

  for (node_id, last_time) in self.last_heartbeat_times {
    let elapsed = current_time - last_time

    // 检查是否超时
    if elapsed > self.heartbeat_interval_ms * self.timeout_threshold {
      // 标记心跳超时
      match self.node_manager.mark_heartbeat_timeout(node_id.to_string()) {
        Ok(_) =>
          // 检查是否需要标记为 Suspect
          match self.node_manager.get_node_state(node_id.to_string()) {
            Some(state) =>
              if state.get_heartbeat_timeouts() >= self.timeout_threshold {
                timed_out_nodes.push(node_id)
              }
            None => ()
          }
        Err(_) => ()
      }
    }
  }

  timed_out_nodes
}

///|
/// 标记节点为 Suspect
pub fn HeartbeatService::mark_suspect(
  self : HeartbeatService,
  node_id : String,
) -> Result[Unit, ClusterError] {
  self.node_manager.mark_suspect(node_id)
}

///|
/// 标记节点为 Dead
pub fn HeartbeatService::mark_dead(
  self : HeartbeatService,
  node_id : String,
) -> Result[Unit, ClusterError] {
  self.node_manager.mark_dead(node_id)
}

///|
/// 启动心跳服务
pub fn HeartbeatService::start(self : HeartbeatService) -> Unit {
  self.is_running = true
}

///|
/// 停止心跳服务
pub fn HeartbeatService::stop(self : HeartbeatService) -> Unit {
  self.is_running = false
}

///|
/// 检查是否在运行
pub fn HeartbeatService::is_running(self : HeartbeatService) -> Bool {
  self.is_running
}

///|
/// 获取节点最后心跳时间
pub fn HeartbeatService::get_last_heartbeat(
  self : HeartbeatService,
  node_id : String,
) -> Int {
  match self.last_heartbeat_times.get(node_id) {
    Some(t) => t
    None => 0
  }
}

///|
/// 移除节点心跳记录
pub fn HeartbeatService::remove_node(
  self : HeartbeatService,
  node_id : String,
) -> Unit {
  self.last_heartbeat_times.remove(node_id)
}

///|
/// 创建心跳服务
pub fn create_heartbeat_service(
  node_manager : NodeManager,
  config : ClusterConfig,
) -> HeartbeatService {
  HeartbeatService::new(node_manager, config)
}
