// 向量检索模块测试

///|
test "create_collection_success" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "test_col",
    128,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  assert_eq(mgr.has_collection("test_col", "tenant1"), true)
}

///|
test "delete_collection_success" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "test_col",
    128,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  mgr.delete_collection("test_col", "tenant1")
  assert_eq(mgr.has_collection("test_col", "tenant1"), false)
}

///|
test "get_collection_success" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "test_col",
    128,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  let meta = mgr.get_collection("test_col", "tenant1")
  assert_true(meta is Some(_))
  match meta {
    Some(m) => {
      assert_eq(m.collection_name, "test_col")
      assert_eq(m.dimension, 128)
    }
    None => assert_true(false)
  }
}

///|
test "list_collections_empty" {
  let mgr = @vector_search.CollectionManager::new()
  let list = mgr.list_collections("tenant1")
  assert_eq(list.length(), 0)
}

///|
test "list_collections_multiple" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "col1",
    128,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  mgr.create_collection(
    "col2",
    256,
    @vector_search.Euclidean,
    @vector_search.Approximate,
    Array(capacity=0),
    "tenant1",
  )
  let list = mgr.list_collections("tenant1")
  assert_eq(list.length(), 2)
}

///|
test "tenant_isolation" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "same_name",
    128,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  mgr.create_collection(
    "same_name",
    128,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant2",
  )
  assert_eq(mgr.has_collection("same_name", "tenant1"), true)
  assert_eq(mgr.has_collection("same_name", "tenant2"), true)
}

///|
test "increment_record_count" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "test_col",
    128,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  mgr.increment_record_count("test_col", "tenant1", 10)
  let meta = mgr.get_collection("test_col", "tenant1")
  match meta {
    Some(m) => assert_eq(m.record_count, 10)
    None => assert_true(false)
  }
}

///|
test "vector_writer_insert_single" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "test_col",
    6,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  let wal = @persistence.WAL::new("test.wal", 1024)
  let writer = @vector_search.VectorWriter::new(mgr, wal)
  let vec : Array[Double] = Array(capacity=6)
  vec.push(0.1)
  vec.push(0.2)
  vec.push(0.3)
  vec.push(0.4)
  vec.push(0.5)
  vec.push(0.6)
  writer.insert_single("test_col", "tenant1", "key1", vec, Map([]))
  let meta = mgr.get_collection("test_col", "tenant1")
  match meta {
    Some(m) => assert_eq(m.record_count, 1)
    None => assert_true(false)
  }
}

///|
test "vector_writer_insert_batch" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "test_col",
    6,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  let wal = @persistence.WAL::new("test.wal", 1024)
  let writer = @vector_search.VectorWriter::new(mgr, wal)
  let records : Array[(String, Array[Double], Map[String, @realtime_db.Value])] = Array(
    capacity=2,
  )
  let vec1 : Array[Double] = Array(capacity=6)
  vec1.push(0.1)
  vec1.push(0.2)
  vec1.push(0.3)
  vec1.push(0.4)
  vec1.push(0.5)
  vec1.push(0.6)
  let vec2 : Array[Double] = Array(capacity=6)
  vec2.push(0.3)
  vec2.push(0.4)
  vec2.push(0.5)
  vec2.push(0.6)
  vec2.push(0.7)
  vec2.push(0.8)
  records.push(("key1", vec1, Map([])))
  records.push(("key2", vec2, Map([])))
  writer.insert_batch("test_col", "tenant1", records)
  let meta = mgr.get_collection("test_col", "tenant1")
  match meta {
    Some(m) => assert_eq(m.record_count, 2)
    None => assert_true(false)
  }
}

///|
test "vector_writer_dimension_mismatch" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "test_col",
    128,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  let wal = @persistence.WAL::new("test.wal", 1024)
  let writer = @vector_search.VectorWriter::new(mgr, wal)
  let vec : Array[Double] = Array(capacity=64)
  vec.push(0.1)
  writer.insert_single("test_col", "tenant1", "key1", vec, Map([]))
  let meta = mgr.get_collection("test_col", "tenant1")
  match meta {
    Some(m) => assert_eq(m.record_count, 0)
    None => assert_true(false)
  }
}

///|
test "vector_writer_empty_key" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "test_col",
    6,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  let wal = @persistence.WAL::new("test.wal", 1024)
  let writer = @vector_search.VectorWriter::new(mgr, wal)
  let vec : Array[Double] = Array(capacity=6)
  vec.push(0.1)
  writer.insert_single("test_col", "tenant1", "", vec, Map([]))
  let meta = mgr.get_collection("test_col", "tenant1")
  match meta {
    Some(m) => assert_eq(m.record_count, 0)
    None => assert_true(false)
  }
}

///|
test "distance_cosine_similarity" {
  let a : Array[Double] = Array(capacity=3)
  a.push(1.0)
  a.push(0.0)
  a.push(0.0)
  let b : Array[Double] = Array(capacity=3)
  b.push(1.0)
  b.push(0.0)
  b.push(0.0)
  let result = @vector_search.DistanceCalculator::cosine_similarity(a, b)
  assert_eq(result, 1.0)
}

///|
test "distance_euclidean" {
  let a : Array[Double] = Array(capacity=2)
  a.push(0.0)
  a.push(0.0)
  let b : Array[Double] = Array(capacity=2)
  b.push(3.0)
  b.push(4.0)
  let result = @vector_search.DistanceCalculator::euclidean_distance(a, b)
  assert_eq(result, 5.0)
}

///|
test "distance_inner_product" {
  let a : Array[Double] = Array(capacity=3)
  a.push(1.0)
  a.push(2.0)
  a.push(3.0)
  let b : Array[Double] = Array(capacity=3)
  b.push(4.0)
  b.push(5.0)
  b.push(6.0)
  let result = @vector_search.DistanceCalculator::inner_product(a, b)
  assert_eq(result, 32.0)
}

///|
test "search_engine_empty_collection" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "test_col",
    6,
    @vector_search.Cosine,
    @vector_search.Exact,
    Array(capacity=0),
    "tenant1",
  )
  let engine = @vector_search.SearchEngine::new(mgr)
  let query : Array[Double] = Array(capacity=6)
  query.push(0.1)
  let results = engine.search_exact("test_col", "tenant1", query, 5)
  assert_eq(results.length(), 0)
}
