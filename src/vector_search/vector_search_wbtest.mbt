// 白盒测试：HNSW 近似索引与写入/检索链路的端到端集成

///|
fn build_writer_engine(
  strategy : IndexStrategy,
) -> (VectorWriter, SearchEngine) {
  let mgr = CollectionManager::new()
  mgr.create_collection(
    "col",
    2,
    Cosine,
    strategy,
    None,
    Array(capacity=0),
    "tenant1",
  )
  let wal = @persistence.WAL::new("test.wal", 1024)
  let writer = VectorWriter::new(mgr, wal)
  let engine = SearchEngine::new(mgr)
  (writer, engine)
}

///|
test "approx_search_uses_hnsw_index" {
  let (writer, engine) = build_writer_engine(Approximate)
  writer.insert_single("col", "tenant1", "a", [1.0, 0.0], Map([]))
  writer.insert_single("col", "tenant1", "b", [0.0, 1.0], Map([]))
  writer.insert_single("col", "tenant1", "c", [0.5, 0.5], Map([]))
  // 查询与 a 完全一致：分数应为 1.0
  let hits = engine.search_approximate("col", "tenant1", [1.0, 0.0], 1)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].primary_key, "a")
  assert_eq(hits[0].score, 1.0)
  // 目标不是入口点时也要能沿图找到
  let hits2 = engine.search_approximate("col", "tenant1", [0.0, 1.0], 1)
  assert_eq(hits2.length(), 1)
  assert_eq(hits2[0].primary_key, "b")
}

///|
test "approx_search_falls_back_to_exact_collection" {
  let (writer, engine) = build_writer_engine(Exact)
  writer.insert_single("col", "tenant1", "a", [1.0, 0.0], Map([]))
  writer.insert_single("col", "tenant1", "b", [0.0, 1.0], Map([]))
  // Exact 集合没有 HNSW 索引，近似检索必须回退到精确检索而非返回空
  let hits = engine.search_approximate("col", "tenant1", [1.0, 0.0], 1)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].primary_key, "a")
}

///|
test "approx_index_reflects_upsert" {
  let (writer, engine) = build_writer_engine(Approximate)
  writer.insert_single("col", "tenant1", "a", [1.0, 0.0], Map([]))
  writer.insert_single("col", "tenant1", "b", [0.0, 1.0], Map([]))
  // 同一主键更新向量：索引必须先删旧节点再插新节点
  writer.insert_single("col", "tenant1", "a", [0.0, 1.0], Map([]))
  let hits = engine.search_approximate("col", "tenant1", [0.0, 1.0], 2)
  assert_eq(hits.length(), 2)
  // a 与 b 现在都是 [0,1]，且旧的 a=[1,0] 节点不应再出现
  assert_eq(hits[0].primary_key == "a" || hits[0].primary_key == "b", true)
  for hit in hits {
    assert_true(hit.primary_key == "a" || hit.primary_key == "b")
  }
}

///|
test "ivf_delete_removes_from_index" {
  let mgr = CollectionManager::new()
  mgr.create_collection(
    "ivf",
    2,
    Cosine,
    Approximate,
    Some(
      IndexConfig::new_ivf(IVFConfig::{ n_list: 2, n_probe: 2, metric: Cosine, }),
    ),
    Array(capacity=0),
    "tenant1",
  )
  let key = "tenant1:ivf"
  let records : Array[(String, Array[Double])] = [
    ("a", [1.0, 0.0]),
    ("b", [0.9, 0.1]),
    ("c", [0.0, 1.0]),
    ("d", [0.1, 0.9]),
  ]
  for (pk, vector) in records {
    let _ = mgr.upsert_record("ivf", "tenant1", VectorRecord::{
      primary_key: pk,
      vector,
      metadata: Map([]),
      version: 1,
      updated_at: 0,
    })
  }

  // 集合创建时 IVF 索引未训练，先训练再补齐插入
  let index = match mgr.ivf_indexes.get(key) {
    Some(i) => i
    None => {
      assert_true(false)
      return
    }
  }
  let training : Array[Array[Double]] = []
  for (_, vector) in records {
    training.push(vector)
  }
  match index.train(training) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  for record in mgr.list_records("ivf", "tenant1") {
    let _ = index.insert(record)
  }
  mgr.ivf_indexes.set(key, index)
  assert_eq(index.size(), 4)

  assert_true(mgr.delete_record("ivf", "tenant1", "a"))
  match mgr.ivf_indexes.get(key) {
    Some(updated) => {
      assert_eq(updated.size(), 3)
      for hit in updated.search_top_k([1.0, 0.0], 10) {
        assert_true(hit.0 != "a")
      }
    }
    None => assert_true(false)
  }
}
