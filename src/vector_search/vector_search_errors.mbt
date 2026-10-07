// 向量检索错误枚举
//
// 覆盖向量检索引擎所有错误场景

///|
pub(all) enum VectorSearchError {
  /// 集合已存在
  CollectionAlreadyExists
  /// 集合不存在
  CollectionNotFound
  /// 维度非法
  InvalidDimension
  /// 距离度量非法
  InvalidMetric
  /// 维度不匹配
  DimensionMismatch
  /// 主键为空
  EmptyPrimaryKey
  /// 主键重复
  DuplicatePrimaryKey
  /// 向量值非法（NaN/无穷值）
  InvalidVectorValue
  /// 元数据非法
  InvalidMetadata
  /// Top-K 非法
  InvalidTopK
  /// 查询向量维度不匹配
  QueryDimensionMismatch
  /// 检索超时
  SearchTimeout
  /// 索引不可用
  IndexUnavailable
  /// 过滤字段未声明
  FilterFieldNotIndexed
  /// 过滤表达式非法
  InvalidFilterExpression
  /// 索引构建资源不足
  IndexBuildResourceExhausted
  /// 索引构建进行中
  IndexBuildInProgress
  /// 持久化失败
  PersistFailed
  /// 导入部分失败
  ImportPartialFailure
} derive(Debug)

///|
pub impl Eq for VectorSearchError with fn equal(self, other) -> Bool {
  match (self, other) {
    (CollectionAlreadyExists, CollectionAlreadyExists) => true
    (CollectionNotFound, CollectionNotFound) => true
    (InvalidDimension, InvalidDimension) => true
    (InvalidMetric, InvalidMetric) => true
    (DimensionMismatch, DimensionMismatch) => true
    (EmptyPrimaryKey, EmptyPrimaryKey) => true
    (DuplicatePrimaryKey, DuplicatePrimaryKey) => true
    (InvalidVectorValue, InvalidVectorValue) => true
    (InvalidMetadata, InvalidMetadata) => true
    (InvalidTopK, InvalidTopK) => true
    (QueryDimensionMismatch, QueryDimensionMismatch) => true
    (SearchTimeout, SearchTimeout) => true
    (IndexUnavailable, IndexUnavailable) => true
    (FilterFieldNotIndexed, FilterFieldNotIndexed) => true
    (InvalidFilterExpression, InvalidFilterExpression) => true
    (IndexBuildResourceExhausted, IndexBuildResourceExhausted) => true
    (IndexBuildInProgress, IndexBuildInProgress) => true
    (PersistFailed, PersistFailed) => true
    (ImportPartialFailure, ImportPartialFailure) => true
    _ => false
  }
}

///|
pub extend VectorSearchError with Eq::{equal, not_equal}

///|
pub extend VectorSearchError with Debug::{to_repr}
