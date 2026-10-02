// WAL 预写日志模块
//
// 提供预写日志功能，保证数据持久性和崩溃恢复能力。
// 所有写操作先写入 WAL，再更新内存。
//
// 注：当前为内存模拟实现——"刷盘"把缓冲区转移到 persisted 区，
// replay 只重放已刷盘的条目（未刷盘内容视为崩溃时丢失）。

///|
/// 日志序列号（LSN）
pub struct Lsn {
  value : Int
}

///|
/// 操作类型
pub(all) enum Operation {
  /// 设置键值
  Set(String, @realtime_db.Value)
  /// 删除键
  Delete(String)
  /// 事务开始
  Begin(Int)
  /// 事务提交
  Commit(Int)
  /// 事务回滚
  Rollback(Int)
}

///|
/// WAL 日志条目
pub struct WalEntry {
  /// 日志序列号
  lsn : Lsn
  /// 操作类型
  operation : Operation
  /// 时间戳
  timestamp : Int
  /// 事务 ID（可选）
  tx_id : Int?
}

///|
/// WAL 结构体
/// 管理日志的写入、刷盘和恢复
pub struct WAL {
  /// 日志文件路径（预留，供未来接入文件 IO）
  file_path : String
  /// 下一个待分配的 LSN
  mut current_lsn : Int
  /// 写入缓冲区（未刷盘）
  mut buffer : Array[WalEntry]
  /// 已刷盘的日志条目
  persisted : Array[WalEntry]
  /// 缓冲区大小阈值
  buffer_threshold : Int
}

///|
/// 创建 LSN
pub fn Lsn::new(value : Int) -> Lsn {
  { value, }
}

///|
/// 获取 LSN 值
pub fn Lsn::value(self : Lsn) -> Int {
  self.value
}

///|
/// 创建 WAL 实例
///
/// ## 参数
/// - file_path: 日志文件路径
/// - buffer_threshold: 缓冲区大小阈值（默认 1000）
pub fn WAL::new(file_path : String, buffer_threshold : Int) -> WAL {
  { file_path, current_lsn: 0, buffer: [], persisted: [], buffer_threshold, }
}

///|
/// 追加写入日志（缓冲区），返回分配的 LSN。
pub fn WAL::append(
  self : WAL,
  operation : Operation,
  timestamp? : Int,
  tx_id? : Int,
) -> Lsn {
  self.append_entry(
    operation,
    match timestamp {
      Some(t) => t
      None => 0
    },
    tx_id,
  )
}

///|
/// 内部：以显式 option 形式追加，便于其他方法转发。
fn WAL::append_entry(
  self : WAL,
  operation : Operation,
  timestamp : Int,
  tx_id : Int?,
) -> Lsn {
  let lsn = Lsn::new(self.current_lsn)
  self.current_lsn = self.current_lsn + 1

  let entry : WalEntry = { lsn, operation, timestamp, tx_id, }

  self.buffer.push(entry)
  lsn
}

///|
/// 同步缓冲区到持久化区：把缓冲区条目全部转移后清空。
/// 返回本次刷盘的条目数。
pub fn WAL::sync(self : WAL) -> Int {
  let n = self.buffer.length()
  for entry in self.buffer {
    self.persisted.push(entry)
  }
  self.buffer = []
  n
}

///|
/// 获取当前缓冲区大小
pub fn WAL::buffer_size(self : WAL) -> Int {
  self.buffer.length()
}

///|
/// 获取已刷盘条目数
pub fn WAL::persisted_size(self : WAL) -> Int {
  self.persisted.length()
}

///|
/// 检查是否需要刷盘
pub fn WAL::should_flush(self : WAL) -> Bool {
  self.buffer.length() >= self.buffer_threshold
}

///|
/// 写入并同步（如果缓冲区已满），返回分配的 LSN。
pub fn WAL::append_and_flush(
  self : WAL,
  operation : Operation,
  timestamp? : Int,
  tx_id? : Int,
) -> Lsn {
  let lsn = self.append_entry(
    operation,
    match timestamp {
      Some(t) => t
      None => 0
    },
    tx_id,
  )
  if self.should_flush() {
    let _ = self.sync()
  }
  lsn
}

///|
/// 重放已刷盘日志（崩溃恢复语义：未刷盘的缓冲区内容不重放）。
///
/// ## 参数
/// - callback: 重放操作的回调函数，接收操作与可选事务 ID
pub fn WAL::replay(self : WAL, callback : (Operation, Int?) -> Unit) -> Unit {
  for entry in self.persisted {
    callback(entry.operation, entry.tx_id)
  }
}

///|
/// 获取下一个待分配的 LSN
pub fn WAL::current_lsn(self : WAL) -> Int {
  self.current_lsn
}

///|
/// 日志条目转字符串
pub fn WalEntry::to_string(self : WalEntry) -> String {
  "LSN=" + self.lsn.value.to_string() + " " + self.operation.to_string()
}

///|
/// 操作转字符串
pub fn Operation::to_string(self : Operation) -> String {
  match self {
    Set(k, v) => "SET " + k + "=" + v.to_string()
    Delete(k) => "DELETE " + k
    Begin(id) => "BEGIN " + id.to_string()
    Commit(id) => "COMMIT " + id.to_string()
    Rollback(id) => "ROLLBACK " + id.to_string()
  }
}
