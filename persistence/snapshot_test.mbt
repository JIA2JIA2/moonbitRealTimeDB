// 快照模块黑盒测试。

///|
test "snapshot_metadata_accessors" {
  let m = @realtime_db.SnapshotMetadata::new(100, 256, "abc123", 7)
  assert_eq(m.create_time(), 100)
  assert_eq(m.size(), 256)
  assert_eq(m.checksum(), "abc123")
  assert_eq(m.version(), 7)
}

///|
test "snapshot_create_computes_size" {
  let data = Map([
    ("a", "1"), // 1+1 = 2
    ("bb", "ccc"), // 2+3 = 5，合计 7
  ])
  let snap = @realtime_db.Snapshot::create(data, 3)
  assert_eq(snap.metadata().version(), 3)
  assert_eq(snap.metadata().size(), 7)
  assert_eq(snap.data().length(), 2)
}

///|
test "snapshot_load" {
  let data = Map([("k", "v")])
  let meta = @realtime_db.SnapshotMetadata::new(50, 2, "sum", 9)
  let snap = @realtime_db.Snapshot::load(data, meta)
  assert_eq(snap.metadata().create_time(), 50)
  assert_eq(snap.metadata().checksum(), "sum")
  assert_eq(snap.data().length(), 1)
}

///|
test "scheduler_should_snapshot" {
  let s = @realtime_db.SnapshotScheduler::new(10, 2)
  assert_eq(s.max_retention(), 2)
  assert_false(s.should_snapshot(9))
  assert_true(s.should_snapshot(10))
  assert_true(s.should_snapshot(11))
}

///|
test "scheduler_evicts_oldest" {
  // 原 bug：超限时 pop() 删掉的是最新快照；应淘汰最老的。
  let s = @realtime_db.SnapshotScheduler::new(1, 2)
  s.record_snapshot("snap-0", 1)
  s.record_snapshot("snap-1", 2)
  assert_eq(s.snapshots(), ["snap-0", "snap-1"])
  // 第三次记录触发淘汰：最老的 snap-0 被删除
  s.record_snapshot("snap-2", 3)
  assert_eq(s.snapshots(), ["snap-1", "snap-2"])
}
