// IVF 索引实现
//
// 实现倒排文件索引的核心算法：
// 1. k-means 聚类训练：从训练集中选出 n_list 个初始中心，迭代收敛
// 2. 插入：找到最近聚类桶，将记录加入桶内
// 3. 搜索：找到最近的 n_probe 个桶，桶内精确扫描

///|
pub(all) struct IvfBucket {
  centroid : Array[Double]
  records : Array[VectorRecord]
  mut count : Int32
}

///|
pub struct IVFIndex {
  config : IVFConfig
  mut centroids : Array[Array[Double]]
  mut buckets : Array[IvfBucket]
  dimension : Int32
  mut trained : Bool
}

///|
pub fn IVFIndex::new(config : IVFConfig, dimension : Int32) -> IVFIndex {
  let centroids : Array[Array[Double]] = Array(capacity=config.n_list)
  let buckets : Array[IvfBucket] = Array(capacity=config.n_list)
  let mut i = 0
  while i < config.n_list {
    let empty : Array[Double] = Array(capacity=dimension)
    centroids.push(empty)
    buckets.push(IvfBucket::{
      centroid: Array(capacity=dimension),
      records: Array(capacity=0),
      count: 0,
    })
    i = i + 1
  }
  IVFIndex::{ config, centroids, buckets, dimension, trained: false, }
}

///|
pub fn IVFIndex::is_trained(self : IVFIndex) -> Bool {
  self.trained
}

///|
pub fn IVFIndex::size(self : IVFIndex) -> Int32 {
  let mut total = 0
  for bucket in self.buckets {
    total = total + bucket.count
  }
  total
}

///|
pub fn IVFIndex::dimension(self : IVFIndex) -> Int32 {
  self.dimension
}

///|
/// 向量加法
fn vec_add(a : Array[Double], b : Array[Double]) -> Array[Double] {
  let out : Array[Double] = Array(capacity=a.length())
  let mut i = 0
  while i < a.length() {
    out.push(a[i] + b[i])
    i = i + 1
  }
  out
}

///|
/// 向量标量乘法
fn vec_scale(a : Array[Double], s : Double) -> Array[Double] {
  let out : Array[Double] = Array(capacity=a.length())
  for x in a {
    out.push(x * s)
  }
  out
}

///|
/// 向量平均
fn vec_mean(vectors : Array[Array[Double]]) -> Array[Double] {
  if vectors.length() == 0 {
    return Array(capacity=0)
  }
  let dim = vectors[0].length()
  let mut sum : Array[Double] = Array(capacity=dim)
  let mut i = 0
  while i < dim {
    sum.push(0.0)
    i = i + 1
  }
  for v in vectors {
    sum = vec_add(sum, v)
  }
  vec_scale(sum, 1.0 / vectors.length().to_double())
}

///|
/// 找到查询向量最近的聚类桶索引
fn find_nearest_centroid(
  query : Array[Double],
  centroids : Array[Array[Double]],
  metric : DistanceMetric,
) -> Int32 {
  if centroids.length() == 0 {
    return 0
  }
  let mut best_idx = 0
  let mut best_dist = DistanceCalculator::cosine_similarity(query, centroids[0])
  let mut i = 1
  while i < centroids.length() {
    let d = match metric {
      Cosine => DistanceCalculator::cosine_similarity(query, centroids[i])
      Euclidean => -DistanceCalculator::euclidean_distance(query, centroids[i])
      InnerProduct => DistanceCalculator::inner_product(query, centroids[i])
      Manhattan => -DistanceCalculator::manhattan_distance(query, centroids[i])
    }
    if d > best_dist {
      best_dist = d
      best_idx = i
    }
    i = i + 1
  }
  best_idx
}

///|
/// 找到最近的 n_probe 个聚类桶索引（按距离排序）
fn find_nearest_centroids(
  query : Array[Double],
  centroids : Array[Array[Double]],
  n_probe : Int32,
  metric : DistanceMetric,
) -> Array[Int32] {
  let scored : Array[(Double, Int32)] = Array(capacity=centroids.length())
  let mut i = 0
  while i < centroids.length() {
    let d = match metric {
      Cosine => DistanceCalculator::cosine_similarity(query, centroids[i])
      Euclidean => -DistanceCalculator::euclidean_distance(query, centroids[i])
      InnerProduct => DistanceCalculator::inner_product(query, centroids[i])
      Manhattan => -DistanceCalculator::manhattan_distance(query, centroids[i])
    }
    scored.push((d, i))
    i = i + 1
  }
  scored.sort_by(fn(a, b) { b.0.compare(a.0) })
  let result : Array[Int32] = Array(capacity=n_probe)
  let mut j = 0
  while j < n_probe && j < scored.length() {
    result.push(scored[j].1)
    j = j + 1
  }
  result
}

///|
/// k-means 训练：从训练集中选出 n_list 个聚类中心，迭代至收敛。
/// 采用 k-means++ 初始化（首中心随机选，后续按距离平方概率选）。
/// 最大迭代次数 20，收敛阈值 1e-4。
///
/// 注意：训练集记录数必须 >= n_list，否则无法初始化所有中心。
pub fn IVFIndex::train(
  self : IVFIndex,
  training_set : Array[Array[Double]],
) -> Result[Unit, String] {
  if training_set.length() < self.config.n_list {
    return Err("training set size must be >= n_list")
  }
  if self.dimension > 0 && training_set[0].length() != self.dimension {
    return Err("training vector dimension mismatch")
  }
  let n = training_set.length()
  let k = self.config.n_list
  let dim = self.dimension

  // k-means++ 初始化：首中心随机
  let mut centroids : Array[Array[Double]] = Array(capacity=k)
  let first_idx = (0x2545F491 & 0x7fffffff) % n
  centroids.push(training_set[first_idx].copy())

  // 后续中心按距离平方概率选
  let mut i = 1
  while i < k {
    let distances : Array[Double] = Array(capacity=n)
    let mut total = 0.0
    let mut t = 0
    while t < n {
      let mut min_d = 1.0e30
      for c in centroids {
        let d = DistanceCalculator::euclidean_distance(training_set[t], c)
        let d2 = d * d
        if d2 < min_d {
          min_d = d2
        }
      }
      distances.push(min_d)
      total = total + min_d
      t = t + 1
    }
    let mut threshold = total *
      ((0x2545F491 & 0x7fffffff).to_double() / 2147483647.0)
    let mut selected = 0
    let mut s = 0
    while s < n {
      threshold = threshold - distances[s]
      if threshold <= 0.0 {
        selected = s
        break
      }
      s = s + 1
    }
    centroids.push(training_set[selected].copy())
    i = i + 1
  }

  // k-means 迭代
  let max_iter = 20
  let mut iter = 0
  while iter < max_iter {
    // 分配：每条记录归入最近中心
    let assignments : Array[Int32] = Array(capacity=n)
    for _v in training_set {
      assignments.push(0)
    }
    let mut t = 0
    while t < n {
      assignments[t] = find_nearest_centroid(
        training_set[t],
        centroids,
        Euclidean,
      )
      t = t + 1
    }

    // 更新：重新计算中心
    let new_centroids : Array[Array[Double]] = Array(capacity=k)
    let mut changed = false
    let mut j = 0
    while j < k {
      let members : Array[Array[Double]] = Array(capacity=0)
      let mut t = 0
      while t < n {
        if assignments[t] == j {
          members.push(training_set[t])
        }
        t = t + 1
      }
      if members.length() > 0 {
        let new_c = vec_mean(members)
        // 检查收敛
        let mut move_dist = 0.0
        let mut d = 0
        while d < dim {
          let diff = new_c[d] - centroids[j][d]
          move_dist = move_dist + diff * diff
          d = d + 1
        }
        move_dist = move_dist.sqrt()
        if move_dist > 1.0e-4 {
          changed = true
        }
        new_centroids.push(new_c)
      } else {
        // 空簇：保留原中心
        new_centroids.push(centroids[j].copy())
      }
      j = j + 1
    }
    centroids = new_centroids
    if !changed {
      break
    }
    iter = iter + 1
  }

  // 写入索引
  self.centroids = centroids
  // 初始化桶
  let buckets : Array[IvfBucket] = Array(capacity=k)
  let mut j = 0
  while j < k {
    buckets.push(IvfBucket::{
      centroid: centroids[j].copy(),
      records: Array(capacity=0),
      count: 0,
    })
    j = j + 1
  }
  self.buckets = buckets
  self.trained = true
  Ok(())
}

///|
/// 插入记录：找到最近聚类桶，将记录加入桶内。
/// 注意：桶容量无硬上限（由调用方通过配置控制）。
pub fn IVFIndex::insert(
  self : IVFIndex,
  record : VectorRecord,
) -> Result[Unit, String] {
  if !self.trained {
    return Err("IVF index not trained")
  }
  if record.vector.length() != self.dimension {
    return Err("vector dimension mismatch")
  }
  let bucket_idx = find_nearest_centroid(
    record.vector,
    self.centroids,
    self.config.metric,
  )
  self.buckets[bucket_idx].records.push(record)
  self.buckets[bucket_idx].count = self.buckets[bucket_idx].count + 1
  Ok(())
}

///|
/// 搜索 Top-K：找到最近的 n_probe 个桶，桶内精确扫描取 Top-K。
///
/// 返回 (主键, 距离)，距离越小越近。
/// 注意：距离为原始度量值（Euclidean/Manhattan 为距离，Cosine/InnerProduct
/// 为相似度），调用方需按需转换。
pub fn IVFIndex::search_top_k(
  self : IVFIndex,
  query : Array[Double],
  top_k : Int32,
) -> Array[(String, Double)] {
  if !self.trained || top_k <= 0 {
    return Array(capacity=0)
  }
  let n_probe = self.config.n_probe
  let probe_buckets = find_nearest_centroids(
    query,
    self.centroids,
    n_probe,
    self.config.metric,
  )

  // 收集候选
  let candidates : Array[(String, Double)] = Array(capacity=0)
  for bucket_idx in probe_buckets {
    for record in self.buckets[bucket_idx].records {
      let dist = match self.config.metric {
        Cosine =>
          1.0 - DistanceCalculator::cosine_similarity(query, record.vector)
        Euclidean =>
          DistanceCalculator::euclidean_distance(query, record.vector)
        InnerProduct => -DistanceCalculator::inner_product(query, record.vector)
        Manhattan =>
          DistanceCalculator::manhattan_distance(query, record.vector)
      }
      candidates.push((record.primary_key, dist))
    }
  }

  // 按距离升序取 Top-K
  candidates.sort_by(fn(a, b) { a.1.compare(b.1) })
  if candidates.length() > top_k {
    candidates.truncate(top_k)
  }
  candidates
}
