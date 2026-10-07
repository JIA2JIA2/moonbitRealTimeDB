// 二级索引集成测试
//
// 测试索引创建、查询、更新、删除、重建等完整流程

///|
/// 测试辅助：从键值对数组构造 Value::Map
fn map_of(pairs : Array[(String, @realtime_db.Value)]) -> @realtime_db.Value {
  let m : Map[String, @realtime_db.Value] = Map([])
  for (k, v) in pairs {
    m.set(k, v)
  }
  @realtime_db.Map(m)
}

///|
/// 测试辅助：数组是否包含某字符串
fn contains_key(arr : Array[String], item : String) -> Bool {
  for x in arr {
    if x == item {
      return true
    }
  }
  false
}

///|
test "test_hash_index_basic" {
  let idx = @index.HashIndex::new("test_hash")
  assert_eq(idx.size(), 0)
  assert_eq(idx.index_type(), @index.Hash)

  // 测试插入
  assert_true(idx.insert(@realtime_db.Int(100), "key1"))
  assert_true(idx.insert(@realtime_db.Int(200), "key2"))
  assert_true(idx.insert(@realtime_db.Int(100), "key3")) // 重复值
  assert_eq(idx.size(), 3)

  // 测试等值查询
  let result = idx.query(@realtime_db.Int(100))
  assert_eq(result.length(), 2)
  assert_true(contains_key(result, "key1"))
  assert_true(contains_key(result, "key3"))

  // 测试删除
  assert_true(idx.delete(@realtime_db.Int(100), "key1"))
  let result2 = idx.query(@realtime_db.Int(100))
  assert_eq(result2.length(), 1)
  assert_eq(result2[0], "key3")

  // 测试清空
  idx.clear()
  assert_eq(idx.size(), 0)
}

///|
test "test_hash_same_key_update_count" {
  // 回归：同一数据键更新值时 total_entries 不应重复计数
  let idx = @index.HashIndex::new("test_hash_update")
  assert_true(idx.insert(@realtime_db.Int(1), "k1"))
  assert_true(idx.insert(@realtime_db.Int(2), "k1")) // 同键换值
  assert_eq(idx.size(), 1)
  assert_eq(idx.query(@realtime_db.Int(1)).length(), 0)
  let r = idx.query(@realtime_db.Int(2))
  assert_eq(r.length(), 1)
  assert_eq(r[0], "k1")

  // 幂等插入相同 (value, key)
  assert_true(idx.insert(@realtime_db.Int(2), "k2"))
  assert_false(idx.insert(@realtime_db.Int(2), "k2"))
  assert_eq(idx.size(), 2)
}

///|
test "test_btree_index_range_query" {
  let idx = @index.BTreeIndex::new("test_btree")
  assert_eq(idx.index_type(), @index.BTree)

  let _ = idx.insert(@realtime_db.Int(10), "key1")
  let _ = idx.insert(@realtime_db.Int(20), "key2")
  let _ = idx.insert(@realtime_db.Int(30), "key3")
  let _ = idx.insert(@realtime_db.Int(40), "key4")
  let _ = idx.insert(@realtime_db.Int(50), "key5")

  // [20, 40)
  let result = idx.range_query(
    Some(@realtime_db.Int(20)),
    Some(@realtime_db.Int(40)),
    Some(true),
    Some(false),
  )
  assert_eq(result.length(), 2)
  assert_true(contains_key(result, "key2"))
  assert_true(contains_key(result, "key3"))

  // [20, 40]
  let result2 = idx.range_query(
    Some(@realtime_db.Int(20)),
    Some(@realtime_db.Int(40)),
    Some(true),
    Some(true),
  )
  assert_eq(result2.length(), 3)

  // (-, 30]
  let result3 = idx.range_query(
    None,
    Some(@realtime_db.Int(30)),
    None,
    Some(true),
  )
  assert_eq(result3.length(), 3)

  // 等值点查
  let exact = idx.query(@realtime_db.Int(30))
  assert_eq(exact.length(), 1)
  assert_eq(exact[0], "key3")
}

///|
test "test_btree_large_insert_and_splits" {
  // 回归：大量插入触发叶子/内部节点分裂后，点查与范围仍然正确
  let idx = @index.BTreeIndex::with_order("test_btree_big", 4)
  let n = 100

  let mut i = 0
  while i < n {
    let key = "k" + i.to_string()
    assert_true(idx.insert(@realtime_db.Int(i), key))
    i = i + 1
  }
  assert_eq(idx.size(), n)
  assert_true(idx.height() >= 3)
  assert_true(idx.node_count() > 1)

  // 每个点都能查到
  i = 0
  while i < n {
    let key = "k" + i.to_string()
    let r = idx.query(@realtime_db.Int(i))
    assert_eq(r.length(), 1)
    assert_eq(r[0], key)
    i = i + 1
  }

  // 范围 [10, 20) = 10 个
  let range = idx.range_query(
    Some(@realtime_db.Int(10)),
    Some(@realtime_db.Int(20)),
    Some(true),
    Some(false),
  )
  assert_eq(range.length(), 10)

  // 逆序插入另一棵树，验证反向分裂
  let idx2 = @index.BTreeIndex::with_order("test_btree_rev", 4)
  let mut j = n - 1
  while j >= 0 {
    let _ = idx2.insert(@realtime_db.Int(j), "r" + j.to_string())
    j = j - 1
  }
  assert_eq(idx2.size(), n)
  let rr = idx2.query(@realtime_db.Int(0))
  assert_eq(rr.length(), 1)
  assert_eq(rr[0], "r0")

  // 删除后点查失效
  assert_true(idx.delete(@realtime_db.Int(50), "k50"))
  assert_eq(idx.query(@realtime_db.Int(50)).length(), 0)
  assert_eq(idx.size(), n - 1)
}

///|
test "test_fulltext_index_prefix_query" {
  let idx = @index.FulltextIndex::new("test_fulltext")
  assert_eq(idx.index_type(), @index.Fulltext)

  let _ = idx.insert(@realtime_db.Str("张三"), "key1")
  let _ = idx.insert(@realtime_db.Str("张四"), "key2")
  let _ = idx.insert(@realtime_db.Str("李四"), "key3")
  let _ = idx.insert(@realtime_db.Str("张五"), "key4")

  let result = idx.prefix_query("张")
  assert_eq(result.length(), 3)
  assert_true(contains_key(result, "key1"))
  assert_true(contains_key(result, "key2"))
  assert_true(contains_key(result, "key4"))

  let result2 = idx.query(@realtime_db.Str("李四"))
  assert_eq(result2.length(), 1)
  assert_eq(result2[0], "key3")

  assert_eq(idx.prefix_query("王").length(), 0)
}

///|
test "test_fulltext_delete_cleanup_and_reinsert" {
  // 回归：删除后悬空 Trie 节点应被清理，且可重新插入
  let idx = @index.FulltextIndex::new("test_fulltext_del")
  assert_true(idx.insert(@realtime_db.Str("apple"), "a"))
  assert_true(idx.insert(@realtime_db.Str("app"), "b"))
  let nodes_before = idx.node_count()

  assert_true(idx.delete(@realtime_db.Str("apple"), "a"))
  assert_eq(idx.query(@realtime_db.Str("apple")).length(), 0)
  // "app" 仍然可查
  let app = idx.query(@realtime_db.Str("app"))
  assert_eq(app.length(), 1)
  assert_eq(app[0], "b")
  assert_true(idx.node_count() < nodes_before)

  // 清理后的路径可重新插入
  assert_true(idx.insert(@realtime_db.Str("apple"), "c"))
  let again = idx.prefix_query("app")
  assert_eq(again.length(), 2)
  assert_true(contains_key(again, "b"))
  assert_true(contains_key(again, "c"))

  // 删除不存在的条目返回 false
  assert_false(idx.delete(@realtime_db.Str("apple"), "missing"))
}

///|
test "test_field_parser" {
  let parser = @index.FieldParser::new()

  let result1 = parser.parse_path("user.name")
  match result1 {
    Ok(segments) => {
      assert_eq(segments.length(), 2)
      match segments[0] {
        @index.Key(k) => assert_eq(k, "user")
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }

  let result2 = parser.parse_path("user.profile.age")
  match result2 {
    Ok(segments) => assert_eq(segments.length(), 3)
    Err(_) => assert_true(false)
  }

  let result3 = parser.parse_path("items[0].name")
  match result3 {
    Ok(segments) => assert_eq(segments.length(), 3)
    Err(_) => assert_true(false)
  }

  // 非法索引
  match parser.parse_path("items[x].name") {
    Ok(_) => assert_true(false)
    Err(_) => assert_true(true)
  }

  let value = map_of([
    (
      "user",
      map_of([
        ("name", @realtime_db.Str("张三")),
        ("age", @realtime_db.Int(25)),
      ]),
    ),
  ])

  let name = parser.extract_value(value, "user.name")
  match name {
    Some(@realtime_db.Str(s)) => assert_eq(s, "张三")
    _ => assert_true(false)
  }

  let age = parser.extract_value(value, "user.age")
  match age {
    Some(@realtime_db.Int(i)) => assert_eq(i, 25)
    _ => assert_true(false)
  }

  assert_true(parser.extract_value(value, "user.address") is None)

  // 第二次解析走缓存，命中率提升
  let _ = parser.parse_path("user.name")
  assert_true(parser.cache_hit_rate() > 0.0)
}

///|
test "test_index_manager_lifecycle" {
  let manager = @index.IndexManager::new()
  let db = @realtime_db.DB::new()
  manager.set_db(Some(db))

  let result = manager.create_index("idx_name", ["name"], @index.Hash, false)
  match result {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(false)
  }

  let result2 = manager.create_index("idx_name", ["name"], @index.Hash, false)
  match result2 {
    Err(@index.Index_Already_Exists) => assert_true(true)
    _ => assert_true(false)
  }

  let indices = manager.list_indexes()
  assert_eq(indices.length(), 1)
  assert_eq(indices[0].name, "idx_name")

  let meta = manager.get_index_meta("idx_name")
  match meta {
    Some(m) => {
      assert_eq(m.name, "idx_name")
      assert_eq(m.status, @index.Active)
    }
    None => assert_true(false)
  }

  let drop_result = manager.drop_index("idx_name")
  match drop_result {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(false)
  }
  assert_eq(manager.list_indexes().length(), 0)
}

///|
test "test_index_query_with_data" {
  let db = @realtime_db.DB::new()
  let manager = @index.IndexManager::new()
  manager.set_db(Some(db))

  db.set(
    "user1",
    map_of([
      ("name", @realtime_db.Str("张三")),
      ("age", @realtime_db.Int(25)),
      ("city", @realtime_db.Str("北京")),
    ]),
  )
  db.set(
    "user2",
    map_of([
      ("name", @realtime_db.Str("李四")),
      ("age", @realtime_db.Int(30)),
      ("city", @realtime_db.Str("上海")),
    ]),
  )
  db.set(
    "user3",
    map_of([
      ("name", @realtime_db.Str("王五")),
      ("age", @realtime_db.Int(25)),
      ("city", @realtime_db.Str("北京")),
    ]),
  )

  let _ = manager.create_index("idx_age", ["age"], @index.Hash, false)

  let storage = manager.get_index_storage("idx_age")
  match storage {
    Some(s) => {
      let keys = s.query(@realtime_db.Int(25))
      assert_eq(keys.length(), 2)
      assert_true(contains_key(keys, "user1"))
      assert_true(contains_key(keys, "user3"))
    }
    None => assert_true(false)
  }
}

///|
test "test_manager_watch_incremental_update" {
  // 回归：数据变更后索引应通过 watch 自动增量更新
  let db = @realtime_db.DB::new()
  let manager = @index.IndexManager::new()
  manager.set_db(Some(db))

  db.set("user1", map_of([("age", @realtime_db.Int(25))]))
  let _ = manager.create_index("idx_age", ["age"], @index.Hash, false)

  // 新增记录
  db.set("user2", map_of([("age", @realtime_db.Int(28))]))
  let storage = manager.get_index_storage("idx_age")
  match storage {
    Some(s) => {
      let keys = s.query(@realtime_db.Int(28))
      assert_eq(keys.length(), 1)
      assert_eq(keys[0], "user2")
    }
    None => assert_true(false)
  }

  // 更新已有记录：旧值条目移除，新值条目出现
  db.set("user1", map_of([("age", @realtime_db.Int(99))]))
  let storage2 = manager.get_index_storage("idx_age")
  match storage2 {
    Some(s) => {
      assert_eq(s.query(@realtime_db.Int(25)).length(), 0)
      let moved = s.query(@realtime_db.Int(99))
      assert_eq(moved.length(), 1)
      assert_eq(moved[0], "user1")
    }
    None => assert_true(false)
  }

  // 删除记录
  let _ = db.delete("user2")
  let storage3 = manager.get_index_storage("idx_age")
  match storage3 {
    Some(s) => assert_eq(s.query(@realtime_db.Int(28)).length(), 0)
    None => assert_true(false)
  }
}

///|
test "test_query_engine" {
  let db = @realtime_db.DB::new()
  let manager = @index.IndexManager::new()
  manager.set_db(Some(db))

  db.set("user1", map_of([("age", @realtime_db.Int(25))]))
  db.set("user2", map_of([("age", @realtime_db.Int(30))]))
  db.set("user3", map_of([("age", @realtime_db.Int(25))]))

  let _ = manager.create_index("idx_age", ["age"], @index.Hash, false)

  let engine = @index.QueryEngine::new()
  engine.set_db(Some(db))
  engine.set_manager(Some(manager))

  let selector = @index.IndexSelector::new()
  selector.set_manager(Some(manager))
  engine.set_selector(Some(selector))

  // 指定索引的等值查询
  let result = engine.index_query(
    Some("idx_age"),
    "age",
    @realtime_db.Int(25),
    None,
    None,
  )
  match result {
    Ok(r) => assert_eq(r.keys.length(), 2)
    Err(_) => assert_true(false)
  }

  // 第二次查询命中缓存
  let result_cached = engine.index_query(
    Some("idx_age"),
    "age",
    @realtime_db.Int(25),
    None,
    None,
  )
  match result_cached {
    Ok(r) => {
      assert_eq(r.keys.length(), 2)
      assert_true(r.hit_cache)
    }
    Err(_) => assert_true(false)
  }

  // limit 分页
  let paged = engine.index_query(
    Some("idx_age"),
    "age",
    @realtime_db.Int(25),
    Some(1),
    Some(0),
  )
  match paged {
    Ok(r) => assert_eq(r.keys.length(), 1)
    Err(_) => assert_true(false)
  }

  // 自动选择索引
  let auto = engine.index_query(None, "age", @realtime_db.Int(30), None, None)
  match auto {
    Ok(r) => {
      assert_eq(r.keys.length(), 1)
      assert_eq(r.index_used, "idx_age")
    }
    Err(_) => assert_true(false)
  }

  // 回表
  match result {
    Ok(r) => {
      let full = engine.fetch_full_data(r.keys)
      assert_eq(full.length(), 2)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_index_rebuild" {
  let db = @realtime_db.DB::new()
  let manager = @index.IndexManager::new()
  manager.set_db(Some(db))

  db.set("key1", map_of([("value", @realtime_db.Int(100))]))
  db.set("key2", map_of([("value", @realtime_db.Int(200))]))

  let create_result = manager.create_index(
    "idx_value",
    ["value"],
    @index.Hash,
    false,
  )
  assert_true(create_result is Ok(_))

  match manager.get_index_storage("idx_value") {
    Some(s) => assert_eq(s.size(), 2)
    None => assert_true(false)
  }

  let rebuild_result = manager.rebuild_index("idx_value", @index.Full)
  match rebuild_result {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(false)
  }

  match manager.get_index_storage("idx_value") {
    Some(s) => {
      assert_eq(s.size(), 2)
      let keys = s.query(@realtime_db.Int(100))
      assert_eq(keys.length(), 1)
    }
    None => assert_true(false)
  }
}

///|
test "test_batch_operations" {
  let idx = @index.HashIndex::new("test_batch")

  let inserts = [
    (@realtime_db.Int(1), "key1"),
    (@realtime_db.Int(2), "key2"),
    (@realtime_db.Int(1), "key3"),
  ]
  let deletes : Array[(@realtime_db.Value, String)] = []

  let result = idx.batch_update(inserts, deletes)
  assert_eq(result.inserted, 3)
  assert_eq(result.deleted, 0)

  let query_result = idx.query(@realtime_db.Int(1))
  assert_eq(query_result.length(), 2)
}

///|
test "test_composite_index_query" {
  let db = @realtime_db.DB::new()
  let manager = @index.IndexManager::new()
  manager.set_db(Some(db))

  db.set("u1", map_of([("a", @realtime_db.Int(1)), ("b", @realtime_db.Int(2))]))
  db.set("u2", map_of([("a", @realtime_db.Int(1)), ("b", @realtime_db.Int(3))]))
  db.set("u3", map_of([("a", @realtime_db.Int(1)), ("b", @realtime_db.Int(2))]))

  let created = manager.create_index(
    "idx_ab",
    ["a", "b"],
    @index.Composite,
    false,
  )
  match created {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(false)
  }

  let engine = @index.QueryEngine::new()
  engine.set_db(Some(db))
  engine.set_manager(Some(manager))

  let r = engine.composite_query(
    "idx_ab",
    [Some(@realtime_db.Int(1)), Some(@realtime_db.Int(2))],
    None,
  )
  match r {
    Ok(qr) => {
      assert_eq(qr.keys.length(), 2)
      assert_true(contains_key(qr.keys, "u1"))
      assert_true(contains_key(qr.keys, "u3"))
    }
    Err(_) => assert_true(false)
  }

  // limit 生效
  let r2 = engine.composite_query(
    "idx_ab",
    [Some(@realtime_db.Int(1)), Some(@realtime_db.Int(2))],
    Some(1),
  )
  match r2 {
    Ok(qr) => assert_eq(qr.keys.length(), 1)
    Err(_) => assert_true(false)
  }
}

///|
test "test_index_selector" {
  let db = @realtime_db.DB::new()
  let manager = @index.IndexManager::new()
  manager.set_db(Some(db))
  db.set("u1", map_of([("age", @realtime_db.Int(25))]))
  let _ = manager.create_index("idx_age", ["age"], @index.Hash, false)

  let selector = @index.IndexSelector::new()
  selector.set_manager(Some(manager))

  let scores = selector.select_index_with_scores([
    @index.QueryCondition::{
      field_path: "age",
      value: Some(@realtime_db.Int(25)),
      query_type: @index.Equal,
    },
  ])
  assert_eq(scores.length(), 1)
  assert_eq(scores[0].index_name, "idx_age")

  let picked = selector.select_index([
    @index.QueryCondition::{
      field_path: "age",
      value: Some(@realtime_db.Int(25)),
      query_type: @index.Equal,
    },
  ])
  match picked {
    Some(name) => assert_eq(name, "idx_age")
    None => assert_true(false)
  }
}

///|
test "test_stats_collector" {
  let db = @realtime_db.DB::new()
  let manager = @index.IndexManager::new()
  manager.set_db(Some(db))
  db.set("u1", map_of([("age", @realtime_db.Int(25))]))
  db.set("u2", map_of([("age", @realtime_db.Int(30))]))
  let _ = manager.create_index("idx_age", ["age"], @index.Hash, false)

  let collector = @index.StatsCollector::new()
  collector.set_manager(Some(manager))

  match collector.collect_stats(Some("idx_age")) {
    Ok(stats) => {
      assert_eq(stats.name, "idx_age")
      assert_eq(stats.total_entries, 2)
      assert_true(stats.memory_usage > 0)
    }
    Err(_) => assert_true(false)
  }

  let cached = collector.get_index_stats("idx_age")
  match cached {
    Some(s) => assert_eq(s.total_entries, 2)
    None => assert_true(false)
  }
  assert_true(collector.expose_metrics().length() > 0)
}

///|
test "test_defragmenter" {
  let db = @realtime_db.DB::new()
  let manager = @index.IndexManager::new()
  manager.set_db(Some(db))
  db.set("u1", map_of([("age", @realtime_db.Int(25))]))
  db.set("u2", map_of([("age", @realtime_db.Int(30))]))
  let _ = manager.create_index("idx_age", ["age"], @index.Hash, false)

  let defrag = @index.Defragmenter::new()
  defrag.set_manager(Some(manager))
  // 阈值设为 0，强制触发整理
  defrag.set_fragmentation_threshold(0.0)

  match defrag.defragment(Some("idx_age")) {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(false)
  }

  // 整理后数据仍在
  match manager.get_index_storage("idx_age") {
    Some(s) => {
      assert_eq(s.size(), 2)
      assert_eq(s.query(@realtime_db.Int(25)).length(), 1)
    }
    None => assert_true(false)
  }

  let st = defrag.get_stats()
  assert_eq(st.total_runs, 1)
  assert_eq(st.indices_processed, 1)
}
