// Raft 日志模块
//
// 实现日志追加、查询、持久化

///|
/// Raft 日志
pub(all) struct RaftLog {
  /// 日志条目数组
  mut entries : Array[LogEntry]
  /// 起始索引
  start_index : Int
  /// 最后索引
  mut last_index : Int
  /// 最后任期
  mut last_term : Int
  /// 提交索引
  mut commit_index : Int
  /// 快照索引
  mut snapshot_index : Int
  /// 快照任期
  mut snapshot_term : Int
}

///|
/// 创建 Raft 日志
pub fn RaftLog::new() -> RaftLog {
  {
    entries: [],
    start_index: 1,
    last_index: 0,
    last_term: 0,
    commit_index: 0,
    snapshot_index: 0,
    snapshot_term: 0,
  }
}

///|
/// 追加日志
pub fn RaftLog::append(self : RaftLog, entry : LogEntry) -> Int {
  entry.index = self.last_index + 1
  let index = entry.index
  let term = entry.term
  self.entries.push(entry)
  self.last_index = index
  self.last_term = term
  index
}

///|
/// 批量追加日志
pub fn RaftLog::append_batch(self : RaftLog, entries : Array[LogEntry]) -> Int {
  for entry in entries {
    entry.index = self.last_index + 1
    let index = entry.index
    let term = entry.term
    self.entries.push(entry)
    self.last_index = index
    self.last_term = term
  }
  self.last_index
}

///|
/// 获取日志条目
pub fn RaftLog::get_entry(self : RaftLog, index : Int) -> LogEntry? {
  if index < self.start_index || index > self.last_index {
    return None
  }

  let idx = index - self.start_index
  if idx >= 0 && idx < self.entries.length() {
    Some(self.entries[idx])
  } else {
    None
  }
}

///|
/// 获取日志条目列表
pub fn RaftLog::get_entries(
  self : RaftLog,
  start : Int,
  end : Int,
) -> Array[LogEntry] {
  let result : Array[LogEntry] = []

  if start < self.start_index || end > self.last_index || start > end {
    return result
  }

  for i in start..<end {
    let idx = i - self.start_index
    if idx >= 0 && idx < self.entries.length() {
      result.push(self.entries[idx])
    }
  }

  result
}

///|
/// 删除日志
pub fn RaftLog::delete_from(self : RaftLog, index : Int) -> Unit {
  if index <= self.last_index {
    let idx = index - self.start_index
    if idx >= 0 && idx < self.entries.length() {
      self.entries.truncate(idx)
      self.last_index = index - 1
      if self.last_index < self.start_index {
        self.last_index = 0
        self.last_term = 0
      } else {
        match self.get_entry(self.last_index) {
          Some(entry) => self.last_term = entry.term
          None => self.last_term = 0
        }
      }
    }
  }
}

///|
/// 截断日志
pub fn RaftLog::truncate(self : RaftLog, index : Int) -> Unit {
  if index < self.start_index {
    return
  }

  if index > self.last_index {
    return
  }

  let idx = index - self.start_index
  if idx >= 0 && idx < self.entries.length() {
    self.entries.truncate(idx)
    self.last_index = index - 1
  }
}

///|
/// 获取最后索引
pub fn RaftLog::last_index(self : RaftLog) -> Int {
  self.last_index
}

///|
/// 获取最后任期
pub fn RaftLog::last_term(self : RaftLog) -> Int {
  self.last_term
}

///|
/// 获取提交索引
pub fn RaftLog::commit_index(self : RaftLog) -> Int {
  self.commit_index
}

///|
/// 更新提交索引
pub fn RaftLog::update_commit_index(self : RaftLog, index : Int) -> Unit {
  if index > self.commit_index && index <= self.last_index {
    self.commit_index = index
  }
}

///|
/// 获取日志大小
pub fn RaftLog::size(self : RaftLog) -> Int {
  self.entries.length()
}

///|
/// 检查是否为空
pub fn RaftLog::is_empty(self : RaftLog) -> Bool {
  self.entries.length() == 0
}

///|
/// 清空日志
pub fn RaftLog::clear(self : RaftLog) -> Unit {
  self.entries = []
  self.last_index = 0
  self.last_term = 0
  self.commit_index = 0
}

///|
/// 创建快照
pub fn RaftLog::create_snapshot(
  self : RaftLog,
  index : Int,
  _data : @realtime_db.Value,
) -> Unit {
  if index <= self.last_index {
    self.snapshot_index = index
    match self.get_entry(index) {
      Some(entry) => self.snapshot_term = entry.term
      None => ()
    }

    // 截断日志
    self.truncate(index + 1)
  }
}

///|
/// 获取快照索引
pub fn RaftLog::snapshot_index(self : RaftLog) -> Int {
  self.snapshot_index
}

///|
/// 获取快照任期
pub fn RaftLog::snapshot_term(self : RaftLog) -> Int {
  self.snapshot_term
}

///|
/// 从快照恢复
pub fn RaftLog::restore_from_snapshot(
  self : RaftLog,
  snapshot_index : Int,
  snapshot_term : Int,
) -> Unit {
  self.snapshot_index = snapshot_index
  self.snapshot_term = snapshot_term
  self.last_index = snapshot_index
  self.last_term = snapshot_term
  self.commit_index = snapshot_index
}

///|
/// 检查日志一致性
pub fn RaftLog::check_consistency(
  self : RaftLog,
  index : Int,
  term : Int,
) -> Bool {
  match self.get_entry(index) {
    Some(entry) => entry.term == term
    None => false
  }
}

///|
/// 创建 Raft 日志
pub fn create_raft_log() -> RaftLog {
  RaftLog::new()
}

///|
/// 日志持久化
pub(all) struct LogPersister {
  /// Raft 日志
  log : RaftLog
  /// WAL
  mut wal : @persistence.WAL?
}

///|
/// 创建日志持久化器
pub fn LogPersister::new(log : RaftLog) -> LogPersister {
  { log, wal: None, }
}

///|
/// 设置 WAL
pub fn LogPersister::set_wal(
  self : LogPersister,
  wal : @persistence.WAL?,
) -> Unit {
  self.wal = wal
}

///|
/// 持久化日志
pub fn LogPersister::persist(
  self : LogPersister,
  _entry : LogEntry,
) -> Result[Unit, ClusterError] {
  match self.wal {
    Some(wal) => {
      // 写入 WAL
      let _ = wal.append(@persistence.Operation::Begin(0))
      let _ = wal.append(@persistence.Operation::Commit(0))
    }
    None => ()
  }

  Ok(())
}

///|
/// 同步日志
pub fn LogPersister::sync(self : LogPersister) -> Result[Unit, ClusterError] {
  match self.wal {
    Some(wal) => {
      let _ = wal.sync()
    }
    None => ()
  }

  Ok(())
}

///|
/// 从 WAL 恢复
pub fn LogPersister::restore_from_wal(
  self : LogPersister,
) -> Result[Unit, ClusterError] {
  match self.wal {
    Some(wal) =>
      // 重放 WAL
      wal.replay(fn(_op, _tx_id) { () })
    None => ()
  }

  Ok(())
}

///|
/// 创建日志持久化器
pub fn create_log_persister(log : RaftLog) -> LogPersister {
  LogPersister::new(log)
}
