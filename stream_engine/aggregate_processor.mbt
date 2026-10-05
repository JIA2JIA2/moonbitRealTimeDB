// 聚合处理器模块
//
// 实现聚合函数接口和聚合计算逻辑
// 支持 Count/Sum/Avg/Max/Min 五种内置聚合

///|
/// 从键值对数组构造 Value::Map
fn vmap(pairs : Array[(String, @realtime_db.Value)]) -> @realtime_db.Value {
  let m : Map[String, @realtime_db.Value] = Map([])
  for (k, v) in pairs {
    m.set(k, v)
  }
  @realtime_db.Map(m)
}

///|
/// 聚合函数接口
pub trait AggregateFunction {
  /// 创建初始状态
  fn create_initial_state(self : Self) -> @realtime_db.Value

  /// 添加元素
  fn add(self : Self, state : @realtime_db.Value, value : @realtime_db.Value) -> @realtime_db.Value

  /// 移除元素（滑动窗口）
  fn remove(self : Self, state : @realtime_db.Value, value : @realtime_db.Value) -> @realtime_db.Value

  /// 合并状态
  fn merge(
    self : Self,
    state1 : @realtime_db.Value,
    state2 : @realtime_db.Value,
  ) -> @realtime_db.Value

  /// 获取结果
  fn get_result(self : Self, state : @realtime_db.Value) -> @realtime_db.Value
}

///|
/// 计数聚合函数
pub(all) struct CountAggregate {}

///|
/// 创建计数聚合函数
pub fn CountAggregate::new() -> CountAggregate {
  CountAggregate::{ }
}

///|
pub impl AggregateFunction for CountAggregate with fn create_initial_state(
  self : CountAggregate,
) -> @realtime_db.Value {
  let _ = self
  vmap([("count", @realtime_db.Int(0))])
}

///|
pub impl AggregateFunction for CountAggregate with fn add(
  self : CountAggregate,
  state : @realtime_db.Value,
  _value : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  match state {
    @realtime_db.Map(m) =>
      match m.get("count") {
        Some(@realtime_db.Int(count)) =>
          vmap([("count", @realtime_db.Int(count + 1))])
        _ => vmap([("count", @realtime_db.Int(1))])
      }
    _ => vmap([("count", @realtime_db.Int(1))])
  }
}

///|
pub impl AggregateFunction for CountAggregate with fn remove(
  self : CountAggregate,
  state : @realtime_db.Value,
  _value : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  match state {
    @realtime_db.Map(m) =>
      match m.get("count") {
        Some(@realtime_db.Int(count)) => {
          let new_count = if count > 0 { count - 1 } else { 0 }
          vmap([("count", @realtime_db.Int(new_count))])
        }
        _ => vmap([("count", @realtime_db.Int(0))])
      }
    _ => vmap([("count", @realtime_db.Int(0))])
  }
}

///|
pub impl AggregateFunction for CountAggregate with fn merge(
  self : CountAggregate,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let count1 = match state1 {
    @realtime_db.Map(m) =>
      match m.get("count") {
        Some(@realtime_db.Int(c)) => c
        _ => 0
      }
    _ => 0
  }

  let count2 = match state2 {
    @realtime_db.Map(m) =>
      match m.get("count") {
        Some(@realtime_db.Int(c)) => c
        _ => 0
      }
    _ => 0
  }

  vmap([("count", @realtime_db.Int(count1 + count2))])
}

///|
pub impl AggregateFunction for CountAggregate with fn get_result(
  self : CountAggregate,
  state : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  match state {
    @realtime_db.Map(m) =>
      match m.get("count") {
        Some(c) => c
        _ => @realtime_db.Int(0)
      }
    _ => @realtime_db.Int(0)
  }
}

///|
pub extend CountAggregate with AggregateFunction::{
  create_initial_state,
  add,
  remove,
  merge,
  get_result,
}

///|
/// 求和聚合函数
pub(all) struct SumAggregate {}

///|
/// 创建求和聚合函数
pub fn SumAggregate::new() -> SumAggregate {
  SumAggregate::{ }
}

///|
pub impl AggregateFunction for SumAggregate with fn create_initial_state(
  self : SumAggregate,
) -> @realtime_db.Value {
  let _ = self
  vmap([("sum", @realtime_db.Int(0))])
}

///|
pub impl AggregateFunction for SumAggregate with fn add(
  self : SumAggregate,
  state : @realtime_db.Value,
  value : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let current_sum = match state {
    @realtime_db.Map(m) =>
      match m.get("sum") {
        Some(@realtime_db.Int(s)) => s
        _ => 0
      }
    _ => 0
  }

  let add_value = match value {
    @realtime_db.Int(i) => i
    @realtime_db.Float(f) => f.to_int()
    _ => 0
  }

  vmap([("sum", @realtime_db.Int(current_sum + add_value))])
}

///|
pub impl AggregateFunction for SumAggregate with fn remove(
  self : SumAggregate,
  state : @realtime_db.Value,
  value : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let current_sum = match state {
    @realtime_db.Map(m) =>
      match m.get("sum") {
        Some(@realtime_db.Int(s)) => s
        _ => 0
      }
    _ => 0
  }

  let remove_value = match value {
    @realtime_db.Int(i) => i
    @realtime_db.Float(f) => f.to_int()
    _ => 0
  }

  vmap([("sum", @realtime_db.Int(current_sum - remove_value))])
}

///|
pub impl AggregateFunction for SumAggregate with fn merge(
  self : SumAggregate,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let sum1 = match state1 {
    @realtime_db.Map(m) =>
      match m.get("sum") {
        Some(@realtime_db.Int(s)) => s
        _ => 0
      }
    _ => 0
  }

  let sum2 = match state2 {
    @realtime_db.Map(m) =>
      match m.get("sum") {
        Some(@realtime_db.Int(s)) => s
        _ => 0
      }
    _ => 0
  }

  vmap([("sum", @realtime_db.Int(sum1 + sum2))])
}

///|
pub impl AggregateFunction for SumAggregate with fn get_result(
  self : SumAggregate,
  state : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  match state {
    @realtime_db.Map(m) =>
      match m.get("sum") {
        Some(s) => s
        _ => @realtime_db.Int(0)
      }
    _ => @realtime_db.Int(0)
  }
}

///|
pub extend SumAggregate with AggregateFunction::{
  create_initial_state,
  add,
  remove,
  merge,
  get_result,
}

///|
/// 平均值聚合函数
pub(all) struct AvgAggregate {}

///|
/// 创建平均值聚合函数
pub fn AvgAggregate::new() -> AvgAggregate {
  AvgAggregate::{ }
}

///|
pub impl AggregateFunction for AvgAggregate with fn create_initial_state(
  self : AvgAggregate,
) -> @realtime_db.Value {
  let _ = self
  vmap([("sum", @realtime_db.Int(0)), ("count", @realtime_db.Int(0))])
}

///|
pub impl AggregateFunction for AvgAggregate with fn add(
  self : AvgAggregate,
  state : @realtime_db.Value,
  value : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let (current_sum, current_count) = match state {
    @realtime_db.Map(m) => {
      let sum = match m.get("sum") {
        Some(@realtime_db.Int(s)) => s
        _ => 0
      }
      let count = match m.get("count") {
        Some(@realtime_db.Int(c)) => c
        _ => 0
      }
      (sum, count)
    }
    _ => (0, 0)
  }

  let add_value = match value {
    @realtime_db.Int(i) => i
    @realtime_db.Float(f) => f.to_int()
    _ => 0
  }

  vmap([
    ("sum", @realtime_db.Int(current_sum + add_value)),
    ("count", @realtime_db.Int(current_count + 1)),
  ])
}

///|
pub impl AggregateFunction for AvgAggregate with fn remove(
  self : AvgAggregate,
  state : @realtime_db.Value,
  value : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let (current_sum, current_count) = match state {
    @realtime_db.Map(m) => {
      let sum = match m.get("sum") {
        Some(@realtime_db.Int(s)) => s
        _ => 0
      }
      let count = match m.get("count") {
        Some(@realtime_db.Int(c)) => c
        _ => 0
      }
      (sum, count)
    }
    _ => (0, 0)
  }

  let remove_value = match value {
    @realtime_db.Int(i) => i
    @realtime_db.Float(f) => f.to_int()
    _ => 0
  }

  let new_count = if current_count > 0 { current_count - 1 } else { 0 }

  vmap([
    ("sum", @realtime_db.Int(current_sum - remove_value)),
    ("count", @realtime_db.Int(new_count)),
  ])
}

///|
pub impl AggregateFunction for AvgAggregate with fn merge(
  self : AvgAggregate,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let (sum1, count1) = match state1 {
    @realtime_db.Map(m) => {
      let sum = match m.get("sum") {
        Some(@realtime_db.Int(s)) => s
        _ => 0
      }
      let count = match m.get("count") {
        Some(@realtime_db.Int(c)) => c
        _ => 0
      }
      (sum, count)
    }
    _ => (0, 0)
  }

  let (sum2, count2) = match state2 {
    @realtime_db.Map(m) => {
      let sum = match m.get("sum") {
        Some(@realtime_db.Int(s)) => s
        _ => 0
      }
      let count = match m.get("count") {
        Some(@realtime_db.Int(c)) => c
        _ => 0
      }
      (sum, count)
    }
    _ => (0, 0)
  }

  vmap([
    ("sum", @realtime_db.Int(sum1 + sum2)),
    ("count", @realtime_db.Int(count1 + count2)),
  ])
}

///|
pub impl AggregateFunction for AvgAggregate with fn get_result(
  self : AvgAggregate,
  state : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  match state {
    @realtime_db.Map(m) => {
      let sum = match m.get("sum") {
        Some(@realtime_db.Int(s)) => s
        _ => 0
      }
      let count = match m.get("count") {
        Some(@realtime_db.Int(c)) => c
        _ => 0
      }
      if count > 0 {
        @realtime_db.Float(sum.to_double() / count.to_double())
      } else {
        @realtime_db.Float(0.0)
      }
    }
    _ => @realtime_db.Float(0.0)
  }
}

///|
pub extend AvgAggregate with AggregateFunction::{
  create_initial_state,
  add,
  remove,
  merge,
  get_result,
}

///|
/// 最大值聚合函数
pub(all) struct MaxAggregate {}

///|
/// 创建最大值聚合函数
pub fn MaxAggregate::new() -> MaxAggregate {
  MaxAggregate::{ }
}

///|
pub impl AggregateFunction for MaxAggregate with fn create_initial_state(
  self : MaxAggregate,
) -> @realtime_db.Value {
  let _ = self
  vmap([("max", @realtime_db.Null)])
}

///|
pub impl AggregateFunction for MaxAggregate with fn add(
  self : MaxAggregate,
  state : @realtime_db.Value,
  value : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let current_max = match state {
    @realtime_db.Map(m) =>
      match m.get("max") {
        Some(@realtime_db.Int(m_)) => m_
        _ => -2147483648
      }
    _ => -2147483648
  }

  let new_value = match value {
    @realtime_db.Int(i) => i
    @realtime_db.Float(f) => f.to_int()
    _ => current_max
  }

  vmap([
    (
      "max",
      @realtime_db.Int(
        if new_value > current_max {
          new_value
        } else {
          current_max
        },
      ),
    ),
  ])
}

///|
pub impl AggregateFunction for MaxAggregate with fn remove(
  self : MaxAggregate,
  state : @realtime_db.Value,
  _value : @realtime_db.Value,
) -> @realtime_db.Value {
  // 移除最大值需要重新计算，简化实现
  let _ = self
  state
}

///|
pub impl AggregateFunction for MaxAggregate with fn merge(
  self : MaxAggregate,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let max1 = match state1 {
    @realtime_db.Map(m) =>
      match m.get("max") {
        Some(@realtime_db.Int(m_)) => m_
        _ => -2147483648
      }
    _ => -2147483648
  }

  let max2 = match state2 {
    @realtime_db.Map(m) =>
      match m.get("max") {
        Some(@realtime_db.Int(m_)) => m_
        _ => -2147483648
      }
    _ => -2147483648
  }

  vmap([("max", @realtime_db.Int(if max1 > max2 { max1 } else { max2 }))])
}

///|
pub impl AggregateFunction for MaxAggregate with fn get_result(
  self : MaxAggregate,
  state : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  match state {
    @realtime_db.Map(m) =>
      match m.get("max") {
        Some(@realtime_db.Int(m_)) => @realtime_db.Int(m_)
        _ => @realtime_db.Int(0)
      }
    _ => @realtime_db.Int(0)
  }
}

///|
pub extend MaxAggregate with AggregateFunction::{
  create_initial_state,
  add,
  remove,
  merge,
  get_result,
}

///|
/// 最小值聚合函数
pub(all) struct MinAggregate {}

///|
/// 创建最小值聚合函数
pub fn MinAggregate::new() -> MinAggregate {
  MinAggregate::{ }
}

///|
pub impl AggregateFunction for MinAggregate with fn create_initial_state(
  self : MinAggregate,
) -> @realtime_db.Value {
  let _ = self
  vmap([("min", @realtime_db.Null)])
}

///|
pub impl AggregateFunction for MinAggregate with fn add(
  self : MinAggregate,
  state : @realtime_db.Value,
  value : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let current_min = match state {
    @realtime_db.Map(m) =>
      match m.get("min") {
        Some(@realtime_db.Int(m_)) => m_
        _ => 2147483647
      }
    _ => 2147483647
  }

  let new_value = match value {
    @realtime_db.Int(i) => i
    @realtime_db.Float(f) => f.to_int()
    _ => current_min
  }

  vmap([
    (
      "min",
      @realtime_db.Int(
        if new_value < current_min {
          new_value
        } else {
          current_min
        },
      ),
    ),
  ])
}

///|
pub impl AggregateFunction for MinAggregate with fn remove(
  self : MinAggregate,
  state : @realtime_db.Value,
  _value : @realtime_db.Value,
) -> @realtime_db.Value {
  // 移除最小值需要重新计算，简化实现
  let _ = self
  state
}

///|
pub impl AggregateFunction for MinAggregate with fn merge(
  self : MinAggregate,
  state1 : @realtime_db.Value,
  state2 : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  let min1 = match state1 {
    @realtime_db.Map(m) =>
      match m.get("min") {
        Some(@realtime_db.Int(m_)) => m_
        _ => 2147483647
      }
    _ => 2147483647
  }

  let min2 = match state2 {
    @realtime_db.Map(m) =>
      match m.get("min") {
        Some(@realtime_db.Int(m_)) => m_
        _ => 2147483647
      }
    _ => 2147483647
  }

  vmap([("min", @realtime_db.Int(if min1 < min2 { min1 } else { min2 }))])
}

///|
pub impl AggregateFunction for MinAggregate with fn get_result(
  self : MinAggregate,
  state : @realtime_db.Value,
) -> @realtime_db.Value {
  let _ = self
  match state {
    @realtime_db.Map(m) =>
      match m.get("min") {
        Some(@realtime_db.Int(m_)) => @realtime_db.Int(m_)
        _ => @realtime_db.Int(0)
      }
    _ => @realtime_db.Int(0)
  }
}

///|
pub extend MinAggregate with AggregateFunction::{
  create_initial_state,
  add,
  remove,
  merge,
  get_result,
}

///|
/// 聚合处理器
pub(all) struct AggregateProcessor {
  /// 聚合函数映射
  functions : Map[String, &AggregateFunction]
  /// 窗口状态映射
  window_states : Map[WindowId, @realtime_db.Value]
}

///|
/// 创建聚合处理器
pub fn AggregateProcessor::new() -> AggregateProcessor {
  { functions: Map([]), window_states: Map([]), }
}

///|
/// 注册聚合函数
pub fn AggregateProcessor::register_function(
  self : AggregateProcessor,
  name : String,
  func : &AggregateFunction,
) -> Result[Unit, StreamError] {
  if self.functions.contains(name) {
    return Err(Aggregate_Computation_Failed)
  }

  self.functions.set(name, func)
  Ok(())
}

///|
/// 获取聚合函数
pub fn AggregateProcessor::get_function(
  self : AggregateProcessor,
  name : String,
) -> &AggregateFunction? {
  self.functions.get(name)
}

///|
/// 执行聚合计算
pub fn AggregateProcessor::compute_aggregate(
  self : AggregateProcessor,
  fn_name : String,
  window_id : WindowId,
  value : @realtime_db.Value,
) -> Result[@realtime_db.Value, StreamError] {
  let func = match self.functions.get(fn_name) {
    Some(f) => f
    None => return Err(Aggregate_Function_Not_Found)
  }

  let state = match self.window_states.get(window_id) {
    Some(s) => s
    None => func.create_initial_state()
  }

  let new_state = func.add(state, value)
  self.window_states.set(window_id, new_state)

  Ok(func.get_result(new_state))
}

///|
/// 获取聚合结果
pub fn AggregateProcessor::get_result(
  self : AggregateProcessor,
  fn_name : String,
  window_id : WindowId,
) -> Result[@realtime_db.Value, StreamError] {
  let func = match self.functions.get(fn_name) {
    Some(f) => f
    None => return Err(Aggregate_Function_Not_Found)
  }

  match self.window_states.get(window_id) {
    Some(state) => Ok(func.get_result(state))
    None => Ok(func.create_initial_state())
  }
}

///|
/// 清除窗口状态
pub fn AggregateProcessor::clear_window_state(
  self : AggregateProcessor,
  window_id : WindowId,
) -> Unit {
  self.window_states.remove(window_id)
}

///|
/// 初始化内置聚合函数，返回注册完成的处理器
pub fn init_builtin_aggregates(
  processor : AggregateProcessor,
) -> AggregateProcessor {
  let _ = processor.register_function(
    "count",
    CountAggregate::new() as &AggregateFunction,
  )
  let _ = processor.register_function(
    "sum",
    SumAggregate::new() as &AggregateFunction,
  )
  let _ = processor.register_function(
    "avg",
    AvgAggregate::new() as &AggregateFunction,
  )
  let _ = processor.register_function(
    "max",
    MaxAggregate::new() as &AggregateFunction,
  )
  let _ = processor.register_function(
    "min",
    MinAggregate::new() as &AggregateFunction,
  )
  processor
}
