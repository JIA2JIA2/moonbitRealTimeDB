// 特征计算模块
//
// 实现特征计算、滑动窗口聚合、特征版本管理

///|
/// 聚合器种类（用于注册和分发）
pub(all) enum AggregatorKind {
  /// 计数
  Count
  /// 求和
  Sum
  /// 平均值
  Avg
  /// 最大值
  Max
  /// 最小值
  Min
}

///|
/// 特征计算引擎
pub(all) struct FeatureComputeEngine {
  /// 特征聚合器映射：特征名 -> 聚合器种类
  mut aggregators : Map[String, AggregatorKind]
  /// 计算窗口配置：特征名 -> 窗口配置
  mut window_configs : Map[String, WindowConfig]
}

///|
/// 创建特征计算引擎
pub fn FeatureComputeEngine::new() -> FeatureComputeEngine {
  { aggregators: Map([]), window_configs: Map([]), }
}

///|
/// 注册特征聚合器
pub fn FeatureComputeEngine::register_aggregator(
  self : FeatureComputeEngine,
  feature_name : String,
  aggregator : AggregatorKind,
) -> Result[Unit, FeatureError] {
  if self.aggregators.contains(feature_name.to_string()) {
    return Err(Feature_Already_Exists)
  }

  self.aggregators.set(feature_name, aggregator)
  Ok(())
}

///|
/// 注册窗口配置
pub fn FeatureComputeEngine::register_window_config(
  self : FeatureComputeEngine,
  feature_name : String,
  config : WindowConfig,
) -> Result[Unit, FeatureError] {
  self.window_configs.set(feature_name, config)
  Ok(())
}

///|
/// 计算特征
pub fn FeatureComputeEngine::compute(
  self : FeatureComputeEngine,
  feature_name : String,
  data : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, FeatureError] {
  let kind = match self.aggregators.get(feature_name) {
    Some(a) => a
    None => return Err(Feature_Not_Found)
  }

  run_aggregate(kind, data)
}

///|
/// 滑动窗口计算
pub fn FeatureComputeEngine::sliding_window_compute(
  self : FeatureComputeEngine,
  feature_name : String,
  events : Array[@stream_engine.StreamEvent],
  window_size_ms : Int,
  slide_interval_ms : Int,
) -> Result[Array[FeatureVector], FeatureError] {
  let _ = window_size_ms
  let kind = match self.aggregators.get(feature_name) {
    Some(a) => a
    None => return Err(Feature_Not_Found)
  }

  // 按窗口分组
  let windowed_data : Map[Int, Array[@stream_engine.StreamEvent]] = Map([])

  for event in events {
    let window_start = event.timestamp - event.timestamp % slide_interval_ms
    let window_events = match windowed_data.get(window_start) {
      Some(w) => w
      None => {
        let new_window : Array[@stream_engine.StreamEvent] = []
        windowed_data.set(window_start, new_window)
        match windowed_data.get(window_start) {
          Some(w) => w
          None => return Err(Internal_Error("Failed to create window"))
        }
      }
    }
    window_events.push(event)
  }

  // 聚合每个窗口
  let results : Array[FeatureVector] = []
  for (window_start, window_events) in windowed_data {
    let values : Array[@realtime_db.Value] = []
    for event in window_events {
      values.push(event.value)
    }

    match run_aggregate(kind, values) {
      Ok(result_value) =>
        results.push(FeatureVector::{
          vector_id: feature_name.to_string() + "_" + window_start.to_string(),
          entity_id: feature_name.to_string(),
          table_id: "".to_string(),
          values: Map([("value", result_value)]),
          version: 1,
          timestamp: window_start,
          is_valid: true,
        })
      Err(_) => ()
    }
  }

  Ok(results)
}

///|
/// 执行聚合分发
fn run_aggregate(
  kind : AggregatorKind,
  data : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, FeatureError] {
  match kind {
    Count => CountAggregator::new().aggregate(data)
    Sum => SumAggregator::new().aggregate(data)
    Avg => AvgAggregator::new().aggregate(data)
    Max => MaxAggregator::new().aggregate(data)
    Min => MinAggregator::new().aggregate(data)
  }
}

///|
/// 特征聚合器接口
pub trait FeatureAggregator {
  /// 聚合数据
  fn aggregate(self : Self, data : Array[@realtime_db.Value]) -> Result[
    @realtime_db.Value,
    FeatureError,
  ]
  /// 合并状态
  fn merge(
    self : Self,
    state1 : @realtime_db.Value,
    state2 : @realtime_db.Value,
  ) -> Result[@realtime_db.Value, FeatureError]
}

///|
/// 计数聚合器
pub(all) struct CountAggregator {
  _placeholder : Unit
}

///|
/// 创建计数聚合器
pub fn CountAggregator::new() -> CountAggregator {
  { _placeholder: (), }
}

///|
pub impl FeatureAggregator for CountAggregator with fn aggregate(
  self : CountAggregator,
  data : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  Ok(@realtime_db.Int(data.length()))
}

///|
pub impl FeatureAggregator for CountAggregator with fn merge(
  self : CountAggregator,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  let count1 = match state1 {
    @realtime_db.Int(i) => i
    _ => 0
  }
  let count2 = match state2 {
    @realtime_db.Int(i) => i
    _ => 0
  }
  Ok(@realtime_db.Int(count1 + count2))
}

///|
pub extend CountAggregator with FeatureAggregator::{aggregate, merge}

///|
/// 求和聚合器
pub(all) struct SumAggregator {
  _placeholder : Unit
}

///|
/// 创建求和聚合器
pub fn SumAggregator::new() -> SumAggregator {
  { _placeholder: (), }
}

///|
pub impl FeatureAggregator for SumAggregator with fn aggregate(
  self : SumAggregator,
  data : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  let mut total = 0
  for value in data {
    match value {
      @realtime_db.Int(i) => total = total + i
      @realtime_db.Float(f) => total = total + f.to_int()
      _ => ()
    }
  }
  Ok(@realtime_db.Int(total))
}

///|
pub impl FeatureAggregator for SumAggregator with fn merge(
  self : SumAggregator,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  let sum1 = match state1 {
    @realtime_db.Int(i) => i
    _ => 0
  }
  let sum2 = match state2 {
    @realtime_db.Int(i) => i
    _ => 0
  }
  Ok(@realtime_db.Int(sum1 + sum2))
}

///|
pub extend SumAggregator with FeatureAggregator::{aggregate, merge}

///|
/// 平均值聚合器
pub(all) struct AvgAggregator {
  _placeholder : Unit
}

///|
/// 创建平均值聚合器
pub fn AvgAggregator::new() -> AvgAggregator {
  { _placeholder: (), }
}

///|
pub impl FeatureAggregator for AvgAggregator with fn aggregate(
  self : AvgAggregator,
  data : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  let mut total = 0.0
  let mut count = 0
  for value in data {
    match value {
      @realtime_db.Int(i) => {
        total = total + i.to_double()
        count = count + 1
      }
      @realtime_db.Float(f) => {
        total = total + f
        count = count + 1
      }
      _ => ()
    }
  }
  if count > 0 {
    Ok(@realtime_db.Float(total / count.to_double()))
  } else {
    Ok(@realtime_db.Float(0.0))
  }
}

///|
pub impl FeatureAggregator for AvgAggregator with fn merge(
  self : AvgAggregator,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  let _ = state1
  let _ = state2
  Ok(@realtime_db.Float(0.0))
}

///|
pub extend AvgAggregator with FeatureAggregator::{aggregate, merge}

///|
/// 最大值聚合器
pub(all) struct MaxAggregator {
  _placeholder : Unit
}

///|
/// 创建最大值聚合器
pub fn MaxAggregator::new() -> MaxAggregator {
  { _placeholder: (), }
}

///|
pub impl FeatureAggregator for MaxAggregator with fn aggregate(
  self : MaxAggregator,
  data : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  let mut max_value : Int? = None
  for value in data {
    match value {
      @realtime_db.Int(i) =>
        match max_value {
          None => max_value = Some(i)
          Some(m) => if i > m { max_value = Some(i) }
        }
      _ => ()
    }
  }
  match max_value {
    Some(m) => Ok(@realtime_db.Int(m))
    None => Ok(@realtime_db.Int(0))
  }
}

///|
pub impl FeatureAggregator for MaxAggregator with fn merge(
  self : MaxAggregator,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  let max1 = match state1 {
    @realtime_db.Int(i) => i
    _ => 0
  }
  let max2 = match state2 {
    @realtime_db.Int(i) => i
    _ => 0
  }
  Ok(@realtime_db.Int(if max1 > max2 { max1 } else { max2 }))
}

///|
pub extend MaxAggregator with FeatureAggregator::{aggregate, merge}

///|
/// 最小值聚合器
pub(all) struct MinAggregator {
  _placeholder : Unit
}

///|
/// 创建最小值聚合器
pub fn MinAggregator::new() -> MinAggregator {
  { _placeholder: (), }
}

///|
pub impl FeatureAggregator for MinAggregator with fn aggregate(
  self : MinAggregator,
  data : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  let mut min_value : Int? = None
  for value in data {
    match value {
      @realtime_db.Int(i) =>
        match min_value {
          None => min_value = Some(i)
          Some(m) => if i < m { min_value = Some(i) }
        }
      _ => ()
    }
  }
  match min_value {
    Some(m) => Ok(@realtime_db.Int(m))
    None => Ok(@realtime_db.Int(0))
  }
}

///|
pub impl FeatureAggregator for MinAggregator with fn merge(
  self : MinAggregator,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> Result[@realtime_db.Value, FeatureError] {
  let _ = self
  let min1 = match state1 {
    @realtime_db.Int(i) => i
    _ => 0
  }
  let min2 = match state2 {
    @realtime_db.Int(i) => i
    _ => 0
  }
  Ok(@realtime_db.Int(if min1 < min2 { min1 } else { min2 }))
}

///|
pub extend MinAggregator with FeatureAggregator::{aggregate, merge}

///|
/// 窗口配置
pub(all) struct WindowConfig {
  /// 窗口大小（毫秒）
  window_size_ms : Int
  /// 滑动间隔（毫秒）
  slide_interval_ms : Int
  /// 聚合器种类
  aggregator : AggregatorKind
}

///|
/// 批计算引擎（简化实现）
pub(all) struct BatchComputeEngine {
  _placeholder : Unit
}

///|
/// 创建特征计算引擎
pub fn create_feature_compute_engine() -> FeatureComputeEngine {
  FeatureComputeEngine::new()
}

///|
/// 创建计数聚合器种类
pub fn create_count_aggregator() -> AggregatorKind {
  Count
}

///|
/// 创建求和聚合器种类
pub fn create_sum_aggregator() -> AggregatorKind {
  Sum
}

///|
/// 创建平均值聚合器种类
pub fn create_avg_aggregator() -> AggregatorKind {
  Avg
}

///|
/// 创建最大值聚合器种类
pub fn create_max_aggregator() -> AggregatorKind {
  Max
}

///|
/// 创建最小值聚合器种类
pub fn create_min_aggregator() -> AggregatorKind {
  Min
}
