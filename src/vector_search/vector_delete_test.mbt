// 向量删除与变更订阅测试

///|
test "delete_single_removes_record_and_count" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "col",
    2,
    @vector_search.Cosine,
    @vector_search.Exact,
    None,
    Array(capacity=0),
    "t1",
  )
  let wal = @persistence.WAL::new("test_delete.wal", 1024)
  let writer = @vector_search.VectorWriter::new(mgr, wal)

  writer.insert_single("col", "t1", "a", [1.0, 0.0], Map([]))
  writer.insert_single("col", "t1", "b", [0.0, 1.0], Map([]))
  assert_eq(mgr.list_records("col", "t1").length(), 2)

  assert_true(writer.delete_single("col", "t1", "a"))
  assert_true(mgr.get_record("col", "t1", "a") is None)
  assert_true(mgr.get_record("col", "t1", "b") is Some(_))
  assert_eq(mgr.list_records("col", "t1").length(), 1)

  // record_count 随删除递减
  match mgr.get_collection("col", "t1") {
    Some(meta) => assert_eq(meta.record_count, 1)
    None => assert_true(false)
  }
}

///|
test "delete_missing_record_returns_false" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "col",
    2,
    @vector_search.Cosine,
    @vector_search.Exact,
    None,
    Array(capacity=0),
    "t1",
  )
  let wal = @persistence.WAL::new("test_delete.wal", 1024)
  let writer = @vector_search.VectorWriter::new(mgr, wal)

  assert_true(!writer.delete_single("col", "t1", "missing"))
  assert_true(!mgr.delete_record("col", "t1", "missing"))
  assert_true(!mgr.delete_record("no_such_collection", "t1", "a"))

  // 不存在的集合不产生负计数
  match mgr.get_collection("col", "t1") {
    Some(meta) => assert_eq(meta.record_count, 0)
    None => assert_true(false)
  }
}

///|
test "delete_batch_counts_successful_deletes" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "col",
    2,
    @vector_search.Cosine,
    @vector_search.Exact,
    None,
    Array(capacity=0),
    "t1",
  )
  let wal = @persistence.WAL::new("test_delete.wal", 1024)
  let writer = @vector_search.VectorWriter::new(mgr, wal)

  writer.insert_single("col", "t1", "a", [1.0, 0.0], Map([]))
  writer.insert_single("col", "t1", "b", [0.0, 1.0], Map([]))
  writer.insert_single("col", "t1", "c", [0.5, 0.5], Map([]))

  let deleted = writer.delete_batch("col", "t1", ["a", "missing", "c"])
  assert_eq(deleted, 2)
  assert_eq(mgr.list_records("col", "t1").length(), 1)
  match mgr.get_collection("col", "t1") {
    Some(meta) => assert_eq(meta.record_count, 1)
    None => assert_true(false)
  }
}

///|
test "delete_syncs_hnsw_index" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "col",
    2,
    @vector_search.Cosine,
    @vector_search.Approximate,
    Some(
      @vector_search.IndexConfig::new_hnsw(@vector_search.HNSWConfig::default()),
    ),
    Array(capacity=0),
    "t1",
  )
  let wal = @persistence.WAL::new("test_delete.wal", 1024)
  let writer = @vector_search.VectorWriter::new(mgr, wal)

  writer.insert_single("col", "t1", "a", [1.0, 0.0], Map([]))
  writer.insert_single("col", "t1", "b", [0.9, 0.1], Map([]))
  writer.insert_single("col", "t1", "c", [0.0, 1.0], Map([]))
  assert_true(writer.delete_single("col", "t1", "a"))

  match mgr.search_index("col", "t1", [1.0, 0.0], 10) {
    Some(hits) => {
      assert_eq(hits.length(), 2)
      for hit in hits {
        assert_true(hit.0 != "a")
      }
    }
    None => assert_true(false)
  }
}

///|
test "change_events_published_and_unsubscribed" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "col",
    2,
    @vector_search.Cosine,
    @vector_search.Exact,
    None,
    Array(capacity=0),
    "t1",
  )
  let wal = @persistence.WAL::new("test_delete.wal", 1024)
  let writer = @vector_search.VectorWriter::new(mgr, wal)
  let events : Array[@vector_search.ChangeEvent] = Array(capacity=0)
  let subscription_id = mgr.subscribe("col", "t1", fn(event) {
    events.push(event)
  })

  writer.insert_single("col", "t1", "a", [1.0, 0.0], Map([]))
  writer.insert_single("col", "t1", "a", [0.9, 0.1], Map([]))
  assert_true(writer.delete_single("col", "t1", "a"))

  assert_eq(events.length(), 3)
  assert_eq(events[0].change_type, @vector_search.Inserted)
  assert_eq(events[0].collection_name, "col")
  assert_eq(events[0].primary_key, "a")
  assert_eq(events[1].change_type, @vector_search.Updated)
  assert_eq(events[2].change_type, @vector_search.Deleted)

  // 取消订阅后不再收到事件
  assert_true(mgr.unsubscribe(subscription_id))
  writer.insert_single("col", "t1", "b", [0.0, 1.0], Map([]))
  assert_eq(events.length(), 3)
  assert_true(!mgr.unsubscribe(subscription_id))
}

///|
test "delete_collection_emits_dropped_event" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "col",
    2,
    @vector_search.Cosine,
    @vector_search.Exact,
    None,
    Array(capacity=0),
    "t1",
  )
  let events : Array[@vector_search.ChangeEvent] = Array(capacity=0)
  let subscription_id = mgr.subscribe("col", "t1", fn(event) {
    events.push(event)
  })

  mgr.delete_collection("col", "t1")
  assert_eq(events.length(), 1)
  assert_eq(events[0].change_type, @vector_search.CollectionDropped)

  // 集合删除后订阅已失效
  assert_true(!mgr.unsubscribe(subscription_id))
}

///|
test "validate_dimension_rejects_out_of_range" {
  assert_true(@vector_search.CollectionManager::validate_dimension(0) is Err(_))
  assert_true(
    @vector_search.CollectionManager::validate_dimension(8193) is Err(_),
  )
  assert_true(@vector_search.CollectionManager::validate_dimension(1) is Ok(_))
  assert_true(
    @vector_search.CollectionManager::validate_dimension(8192) is Ok(_),
  )
}
