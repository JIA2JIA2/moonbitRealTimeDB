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
