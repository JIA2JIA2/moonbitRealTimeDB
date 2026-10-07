// Raft 节点模块
//
// 实现 Raft 节点、投票请求、日志复制

///|
/// 投票请求
pub(all) struct VoteRequest {
  /// 任期
  term : Int
  /// 候选人 ID
  candidate_id : String
  /// 最后日志索引
  last_log_index : Int
  /// 最后日志任期
  last_log_term : Int
}

///|
/// 投票响应
pub(all) struct VoteResponse {
  /// 任期
  term : Int
  /// 是否投票
  vote_granted : Bool
  /// 错误信息
  error : String?
}

///|
/// 附加日志请求
pub(all) struct AppendEntriesRequest {
  /// 任期
  term : Int
  /// 领导者 ID
  leader_id : String
  /// 前一个日志索引
  prev_log_index : Int
  /// 前一个日志任期
  prev_log_term : Int
  /// 日志条目
  entries : Array[LogEntry]
  /// 领导者提交索引
  leader_commit : Int
}

///|
/// 附加日志响应
pub(all) struct AppendEntriesResponse {
  /// 任期
  term : Int
  /// 是否成功
  success : Bool
  /// 冲突索引
  conflict_index : Int
  /// 冲突任期
  conflict_term : Int
}

///|
/// 日志条目
pub(all) struct LogEntry {
  /// 索引
  mut index : Int
  /// 任期
  term : Int
  /// 命令
  command : String
  /// 数据
  data : @realtime_db.Value?
}

///|
/// 投票服务
pub(all) struct VoteService {
  /// Raft 状态
  state : RaftState
  /// 节点 ID
  node_id : String
}

///|
/// 创建投票服务
pub fn VoteService::new(state : RaftState, node_id : String) -> VoteService {
  { state, node_id, }
}

///|
/// 请求投票
pub fn VoteService::request_vote(
  self : VoteService,
  req : VoteRequest,
) -> VoteResponse {
  // 检查任期
  if req.term < self.state.current_term() {
    return VoteResponse::{
      term: self.state.current_term(),
      vote_granted: false,
      error: Some("Stale term"),
    }
  }

  // 更新任期
  if req.term > self.state.current_term() {
    self.state.set_term(req.term)
  }

  // 检查是否已投票
  let voted_for_other = match self.state.voted_for() {
    Some(voted) => voted != req.candidate_id.to_string()
    None => false
  }
  if self.state.has_voted() && voted_for_other {
    return VoteResponse::{
      term: self.state.current_term(),
      vote_granted: false,
      error: Some("Already voted"),
    }
  }

  // 检查日志是否更新
  if !self.state.is_log_up_to_date(req.last_log_index, req.last_log_term) {
    return VoteResponse::{
      term: self.state.current_term(),
      vote_granted: false,
      error: Some("Log outdated"),
    }
  }

  // 投票
  self.state.set_voted_for(req.candidate_id)

  VoteResponse::{
    term: self.state.current_term(),
    vote_granted: true,
    error: None,
  }
}

///|
/// Raft 节点
pub(all) struct RaftNode {
  /// 节点 ID
  node_id : String
  /// Raft 状态
  state : RaftState
  /// 集群节点
  mut peers : Array[String]
  /// 投票服务
  vote_service : VoteService
  /// 选举超时
  election_timeout : Int
  /// 心跳间隔
  heartbeat_interval_ms : Int
  /// 是否在运行
  mut is_running : Bool
}

///|
/// 创建 Raft 节点
pub fn RaftNode::new(
  node_id : String,
  peers : Array[String],
  config : ClusterConfig,
) -> RaftNode {
  let state = RaftState::new(
    config.election_timeout_min_ms,
    config.election_timeout_max_ms,
  )
  let vote_service = VoteService::new({ ..state, }, node_id.to_string())

  {
    node_id,
    state,
    peers,
    vote_service,
    election_timeout: config.election_timeout_min_ms,
    heartbeat_interval_ms: config.heartbeat_interval_ms,
    is_running: false,
  }
}

///|
/// 启动 Raft 节点
pub fn RaftNode::start(self : RaftNode) -> Unit {
  self.is_running = true
  self.state.update_heartbeat()
}

///|
/// 停止 Raft 节点
pub fn RaftNode::stop(self : RaftNode) -> Unit {
  self.is_running = false
}

///|
/// 检查是否在运行
pub fn RaftNode::is_running(self : RaftNode) -> Bool {
  self.is_running
}

///|
/// 请求投票
pub fn RaftNode::request_vote(
  self : RaftNode,
  req : VoteRequest,
) -> VoteResponse {
  self.vote_service.request_vote(req)
}

///|
/// 开始选举
pub fn RaftNode::start_election(self : RaftNode) -> Unit {
  // 转换为 Candidate
  self.state.become_candidate()

  // 重置投票
  self.state.reset_vote_count()

  // 投票给自己
  self.state.set_voted_for(self.node_id)
  let _ = self.state.increment_vote_count()

  // 发送投票请求给其他节点
  for peer in self.peers {
    // 简化实现：实际需要发送 RPC 请求
    let _ = peer
  }
}

///|
/// 接收投票响应
pub fn RaftNode::receive_vote_response(
  self : RaftNode,
  resp : VoteResponse,
) -> Bool {
  // 检查任期
  if resp.term > self.state.current_term() {
    self.state.set_term(resp.term)
    return false
  }

  // 检查是否 Leader
  if !self.state.is_candidate() {
    return false
  }

  // 检查投票
  if resp.vote_granted {
    let count = self.state.increment_vote_count()
    let majority = self.peers.length() / 2 + 1
    if count >= majority {
      // 成为 Leader
      self.state.become_leader()
      return true
    }
  }

  false
}

///|
/// 发送心跳
pub fn RaftNode::send_heartbeat(self : RaftNode) -> Array[AppendEntriesRequest] {
  let requests : Array[AppendEntriesRequest] = []

  if !self.state.is_leader() {
    return requests
  }

  let req = AppendEntriesRequest::{
    term: self.state.current_term(),
    leader_id: self.node_id.to_string(),
    prev_log_index: self.state.last_log_index(),
    prev_log_term: self.state.last_log_term(),
    entries: [],
    leader_commit: self.state.commit_index(),
  }

  for peer in self.peers {
    let _ = peer
    requests.push({ ..req, })
  }

  self.state.update_heartbeat()

  requests
}

///|
/// 接收附加日志请求
pub fn RaftNode::receive_append_entries(
  self : RaftNode,
  req : AppendEntriesRequest,
) -> AppendEntriesResponse {
  // 检查任期
  if req.term < self.state.current_term() {
    return AppendEntriesResponse::{
      term: self.state.current_term(),
      success: false,
      conflict_index: 0,
      conflict_term: 0,
    }
  }

  // 更新任期
  if req.term > self.state.current_term() {
    self.state.set_term(req.term)
  }

  // 转换为 Follower
  if !self.state.is_follower() {
    self.state.become_follower(req.term)
  }

  // 更新心跳时间
  self.state.update_heartbeat()

  // 检查日志一致性
  if req.prev_log_index > 0 && req.prev_log_index > self.state.last_log_index() {
    return AppendEntriesResponse::{
      term: self.state.current_term(),
      success: false,
      conflict_index: self.state.last_log_index(),
      conflict_term: 0,
    }
  }

  // 更新提交索引
  if req.leader_commit > self.state.commit_index() {
    self.state.update_commit_index(req.leader_commit)
  }

  AppendEntriesResponse::{
    term: self.state.current_term(),
    success: true,
    conflict_index: 0,
    conflict_term: 0,
  }
}

///|
/// 追加日志
pub fn RaftNode::append_log(
  self : RaftNode,
  _command : String,
  _data : @realtime_db.Value?,
) -> Int {
  if !self.state.is_leader() {
    return -1
  }

  let index = self.state.last_log_index() + 1
  let term = self.state.current_term()

  // 更新日志索引
  self.state.update_log_index(index, term)

  index
}

///|
/// 获取节点 ID
pub fn RaftNode::node_id(self : RaftNode) -> String {
  self.node_id
}

///|
/// 获取状态
pub fn RaftNode::state(self : RaftNode) -> RaftState {
  self.state
}

///|
/// 判断是否 Leader
pub fn RaftNode::is_leader(self : RaftNode) -> Bool {
  self.state.is_leader()
}

///|
/// 获取任期
pub fn RaftNode::current_term(self : RaftNode) -> Int {
  self.state.current_term()
}

///|
/// 创建 Raft 节点
pub fn create_raft_node(
  node_id : String,
  peers : Array[String],
  config : ClusterConfig,
) -> RaftNode {
  RaftNode::new(node_id, peers, config)
}
