// 集群核心类型定义
//
// 定义节点、分片、副本、路由表、错误类型等核心数据结构

///|
/// 节点状态枚举
///
/// 状态流转：
/// - Joining → Active（节点加入集群）
/// - Active → Suspect（心跳超时）
/// - Suspect → Dead（超时未恢复）
/// - Dead → Left（节点离开）
/// - Active → Leaving（节点主动离开）
/// - Leaving → Left（离开完成）
pub(all) enum NodeStatus {
  /// 加入中：节点正在加入集群
  Joining
  /// 活跃：节点正常服务
  Active
  /// 疑似故障：心跳超时
  Suspect
  /// 离开中：节点正在离开
  Leaving
  /// 已离开：节点已离开集群
  Left
  /// 已下线：节点不可用
  Dead
}

///|
impl Eq for NodeStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Joining, Joining) => true
    (Active, Active) => true
    (Suspect, Suspect) => true
    (Leaving, Leaving) => true
    (Left, Left) => true
    (Dead, Dead) => true
    _ => false
  }
}

///|
pub extend NodeStatus with Eq::{equal, not_equal}

///|
impl Debug for NodeStatus with fn to_repr(self) -> Repr {
  match self {
    Joining => Repr::ctor("Joining", [])
    Active => Repr::ctor("Active", [])
    Suspect => Repr::ctor("Suspect", [])
    Leaving => Repr::ctor("Leaving", [])
    Left => Repr::ctor("Left", [])
    Dead => Repr::ctor("Dead", [])
  }
}

///|
pub extend NodeStatus with Debug::{to_repr}

///|
/// 验证状态转换是否合法
pub fn NodeStatus::can_transition_to(
  self : NodeStatus,
  new_status : NodeStatus,
) -> Bool {
  match (self, new_status) {
    (Joining, Active) => true
    (Active, Suspect) => true
    (Active, Leaving) => true
    (Suspect, Active) => true
    (Suspect, Dead) => true
    (Dead, Left) => true
    (Leaving, Left) => true
    (Active, Active) => true // 保持活跃状态
    _ => false
  }
}

///|
/// 判断节点是否可用
pub fn NodeStatus::is_available(self : NodeStatus) -> Bool {
  match self {
    Active => true
    Joining => true
    _ => false
  }
}

///|
/// 判断节点是否健康
pub fn NodeStatus::is_healthy(self : NodeStatus) -> Bool {
  match self {
    Active => true
    Joining => true
    Suspect => false
    Leaving => false
    Left => false
    Dead => false
  }
}

///|
/// 分片状态枚举
///
/// 状态流转：
/// - Creating → Active（分片创建完成）
/// - Active → Moving（分片迁移中）
/// - Moving → Active（迁移完成）
/// - Active → Deleting（分片删除中）
/// - Deleting → 删除完成
/// - 任意状态 → Failed（失败）
pub(all) enum ShardStatus {
  /// 创建中：分片正在创建
  Creating
  /// 活跃：分片正常服务
  Active
  /// 迁移中：分片正在迁移
  Moving
  /// 删除中：分片正在删除
  Deleting
  /// 失败：分片不可用
  Failed
}

///|
impl Eq for ShardStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Creating, Creating) => true
    (Active, Active) => true
    (Moving, Moving) => true
    (Deleting, Deleting) => true
    (Failed, Failed) => true
    _ => false
  }
}

///|
pub extend ShardStatus with Eq::{equal, not_equal}

///|
impl Debug for ShardStatus with fn to_repr(self) -> Repr {
  match self {
    Creating => Repr::ctor("Creating", [])
    Active => Repr::ctor("Active", [])
    Moving => Repr::ctor("Moving", [])
    Deleting => Repr::ctor("Deleting", [])
    Failed => Repr::ctor("Failed", [])
  }
}

///|
pub extend ShardStatus with Debug::{to_repr}

///|
/// 验证状态转换是否合法
pub fn ShardStatus::can_transition_to(
  self : ShardStatus,
  new_status : ShardStatus,
) -> Bool {
  match (self, new_status) {
    (Creating, Active) => true
    (Active, Moving) => true
    (Active, Deleting) => true
    (Moving, Active) => true
    (Moving, Failed) => true
    (Deleting, Failed) => true
    (Active, Active) => true // 保持活跃状态
    (Creating, Creating) => true // 保持创建状态
    _ => false
  }
}

///|
/// 判断分片是否可读
pub fn ShardStatus::is_readable(self : ShardStatus) -> Bool {
  match self {
    Active => true
    Moving => true // 迁移中源分片可读
    _ => false
  }
}

///|
/// 判断分片是否可写
pub fn ShardStatus::is_writable(self : ShardStatus) -> Bool {
  match self {
    Active => true
    Moving => false // 迁移中源分片只读
    _ => false
  }
}

///|
/// 副本角色枚举
pub(all) enum ReplicaRole {
  /// 主副本：处理写请求
  Primary
  /// 从副本：处理读请求
  Secondary
}

///|
impl Eq for ReplicaRole with fn equal(self, other) -> Bool {
  match (self, other) {
    (Primary, Primary) => true
    (Secondary, Secondary) => true
    _ => false
  }
}

///|
pub extend ReplicaRole with Eq::{equal, not_equal}

///|
impl Debug for ReplicaRole with fn to_repr(self) -> Repr {
  match self {
    Primary => Repr::ctor("Primary", [])
    Secondary => Repr::ctor("Secondary", [])
  }
}

///|
pub extend ReplicaRole with Debug::{to_repr}

///|
/// 副本结构体
pub(all) struct Replica {
  /// 副本 ID
  id : String
  /// 节点 ID
  node_id : String
  /// 副本角色
  role : ReplicaRole
  /// 延迟（毫秒）
  latency_ms : Int32
  /// 是否健康
  is_healthy : Bool
  /// 最后心跳时间
  last_heartbeat : Int32
}

///|
/// 分片键范围
pub(all) struct ShardKeyRange {
  /// 起始键（包含）
  start_key : String
  /// 结束键（不包含）
  end_key : String
}

///|
/// 分片信息结构体
pub(all) struct ShardInfo {
  /// 分片 ID
  id : String
  /// 副本列表
  replicas : Array[Replica]
  /// 主节点 ID
  primary_node_id : String
  /// 分片状态
  mut status : ShardStatus
  /// 版本号
  mut version : Int32
  /// 键范围
  key_range : ShardKeyRange
  /// 分片大小（字节）
  size_bytes : Int32
  /// 创建时间
  created_at : Int32
  /// 更新时间
  updated_at : Int32
}

///|
/// 路由条目
pub(all) struct RoutingEntry {
  /// 分片 ID
  shard_id : String
  /// 主节点地址
  primary_addr : String
  /// 副本地址列表
  replica_addrs : Array[String]
  /// 版本号
  version : Int32
}

///|
/// 路由表结构体
pub(all) struct RoutingTable {
  /// 路由条目映射：分片ID -> 路由条目
  entries : Map[String, RoutingEntry]
  /// 分片键映射：哈希值 -> 分片ID
  shard_mapping : Map[Int32, String]
  /// 版本号
  mut version : Int32
  /// 更新时间
  updated_at : Int32
}

///|
/// 创建路由表
pub fn RoutingTable::new() -> RoutingTable {
  { entries: Map([]), shard_mapping: Map([]), version: 0, updated_at: 0, }
}

///|
/// 添加路由条目
pub fn RoutingTable::add_entry(
  self : RoutingTable,
  entry : RoutingEntry,
) -> Unit {
  self.entries.set(entry.shard_id, entry)
  self.version = self.version + 1
}

///|
/// 获取路由条目
pub fn RoutingTable::get_entry(
  self : RoutingTable,
  shard_id : String,
) -> RoutingEntry? {
  self.entries.get(shard_id)
}

///|
/// 删除路由条目
pub fn RoutingTable::remove_entry(
  self : RoutingTable,
  shard_id : String,
) -> Unit {
  self.entries.remove(shard_id)
  self.version = self.version + 1
}

///|
/// 获取所有路由条目
pub fn RoutingTable::get_all_entries(
  self : RoutingTable,
) -> Array[RoutingEntry] {
  let result : Array[RoutingEntry] = []
  for (_, entry) in self.entries {
    result.push(entry)
  }
  result
}

///|
/// 获取版本号
pub fn RoutingTable::get_version(self : RoutingTable) -> Int32 {
  self.version
}

///|
/// 节点信息结构体
pub(all) struct NodeInfo {
  /// 节点 ID
  id : String
  /// 节点地址
  addr : String
  /// 节点状态
  mut status : NodeStatus
  /// 节点标签
  labels : Map[String, String]
  /// 分片数量
  mut shard_count : Int32
  /// 负载分数
  mut load_score : Double
  /// 加入时间
  joined_at : Int32
  /// 最后活跃时间
  mut last_active_at : Int32
  /// 心跳超时次数
  mut heartbeat_timeouts : Int32
}

///|
/// 集群错误枚举
pub(all) enum ClusterError {
  // 节点错误 (1001-1010)
  /// 无效节点 ID
  Invalid_Node_Id
  /// 认证失败
  Auth_Failed
  /// 节点已存在
  Node_Already_Exists
  /// 节点不存在
  Node_Not_Found
  /// 节点不可用
  Node_Unavailable
  /// 节点状态错误
  Node_Invalid_State

  // 分片错误 (1101-1110)
  /// 无效分片 ID
  Invalid_Shard_Id
  /// 分片已存在
  Shard_Already_Exists
  /// 分片不存在
  Shard_Not_Found
  /// 分片不可用
  Shard_Unavailable
  /// 分片状态错误
  Shard_Invalid_State

  // 路由错误 (1201-1210)
  /// 路由未找到
  Route_Not_Found
  /// 路由过期
  Route_Expired
  /// 路由冲突
  Route_Conflict

  // Raft 错误 (1301-1310)
  /// 任期过期
  Stale_Term
  /// 日志过时
  Log_Outdated
  /// 已投票
  Already_Voted
  /// 不是领导者
  Not_Leader
  /// 选主超时
  Election_Timeout

  // 故障转移错误 (1401-1410)
  /// 无候选节点
  No_Candidate
  /// 转移失败
  Failover_Failed

  // 再平衡错误 (1501-1510)
  /// 再平衡进行中
  Rebalance_In_Progress
  /// 迁移失败
  Migration_Failed

  // 通用错误
  /// 超时
  Timeout
  /// 内部错误
  Internal_Error(String)
  /// 无效配置
  Invalid_Config
  /// 资源不足
  Resource_Exhausted
}

///|
impl Eq for ClusterError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Invalid_Node_Id, Invalid_Node_Id) => true
    (Auth_Failed, Auth_Failed) => true
    (Node_Already_Exists, Node_Already_Exists) => true
    (Node_Not_Found, Node_Not_Found) => true
    (Node_Unavailable, Node_Unavailable) => true
    (Node_Invalid_State, Node_Invalid_State) => true
    (Invalid_Shard_Id, Invalid_Shard_Id) => true
    (Shard_Already_Exists, Shard_Already_Exists) => true
    (Shard_Not_Found, Shard_Not_Found) => true
    (Shard_Unavailable, Shard_Unavailable) => true
    (Shard_Invalid_State, Shard_Invalid_State) => true
    (Route_Not_Found, Route_Not_Found) => true
    (Route_Expired, Route_Expired) => true
    (Route_Conflict, Route_Conflict) => true
    (Stale_Term, Stale_Term) => true
    (Log_Outdated, Log_Outdated) => true
    (Already_Voted, Already_Voted) => true
    (Not_Leader, Not_Leader) => true
    (Election_Timeout, Election_Timeout) => true
    (No_Candidate, No_Candidate) => true
    (Failover_Failed, Failover_Failed) => true
    (Rebalance_In_Progress, Rebalance_In_Progress) => true
    (Migration_Failed, Migration_Failed) => true
    (Timeout, Timeout) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    (Invalid_Config, Invalid_Config) => true
    (Resource_Exhausted, Resource_Exhausted) => true
    _ => false
  }
}

///|
pub extend ClusterError with Eq::{equal, not_equal}

///|
impl Debug for ClusterError with fn to_repr(self) -> Repr {
  match self {
    Invalid_Node_Id => Repr::ctor("Invalid_Node_Id", [])
    Auth_Failed => Repr::ctor("Auth_Failed", [])
    Node_Already_Exists => Repr::ctor("Node_Already_Exists", [])
    Node_Not_Found => Repr::ctor("Node_Not_Found", [])
    Node_Unavailable => Repr::ctor("Node_Unavailable", [])
    Node_Invalid_State => Repr::ctor("Node_Invalid_State", [])
    Invalid_Shard_Id => Repr::ctor("Invalid_Shard_Id", [])
    Shard_Already_Exists => Repr::ctor("Shard_Already_Exists", [])
    Shard_Not_Found => Repr::ctor("Shard_Not_Found", [])
    Shard_Unavailable => Repr::ctor("Shard_Unavailable", [])
    Shard_Invalid_State => Repr::ctor("Shard_Invalid_State", [])
    Route_Not_Found => Repr::ctor("Route_Not_Found", [])
    Route_Expired => Repr::ctor("Route_Expired", [])
    Route_Conflict => Repr::ctor("Route_Conflict", [])
    Stale_Term => Repr::ctor("Stale_Term", [])
    Log_Outdated => Repr::ctor("Log_Outdated", [])
    Already_Voted => Repr::ctor("Already_Voted", [])
    Not_Leader => Repr::ctor("Not_Leader", [])
    Election_Timeout => Repr::ctor("Election_Timeout", [])
    No_Candidate => Repr::ctor("No_Candidate", [])
    Failover_Failed => Repr::ctor("Failover_Failed", [])
    Rebalance_In_Progress => Repr::ctor("Rebalance_In_Progress", [])
    Migration_Failed => Repr::ctor("Migration_Failed", [])
    Timeout => Repr::ctor("Timeout", [])
    Internal_Error(msg) => Repr::ctor("Internal_Error", [(None, Repr(msg))])
    Invalid_Config => Repr::ctor("Invalid_Config", [])
    Resource_Exhausted => Repr::ctor("Resource_Exhausted", [])
  }
}

///|
pub extend ClusterError with Debug::{to_repr}

///|
/// 获取错误码
pub fn ClusterError::code(self : ClusterError) -> Int32 {
  match self {
    Invalid_Node_Id => 1001
    Auth_Failed => 1002
    Node_Already_Exists => 1003
    Node_Not_Found => 1004
    Node_Unavailable => 1005
    Node_Invalid_State => 1006
    Invalid_Shard_Id => 1101
    Shard_Already_Exists => 1102
    Shard_Not_Found => 1103
    Shard_Unavailable => 1104
    Shard_Invalid_State => 1105
    Route_Not_Found => 1201
    Route_Expired => 1202
    Route_Conflict => 1203
    Stale_Term => 1301
    Log_Outdated => 1302
    Already_Voted => 1303
    Not_Leader => 1304
    Election_Timeout => 1305
    No_Candidate => 1401
    Failover_Failed => 1402
    Rebalance_In_Progress => 1501
    Migration_Failed => 1502
    Timeout => 9001
    Internal_Error(_) => 9002
    Invalid_Config => 9003
    Resource_Exhausted => 9004
  }
}

///|
/// 获取错误消息
pub fn ClusterError::message(self : ClusterError) -> String {
  match self {
    Invalid_Node_Id => "Invalid node ID"
    Auth_Failed => "Authentication failed"
    Node_Already_Exists => "Node already exists"
    Node_Not_Found => "Node not found"
    Node_Unavailable => "Node unavailable"
    Node_Invalid_State => "Invalid node state"
    Invalid_Shard_Id => "Invalid shard ID"
    Shard_Already_Exists => "Shard already exists"
    Shard_Not_Found => "Shard not found"
    Shard_Unavailable => "Shard unavailable"
    Shard_Invalid_State => "Invalid shard state"
    Route_Not_Found => "Route not found"
    Route_Expired => "Route expired"
    Route_Conflict => "Route conflict"
    Stale_Term => "Stale term"
    Log_Outdated => "Log outdated"
    Already_Voted => "Already voted"
    Not_Leader => "Not leader"
    Election_Timeout => "Election timeout"
    No_Candidate => "No candidate"
    Failover_Failed => "Failover failed"
    Rebalance_In_Progress => "Rebalance in progress"
    Migration_Failed => "Migration failed"
    Timeout => "Operation timeout"
    Internal_Error(msg) => "Internal error: " + msg
    Invalid_Config => "Invalid configuration"
    Resource_Exhausted => "Resource exhausted"
  }
}

///|
/// 转为字符串
pub fn ClusterError::to_string(self : ClusterError) -> String {
  "[Error " + self.code().to_string() + "] " + self.message()
}

///|
/// Raft 错误枚举
pub(all) enum RaftError {
  /// 任期过期
  Stale_Term
  /// 日志过时
  Log_Outdated
  /// 已投票
  Already_Voted
  /// 不是领导者
  Not_Leader
  /// 选主超时
  Election_Timeout
  /// 日志不一致
  Log_Inconsistency
  /// 压缩进行中
  Compaction_In_Progress
  /// 快照过时
  Snapshot_Outdated
  /// 内部错误
  Internal_Error(String)
}

///|
impl Eq for RaftError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Stale_Term, Stale_Term) => true
    (Log_Outdated, Log_Outdated) => true
    (Already_Voted, Already_Voted) => true
    (Not_Leader, Not_Leader) => true
    (Election_Timeout, Election_Timeout) => true
    (Log_Inconsistency, Log_Inconsistency) => true
    (Compaction_In_Progress, Compaction_In_Progress) => true
    (Snapshot_Outdated, Snapshot_Outdated) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend RaftError with Eq::{equal, not_equal}

///|
/// 代理错误枚举
pub(all) enum ProxyError {
  /// 路由未找到
  Route_Not_Found
  /// 后端不可用
  Backend_Unavailable
  /// 请求超时
  Request_Timeout
  /// 无效请求
  Invalid_Request
  /// 内部错误
  Internal_Error(String)
}

///|
impl Eq for ProxyError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Route_Not_Found, Route_Not_Found) => true
    (Backend_Unavailable, Backend_Unavailable) => true
    (Request_Timeout, Request_Timeout) => true
    (Invalid_Request, Invalid_Request) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend ProxyError with Eq::{equal, not_equal}

///|
/// 集群配置
pub(all) struct ClusterConfig {
  /// 节点 ID 正则校验
  node_id_pattern : String
  /// 心跳间隔（毫秒）
  heartbeat_interval_ms : Int32
  /// 心跳超时次数
  heartbeat_timeout_count : Int32
  /// 疑似故障超时（毫秒）
  suspect_timeout_ms : Int32
  /// 副本因子
  replica_factor : Int32
  /// 分片总数
  total_shards : Int32
  /// 选举超时最小（毫秒）
  election_timeout_min_ms : Int32
  /// 选举超时最大（毫秒）
  election_timeout_max_ms : Int32
  /// 故障转移超时（毫秒）
  failover_timeout_ms : Int32
}

///|
/// 默认配置
pub fn ClusterConfig::default() -> ClusterConfig {
  {
    node_id_pattern: "^[a-zA-Z0-9_-]{1,64}$",
    heartbeat_interval_ms: 5000,
    heartbeat_timeout_count: 3,
    suspect_timeout_ms: 10000,
    replica_factor: 3,
    total_shards: 256,
    election_timeout_min_ms: 150,
    election_timeout_max_ms: 300,
    failover_timeout_ms: 10000,
  }
}
