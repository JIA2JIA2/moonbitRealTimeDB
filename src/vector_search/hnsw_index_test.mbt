// HNSW 索引测试

///|
test "hnsw_insert_and_retrieve" {
  // 测试插入后检索
  let config = @vector_search.HNSWConfig::default()
  let index = @vector_search.HNSWIndex::new(config)
  // 插入测试向量
  let vector1 : Array[Double] = [1.0, 0.0, 0.0]
  let vector2 : Array[Double] = [0.9, 0.1, 0.0]
  let vector3 : Array[Double] = [0.0, 0.0, 1.0]
  let _ = index.insert("vec1", vector1, @vector_search.Cosine)
  let _ = index.insert("vec2", vector2, @vector_search.Cosine)
  let _ = index.insert("vec3", vector3, @vector_search.Cosine)
  // 检索与 vec1 相似的向量
  let query : Array[Double] = [1.0, 0.0, 0.0]
  let results = index.search_top_k(query, 1, @vector_search.Cosine)
  // 验证结果 - 至少找到1个
  assert_true(results.length() >= 1)
  // vec1 应该是第一个结果
  assert_eq(results[0].0, "vec1")
}

///|
test "hnsw_delete" {
  // 测试删除功能
  let config = @vector_search.HNSWConfig::default()
  let index = @vector_search.HNSWIndex::new(config)
  // 插入向量
  let vector1 : Array[Double] = [1.0, 0.0]
  let vector2 : Array[Double] = [0.0, 1.0]
  let _ = index.insert("vec1", vector1, @vector_search.Cosine)
  let _ = index.insert("vec2", vector2, @vector_search.Cosine)
  // 验证插入成功
  assert_eq(index.size(), 2)
  // 删除 vec1
  let result = index.delete("vec1", @vector_search.Cosine)
  assert_true(result is Ok(_))
  // 验证删除后索引大小
  assert_eq(index.size(), 1)
  // 验证 vec1 不存在
  assert_true(!index.contains("vec1"))
  // 验证 vec2 存在
  assert_true(index.contains("vec2"))
}

///|
test "hnsw_empty_index_search" {
  // 测试空索引检索
  let config = @vector_search.HNSWConfig::default()
  let index = @vector_search.HNSWIndex::new(config)
  let query : Array[Double] = [1.0, 0.0]
  let results = index.search_top_k(query, 5, @vector_search.Cosine)
  assert_eq(results.length(), 0)
}

///|
test "hnsw_duplicate_insert" {
  // 测试重复插入
  let config = @vector_search.HNSWConfig::default()
  let index = @vector_search.HNSWIndex::new(config)
  let vector : Array[Double] = [1.0, 0.0]
  let _ = index.insert("vec1", vector, @vector_search.Cosine)
  // 重复插入应该返回错误
  let result = index.insert("vec1", vector, @vector_search.Cosine)
  assert_true(result is Err(_))
}

///|
test "hnsw_config_validation" {
  // 测试配置验证
  let config = @vector_search.HNSWConfig::{
    m: 8,
    ef_construction: 50,
    ef_search: 25,
    max_layers: 4,
  }
  let index = @vector_search.HNSWIndex::new(config)
  assert_eq(index.config.m, 8)
  assert_eq(index.config.ef_construction, 50)
  assert_eq(index.config.ef_search, 25)
  assert_eq(index.config.max_layers, 4)
}

///|
test "hnsw_clear" {
  // 测试清空索引
  let config = @vector_search.HNSWConfig::default()
  let index = @vector_search.HNSWIndex::new(config)
  // 插入一些向量
  let _ = index.insert("vec1", [1.0, 0.0], @vector_search.Cosine)
  let _ = index.insert("vec2", [0.0, 1.0], @vector_search.Cosine)
  assert_eq(index.size(), 2)
  // 清空索引
  index.clear()
  assert_eq(index.size(), 0)
  assert_eq(index.entry_level, -1)
  assert_eq(index.entry_point, "")
}

///|
test "hnsw_backlinks_connected" {
  // 双向连接必须写回节点表：首节点也应能看到后续节点的入边
  let config = @vector_search.HNSWConfig::default()
  let index = @vector_search.HNSWIndex::new(config)
  let _ = index.insert("a", [1.0, 0.0], @vector_search.Cosine)
  let _ = index.insert("b", [0.0, 1.0], @vector_search.Cosine)
  let _ = index.insert("c", [0.5, 0.5], @vector_search.Cosine)
  match index.get("a") {
    Some(node) => assert_true(node.neighbors[0].contains("b"))
    None => assert_true(false)
  }
}

///|
test "hnsw_search_traverses_graph" {
  // 目标不是入口点时，必须沿图边遍历找到它（验证余弦距离方向）
  let config = @vector_search.HNSWConfig::default()
  let index = @vector_search.HNSWIndex::new(config)
  let _ = index.insert("a", [1.0, 0.0], @vector_search.Cosine)
  let _ = index.insert("b", [0.0, 1.0], @vector_search.Cosine)
  let _ = index.insert("c", [0.5, 0.5], @vector_search.Cosine)
  let results = index.search_top_k([0.0, 1.0], 1, @vector_search.Cosine)
  assert_eq(results.length(), 1)
  assert_eq(results[0].0, "b")
}

///|
test "hnsw_search_after_entry_deleted" {
  // 删除入口点后，悬空引用必须被清理，后续检索不能 panic 且结果正确
  let config = @vector_search.HNSWConfig::default()
  let index = @vector_search.HNSWIndex::new(config)
  let _ = index.insert("a", [1.0, 0.0], @vector_search.Cosine)
  let _ = index.insert("b", [0.0, 1.0], @vector_search.Cosine)
  let _ = index.insert("c", [0.5, 0.5], @vector_search.Cosine)
  let _ = index.delete("a", @vector_search.Cosine)
  let results = index.search_top_k([1.0, 0.0], 1, @vector_search.Cosine)
  assert_eq(results.length(), 1)
  assert_eq(results[0].0, "c")
}

///|
test "index_type_eq" {
  assert_true(@vector_search.HNSW == @vector_search.HNSW)
  assert_true(@vector_search.IVF == @vector_search.IVF)
  assert_true(@vector_search.HNSW != @vector_search.IVF)
}

///|
test "hnsw_basic_insert_search" {
  // 基本插入和搜索测试
  let config = @vector_search.HNSWConfig::default()
  let index = @vector_search.HNSWIndex::new(config)

  // 插入多条向量
  let _ = index.insert("a", [1.0, 0.0], @vector_search.Cosine)
  let _ = index.insert("b", [0.0, 1.0], @vector_search.Cosine)
  let _ = index.insert("c", [0.5, 0.5], @vector_search.Cosine)

  // 验证索引大小
  assert_eq(index.size(), 3)

  // 搜索最相似的向量
  let query : Array[Double] = [1.0, 0.0]
  let results = index.search_top_k(query, 1, @vector_search.Cosine)

  // 验证结果 - 至少找到1个
  assert_true(results.length() >= 1)
  assert_eq(results[0].0, "a")
}

///|
test "hnsw_level_clamped_by_max_layers" {
  // 随机层级必须受 max_layers 约束：max_layers=2 时最高只允许 level 1
  let config = @vector_search.HNSWConfig::{
    m: 8,
    ef_construction: 50,
    ef_search: 25,
    max_layers: 2,
  }
  let index = @vector_search.HNSWIndex::new(config)
  let result = index.insert("a", [1.0, 0.0], @vector_search.Cosine)
  assert_true(result is Ok(_))
  match index.get("a") {
    Some(node) => assert_true(node.level <= 1)
    None => assert_true(false)
  }
  // 入口层级与首节点层级一致（修复前所有节点固定落在顶层，
  // 多层结构名存实亡；现在层级按几何分布随机采样）
  assert_eq(index.entry_level, index.get("a").unwrap().level)
}

///|
test "hnsw_config_validate" {
  let valid = @vector_search.HNSWConfig::default()
  assert_true(valid.validate() is Ok(_))
  let bad = @vector_search.HNSWConfig::{
    m: 0,
    ef_construction: 50,
    ef_search: 25,
    max_layers: 4,
  }
  assert_true(bad.validate() is Err(_))
  // 非法配置下插入必须报错而不是 panic
  let index = @vector_search.HNSWIndex::new(bad)
  let result = index.insert("a", [1.0, 0.0], @vector_search.Cosine)
  assert_true(result is Err(_))
  // 非法配置下检索安全返回空
  assert_eq(
    index.search_top_k([1.0, 0.0], 1, @vector_search.Cosine).length(),
    0,
  )
}

///|
/// 确定性伪随机向量生成器（xorshift32），生成 dim 维均匀分布向量
fn test_vector(seed : Int, dim : Int) -> Array[Double] {
  let v : Array[Double] = Array(capacity=dim)
  let mut x = if seed == 0 { 1 } else { seed }
  let mut j = 0
  while j < dim {
    x = x ^ (x << 13)
    x = x ^ (x >>> 17)
    x = x ^ (x << 5)
    v.push((x & 0x7fffffff).to_double() / 2147483647.0 - 0.5)
    j = j + 1
  }
  v
}

///|
/// 守门员测试：100 个节点（超过 m=8，邻居饱和场景）下，近似
/// Top-10 与全量扫描的精确 Top-10 平均召回率必须 >= 0.9。
/// 这是后续所有 HNSW 改动的召回率回归底线。
test "hnsw_recall_against_exact" {
  let config = @vector_search.HNSWConfig::{
    m: 8,
    ef_construction: 40,
    ef_search: 64,
    max_layers: 6,
  }
  let index = @vector_search.HNSWIndex::new(config)
  let dim = 4
  let n = 100
  let mut i = 0
  while i < n {
    let _ = index.insert("v_\{i}", test_vector(i + 1, dim), @vector_search.Euclidean)
    i = i + 1
  }
  assert_eq(index.size(), n)
  let k = 10
  let mut total_recall = 0.0
  let mut q = 0
  while q < 20 {
    let query = test_vector(100000 + q, dim)
    // 精确 Top-K：全量扫描
    let exact : Array[(String, Double)] = Array(capacity=n)
    let mut t = 0
    while t < n {
      let key = "v_\{t}"
      match index.get(key) {
        Some(node) =>
          exact.push(
            (
              key,
              @vector_search.DistanceCalculator::euclidean_distance(
                query,
                node.vector,
              ),
            ),
          )
        None => ()
      }
      t = t + 1
    }
    exact.sort_by(fn(a, b) { a.1.compare(b.1) })
    let exact_keys : Array[String] = Array(capacity=k)
    let mut e = 0
    while e < k && e < exact.length() {
      exact_keys.push(exact[e].0)
      e = e + 1
    }
    // 近似 Top-K
    let approx = index.search_top_k(query, k, @vector_search.Euclidean)
    let mut hits = 0
    for (id, _) in approx {
      if exact_keys.contains(id) {
        hits = hits + 1
      }
    }
    total_recall = total_recall +
      hits.to_double() /
      exact_keys.length().to_double()
    q = q + 1
  }
  let avg_recall = total_recall / 20.0
  assert_true(avg_recall >= 0.9)
}
