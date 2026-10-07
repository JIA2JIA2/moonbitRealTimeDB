// 向量检索核心类型定义
//
// 定义向量检索引擎所需的枚举类型与结构体

///|
/// 距离度量类型
pub(all) enum DistanceMetric {
  /// 余弦相似度：越大越相似
  Cosine
  /// 欧氏距离：越小越相似
  Euclidean
  /// 内积：越大越相似
  InnerProduct
  /// 曼哈顿距离：越小越相似
  Manhattan
} derive(Debug)

///|
pub impl Eq for DistanceMetric with fn equal(self, other) -> Bool {
  match (self, other) {
    (Cosine, Cosine) => true
    (Euclidean, Euclidean) => true
    (InnerProduct, InnerProduct) => true
    (Manhattan, Manhattan) => true
    _ => false
  }
}

///|
pub extend DistanceMetric with Eq::{equal, not_equal}

///|
pub extend DistanceMetric with Debug::{to_repr}

///|
/// 索引策略
pub(all) enum IndexStrategy {
  /// 精确索引（全量扫描）
  Exact
  /// 近似索引（HNSW/IVF 加速）
  Approximate
} derive(Debug)

///|
pub impl Eq for IndexStrategy with fn equal(self, other) -> Bool {
  match (self, other) {
    (Exact, Exact) => true
    (Approximate, Approximate) => true
    _ => false
  }
}

///|
pub extend IndexStrategy with Eq::{equal, not_equal}

///|
pub extend IndexStrategy with Debug::{to_repr}

///|
/// 检索模式
pub(all) enum SearchMode {
  /// 精确检索（全量计算）
  Exact
  /// 近似检索（索引加速）
  Approximate
} derive(Debug)

///|
pub impl Eq for SearchMode with fn equal(self, other) -> Bool {
  match (self, other) {
    (Exact, Exact) => true
    (Approximate, Approximate) => true
    _ => false
  }
}

///|
pub extend SearchMode with Eq::{equal, not_equal}

///|
pub extend SearchMode with Debug::{to_repr}

///|
/// 向量集合元数据
pub(all) struct VectorCollectionMeta {
  /// 集合名称
  collection_name : String
  /// 向量维度
  dimension : Int
  /// 距离度量
  distance_metric : DistanceMetric
  /// 索引策略
  index_strategy : IndexStrategy
  /// 可过滤字段列表
  filterable_fields : Array[String]
  /// 记录数
  record_count : Int
  /// 租户 ID
  tenant_id : String
  /// 创建时间戳
  created_at : Int
}

///|
/// 向量记录
pub(all) struct VectorRecord {
  /// 主键
  primary_key : String
  /// 向量数据
  vector : Array[Double]
  /// 元数据
  metadata : Map[String, @realtime_db.Value]
  /// 版本号
  version : Int
  /// 更新时间戳
  updated_at : Int
}

///|
/// 检索结果
pub(all) struct SearchResult {
  /// 主键
  primary_key : String
  /// 相似度分数
  score : Double
  /// 元数据
  metadata : Map[String, @realtime_db.Value]
  /// 距离度量
  distance_metric : DistanceMetric
  /// 检索模式
  search_mode : SearchMode
  /// 扫描记录数
  scanned_count : Int
}

///|
/// 向量检索监控指标
pub(all) struct VectorSearchMetrics {
  /// 检索 QPS
  search_qps : Double
  /// 检索延迟 P50
  search_latency_p50 : Double
  /// 检索延迟 P95
  search_latency_p95 : Double
  /// 检索延迟 P99
  search_latency_p99 : Double
  /// 索引内存占用（字节）
  index_memory_bytes : Int
  /// 集合记录数
  collection_record_count : Int
  /// 索引健康状态
  index_healthy : Bool
  /// 批量导入吞吐（条/秒）
  import_throughput : Double
}

///|
/// 索引状态
pub(all) enum IndexStatus {
  /// 已创建
  Created
  /// 构建中
  Building
  /// 活跃（可查询）
  Active
  /// 重建中
  Rebuilding
  /// 失败
  Failed
} derive(Debug)

///|
pub impl Eq for IndexStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Created, Created) => true
    (Building, Building) => true
    (Active, Active) => true
    (Rebuilding, Rebuilding) => true
    (Failed, Failed) => true
    _ => false
  }
}

///|
pub extend IndexStatus with Eq::{equal, not_equal}

///|
pub extend IndexStatus with Debug::{to_repr}

///|
/// 向量索引状态报告
pub(all) struct IndexStatusReport {
  /// 索引类型
  index_type : String
  /// 已索引记录数
  indexed_count : Int
  /// 构建进度（0~100）
  build_progress : Int
  /// 是否就绪
  is_ready : Bool
  /// 最近优化时间戳
  last_optimized_at : Int
  /// 内存占用（字节）
  memory_bytes : Int
}

///|
/// 变更事件类型
pub(all) enum ChangeEventType {
  /// 新增
  Inserted
  /// 更新
  Updated
  /// 删除
  Deleted
  /// 集合删除
  CollectionDropped
} derive(Debug)

///|
pub impl Eq for ChangeEventType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Inserted, Inserted) => true
    (Updated, Updated) => true
    (Deleted, Deleted) => true
    (CollectionDropped, CollectionDropped) => true
    _ => false
  }
}

///|
pub extend ChangeEventType with Eq::{equal, not_equal}

///|
pub extend ChangeEventType with Debug::{to_repr}

///|
/// 变更事件
pub(all) struct ChangeEvent {
  /// 集合名
  collection_name : String
  /// 主键
  primary_key : String
  /// 变更类型
  change_type : ChangeEventType
  /// 发生时间戳
  occurred_at : Int
}

///|
/// 导入任务状态
pub(all) enum ImportTaskStatus {
  /// 等待中
  Pending
  /// 执行中
  Running
  /// 已完成
  Completed
  /// 失败
  Failed
  /// 已取消
  Cancelled
} derive(Debug)

///|
pub impl Eq for ImportTaskStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Pending, Pending) => true
    (Running, Running) => true
    (Completed, Completed) => true
    (Failed, Failed) => true
    (Cancelled, Cancelled) => true
    _ => false
  }
}

///|
pub extend ImportTaskStatus with Eq::{equal, not_equal}

///|
pub extend ImportTaskStatus with Debug::{to_repr}

///|
/// 导入任务进度
pub(all) struct ImportTaskProgress {
  /// 任务 ID
  task_id : String
  /// 任务状态
  status : ImportTaskStatus
  /// 总记录数
  total_records : Int
  /// 成功记录数
  success_count : Int
  /// 失败记录数
  failure_count : Int
  /// 错误信息
  error_message : String
}

///|
/// 过滤表达式
pub(all) enum FilterExpr {
  /// 等值过滤：字段 = 值
  Eq(String, @realtime_db.Value)
  /// 范围过滤：字段 > / < / >= / <= 值
  Gt(String, Double)
  Lt(String, Double)
  Gte(String, Double)
  Lte(String, Double)
  /// 存在性检查
  Exists(String)
  /// 逻辑组合
  And(Array[FilterExpr])
  Or(Array[FilterExpr])
  Not(FilterExpr)
} derive(Debug)

///|
pub extend FilterExpr with Debug::{to_repr}
