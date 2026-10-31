// 跨集群复制模块 - 核心类型定义
//
// 定义复制拓扑、冲突检测、复制任务等核心数据结构

///|
/// 复制拓扑类型
pub(all) enum ReplicationTopology {
  /// 主从复制
  Primary_Replica
  /// 多主复制
  Multi_Master
  /// 环形复制
  Ring
  /// 星型复制
  Star
  /// 全连接复制
  Full_Mesh
}

///|
pub impl Eq for ReplicationTopology with fn equal(self, other) -> Bool {
  match (self, other) {
    (Primary_Replica, Primary_Replica) => true
    (Multi_Master, Multi_Master) => true
    (Ring, Ring) => true
    (Star, Star) => true
    (Full_Mesh, Full_Mesh) => true
    _ => false
  }
}

///|
pub extend ReplicationTopology with Eq::{equal, not_equal}

///|
pub impl Debug for ReplicationTopology with fn to_repr(self) -> Repr {
  match self {
    Primary_Replica => Repr::ctor("Primary_Replica", [])
    Multi_Master => Repr::ctor("Multi_Master", [])
    Ring => Repr::ctor("Ring", [])
    Star => Repr::ctor("Star", [])
    Full_Mesh => Repr::ctor("Full_Mesh", [])
  }
}

///|
pub extend ReplicationTopology with Debug::{to_repr}

///|
/// 复制模式
pub(all) enum ReplicationMode {
  /// 同步复制
  Sync
  /// 异步复制
  Async
  /// 半同步复制
  Semi_Sync
} derive(Debug)

///|
pub extend ReplicationMode with Debug::{to_repr}

///|
pub impl Eq for ReplicationMode with fn equal(self, other) -> Bool {
  match (self, other) {
    (Sync, Sync) => true
    (Async, Async) => true
    (Semi_Sync, Semi_Sync) => true
    _ => false
  }
}

///|
pub extend ReplicationMode with Eq::{equal, not_equal}

///|
/// 复制状态
pub(all) enum ReplicationStatus {
  /// 初始化
  Initializing
  /// 运行中
  Running
  /// 暂停
  Paused
  /// 停止
  Stopped
  /// 错误
  Error
  /// 断开连接
  Disconnected
} derive(Debug)

///|
pub extend ReplicationStatus with Debug::{to_repr}

///|
pub impl Eq for ReplicationStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Initializing, Initializing) => true
    (Running, Running) => true
    (Paused, Paused) => true
    (Stopped, Stopped) => true
    (Error, Error) => true
    (Disconnected, Disconnected) => true
    _ => false
  }
}

///|
pub extend ReplicationStatus with Eq::{equal, not_equal}

///|
/// 冲突解决策略
pub(all) enum ConflictResolutionStrategy {
  /// 时间戳优先
  Timestamp
  /// 版本号优先
  Version
  /// 源节点优先
  Source_Priority
  /// 目标节点优先
  Target_Priority
  /// 自定义
  Custom
} derive(Debug)

///|
pub extend ConflictResolutionStrategy with Debug::{to_repr}

///|
pub impl Eq for ConflictResolutionStrategy with fn equal(self, other) -> Bool {
  match (self, other) {
    (Timestamp, Timestamp) => true
    (Version, Version) => true
    (Source_Priority, Source_Priority) => true
    (Target_Priority, Target_Priority) => true
    (Custom, Custom) => true
    _ => false
  }
}

///|
pub extend ConflictResolutionStrategy with Eq::{equal, not_equal}

///|
/// 集群信息
pub(all) struct ClusterInfo {
  /// 集群 ID
  cluster_id : String
  /// 集群名称
  cluster_name : String
  /// 集群地址
  cluster_addr : String
  /// 节点列表
  nodes : Array[NodeInfo]
  /// 创建时间
  created_at : Int32
  /// 最后活跃时间
  last_active_at : Int32
}

///|
/// 节点信息
pub(all) struct NodeInfo {
  /// 节点 ID
  node_id : String
  /// 节点地址
  node_addr : String
  /// 是否主节点
  is_primary : Bool
  /// 优先级
  priority : Int32
  /// 延迟（毫秒）
  latency_ms : Int32
  /// 是否健康
  is_healthy : Bool
}

///|
/// 复制任务
pub(all) struct ReplicationTask {
  /// 任务 ID
  task_id : String
  /// 任务名称
  task_name : String
  /// 源集群
  source_cluster : ClusterInfo
  /// 目标集群
  target_cluster : ClusterInfo
  /// 复制拓扑
  topology : ReplicationTopology
  /// 复制模式
  mode : ReplicationMode
  /// 复制状态
  mut status : ReplicationStatus
  /// 冲突解决策略
  conflict_strategy : ConflictResolutionStrategy
  /// 创建时间
  created_at : Int32
  /// 更新时间
  mut updated_at : Int32
  /// 已复制记录数
  replicated_records : Int32
  /// 总记录数
  total_records : Int32
  /// 延迟（毫秒）
  replication_lag_ms : Int32
  /// 错误信息
  error_message : String?
}

///|
/// 复制任务配置
pub(all) struct ReplicationTaskConfig {
  /// 任务名称
  task_name : String
  /// 源集群 ID
  source_cluster_id : String
  /// 目标集群 ID
  target_cluster_id : String
  /// 复制拓扑
  topology : ReplicationTopology
  /// 复制模式
  mode : ReplicationMode
  /// 冲突解决策略
  conflict_strategy : ConflictResolutionStrategy
  /// 批次大小
  batch_size : Int32
  /// 复制间隔（毫秒）
  replication_interval_ms : Int32
  /// 是否启用断点续传
  enable_checkpoint : Bool
  /// 最大重试次数
  max_retries : Int32
  /// 重试间隔（毫秒）
  retry_interval_ms : Int32
}

///|
/// 复制日志
pub(all) struct ReplicationLog {
  /// 日志 ID
  log_id : String
  /// 任务 ID
  task_id : String
  /// 操作类型
  operation : String
  /// 键
  key : String
  /// 值
  value : @realtime_db.Value?
  /// 时间戳
  timestamp : Int32
  /// 源集群
  source_cluster : String
  /// 目标集群
  target_cluster : String
  /// 是否成功
  success : Bool
  /// 错误信息
  error_message : String?
}

///|
/// 冲突记录
pub(all) struct ConflictRecord {
  /// 冲突 ID
  conflict_id : String
  /// 任务 ID
  task_id : String
  /// 键
  key : String
  /// 源值
  source_value : @realtime_db.Value
  /// 目标值
  target_value : @realtime_db.Value
  /// 源时间戳
  source_timestamp : Int32
  /// 目标时间戳
  target_timestamp : Int32
  /// 源版本
  source_version : Int32
  /// 目标版本
  target_version : Int32
  /// 解决策略
  resolution_strategy : ConflictResolutionStrategy
  /// 解决后的值
  resolved_value : @realtime_db.Value?
  /// 解决时间
  resolved_at : Int32
}

///|
/// 复制错误类型
pub(all) enum ReplicationError {
  /// 任务已存在
  Task_Already_Exists
  /// 任务不存在
  Task_Not_Found
  /// 集群不存在
  Cluster_Not_Found
  /// 连接失败
  Connection_Failed
  /// 认证失败
  Authentication_Failed
  /// 复制超时
  Replication_Timeout
  /// 数据不一致
  Data_Inconsistency
  /// 冲突检测失败
  Conflict_Detection_Failed
  /// 冲突解决失败
  Conflict_Resolution_Failed
  /// 断点续传失败
  Checkpoint_Failed
  /// 内部错误
  Internal_Error(String)
}

///|
pub impl Eq for ReplicationError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Task_Already_Exists, Task_Already_Exists) => true
    (Task_Not_Found, Task_Not_Found) => true
    (Cluster_Not_Found, Cluster_Not_Found) => true
    (Connection_Failed, Connection_Failed) => true
    (Authentication_Failed, Authentication_Failed) => true
    (Replication_Timeout, Replication_Timeout) => true
    (Data_Inconsistency, Data_Inconsistency) => true
    (Conflict_Detection_Failed, Conflict_Detection_Failed) => true
    (Conflict_Resolution_Failed, Conflict_Resolution_Failed) => true
    (Checkpoint_Failed, Checkpoint_Failed) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend ReplicationError with Eq::{equal, not_equal}

///|
pub impl Debug for ReplicationError with fn to_repr(self) -> Repr {
  match self {
    Task_Already_Exists => Repr::ctor("Task_Already_Exists", [])
    Task_Not_Found => Repr::ctor("Task_Not_Found", [])
    Cluster_Not_Found => Repr::ctor("Cluster_Not_Found", [])
    Connection_Failed => Repr::ctor("Connection_Failed", [])
    Authentication_Failed => Repr::ctor("Authentication_Failed", [])
    Replication_Timeout => Repr::ctor("Replication_Timeout", [])
    Data_Inconsistency => Repr::ctor("Data_Inconsistency", [])
    Conflict_Detection_Failed => Repr::ctor("Conflict_Detection_Failed", [])
    Conflict_Resolution_Failed => Repr::ctor("Conflict_Resolution_Failed", [])
    Checkpoint_Failed => Repr::ctor("Checkpoint_Failed", [])
    Internal_Error(msg) => Repr::ctor("Internal_Error", [(None, Repr(msg))])
  }
}

///|
pub extend ReplicationError with Debug::{to_repr}

///|
/// 获取错误码
pub fn ReplicationError::code(self : ReplicationError) -> Int32 {
  match self {
    Task_Already_Exists => 5001
    Task_Not_Found => 5002
    Cluster_Not_Found => 5003
    Connection_Failed => 5004
    Authentication_Failed => 5005
    Replication_Timeout => 5006
    Data_Inconsistency => 5007
    Conflict_Detection_Failed => 5008
    Conflict_Resolution_Failed => 5009
    Checkpoint_Failed => 5010
    Internal_Error(_) => 5099
  }
}

///|
/// 获取错误消息
pub fn ReplicationError::message(self : ReplicationError) -> String {
  match self {
    Task_Already_Exists => "Replication task already exists"
    Task_Not_Found => "Replication task not found"
    Cluster_Not_Found => "Cluster not found"
    Connection_Failed => "Connection failed"
    Authentication_Failed => "Authentication failed"
    Replication_Timeout => "Replication timeout"
    Data_Inconsistency => "Data inconsistency detected"
    Conflict_Detection_Failed => "Conflict detection failed"
    Conflict_Resolution_Failed => "Conflict resolution failed"
    Checkpoint_Failed => "Checkpoint failed"
    Internal_Error(msg) => "Internal error: " + msg
  }
}

///|
/// 转为字符串
pub fn ReplicationError::to_string(self : ReplicationError) -> String {
  "[Error " + self.code().to_string() + "] " + self.message()
}

///|
/// 复制统计
pub(all) struct ReplicationStats {
  /// 任务 ID
  task_id : String
  /// 总记录数
  total_records : Int32
  /// 已复制记录数
  replicated_records : Int32
  /// 失败记录数
  failed_records : Int32
  /// 冲突记录数
  conflict_records : Int32
  /// 平均延迟（毫秒）
  avg_latency_ms : Double
  /// P99 延迟（毫秒）
  p99_latency_ms : Int32
  /// 复制吞吐量（条/秒）
  throughput_qps : Double
  /// 复制延迟（毫秒）
  replication_lag_ms : Int32
}
