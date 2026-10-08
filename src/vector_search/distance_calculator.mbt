// 距离计算引擎
//
// 实现四种距离度量：余弦相似度、欧氏距离、内积、曼哈顿距离

///|
/// 无状态的距离计算器，由检索引擎持有
pub struct DistanceCalculator {}

///|
pub fn DistanceCalculator::new() -> DistanceCalculator {
  DistanceCalculator::{ }
}

///|
pub fn DistanceCalculator::cosine_similarity(
  a : Array[Double],
  b : Array[Double],
) -> Double {
  if a.length() == 0 || a.length() != b.length() {
    return 0.0
  }
  let mut dot = 0.0
  let mut norm_a = 0.0
  let mut norm_b = 0.0
  let mut i = 0
  while i < a.length() {
    let ai = a[i]
    let bi = b[i]
    dot = dot + ai * bi
    norm_a = norm_a + ai * ai
    norm_b = norm_b + bi * bi
    i = i + 1
  }
  if norm_a == 0.0 || norm_b == 0.0 {
    return 0.0
  }
  dot / (norm_a.sqrt() * norm_b.sqrt())
}

///|
pub fn DistanceCalculator::euclidean_distance(
  a : Array[Double],
  b : Array[Double],
) -> Double {
  if a.length() == 0 || a.length() != b.length() {
    return 0.0
  }
  let mut sum = 0.0
  let mut i = 0
  while i < a.length() {
    let diff = a[i] - b[i]
    sum = sum + diff * diff
    i = i + 1
  }
  sum.sqrt()
}

///|
pub fn DistanceCalculator::inner_product(
  a : Array[Double],
  b : Array[Double],
) -> Double {
  if a.length() == 0 || a.length() != b.length() {
    return 0.0
  }
  let mut result = 0.0
  let mut i = 0
  while i < a.length() {
    result = result + a[i] * b[i]
    i = i + 1
  }
  result
}

///|
pub fn DistanceCalculator::manhattan_distance(
  a : Array[Double],
  b : Array[Double],
) -> Double {
  if a.length() == 0 || a.length() != b.length() {
    return 0.0
  }
  let mut sum = 0.0
  let mut i = 0
  while i < a.length() {
    sum = sum + (a[i] - b[i]).abs()
    i = i + 1
  }
  sum
}

///|
/// 将原始距离归一化为相似度分数（越大越相似），统一用于 Top-K 排序
pub fn DistanceCalculator::normalize_score(
  raw : Double,
  metric : DistanceMetric,
) -> Double {
  match metric {
    Cosine => if raw < 0.0 { 0.0 } else if raw > 1.0 { 1.0 } else { raw }
    Euclidean | Manhattan => if raw == 0.0 { 1.0 } else { 1.0 / (1.0 + raw) }
    InnerProduct => if raw < 0.0 { 0.0 } else { raw }
  }
}
