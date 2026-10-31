// 时间序列引擎管理器模块
//
// 实现度量管理、数据点写入、查询、降采样、连续查询

///|
/// 时间序列引擎
pub(all) struct TimeSeriesEngine {
  /// 度量映射
  mut metrics : Map[String, Metric]
  /// 降采样策略映射
  mut downsample_policies : Map[String, DownsamplePolicy]
  /// 连续查询映射
  mut continuous_queries : Map[String, ContinuousQuery]
  /// 保留策略映射
  mut retention_policies : Map[String, RetentionPolicy]
  /// 配置
  config : TimeSeriesConfig
  /// 统计
  mut stats : TimeSeriesStats
  /// 下一个度量 ID
  mut next_metric_id : Int
  /// 下一个策略 ID
  mut next_policy_id : Int
  /// 下一个查询 ID
  mut next_query_id : Int
}

///|
/// 创建时间序列引擎
pub fn TimeSeriesEngine::new(config : TimeSeriesConfig) -> TimeSeriesEngine {
  TimeSeriesEngine::{
    metrics: Map([]),
    downsample_policies: Map([]),
    continuous_queries: Map([]),
    retention_policies: Map([]),
    config,
    stats: TimeSeriesStats::{
      metric_count: 0,
      total_data_points: 0,
      total_size_bytes: 0,
      avg_write_latency_ms: 0.0,
      avg_query_latency_ms: 0.0,
      p99_query_latency_ms: 0,
      query_throughput_qps: 0.0,
    },
    next_metric_id: 0,
    next_policy_id: 0,
    next_query_id: 0,
  }
}

///|
/// 创建度量
pub fn TimeSeriesEngine::create_metric(
  self : TimeSeriesEngine,
  metric_name : String,
  labels : Map[String, String],
) -> Result[String, TimeSeriesError] {
  // 检查度量是否已存在
  if self.metrics.contains(metric_name) {
    return Err(Metric_Already_Exists)
  }

  // 生成度量 ID
  let metric_id = "metric_" + self.next_metric_id.to_string()
  self.next_metric_id = self.next_metric_id + 1

  // 创建度量
  let metric = Metric::{
    metric_id: metric_id.to_string(),
    metric_name,
    labels,
    data_points: [],
    created_at: 0,
    updated_at: 0,
  }

  // 保存度量
  self.metrics.set(metric_name, metric)
  self.stats.metric_count = self.stats.metric_count + 1

  Ok(metric_id)
}

///|
/// 获取度量
pub fn TimeSeriesEngine::get_metric(
  self : TimeSeriesEngine,
  metric_name : String,
) -> Metric? {
  self.metrics.get(metric_name)
}

///|
/// 列出所有度量
pub fn TimeSeriesEngine::list_metrics(self : TimeSeriesEngine) -> Array[Metric] {
  let result : Array[Metric] = []
  for (_, metric) in self.metrics {
    result.push(metric)
  }
  result
}

///|
/// 删除度量
pub fn TimeSeriesEngine::delete_metric(
  self : TimeSeriesEngine,
  metric_name : String,
) -> Result[Unit, TimeSeriesError] {
  if !self.metrics.contains(metric_name) {
    return Err(Metric_Not_Found)
  }

  self.metrics.remove(metric_name)
  self.stats.metric_count = self.stats.metric_count - 1

  Ok(())
}

///|
/// 写入数据点
pub fn TimeSeriesEngine::write_data_point(
  self : TimeSeriesEngine,
  metric_name : String,
  timestamp : Int,
  value : Double,
) -> Result[Unit, TimeSeriesError] {
  // 获取度量
  let metric = match self.metrics.get(metric_name) {
    Some(m) => m
    None => return Err(Metric_Not_Found)
  }

  // 创建数据点
  let data_point = DataPoint::{ timestamp, value, is_valid: true, }

  // 添加数据点
  metric.data_points.push(data_point)
  metric.updated_at = 0

  // 更新统计
  self.stats.total_data_points = self.stats.total_data_points + 1

  // 检查数据点数量限制
  if metric.data_points.length() > self.config.max_data_points {
    // 简化实现：删除最旧的数据点
    let _ = metric.data_points.remove(0)
  }

  Ok(())
}

///|
/// 批量写入数据点
pub fn TimeSeriesEngine::batch_write_data_points(
  self : TimeSeriesEngine,
  metric_name : String,
  data_points : Array[DataPoint],
) -> Result[Unit, TimeSeriesError] {
  // 获取度量
  let metric = match self.metrics.get(metric_name) {
    Some(m) => m
    None => return Err(Metric_Not_Found)
  }

  // 添加数据点
  for dp in data_points {
    metric.data_points.push(dp)
  }

  metric.updated_at = 0
  self.stats.total_data_points = self.stats.total_data_points +
    data_points.length()

  Ok(())
}

///|
/// 查询数据
pub fn TimeSeriesEngine::query(
  self : TimeSeriesEngine,
  request : QueryRequest,
) -> Result[QueryResult, TimeSeriesError] {
  // 获取度量
  let metric = match self.metrics.get(request.metric_name) {
    Some(m) => m
    None => return Err(Metric_Not_Found)
  }

  // 过滤时间范围
  let filtered_data : Array[DataPoint] = []
  for dp in metric.data_points {
    if dp.timestamp >= request.start_time && dp.timestamp <= request.end_time {
      // 检查标签过滤器
      let mut match_filter = true
      for (key, value) in request.label_filters {
        match metric.labels.get(key) {
          Some(v) => if v != value { match_filter = false }
          None => match_filter = false
        }
      }

      if match_filter {
        filtered_data.push(dp)
      }
    }
  }

  // 聚合数据
  let aggregated_data = self.aggregate_data(
    filtered_data,
    request.aggregation,
    request.window_seconds,
  )

  // 应用降采样
  let final_data = match request.precision {
    Some(precision) => self.downsample(aggregated_data, precision)
    None => aggregated_data
  }

  // 限制数据点数量
  let final_len = final_data.length()
  let limited_data = match request.max_data_points {
    Some(max) =>
      if final_len > max {
        let limited : Array[DataPoint] = []
        for i in 0..<max {
          limited.push(final_data[i])
        }
        limited
      } else {
        final_data
      }
    None => final_data
  }

  Ok(QueryResult::{
    data_points: limited_data,
    aggregation: request.aggregation,
    precision: request.precision,
    latency_ms: 0,
  })
}

///|
/// 聚合数据
fn TimeSeriesEngine::aggregate_data(
  self : TimeSeriesEngine,
  data : Array[DataPoint],
  aggregation : AggregationType,
  window_seconds : Int?,
) -> Array[DataPoint] {
  if data.length() == 0 {
    return []
  }

  // 如果没有窗口，直接聚合所有数据
  let window_size = match window_seconds {
    Some(ws) => ws
    None => {
      let result = self.calculate_aggregation(data, aggregation)
      return match result {
        Some(value) =>
          [DataPoint::{ timestamp: data[0].timestamp, value, is_valid: true, }]
        None => []
      }
    }
  }

  // 按窗口聚合
  let result : Array[DataPoint] = []

  // 按时间排序
  let sorted_data = data
  // 简化实现：假设数据已排序

  // 按窗口分组
  let mut current_window_start = sorted_data[0].timestamp -
    sorted_data[0].timestamp % window_size
  let mut window_data : Array[DataPoint] = []

  for dp in sorted_data {
    let window_start = dp.timestamp - dp.timestamp % window_size

    if window_start != current_window_start {
      // 计算窗口聚合
      let agg_result = self.calculate_aggregation(window_data, aggregation)
      match agg_result {
        Some(value) =>
          result.push(DataPoint::{
            timestamp: current_window_start,
            value,
            is_valid: true,
          })
        None => ()
      }

      current_window_start = window_start
      window_data = []
    }

    window_data.push(dp)
  }

  // 处理最后一个窗口
  if window_data.length() > 0 {
    let agg_result = self.calculate_aggregation(window_data, aggregation)
    match agg_result {
      Some(value) =>
        result.push(DataPoint::{
          timestamp: current_window_start,
          value,
          is_valid: true,
        })
      None => ()
    }
  }

  result
}

///|
/// 计算聚合值
fn TimeSeriesEngine::calculate_aggregation(
  self : TimeSeriesEngine,
  data : Array[DataPoint],
  aggregation : AggregationType,
) -> Double? {
  let _ = self
  if data.length() == 0 {
    return None
  }

  match aggregation {
    Avg => {
      let mut total = 0.0
      for dp in data {
        total = total + dp.value
      }
      Some(total / data.length().to_double())
    }
    Sum => {
      let mut total = 0.0
      for dp in data {
        total = total + dp.value
      }
      Some(total)
    }
    Min => {
      let mut min = data[0].value
      for dp in data {
        if dp.value < min {
          min = dp.value
        }
      }
      Some(min)
    }
    Max => {
      let mut max = data[0].value
      for dp in data {
        if dp.value > max {
          max = dp.value
        }
      }
      Some(max)
    }
    Count => Some(data.length().to_double())
    First => Some(data[0].value)
    Last => Some(data[data.length() - 1].value)
    Median => {
      // 简化实现：取中间值（假设已排序）
      let sorted = data
      Some(sorted[sorted.length() / 2].value)
    }
    P50 => Some(data[data.length() / 2].value)
    P90 => {
      let idx = data.length() * 90 / 100
      Some(data[idx].value)
    }
    P99 => {
      let idx = data.length() * 99 / 100
      Some(data[idx].value)
    }
  }
}

///|
/// 降采样
fn TimeSeriesEngine::downsample(
  self : TimeSeriesEngine,
  data : Array[DataPoint],
  precision : DownsamplePrecision,
) -> Array[DataPoint] {
  let _ = (self, precision)
  // 简化实现：返回原数据
  // 实际实现应该根据精度进行降采样
  data
}

///|
/// 创建降采样策略
pub fn TimeSeriesEngine::create_downsample_policy(
  self : TimeSeriesEngine,
  policy_name : String,
  precision : DownsamplePrecision,
  aggregation : AggregationType,
  retention_seconds : Int,
) -> Result[String, TimeSeriesError] {
  // 检查策略是否已存在
  if self.downsample_policies.contains(policy_name) {
    return Err(Downsample_Policy_Already_Exists)
  }

  // 生成策略 ID
  let policy_id = "policy_" + self.next_policy_id.to_string()
  self.next_policy_id = self.next_policy_id + 1

  // 创建策略
  let policy = DownsamplePolicy::{
    policy_id: policy_id.to_string(),
    policy_name,
    precision,
    aggregation,
    retention_seconds,
    is_enabled: true,
  }

  // 保存策略
  self.downsample_policies.set(policy_name, policy)

  Ok(policy_id)
}

///|
/// 创建连续查询
pub fn TimeSeriesEngine::create_continuous_query(
  self : TimeSeriesEngine,
  query_name : String,
  source_metric : String,
  target_metric : String,
  query_interval_seconds : Int,
  aggregation : AggregationType,
  window_seconds : Int,
) -> Result[String, TimeSeriesError] {
  // 检查查询是否已存在
  if self.continuous_queries.contains(query_name) {
    return Err(Continuous_Query_Already_Exists)
  }

  // 检查源度量是否存在
  if !self.metrics.contains(source_metric) {
    return Err(Metric_Not_Found)
  }

  // 生成查询 ID
  let query_id = "cq_" + self.next_query_id.to_string()
  self.next_query_id = self.next_query_id + 1

  // 创建查询
  let query = ContinuousQuery::{
    query_id: query_id.to_string(),
    query_name,
    source_metric,
    target_metric,
    query_interval_seconds,
    aggregation,
    window_seconds,
    is_enabled: true,
  }

  // 保存查询
  self.continuous_queries.set(query_name, query)

  Ok(query_id)
}

///|
/// 创建保留策略
pub fn TimeSeriesEngine::create_retention_policy(
  self : TimeSeriesEngine,
  policy_name : String,
  policy_type : RetentionPolicyType,
  retention_seconds : Int,
  max_data_points : Int,
  max_size_bytes : Int,
) -> Result[String, TimeSeriesError] {
  // 检查策略是否已存在
  if self.retention_policies.contains(policy_name) {
    return Err(Retention_Policy_Already_Exists)
  }

  // 生成策略 ID
  let policy_id = "rp_" + self.next_policy_id.to_string()
  self.next_policy_id = self.next_policy_id + 1

  // 创建策略
  let policy = RetentionPolicy::{
    policy_id: policy_id.to_string(),
    policy_name,
    policy_type,
    retention_seconds,
    max_data_points,
    max_size_bytes,
    is_enabled: true,
  }

  // 保存策略
  self.retention_policies.set(policy_name, policy)

  Ok(policy_id)
}

///|
/// 执行连续查询
pub fn TimeSeriesEngine::execute_continuous_queries(
  self : TimeSeriesEngine,
) -> Unit {
  for (_, query) in self.continuous_queries {
    if query.is_enabled {
      let source_name = query.source_metric.to_string()
      let target_name = query.target_metric.to_string()
      let aggregation = query.aggregation

      // 获取源度量
      match self.metrics.get(source_name) {
        Some(source_metric) => {
          // 获取或创建目标度量
          if !self.metrics.contains(target_name.to_string()) {
            let _ = self.create_metric(target_name.to_string(), Map([]))
          }

          // 计算聚合
          let latest_data = source_metric.data_points.copy()
          let result = self.calculate_aggregation(latest_data, aggregation)

          match result {
            Some(value) => {
              // 写入目标度量
              let _ = self.write_data_point(target_name, 0, value)
            }
            None => ()
          }
        }
        None => ()
      }
    }
  }
}

///|
/// 清理过期数据。
///
/// 以 current_time 为基准删除超过保留期
/// （default_retention_seconds，<=0 视为永久保留）的数据点；
/// 未指定 current_time 时取引擎内全部数据点中的最大时间戳作为
/// 数据驱动的水位时间（无数据则为 0，不会清理任何数据）。
///
/// 注意：修改必须显式写回 self.metrics，仅对迭代得到的 struct
/// 拷贝赋值不会生效。
pub fn TimeSeriesEngine::cleanup_expired_data(
  self : TimeSeriesEngine,
  current_time? : Int,
) -> Int {
  let retention_seconds = self.config.default_retention_seconds
  if retention_seconds <= 0 {
    return 0
  }
  let now = match current_time {
    Some(t) => t
    None => self.data_watermark()
  }
  let mut cleaned_count = 0
  for metric_name, metric in self.metrics {
    if metric.data_points.length() == 0 {
      continue
    }
    let valid_data : Array[DataPoint] = []
    let mut removed = false
    for dp in metric.data_points {
      if now - dp.timestamp <= retention_seconds {
        valid_data.push(dp)
      } else {
        cleaned_count = cleaned_count + 1
        removed = true
      }
    }
    if removed {
      self.metrics.set(
        metric_name,
        { ..metric, data_points: valid_data },
      )
    }
  }
  cleaned_count
}

///|
/// 计算数据驱动的水位时间：全部度量数据点中的最大时间戳。
/// 无任何数据时返回 0。
fn TimeSeriesEngine::data_watermark(self : TimeSeriesEngine) -> Int {
  let mut max_ts = 0
  for _, metric in self.metrics {
    for dp in metric.data_points {
      if dp.timestamp > max_ts {
        max_ts = dp.timestamp
      }
    }
  }
  max_ts
}

///|
/// 获取统计
pub fn TimeSeriesEngine::get_stats(self : TimeSeriesEngine) -> TimeSeriesStats {
  TimeSeriesStats::{
    metric_count: self.stats.metric_count,
    total_data_points: self.stats.total_data_points,
    total_size_bytes: self.stats.total_size_bytes,
    avg_write_latency_ms: self.stats.avg_write_latency_ms,
    avg_query_latency_ms: self.stats.avg_query_latency_ms,
    p99_query_latency_ms: self.stats.p99_query_latency_ms,
    query_throughput_qps: self.stats.query_throughput_qps,
  }
}

///|
/// 创建时间序列引擎
pub fn create_timeseries_engine(config : TimeSeriesConfig) -> TimeSeriesEngine {
  TimeSeriesEngine::new(config)
}

///|
/// 创建默认时间序列引擎
pub fn create_default_timeseries_engine() -> TimeSeriesEngine {
  TimeSeriesEngine::new(TimeSeriesConfig::default())
}
