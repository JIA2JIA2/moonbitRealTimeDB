// 事务支持模块
//
// 提供事务管理功能，包括：
// - 事务生命周期管理（begin/commit/rollback）
// - 锁管理（多持有者共享锁、排他锁、同事务重入与锁升级）
// - 事务超时处理

///|
/// 事务 ID 类型（封装 Int）
pub struct TransactionId {
  value : Int
}

///|
pub impl Eq for TransactionId with fn equal(self, other) -> Bool {
  self.value == other.value
}

///|
pub extend TransactionId with Eq::{equal, not_equal}

///|
pub impl Hash for TransactionId with fn hash_combine(self, hasher) {
  hasher.combine_int(self.value)
}

///|
pub extend TransactionId with Hash::{hash, hash_combine}

///|
/// 事务状态枚举
pub(all) enum TransactionStatus {
  /// 事务活跃中
  Active
  /// 事务已提交
  Committed
  /// 事务已回滚
  Rolled_Back
}

///|
/// 事务错误类型
pub(all) enum TransactionError {
  /// 事务不存在
  TX_Not_Found
  /// 事务已结束
  TX_Already_Finished
}

///|
/// 锁模式
pub(all) enum LockMode {
  /// 共享锁（读锁）
  Shared
  /// 排他锁（写锁）
  Exclusive
}

///|
/// 事务结构体
pub struct Transaction {
  /// 事务 ID
  id : TransactionId
  /// 事务状态
  mut status : TransactionStatus
  /// 事务开始时间
  begin_time : Int
}

///|
/// 创建事务 ID
pub fn TransactionId::new(value : Int) -> TransactionId {
  { value, }
}

///|
/// 获取事务 ID 的值
pub fn TransactionId::value(self : TransactionId) -> Int {
  self.value
}

///|
/// 创建事务
pub fn Transaction::new(id : TransactionId, begin_time : Int) -> Transaction {
  { id, status: Active, begin_time, }
}

///|
/// 获取事务 ID
pub fn Transaction::id(self : Transaction) -> TransactionId {
  self.id
}

///|
/// 获取事务状态
pub fn Transaction::status(self : Transaction) -> TransactionStatus {
  self.status
}

///|
/// 获取事务开始时间
pub fn Transaction::begin_time(self : Transaction) -> Int {
  self.begin_time
}

///|
/// 锁管理器
/// 每个键记录全部持有者及其锁模式，支持多事务并发持有共享锁。
pub struct LockManager {
  /// 锁表：键 -> (持有者事务 ID -> 锁模式)
  lock_table : Map[String, Map[TransactionId, LockMode]]
}

///|
/// 创建锁管理器
pub fn LockManager::new() -> LockManager {
  { lock_table: Map([]), }
}

///|
/// 尝试获取锁
///
/// 兼容规则：
/// - 无持有者：直接获取
/// - 同一事务重入：共享锁可在唯一持有时升级为排他锁
/// - 不同事务：多方只能同时持有共享锁；任一排他锁存在即冲突
pub fn LockManager::try_acquire(
  self : LockManager,
  key : String,
  mode : LockMode,
  tx_id : TransactionId,
) -> Bool {
  match self.lock_table.get(key) {
    None => {
      let holders : Map[TransactionId, LockMode] = Map([(tx_id, mode)])
      self.lock_table.set(key, holders)
      true
    }
    Some(holders) =>
      match holders.get(tx_id) {
        Some(held) =>
          // 同事务重入
          match (held, mode) {
            (Exclusive, _) => true // 已持排他锁
            (Shared, Shared) => true
            (Shared, Exclusive) =>
              // 锁升级：仅当自己是唯一持有者
              if holders.length() == 1 {
                holders.set(tx_id, Exclusive)
                true
              } else {
                false
              }
          }
        None => {
          // 别的事务持有，检查兼容性
          let mut has_exclusive = false
          for _, m in holders {
            if m is Exclusive {
              has_exclusive = true
            }
          }
          match (mode, has_exclusive) {
            (Shared, false) => {
              holders.set(tx_id, Shared)
              true
            }
            _ => false
          }
        }
      }
  }
}

///|
/// 释放某事务在指定键上的锁。
pub fn LockManager::release(
  self : LockManager,
  key : String,
  tx_id : TransactionId,
) -> Unit {
  match self.lock_table.get(key) {
    Some(holders) => {
      let _ = holders.remove(tx_id)
      if holders.length() == 0 {
        let _ = self.lock_table.remove(key)
      }
    }
    None => ()
  }
}

///|
/// 释放某事务持有的全部锁（提交/回滚时调用）。
pub fn LockManager::release_all(
  self : LockManager,
  tx_id : TransactionId,
) -> Unit {
  let empty_keys : Array[String] = []
  for key, holders in self.lock_table {
    let _ = holders.remove(tx_id)
    if holders.length() == 0 {
      empty_keys.push(key)
    }
  }
  for key in empty_keys {
    let _ = self.lock_table.remove(key)
  }
}

///|
/// 当前被锁定的键数量。
pub fn LockManager::locked_key_count(self : LockManager) -> Int {
  self.lock_table.length()
}

///|
/// 查询某键的持有者数量。
pub fn LockManager::holder_count(self : LockManager, key : String) -> Int {
  match self.lock_table.get(key) {
    Some(holders) => holders.length()
    None => 0
  }
}

///|
/// 事务管理器
/// 管理事务的生命周期（begin/commit/rollback）
pub struct TransactionManager {
  /// 事务表：事务 ID -> 事务
  transactions : Map[TransactionId, Transaction]
  /// 下一个事务 ID
  mut next_tx_id : Int
  /// 锁管理器
  lock_manager : LockManager
  /// 事务超时时间（逻辑时钟单位，<=0 表示不超时）
  timeout : Int
}

///|
/// 创建事务管理器
pub fn TransactionManager::new(timeout : Int) -> TransactionManager {
  {
    transactions: Map([]),
    next_tx_id: 0,
    lock_manager: LockManager::new(),
    timeout,
  }
}

///|
/// 开始新事务，返回事务 ID。
pub fn TransactionManager::begin(
  self : TransactionManager,
  current_clock : Int,
) -> TransactionId {
  let tx_id = TransactionId::new(self.next_tx_id)
  self.next_tx_id = self.next_tx_id + 1

  let tx = Transaction::new(tx_id, current_clock)
  self.transactions.set(tx_id, tx)

  tx_id
}

///|
/// 提交事务：更新状态为 Committed 并释放其全部锁。
/// 已结束的事务保留在表中，重复提交返回 TX_Already_Finished。
pub fn TransactionManager::commit(
  self : TransactionManager,
  tx_id : TransactionId,
) -> Result[Unit, TransactionError] {
  guard self.transactions.get(tx_id) is Some(tx) else {
    return Err(TX_Not_Found)
  }
  match tx.status() {
    Active => {
      tx.status = Committed
      self.lock_manager.release_all(tx_id)
      Ok(())
    }
    _ => Err(TX_Already_Finished)
  }
}

///|
/// 回滚事务：更新状态为 Rolled_Back 并释放其全部锁。
pub fn TransactionManager::rollback(
  self : TransactionManager,
  tx_id : TransactionId,
) -> Result[Unit, TransactionError] {
  guard self.transactions.get(tx_id) is Some(tx) else {
    return Err(TX_Not_Found)
  }
  match tx.status() {
    Active => {
      tx.status = Rolled_Back
      self.lock_manager.release_all(tx_id)
      Ok(())
    }
    _ => Err(TX_Already_Finished)
  }
}

///|
/// 清理所有已结束（Committed/Rolled_Back）的事务记录。返回清理数量。
pub fn TransactionManager::purge_finished(self : TransactionManager) -> Int {
  let dead : Array[TransactionId] = []
  for id, tx in self.transactions {
    if !(tx.status() is Active) {
      dead.push(id)
    }
  }
  for id in dead {
    let _ = self.transactions.remove(id)
  }
  dead.length()
}

///|
/// 超时处理：将活跃时间超过 timeout 的事务标记为 Rolled_Back 并释放锁。
/// 返回被超时回滚的事务 ID 列表。
pub fn TransactionManager::expire_old(
  self : TransactionManager,
  current_clock : Int,
) -> Array[TransactionId] {
  let expired : Array[TransactionId] = []
  guard self.timeout > 0 else { return expired }
  for id, tx in self.transactions {
    if tx.status() is Active && current_clock - tx.begin_time() >= self.timeout {
      tx.status = Rolled_Back
      self.lock_manager.release_all(id)
      expired.push(id)
    }
  }
  expired
}

///|
/// 获取事务
pub fn TransactionManager::get_transaction(
  self : TransactionManager,
  tx_id : TransactionId,
) -> Transaction? {
  self.transactions.get(tx_id)
}

///|
/// 获取锁管理器
pub fn TransactionManager::lock_manager(
  self : TransactionManager,
) -> LockManager {
  self.lock_manager
}

///|
/// 获取活跃事务数量
pub fn TransactionManager::active_count(self : TransactionManager) -> Int {
  let mut count = 0
  for _, tx in self.transactions {
    if tx.status() is Active {
      count = count + 1
    }
  }
  count
}
