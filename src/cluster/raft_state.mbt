// Raft 状态管理模块
//
// 实现 Raft 状态结构体、节点状态机

///|
/// Raft 节点状态
pub(all) enum RaftNodeState {
  /// Follower：跟随者
  Follower
  /// Candidate：候选人
  Candidate
  /// Leader：领导者
  Leader
}

///|
impl Eq for RaftNodeState with fn equal(self, other) -> Bool {
  match (self, other) {
    (Follower, Follower) => true
    (Candidate, Candidate) => true
    (Leader, Leader) => true
    _ => false
  }
}

///|
pub extend RaftNodeState with Eq::{equal, not_equal}

///|
impl Debug for RaftNodeState with fn to_repr(self) -> Repr {
  match self {
    Follower => Repr::ctor("Follower", [])
    Candidate => Repr::ctor("Candidate", [])
    Leader => Repr::ctor("Leader", [])
  }
}

///|
pub extend RaftNodeState with Debug::{to_repr}

///|
/// Raft 状态结构体
pub(all) struct RaftState {
  /// 当前任期
  mut current_term : Int
  /// 投票给谁
  mut voted_for : String?
  /// 当前状态
  mut state : RaftNodeState
  /// 提交索引
  mut commit_index : Int
  /// 最后应用索引
  mut last_applied : Int
  /// 日志索引
  mut last_log_index : Int
  /// 日志任期
  mut last_log_term : Int
  /// 选举超时最小（毫秒）
  election_timeout_min_ms : Int
  /// 选举超时最大（毫秒）
  election_timeout_max_ms : Int
  /// 上次心跳时间
  mut last_heartbeat : Int
  /// 上次投票时间
  mut last_vote_time : Int
  /// 投票计数
  mut vote_count : Int
}

///|
/// 创建 Raft 状态
pub fn RaftState::new(
  election_timeout_min_ms : Int,
  election_timeout_max_ms : Int,
) -> RaftState {
  {
    current_term: 0,
    voted_for: None,
    state: Follower,
    commit_index: 0,
    last_applied: 0,
    last_log_index: 0,
    last_log_term: 0,
    election_timeout_min_ms,
    election_timeout_max_ms,
    last_heartbeat: 0,
    last_vote_time: 0,
    vote_count: 0,
  }
}

///|
/// 获取当前任期
pub fn RaftState::current_term(self : RaftState) -> Int {
  self.current_term
}

///|
/// 增加任期
pub fn RaftState::increment_term(self : RaftState) -> Unit {
  self.current_term = self.current_term + 1
  self.voted_for = None
  self.vote_count = 0
}

///|
/// 设置任期
pub fn RaftState::set_term(self : RaftState, term : Int) -> Unit {
  if term > self.current_term {
    self.current_term = term
    self.voted_for = None
    self.vote_count = 0
    self.state = Follower
  }
}

///|
/// 获取状态
pub fn RaftState::state(self : RaftState) -> RaftNodeState {
  self.state
}

///|
/// 设置状态
pub fn RaftState::set_state(
  self : RaftState,
  new_state : RaftNodeState,
) -> Unit {
  self.state = new_state
  self.vote_count = 0
}

///|
/// 判断是否 Follower
pub fn RaftState::is_follower(self : RaftState) -> Bool {
  self.state == Follower
}

///|
/// 判断是否 Candidate
pub fn RaftState::is_candidate(self : RaftState) -> Bool {
  self.state == Candidate
}

///|
/// 判断是否 Leader
pub fn RaftState::is_leader(self : RaftState) -> Bool {
  self.state == Leader
}

///|
/// 转换为 Candidate
pub fn RaftState::become_candidate(self : RaftState) -> Unit {
  self.state = Candidate
  self.increment_term()
  self.voted_for = None
  self.vote_count = 1
}

///|
/// 转换为 Leader
pub fn RaftState::become_leader(self : RaftState) -> Unit {
  self.state = Leader
  self.last_heartbeat = 0
}

///|
/// 转换为 Follower
pub fn RaftState::become_follower(self : RaftState, term : Int) -> Unit {
  self.set_term(term)
  self.state = Follower
  self.voted_for = None
}

///|
/// 设置投票
pub fn RaftState::set_voted_for(
  self : RaftState,
  candidate_id : String,
) -> Unit {
  self.voted_for = Some(candidate_id)
  self.last_vote_time = 0
}

///|
/// 获取投票给谁
pub fn RaftState::voted_for(self : RaftState) -> String? {
  self.voted_for
}

///|
/// 检查是否已投票
pub fn RaftState::has_voted(self : RaftState) -> Bool {
  self.voted_for is Some(_)
}

///|
/// 增加投票计数
pub fn RaftState::increment_vote_count(self : RaftState) -> Int {
  self.vote_count = self.vote_count + 1
  self.vote_count
}

///|
/// 获取投票计数
pub fn RaftState::vote_count(self : RaftState) -> Int {
  self.vote_count
}

///|
/// 重置投票计数
pub fn RaftState::reset_vote_count(self : RaftState) -> Unit {
  self.vote_count = 0
}

///|
/// 更新心跳时间
pub fn RaftState::update_heartbeat(self : RaftState) -> Unit {
  self.last_heartbeat = 0
}

///|
/// 获取上次心跳时间
pub fn RaftState::last_heartbeat(self : RaftState) -> Int {
  self.last_heartbeat
}

///|
/// 检查是否超时
pub fn RaftState::is_timeout(
  self : RaftState,
  current_time : Int,
  random_timeout : Int,
) -> Bool {
  current_time - self.last_heartbeat > random_timeout
}

///|
/// 获取随机选举超时
pub fn RaftState::get_random_election_timeout(self : RaftState) -> Int {
  // 简化实现：返回固定值
  self.election_timeout_min_ms
}

///|
/// 更新提交索引
pub fn RaftState::update_commit_index(self : RaftState, index : Int) -> Unit {
  if index > self.commit_index {
    self.commit_index = index
  }
}

///|
/// 获取提交索引
pub fn RaftState::commit_index(self : RaftState) -> Int {
  self.commit_index
}

///|
/// 更新日志索引
pub fn RaftState::update_log_index(
  self : RaftState,
  index : Int,
  term : Int,
) -> Unit {
  if index > self.last_log_index {
    self.last_log_index = index
    self.last_log_term = term
  }
}

///|
/// 获取最后日志索引
pub fn RaftState::last_log_index(self : RaftState) -> Int {
  self.last_log_index
}

///|
/// 获取最后日志任期
pub fn RaftState::last_log_term(self : RaftState) -> Int {
  self.last_log_term
}

///|
/// 比较日志是否更新
pub fn RaftState::is_log_up_to_date(
  self : RaftState,
  last_log_index : Int,
  last_log_term : Int,
) -> Bool {
  if last_log_term > self.last_log_term {
    return true
  }
  if last_log_term == self.last_log_term &&
    last_log_index >= self.last_log_index {
    return true
  }
  false
}

///|
/// 创建 Raft 状态
pub fn create_raft_state(
  election_timeout_min_ms : Int,
  election_timeout_max_ms : Int,
) -> RaftState {
  RaftState::new(election_timeout_min_ms, election_timeout_max_ms)
}

///|
/// 创建默认 Raft 状态
pub fn create_default_raft_state() -> RaftState {
  RaftState::new(150, 300)
}
