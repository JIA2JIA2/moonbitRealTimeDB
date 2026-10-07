// 时间序列引擎模块 - 核心类型定义
//
// 定义时间序列、度量、数据点、降采样策略等核心数据结构

///|
/// 聚合类型枚举
pub(all) enum AggregationType {
  /// 平均值
  Avg
  /// 求和
  Sum
  /// 最小值
  Min
  /// 最大值
  Max
  /// 计数
  Count
  /// 第一个值
  First
  /// 最后一个值
  Last
  /// 中位数
  Median
  /// P50 分位数
  P50
  /// P90 分位数
  P90
  /// P99 分位数
  P99
} derive(Debug)

///|
pub impl Eq for AggregationType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Avg, Avg) => true
    (Sum, Sum) => true
    (Min, Min) => true
    (Max, Max) => true
    (Count, Count) => true
    (First, First) => true
    (Last, Last) => true
    (Median, Median) => true
    (P50, P50) => true
    (P90, P90) => true
    (P99, P99) => true
    _ => false
  }
}

///|
pub extend AggregationType with Eq::{equal, not_equal}

///|
pub extend AggregationType with Debug::{to_repr}

///|
/// 保留策略类型
pub(all) enum RetentionPolicyType {
  /// 时间过期
  TimeExpired
  /// 数量限制
  CountLimited
  /// 大小限制
  SizeLimited
} derive(Debug)

///|
pub extend RetentionPolicyType with Debug::{to_repr}

///|
pub impl Eq for RetentionPolicyType with fn equal(self, other) -> Bool {
  match (self, other) {
    (TimeExpired, TimeExpired) => true
    (CountLimited, CountLimited) => true
    (SizeLimited, SizeLimited) => true
    _ => false
  }
}

///|
pub extend RetentionPolicyType with Eq::{equal, not_equal}

///|
/// 降采样精度
pub(all) enum DownsamplePrecision {
  /// 秒级
  Second
  /// 分钟级
  Minute
  /// 小时级
  Hour
  /// 天级
  Day
  /// 周级
  Week
  /// 月级
  Month
} derive(Debug)

///|
pub impl Eq for DownsamplePrecision with fn equal(self, other) -> Bool {
  match (self, other) {
    (Second, Second) => true
    (Minute, Minute) => true
    (Hour, Hour) => true
    (Day, Day) => true
    (Week, Week) => true
    (Month, Month) => true
    _ => false
  }
}

///|
pub extend DownsamplePrecision with Eq::{equal, not_equal}

///|
pub extend DownsamplePrecision with Debug::{to_repr}

///|
/// 时间序列度量
pub(all) struct Metric {
  /// 度量 ID
  metric_id : String
  /// 度量名
  metric_name : String
  /// 标签
  labels : Map[String, String]
  /// 数据点列表
  mut data_points : Array[DataPoint]
  /// 创建时间
  created_at : Int
  /// 更新时间
  mut updated_at : Int
}

///|
/// 数据点
pub(all) struct DataPoint {
  /// 时间戳
  timestamp : Int
  /// 值
  value : Double
  /// 是否有效
  is_valid : Bool
}

///|
/// 降采样策略
pub(all) struct DownsamplePolicy {
  /// 策略 ID
  policy_id : String
  /// 策略名
  policy_name : String
  /// 精度
  precision : DownsamplePrecision
  /// 聚合类型
  aggregation : AggregationType
  /// 保留时间（秒）
  retention_seconds : Int
  /// 是否启用
  is_enabled : Bool
}

///|
/// 连续查询
pub(all) struct ContinuousQuery {
  /// 查询 ID
  query_id : String
  /// 查询名
  query_name : String
  /// 源度量
  source_metric : String
  /// 目标度量
  target_metric : String
  /// 查询间隔（秒）
  query_interval_seconds : Int
  /// 聚合类型
  aggregation : AggregationType
  /// 窗口大小（秒）
  window_seconds : Int
  /// 是否启用
  is_enabled : Bool
}

///|
/// 保留策略
pub(all) struct RetentionPolicy {
  /// 策略 ID
  policy_id : String
  /// 策略名
  policy_name : String
  /// 策略类型
  policy_type : RetentionPolicyType
  /// 保留时间（秒）
  retention_seconds : Int
  /// 最大数据点数
  max_data_points : Int
  /// 最大大小（字节）
  max_size_bytes : Int
  /// 是否启用
  is_enabled : Bool
}

///|
/// 时间序列配置
pub(all) struct TimeSeriesConfig {
  /// 默认保留时间（秒）
  default_retention_seconds : Int
  /// 最大数据点数
  max_data_points : Int
  /// 是否启用自动降采样
  auto_downsample : Bool
  /// 默认降采样精度
  default_precision : DownsamplePrecision
  /// 是否启用连续查询
  enable_continuous_query : Bool
  /// 数据刷新间隔（毫秒）
  flush_interval_ms : Int
}

///|
/// 默认时间序列配置
pub fn TimeSeriesConfig::default() -> TimeSeriesConfig {
  TimeSeriesConfig::{
    default_retention_seconds: 2592000, // 30 天
    max_data_points: 1000000000,
    auto_downsample: true,
    default_precision: Minute,
    enable_continuous_query: true,
    flush_interval_ms: 1000,
  }
}

///|
/// 时间序列错误类型
pub(all) enum TimeSeriesError {
  /// 度量已存在
  Metric_Already_Exists
  /// 度量不存在
  Metric_Not_Found
  /// 降采样策略已存在
  Downsample_Policy_Already_Exists
  /// 降采样策略不存在
  Downsample_Policy_Not_Found
  /// 连续查询已存在
  Continuous_Query_Already_Exists
  /// 连续查询不存在
  Continuous_Query_Not_Found
  /// 保留策略已存在
  Retention_Policy_Already_Exists
  /// 保留策略不存在
  Retention_Policy_Not_Found
  /// 无效数据点
  Invalid_DataPoint
  /// 数据点过多
  Too_Many_DataPoints
  /// 查询超时
  Query_Timeout
  /// 内部错误
  Internal_Error(String)
} derive(Debug)

///|
pub impl Eq for TimeSeriesError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Metric_Already_Exists, Metric_Already_Exists) => true
    (Metric_Not_Found, Metric_Not_Found) => true
    (Downsample_Policy_Already_Exists, Downsample_Policy_Already_Exists) => true
    (Downsample_Policy_Not_Found, Downsample_Policy_Not_Found) => true
    (Continuous_Query_Already_Exists, Continuous_Query_Already_Exists) => true
    (Continuous_Query_Not_Found, Continuous_Query_Not_Found) => true
    (Retention_Policy_Already_Exists, Retention_Policy_Already_Exists) => true
    (Retention_Policy_Not_Found, Retention_Policy_Not_Found) => true
    (Invalid_DataPoint, Invalid_DataPoint) => true
    (Too_Many_DataPoints, Too_Many_DataPoints) => true
    (Query_Timeout, Query_Timeout) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend TimeSeriesError with Eq::{equal, not_equal}

///|
pub extend TimeSeriesError with Debug::{to_repr}

///|
/// 获取错误码
pub fn TimeSeriesError::code(self : TimeSeriesError) -> Int {
  match self {
    Metric_Already_Exists => 9001
    Metric_Not_Found => 9002
    Downsample_Policy_Already_Exists => 9003
    Downsample_Policy_Not_Found => 9004
    Continuous_Query_Already_Exists => 9005
    Continuous_Query_Not_Found => 9006
    Retention_Policy_Already_Exists => 9007
    Retention_Policy_Not_Found => 9008
    Invalid_DataPoint => 9009
    Too_Many_DataPoints => 9010
    Query_Timeout => 9011
    Internal_Error(_) => 9099
  }
}

///|
/// 获取错误消息
pub fn TimeSeriesError::message(self : TimeSeriesError) -> String {
  match self {
    Metric_Already_Exists => "Metric already exists"
    Metric_Not_Found => "Metric not found"
    Downsample_Policy_Already_Exists => "Downsample policy already exists"
    Downsample_Policy_Not_Found => "Downsample policy not found"
    Continuous_Query_Already_Exists => "Continuous query already exists"
    Continuous_Query_Not_Found => "Continuous query not found"
    Retention_Policy_Already_Exists => "Retention policy already exists"
    Retention_Policy_Not_Found => "Retention policy not found"
    Invalid_DataPoint => "Invalid data point"
    Too_Many_DataPoints => "Too many data points"
    Query_Timeout => "Query timeout"
    Internal_Error(msg) => "Internal error: " + msg
  }
}

///|
/// 转为字符串
pub fn TimeSeriesError::to_string(self : TimeSeriesError) -> String {
  "[Error " + self.code().to_string() + "] " + self.message()
}

///|
/// 查询请求
pub(all) struct QueryRequest {
  /// 度量名
  metric_name : String
  /// 标签过滤器
  label_filters : Map[String, String]
  /// 起始时间
  start_time : Int
  /// 结束时间
  end_time : Int
  /// 聚合类型
  aggregation : AggregationType
  /// 窗口大小（秒）
  window_seconds : Int?
  /// 降采样精度
  precision : DownsamplePrecision?
  /// 最大数据点数
  max_data_points : Int?
}

///|
/// 查询结果
pub(all) struct QueryResult {
  /// 数据点列表
  data_points : Array[DataPoint]
  /// 聚合类型
  aggregation : AggregationType
  /// 精度
  precision : DownsamplePrecision?
  /// 查询耗时（毫秒）
  latency_ms : Int
}

///|
/// 时间序列统计
pub(all) struct TimeSeriesStats {
  /// 度量数
  mut metric_count : Int
  /// 总数据点数
  mut total_data_points : Int
  /// 总大小（字节）
  mut total_size_bytes : Int
  /// 平均写入延迟（毫秒）
  mut avg_write_latency_ms : Double
  /// 平均查询延迟（毫秒）
  mut avg_query_latency_ms : Double
  /// P99 查询延迟（毫秒）
  mut p99_query_latency_ms : Int
  /// 查询吞吐量（查询/秒）
  mut query_throughput_qps : Double
}
