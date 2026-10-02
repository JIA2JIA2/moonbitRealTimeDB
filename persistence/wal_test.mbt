// WAL 模块黑盒测试。

///|
test "wal_append_assigns_incremental_lsn" {
  let wal = @realtime_db.WAL::new("/tmp/test.wal", 100)
  let l1 = wal.append(@realtime_db.Operation::Set("a", @realtime_db.Int(1)))
  let l2 = wal.append(@realtime_db.Operation::Delete("a"), timestamp=7, tx_id=3)
  assert_eq(l1.value(), 0)
  assert_eq(l2.value(), 1)
  assert_eq(wal.current_lsn(), 2)
  assert_eq(wal.buffer_size(), 2)
  assert_eq(wal.persisted_size(), 0)
}

///|
test "wal_sync_persists_instead_of_dropping" {
  // 原 bug：sync 直接清空 buffer，日志全部丢失。
  let wal = @realtime_db.WAL::new("/tmp/test.wal", 100)
  let _ = wal.append(@realtime_db.Operation::Set("a", @realtime_db.Int(1)))
  let _ = wal.append(@realtime_db.Operation::Delete("a"))
  let n = wal.sync()
  assert_eq(n, 2)
  assert_eq(wal.buffer_size(), 0)
  assert_eq(wal.persisted_size(), 2) // 日志保留在持久化区
}

///|
test "wal_replay_only_persisted" {
  // 崩溃恢复语义：只重放已刷盘条目，未刷盘的缓冲区内容丢失。
  let wal = @realtime_db.WAL::new("/tmp/test.wal", 100)
  let _ = wal.append(@realtime_db.Operation::Set("a", @realtime_db.Int(1)))
  let _ = wal.append(@realtime_db.Operation::Commit(1))
  let _ = wal.sync()
  // 刷盘后新写入但未刷盘的条目
  let _ = wal.append(@realtime_db.Operation::Set("b", @realtime_db.Int(2)))

  let replayed : Array[String] = []
  wal.replay(fn(op, _tx) { replayed.push(op.to_string()) })
  assert_eq(replayed, ["SET a=1", "COMMIT 1"])
}

///|
test "wal_append_and_flush_at_threshold" {
  let wal = @realtime_db.WAL::new("/tmp/test.wal", 2)
  assert_false(wal.should_flush())
  let _ = wal.append_and_flush(@realtime_db.Operation::Begin(1))
  assert_eq(wal.buffer_size(), 1) // 阈值未到，不刷盘
  let _ = wal.append_and_flush(
    @realtime_db.Operation::Set("k", @realtime_db.Null),
    timestamp=1,
    tx_id=1,
  )
  assert_eq(wal.buffer_size(), 0) // 达到阈值自动刷盘
  assert_eq(wal.persisted_size(), 2)
}

///|
test "wal_operation_to_string_all_variants" {
  assert_eq(
    @realtime_db.Operation::Set("k", @realtime_db.Int(9)).to_string(),
    "SET k=9",
  )
  assert_eq(@realtime_db.Operation::Delete("k").to_string(), "DELETE k")
  assert_eq(@realtime_db.Operation::Begin(7).to_string(), "BEGIN 7")
  assert_eq(@realtime_db.Operation::Commit(7).to_string(), "COMMIT 7")
  assert_eq(@realtime_db.Operation::Rollback(7).to_string(), "ROLLBACK 7")
}
