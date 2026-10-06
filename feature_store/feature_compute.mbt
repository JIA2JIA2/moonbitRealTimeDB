// 特征计算模块
//
// 实现特征计算、滑动窗口聚合、特征版本管理

///|
/// 特征计算引擎
pub(all) struct FeatureComputeEngine {
  /// 流引擎引用
  stream_engine : @realtime_db.StreamEngine?
  /// 批处理引擎
  batch_engine : BatchComputeEngine?
  /// 特征聚合器映射
  mut aggregators : Map[String, FeatureAggregator>
  /// 计算窗口配置
  window_configs : Map[String, WindowConfig>
}

///|
/// 创建特征计算引擎
pub fn FeatureComputeEngine::new() -> FeatureComputeEngine {
  {
    stream_engine: None,
    batch_engine: None,
    aggregators: Map([]),
    window_configs: Map([]),
  }
}

///|
/// 设置流引擎
pub fn FeatureComputeEngine::set_stream_engine(self : FeatureComputeEngine, engine : @realtime_db.StreamEngine?) -> Unit {
  self.stream_engine = engine
}

///|
/// 注册特征聚合器
pub fn FeatureComputeEngine::register_aggregator(
  self : FeatureComputeEngine,
  feature_name : String,
  aggregator : FeatureAggregator,
) -> Result[Unit, FeatureError> {
  if self.aggregators.contains_key(feature_name) {
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
) -> Result[Unit, FeatureError> {
  self.window_configs.set(feature_name, config)
  Ok(())
}

///|
/// 计算特征
pub fn FeatureComputeEngine::compute(
  self : FeatureComputeEngine,
  feature_name : String,
  data : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, FeatureError> {
  let aggregator = match self.aggregators.get(feature_name) {
    Some(a) => a
    None => return Err(Feature_Not_Found),
  }

  aggregator.aggregate(data)
}

///|
/// 滑动窗口计算
pub fn FeatureComputeEngine::sliding_window_compute(
  self : FeatureComputeEngine,
  feature_name : String,
  events : Array[@realtime_db.StreamEvent],
  window_size_ms : Int,
  slide_interval_ms : Int,
) -> Result[Array[FeatureVector], FeatureError> {
  let aggregator = match self.aggregators.get(feature_name) {
    Some(a) => a
    None => return Err(Feature_Not_Found),
  }

  // 按窗口分组
  let windowed_data : Map[Int, Array[@realtime_db.StreamEvent]] = Map([])

  for event in events {
    let window_start = event.timestamp - (event.timestamp % slide_interval_ms)
    let window_events = match windowed_data.get(window_start) {
      Some(w) => w
      None => {
        let new_window = Array[@realtime_db.StreamEvent]
        windowed_data.set(window_start, new_window)
        new_window
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

    match aggregator.aggregate(values) {
      Ok(result_value) => {
        results.push(FeatureVector {
          vector_id: feature_name + "_" + window_start.to_string(),
          entity_id: feature_name,
          table_id: "",
          values: Map([("value", result_value)]),
          version: 1,
          timestamp: window_start,
          is_valid: true,
        })
      }
      Err(_) => ()
    }
  }

  Ok(results)
}

///|
/// 特征聚合器接口
pub(all) trait FeatureAggregator {
  /// 聚合数据
  fn aggregate(self : Self, data : Array[@realtime_db.Value]) -> Result[@realtime_db.Value, FeatureError>
  /// 合并状态
  fn merge(self : Self, state1 : @realtime_db.Value, state2 : @realtime_db.Value) -> Result[@realtime_db.Value, FeatureError>
}

///|
/// 计数聚合器
pub(all) struct CountAggregator {}

///|
/// 创建计数聚合器
pub fn CountAggregator::new() -> CountAggregator {
  {}
}

///|
impl FeatureAggregator for CountAggregator with fn aggregate(self, data) -> Result[@realtime_db.Value, FeatureError] {
  Ok(@realtime_db.Int(data.length()))
}

fn merge(self : CountAggregator, state1 : @realtime_db.Value, state2 : @realtime_db.Value) -> Result[@realtime_db.Value, FeatureError] {
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
/// 求和聚合器
pub(all) struct SumAggregator {}

///|
/// 创建求和聚合器
pub fn SumAggregator::new() -> SumAggregator {
  {}
}

///|
impl FeatureAggregator for SumAggregator with fn aggregate(self, data) -> Result[@realtime_db.Value, FeatureError] {
  var total = 0
  for value in data {
    match value {
      @realtime_db.Int(i) => total = total + i
      @realtime_db.Float(f) => total = total + f.to_int()
      _ => ()
    }
  }
  Ok(@realtime_db.Int(total))
}

fn merge(self : SumAggregator, state1 : @realtime_db.Value, state2 : @realtime_db.Value) -> Result[@realtime_db.Value, FeatureError] {
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
/// 平均值聚合器
pub(all) struct AvgAggregator {}

///|
/// 创建平均值聚合器
pub fn AvgAggregator::new() -> AvgAggregator {
  {}
}

///|
impl FeatureAggregator for AvgAggregator with fn aggregate(self, data) -> Result[@realtime_db.Value, FeatureError] {
  var total = 0.0
  var count = 0
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

fn merge(self : AvgAggregator, state1 : @realtime_db.Value, state2 : @realtime_db.Value) -> Result[@realtime_db.Value, FeatureError] {
  let _ = state1
  let _ = state2
  Ok(@realtime_db.Float(0.0))
}

///|
/// 最大值聚合器
pub(all) struct MaxAggregator {}

///|
/// 创建最大值聚合器
pub fn MaxAggregator::new() -> MaxAggregator {
  {}
}

///|
impl FeatureAggregator for MaxAggregator with fn aggregate(self, data) -> Result[@realtime_db.Value, FeatureError] {
  var max : Int? = None
  for value in data {
    match value {
      @realtime_db.Int(i) => {
        if max is None or i > max? {
          max = Some(i)
        }
      }
      _ => ()
    }
  }
  Ok(@realtime_db.Int(max? ?? 0))
}

fn merge(self : MaxAggregator, state1 : @realtime_db.Value, state2 : @realtime_db.Value) -> Result[@realtime_db.Value, FeatureError] {
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
/// 最小值聚合器
pub(all) struct MinAggregator {}

///|
/// 创建最小值聚合器
pub fn MinAggregator::new() -> MinAggregator {
  {}
}

///|
impl FeatureAggregator for MinAggregator with fn aggregate(self, data) -> Result[@realtime_db.Value, FeatureError] {
  var min : Int? = None
  for value in data {
    match value {
      @realtime_db.Int(i) => {
        if min is None or i < min? {
          min = Some(i)
        }
      }
      _ => ()
    }
  }
  Ok(@realtime_db.Int(min? ?? 0))
}

fn merge(self : MinAggregator, state1 : @realtime_db.Value, state2 : @realtime_db.Value) -> Result[@realtime_db.Value, FeatureError] {
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
/// 窗口配置
pub(all) struct WindowConfig {
  /// 窗口大小（毫秒）
  window_size_ms : Int
  /// 滑动间隔（毫秒）
  slide_interval_ms : Int
  /// 聚合函数
  aggregator : FeatureAggregator
}

///|
/// 批计算引擎（简化实现）
pub(all) struct BatchComputeEngine {}

///|
/// 创建特征计算引擎
pub fn create_feature_compute_engine() -> FeatureComputeEngine {
  FeatureComputeEngine::new()
}

///|
/// 创建计数聚合器
pub fn create_count_aggregator() -> FeatureAggregator {
  CountAggregator::new() as FeatureAggregator
}

///|
/// 创建求和聚合器
pub fn create_sum_aggregator() -> FeatureAggregator {
  SumAggregator::new() as FeatureAggregator
}

///|
/// 创建平均值聚合器
pub fn create_avg_aggregator() -> FeatureAggregator {
  AvgAggregator::new() as FeatureAggregator
}

///|
/// 创建最大值聚合器
pub fn create_max_aggregator() -> FeatureAggregator {
  MaxAggregator::new() as FeatureAggregator
}

///|
/// 创建最小值聚合器
pub fn create_min_aggregator() -> FeatureAggregator {
  MinAggregator::new() as FeatureAggregator
}