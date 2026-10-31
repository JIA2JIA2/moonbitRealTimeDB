// 索引选择器模块
//
// 基于统计信息选择最优索引
// 考虑覆盖度、选择性、代价等因素

///|
/// 查询条件
pub(all) struct QueryCondition {
  /// 字段路径
  field_path : String
  /// 查询值
  value : @realtime_db.Value?
  /// 查询类型
  query_type : QueryType
}

///|
/// 查询类型
pub(all) enum QueryType {
  /// 等值查询
  Equal
  /// 范围查询
  Range
  /// 前缀匹配
  Prefix
}

///|
pub impl Eq for QueryType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Equal, Equal) => true
    (Range, Range) => true
    (Prefix, Prefix) => true
    _ => false
  }
}

///|
pub extend QueryType with Eq::{equal, not_equal}

///|
/// 索引评分
pub(all) struct IndexScore {
  /// 索引名称
  index_name : String
  /// 覆盖度得分（0.0-1.0）
  coverage_score : Double
  /// 选择性得分（0.0-1.0）
  selectivity_score : Double
  /// 代价得分（0.0-1.0，越高越好）
  cost_score : Double
  /// 总得分
  total_score : Double
}

///|
/// 索引选择器结构体
pub struct IndexSelector {
  /// 索引管理器引用
  mut manager : IndexManager?
  /// 统计收集器引用
  mut stats_collector : StatsCollector?
}

///|
/// 创建索引选择器
pub fn IndexSelector::new() -> IndexSelector {
  { manager: None, stats_collector: None, }
}

///|
/// 设置索引管理器
pub fn IndexSelector::set_manager(
  self : IndexSelector,
  manager : IndexManager?,
) -> Unit {
  self.manager = manager
}

///|
/// 设置统计收集器
pub fn IndexSelector::set_stats_collector(
  self : IndexSelector,
  collector : StatsCollector?,
) -> Unit {
  self.stats_collector = collector
}

///|
/// 选择最优索引
pub fn IndexSelector::select_index(
  self : IndexSelector,
  conditions : Array[QueryCondition],
) -> String? {
  let scores = self.select_index_with_scores(conditions)
  if scores.length() > 0 {
    Some(scores[0].index_name)
  } else {
    None
  }
}

///|
/// 获取活跃索引（内部方法）
fn IndexSelector::get_active_indices(
  self : IndexSelector,
  manager : IndexManager,
) -> Array[(String, IndexDef)] {
  let _ = self
  let result : Array[(String, IndexDef)] = []
  for (name, def) in manager.indices {
    if def.status is Active {
      result.push((name, def))
    }
  }
  result
}

///|
/// 计算索引得分（内部方法）
fn IndexSelector::calculate_score(
  self : IndexSelector,
  name : String,
  def : IndexDef,
  conditions : Array[QueryCondition],
) -> IndexScore {
  let coverage = self.calculate_coverage(def, conditions)
  let selectivity = self.calculate_selectivity(name, conditions)
  let cost = self.calculate_cost(def, conditions)
  let total = coverage * 0.4 + selectivity * 0.35 + cost * 0.25

  {
    index_name: name,
    coverage_score: coverage,
    selectivity_score: selectivity,
    cost_score: cost,
    total_score: total,
  }
}

///|
/// 计算覆盖度（内部方法）
fn IndexSelector::calculate_coverage(
  self : IndexSelector,
  def : IndexDef,
  conditions : Array[QueryCondition],
) -> Double {
  let _ = self
  // 去重收集查询字段
  let query_fields : Array[String] = []
  for cond in conditions {
    if !array_contains(query_fields, cond.field_path) {
      query_fields.push(cond.field_path)
    }
  }

  let mut covered = 0
  for field in query_fields {
    if array_contains(def.field_paths, field) {
      covered = covered + 1
    }
  }

  if query_fields.length() == 0 {
    0.0
  } else {
    covered.to_double() / query_fields.length().to_double()
  }
}

///|
/// 计算选择性（内部方法）
fn IndexSelector::calculate_selectivity(
  self : IndexSelector,
  name : String,
  conditions : Array[QueryCondition],
) -> Double {
  let _ = conditions
  let stats = match self.stats_collector {
    Some(collector) => collector.get_index_stats(name)
    None => return 0.5
  }

  match stats {
    Some(s) =>
      if s.total_entries == 0 {
        0.0
      } else {
        s.cardinality.to_double() / s.total_entries.to_double()
      }
    None => 0.5
  }
}

///|
/// 计算代价得分（内部方法）
fn IndexSelector::calculate_cost(
  self : IndexSelector,
  def : IndexDef,
  conditions : Array[QueryCondition],
) -> Double {
  let _ = self
  let mut score = 1.0

  for cond in conditions {
    match (def.index_type, cond.query_type) {
      (Hash, Equal) => ()
      (Hash, Range) => score = score - 0.3
      (Hash, Prefix) => score = score - 0.3
      (Fulltext, Equal) => score = score - 0.1
      (Fulltext, Range) => score = score - 0.1
      (Fulltext, Prefix) => ()
      (Composite, _) => ()
      (BTree, _) => ()
    }
  }

  if def.field_paths.length() > 1 {
    let used_fields = count_used_fields(def, conditions)
    if used_fields < def.field_paths.length() {
      let ratio = used_fields.to_double() / def.field_paths.length().to_double()
      score = score * (0.5 + ratio * 0.5)
    }
  }

  if score < 0.0 {
    0.0
  } else if score > 1.0 {
    1.0
  } else {
    score
  }
}

///|
/// 计算使用的字段数（最左前缀原则）
fn count_used_fields(
  def : IndexDef,
  conditions : Array[QueryCondition],
) -> Int32 {
  let mut count = 0
  for path in def.field_paths {
    let mut found = false
    for cond in conditions {
      if cond.field_path == path {
        found = true
        break
      }
    }
    if found {
      count = count + 1
    } else {
      break
    }
  }
  count
}

///|
/// 选择索引并返回详细评分信息（按得分降序）
pub fn IndexSelector::select_index_with_scores(
  self : IndexSelector,
  conditions : Array[QueryCondition],
) -> Array[IndexScore] {
  let manager = match self.manager {
    Some(m) => m
    None => return []
  }

  let active_indices = self.get_active_indices(manager)
  let scores : Array[IndexScore] = []

  for (name, def) in active_indices {
    scores.push(self.calculate_score(name, def, conditions))
  }

  scores.sort_by(fn(a : IndexScore, b : IndexScore) -> Int32 {
    if a.total_score > b.total_score {
      -1
    } else if a.total_score < b.total_score {
      1
    } else {
      0
    }
  })

  scores
}
