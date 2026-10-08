// 向量检索引擎
//
// 实现精确检索与近似检索，支持 Top-K 查询

///|
pub struct SearchEngine {
  collection_manager : CollectionManager
  distance_calculator : DistanceCalculator
}

///|
pub struct SearchHit {
  primary_key : String
  score : Double
  metadata : Map[String, @realtime_db.Value]
}

///|
pub fn SearchEngine::new(
  collection_manager : CollectionManager,
) -> SearchEngine {
  SearchEngine::{
    collection_manager,
    distance_calculator: DistanceCalculator::new(),
  }
}

///|
/// 精确检索：按集合配置的距离度量全量扫描所有记录，返回归一化分数
/// 最高的 top_k 条结果（分数越大越相似）。
pub fn SearchEngine::search_exact(
  self : SearchEngine,
  collection_name : String,
  tenant_id : String,
  query_vector : Array[Double],
  top_k : Int,
) -> Array[SearchHit] {
  let meta = match
    self.collection_manager.get_collection(collection_name, tenant_id) {
    Some(m) => m
    None => return Array(capacity=0)
  }
  if top_k <= 0 || top_k > 1000 {
    return Array(capacity=0)
  }
  let metric = meta.distance_metric
  let dimension = meta.dimension
  if query_vector.length() == 0 || query_vector.length() != dimension {
    return Array(capacity=0)
  }
  let records = self.collection_manager.list_records(collection_name, tenant_id)
  let hits : Array[SearchHit] = Array(capacity=0)
  for record in records {
    if record.vector.length() != dimension {
      continue
    }
    let raw = match metric {
      Cosine =>
        DistanceCalculator::cosine_similarity(query_vector, record.vector)
      Euclidean =>
        DistanceCalculator::euclidean_distance(query_vector, record.vector)
      InnerProduct =>
        DistanceCalculator::inner_product(query_vector, record.vector)
      Manhattan =>
        DistanceCalculator::manhattan_distance(query_vector, record.vector)
    }
    hits.push(SearchHit::{
      primary_key: record.primary_key,
      score: DistanceCalculator::normalize_score(raw, metric),
      metadata: record.metadata,
    })
  }
  // 归一化后分数越大越相似，统一降序
  hits.sort_by(fn(a, b) { b.score.compare(a.score) })
  if hits.length() > top_k {
    hits.truncate(top_k)
  }
  hits
}

///|
/// 近似检索：近似索引尚未实现，暂时退化为精确检索
pub fn SearchEngine::search_approximate(
  self : SearchEngine,
  collection_name : String,
  tenant_id : String,
  query_vector : Array[Double],
  top_k : Int,
) -> Array[SearchHit] {
  self.search_exact(collection_name, tenant_id, query_vector, top_k)
}
