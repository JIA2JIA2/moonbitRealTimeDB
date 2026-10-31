// 向量检索引擎
//
// 实现精确检索与近似检索，支持 Top-K 查询与元数据过滤

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
/// 检索前的统一参数校验，返回集合元数据；任何输入不合法时返回 None
fn SearchEngine::validate_query(
  self : SearchEngine,
  collection_name : String,
  tenant_id : String,
  query_vector : Array[Double],
  top_k : Int,
) -> VectorCollectionMeta? {
  let meta = match
    self.collection_manager.get_collection(collection_name, tenant_id) {
    Some(m) => m
    None => return None
  }
  if top_k <= 0 || top_k > 1000 {
    return None
  }
  if query_vector.length() == 0 || query_vector.length() != meta.dimension {
    return None
  }
  Some(meta)
}

///|
/// 精确检索：按集合配置的距离度量全量扫描所有记录，返回归一化分数
/// 最高的 top_k 条结果（分数越大越相似）。
///
/// 可选 filter 对每条记录的元数据求值 FilterExpr，仅保留匹配记录。
pub fn SearchEngine::search_exact(
  self : SearchEngine,
  collection_name : String,
  tenant_id : String,
  query_vector : Array[Double],
  top_k : Int,
  filter? : FilterExpr,
) -> Array[SearchHit] {
  self.search_exact_impl(
    collection_name, tenant_id, query_vector, top_k, filter,
  )
}

///|
/// 精确检索实现：filter 为可空参数，供近似检索回退时内部转发
fn SearchEngine::search_exact_impl(
  self : SearchEngine,
  collection_name : String,
  tenant_id : String,
  query_vector : Array[Double],
  top_k : Int,
  filter : FilterExpr?,
) -> Array[SearchHit] {
  let meta = match
    self.validate_query(collection_name, tenant_id, query_vector, top_k) {
    Some(m) => m
    None => return Array(capacity=0)
  }
  let metric = meta.distance_metric
  let dimension = meta.dimension
  let records = self.collection_manager.list_records(collection_name, tenant_id)
  let hits : Array[SearchHit] = Array(capacity=0)
  for record in records {
    if record.vector.length() != dimension {
      continue
    }
    // 元数据过滤：不匹配的记录跳过
    match filter {
      Some(f) =>
        if !f.evaluate(record.metadata) {
          continue
        }
      None => ()
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
/// 近似检索：优先走集合的 HNSW 索引，索引不可用时回退精确检索。
///
/// HNSW 返回的是内部图距离（越小越近），这里先还原为各度量的原始值，
/// 再复用精确检索的归一化逻辑，保证两种路径的 score 语义一致（越大越相似）。
///
/// 带 filter 时为后置过滤：先按 top_k 的 4 倍（上限 1000）over-fetch，
/// 过滤后截断到 top_k；过滤后命中不足 top_k 或索引候选不足时回退
/// 精确检索，保证结果数量语义与精确路径一致。
pub fn SearchEngine::search_approximate(
  self : SearchEngine,
  collection_name : String,
  tenant_id : String,
  query_vector : Array[Double],
  top_k : Int,
  filter? : FilterExpr,
) -> Array[SearchHit] {
  self.search_approximate_impl(
    collection_name, tenant_id, query_vector, top_k, filter,
  )
}

///|
/// 近似检索实现：filter 为可空参数，供回退时内部转发
fn SearchEngine::search_approximate_impl(
  self : SearchEngine,
  collection_name : String,
  tenant_id : String,
  query_vector : Array[Double],
  top_k : Int,
  filter : FilterExpr?,
) -> Array[SearchHit] {
  let meta = match
    self.validate_query(collection_name, tenant_id, query_vector, top_k) {
    Some(m) => m
    None => return Array(capacity=0)
  }
  let metric = meta.distance_metric
  // 带 filter 时 over-fetch：后置过滤会丢弃部分候选，多取缓解召回损失
  let fetch_k = match filter {
    Some(_) => {
      let expanded = top_k * 4
      if expanded > 1000 { 1000 } else { expanded }
    }
    None => top_k
  }
  let pairs = match
    self.collection_manager.search_index(
      collection_name, tenant_id, query_vector, fetch_k,
    ) {
    Some(p) => p
    None =>
      return self.search_exact_impl(
        collection_name, tenant_id, query_vector, top_k, filter,
      )
  }
  // 索引结果不足 over-fetch 目标（记录数不够或图漏检）：
  // 过滤后数量无保证，直接回退精确检索
  if pairs.length() < fetch_k {
    return self.search_exact_impl(
      collection_name, tenant_id, query_vector, top_k, filter,
    )
  }
  let hits : Array[SearchHit] = Array(capacity=0)
  for (primary_key, graph_distance) in pairs {
    let metadata = match
      self.collection_manager.get_record(
        collection_name, tenant_id, primary_key,
      ) {
      Some(record) => record.metadata
      None => Map([])
    }
    // 元数据过滤：不匹配的记录跳过
    match filter {
      Some(f) =>
        if !f.evaluate(metadata) {
          continue
        }
      None => ()
    }
    let raw = match metric {
      Cosine => 1.0 - graph_distance
      InnerProduct => -graph_distance
      Euclidean | Manhattan => graph_distance
    }
    hits.push(SearchHit::{
      primary_key,
      score: DistanceCalculator::normalize_score(raw, metric),
      metadata,
    })
  }
  if hits.length() > top_k {
    hits.truncate(top_k)
  }
  // 过滤后命中不足 top_k：回退精确检索保证数量语义
  if filter is Some(_) && hits.length() < top_k {
    return self.search_exact_impl(
      collection_name, tenant_id, query_vector, top_k, filter,
    )
  }
  hits
}
