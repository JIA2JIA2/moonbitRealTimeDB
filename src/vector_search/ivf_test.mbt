// IVF 索引黑盒测试
//
// 覆盖：训练、插入、搜索、边界条件、k-means 收敛

///|
/// 构造测试向量（dim 维，值在 [0, 1) 均匀分布）
fn ivf_test_vector(seed : Int32, dim : Int32) -> Array[Double] {
  let v : Array[Double] = Array(capacity=dim)
  let mut x = if seed == 0 { 1 } else { seed }
  let mut i = 0
  while i < dim {
    x = x ^ (x << 13)
    x = x ^ (x >> 17)
    x = x ^ (x << 5)
    v.push((x & 0x7fffffff).to_double() / 2147483647.0)
    i = i + 1
  }
  v
}

///|
test "ivf_config_validate" {
  let valid = @vector_search.IVFConfig::default()
  assert_true(valid.validate() is Ok(_))
  let bad_nlist = @vector_search.IVFConfig::{
    n_list: 0,
    n_probe: 4,
    metric: @vector_search.Cosine,
  }
  assert_true(bad_nlist.validate() is Err(_))
  let bad_nprobe = @vector_search.IVFConfig::{
    n_list: 10,
    n_probe: 20,
    metric: @vector_search.Cosine,
  }
  assert_true(bad_nprobe.validate() is Err(_))
}

///|
test "ivf_train_and_insert" {
  let config = @vector_search.IVFConfig::{
    n_list: 4,
    n_probe: 2,
    metric: @vector_search.Cosine,
  }
  let index = @vector_search.IVFIndex::new(config, 2)
  assert_false(index.is_trained())

  // 训练集：4 个聚类中心附近各 10 条
  let training : Array[Array[Double]] = Array(capacity=40)
  let centers : Array[Array[Double]] = [
    [1.0, 0.0],
    [0.0, 1.0],
    [-1.0, 0.0],
    [0.0, -1.0],
  ]
  for center in centers {
    let mut i = 0
    while i < 10 {
      let v : Array[Double] = Array(capacity=2)
      let mut d = 0
      while d < 2 {
        v.push(center[d] + (ivf_test_vector(i, 1)[0] - 0.5) * 0.1)
        d = d + 1
      }
      training.push(v)
      i = i + 1
    }
  }
  assert_true(index.train(training) is Ok(_))
  assert_true(index.is_trained())

  // 插入 4 条记录
  let _ = index.insert(@vector_search.VectorRecord::{
    primary_key: "a",
    vector: [1.0, 0.0],
    metadata: Map([]),
    version: 1,
    updated_at: 0,
  })
  let _ = index.insert(@vector_search.VectorRecord::{
    primary_key: "b",
    vector: [0.0, 1.0],
    metadata: Map([]),
    version: 1,
    updated_at: 0,
  })
  let _ = index.insert(@vector_search.VectorRecord::{
    primary_key: "c",
    vector: [-1.0, 0.0],
    metadata: Map([]),
    version: 1,
    updated_at: 0,
  })
  let _ = index.insert(@vector_search.VectorRecord::{
    primary_key: "d",
    vector: [0.0, -1.0],
    metadata: Map([]),
    version: 1,
    updated_at: 0,
  })
  assert_eq(index.size(), 4)
}

///|
test "ivf_search_top_k" {
  let config = @vector_search.IVFConfig::{
    n_list: 4,
    n_probe: 2,
    metric: @vector_search.Cosine,
  }
  let index = @vector_search.IVFIndex::new(config, 2)

  // 训练集
  let training : Array[Array[Double]] = Array(capacity=40)
  let centers : Array[Array[Double]] = [
    [1.0, 0.0],
    [0.0, 1.0],
    [-1.0, 0.0],
    [0.0, -1.0],
  ]
  for center in centers {
    let mut i = 0
    while i < 10 {
      let v : Array[Double] = Array(capacity=2)
      let mut d = 0
      while d < 2 {
        v.push(center[d] + (ivf_test_vector(i, 1)[0] - 0.5) * 0.1)
        d = d + 1
      }
      training.push(v)
      i = i + 1
    }
  }
  let _ = index.train(training)

  // 插入 4 条记录
  let _ = index.insert(@vector_search.VectorRecord::{
    primary_key: "a",
    vector: [1.0, 0.0],
    metadata: Map([]),
    version: 1,
    updated_at: 0,
  })
  let _ = index.insert(@vector_search.VectorRecord::{
    primary_key: "b",
    vector: [0.0, 1.0],
    metadata: Map([]),
    version: 1,
    updated_at: 0,
  })
  let _ = index.insert(@vector_search.VectorRecord::{
    primary_key: "c",
    vector: [-1.0, 0.0],
    metadata: Map([]),
    version: 1,
    updated_at: 0,
  })
  let _ = index.insert(@vector_search.VectorRecord::{
    primary_key: "d",
    vector: [0.0, -1.0],
    metadata: Map([]),
    version: 1,
    updated_at: 0,
  })

  // 查询 [1.0, 0.0] 应命中 a
  let results = index.search_top_k([1.0, 0.0], 1)
  assert_eq(results.length(), 1)
  assert_eq(results[0].0, "a")

  // 查询 [0.0, 1.0] 应命中 b
  let results2 = index.search_top_k([0.0, 1.0], 1)
  assert_eq(results2.length(), 1)
  assert_eq(results2[0].0, "b")

  // Top-2 查询应返回两个最近桶的记录
  let results3 = index.search_top_k([1.0, 0.0], 2)
  assert_eq(results3.length(), 2)
}

///|
test "ivf_search_returns_empty_when_not_trained" {
  let config = @vector_search.IVFConfig::default()
  let index = @vector_search.IVFIndex::new(config, 2)
  let results = index.search_top_k([1.0, 0.0], 1)
  assert_eq(results.length(), 0)
}

///|
test "ivf_insert_rejects_wrong_dimension" {
  let config = @vector_search.IVFConfig::default()
  let index = @vector_search.IVFIndex::new(config, 2)
  let training : Array[Array[Double]] = Array(capacity=10)
  let mut i = 0
  while i < 10 {
    training.push(ivf_test_vector(i, 2))
    i = i + 1
  }
  let _ = index.train(training)
  let bad_record = @vector_search.VectorRecord::{
    primary_key: "x",
    vector: [1.0, 0.0, 0.0], // 3 维，但索引是 2 维
    metadata: Map([]),
    version: 1,
    updated_at: 0,
  }
  assert_true(index.insert(bad_record) is Err(_))
}

///|
test "ivf_train_rejects_insufficient_data" {
  let config = @vector_search.IVFConfig::{
    n_list: 100,
    n_probe: 10,
    metric: @vector_search.Cosine,
  }
  let index = @vector_search.IVFIndex::new(config, 2)
  let training : Array[Array[Double]] = Array(capacity=50)
  let mut i = 0
  while i < 50 {
    training.push(ivf_test_vector(i, 2))
    i = i + 1
  }
  assert_true(index.train(training) is Err(_))
}
