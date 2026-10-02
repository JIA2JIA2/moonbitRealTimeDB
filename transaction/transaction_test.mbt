// 事务模块黑盒测试。

///|
test "tx_lifecycle_commit" {
  let tm = @realtime_db.TransactionManager::new(0)
  let t1 = tm.begin(100)
  assert_eq(t1.value(), 0)
  assert_eq(tm.active_count(), 1)
  let tx = tm.get_transaction(t1)
  assert_true(tx is Some(_))
  assert_true(tt_unwrap(tx).status() is @realtime_db.Active)
  assert_eq(tt_unwrap(tx).begin_time(), 100)

  assert_true(tm.commit(t1) is Ok(_))
  assert_true(
    tt_unwrap(tm.get_transaction(t1)).status() is @realtime_db.Committed,
  )
  assert_eq(tm.active_count(), 0)
  // 重复提交
  assert_true(tm.commit(t1) is Err(@realtime_db.TX_Already_Finished))
  // 清理已结束事务
  assert_eq(tm.purge_finished(), 1)
  assert_true(tm.get_transaction(t1) is None)
}

///|
fn tt_unwrap(t : @realtime_db.Transaction?) -> @realtime_db.Transaction {
  match t {
    Some(x) => x
    None => abort("expected transaction")
  }
}

///|
test "tx_rollback_and_not_found" {
  let tm = @realtime_db.TransactionManager::new(0)
  let t1 = tm.begin(0)
  assert_true(tm.rollback(t1) is Ok(_))
  assert_true(
    tt_unwrap(tm.get_transaction(t1)).status() is @realtime_db.Rolled_Back,
  )
  // 回滚后再提交
  assert_true(tm.commit(t1) is Err(@realtime_db.TX_Already_Finished))
  // 不存在的事务
  let ghost = @realtime_db.TransactionId::new(999)
  assert_true(tm.commit(ghost) is Err(@realtime_db.TX_Not_Found))
  assert_true(tm.rollback(ghost) is Err(@realtime_db.TX_Not_Found))
  assert_true(tm.get_transaction(ghost) is None)
}

///|
test "tx_ids_increment" {
  let tm = @realtime_db.TransactionManager::new(0)
  let a = tm.begin(0)
  let b = tm.begin(0)
  assert_true(a != b)
  assert_eq(b.value(), 1)
}

///|
test "locks_shared_compatible" {
  let tm = @realtime_db.TransactionManager::new(0)
  let t1 = tm.begin(0)
  let t2 = tm.begin(0)
  let t3 = tm.begin(0)
  let lm = tm.lock_manager()

  assert_true(lm.try_acquire("k", @realtime_db.Shared, t1))
  assert_true(lm.try_acquire("k", @realtime_db.Shared, t2))
  assert_eq(lm.holder_count("k"), 2)
  // 有共享锁时，其他事务不能拿排他锁
  assert_false(lm.try_acquire("k", @realtime_db.Exclusive, t3))
  // 非唯一持有者不能升级
  assert_false(lm.try_acquire("k", @realtime_db.Exclusive, t1))
  // t2 结束后只剩 t1，可以升级
  let _ = tm.rollback(t2)
  assert_eq(lm.holder_count("k"), 1)
  assert_true(lm.try_acquire("k", @realtime_db.Exclusive, t1))
  // 排他锁存在时，共享锁也被拒绝
  assert_false(lm.try_acquire("k", @realtime_db.Shared, t3))
}

///|
test "locks_released_on_commit" {
  // 原 bug：commit/rollback 不释放锁，这里验证锁已被回收
  let tm = @realtime_db.TransactionManager::new(0)
  let t1 = tm.begin(0)
  let t2 = tm.begin(0)
  let lm = tm.lock_manager()

  assert_true(lm.try_acquire("a", @realtime_db.Exclusive, t1))
  assert_true(lm.try_acquire("b", @realtime_db.Shared, t2))
  assert_eq(lm.locked_key_count(), 2)
  let _ = tm.commit(t1)
  assert_eq(lm.locked_key_count(), 1)
  // t1 提交后，t2 现在可以拿 a 的排他锁
  assert_true(lm.try_acquire("a", @realtime_db.Exclusive, t2))
  // 手动释放单键
  lm.release("b", t2)
  assert_eq(lm.locked_key_count(), 1)
  lm.release("a", t2)
  assert_eq(lm.locked_key_count(), 0)
}

///|
test "locks_same_tx_reentrant" {
  let tm = @realtime_db.TransactionManager::new(0)
  let t1 = tm.begin(0)
  let lm = tm.lock_manager()
  // 同事务重复获取共享锁
  assert_true(lm.try_acquire("k", @realtime_db.Shared, t1))
  assert_true(lm.try_acquire("k", @realtime_db.Shared, t1))
  assert_eq(lm.holder_count("k"), 1)
  // 唯一持有者，直接升级排他
  assert_true(lm.try_acquire("k", @realtime_db.Exclusive, t1))
  // 持排他锁后任何重入都成功
  assert_true(lm.try_acquire("k", @realtime_db.Shared, t1))
  assert_eq(lm.holder_count("k"), 1)
  // release 后键被清空
  lm.release("k", t1)
  assert_eq(lm.holder_count("k"), 0)
}

///|
test "tx_timeout_rollback" {
  let tm = @realtime_db.TransactionManager::new(5)
  let t1 = tm.begin(0)
  let t2 = tm.begin(3)
  let lm = tm.lock_manager()
  assert_true(lm.try_acquire("k", @realtime_db.Exclusive, t1))

  // clock=5：t1(开始于0) 超时，t2(开始于3) 未超时
  let expired = tm.expire_old(5)
  assert_eq(expired.length(), 1)
  assert_true(
    tt_unwrap(tm.get_transaction(t1)).status() is @realtime_db.Rolled_Back,
  )
  assert_true(tt_unwrap(tm.get_transaction(t2)).status() is @realtime_db.Active)
  // 超时回滚同样释放锁
  assert_eq(lm.locked_key_count(), 0)
  assert_eq(tm.active_count(), 1)
}
