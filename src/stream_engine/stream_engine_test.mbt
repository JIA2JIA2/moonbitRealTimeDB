// 流引擎集成测试
//
// 测试窗口引擎、聚合处理器、过滤订阅器、管道管理器

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
test "test_window_assigner" {
  // 测试滚动窗口分配器
  let assigner = @stream_engine.TumblingWindowAssigner::new(1000)
  let config = @stream_engine.WindowConfig::{
    name: "test",
    window_type: @stream_engine.Tumbling,
    size_ms: 1000,
    slide_ms: 0,
    timeout_ms: 0,
    late_data_policy: @stream_engine.Drop,
  }

  let windows = assigner.assign_windows(1500, config)
  assert_eq(windows.length(), 1)
  assert_eq(windows[0].start_time, 1000)

  // 测试滑动窗口分配器
  let sliding_assigner = @stream_engine.SlidingWindowAssigner::new(5000, 1000)
  let sliding_config = @stream_engine.WindowConfig::{
    name: "sliding_test",
    window_type: @stream_engine.Sliding,
    size_ms: 5000,
    slide_ms: 1000,
    timeout_ms: 0,
    late_data_policy: @stream_engine.Drop,
  }

  let sliding_windows = sliding_assigner.assign_windows(3000, sliding_config)
  assert_true(sliding_windows.length() > 0)
}

///|
test "test_count_aggregate" {
  let agg = @stream_engine.CountAggregate::new()
  let state = agg.create_initial_state()

  // 测试添加元素
  let state1 = agg.add(state, @realtime_db.Int(1))
  let state2 = agg.add(state1, @realtime_db.Int(2))
  let state3 = agg.add(state2, @realtime_db.Int(3))

  // 测试结果
  let result = agg.get_result(state3)
  match result {
    @realtime_db.Int(count) => assert_eq(count, 3)
    _ => assert_true(false)
  }

  // 测试移除元素
  let state4 = agg.remove(state3, @realtime_db.Int(1))
  let result2 = agg.get_result(state4)
  match result2 {
    @realtime_db.Int(count) => assert_eq(count, 2)
    _ => assert_true(false)
  }
}

///|
test "test_sum_aggregate" {
  let agg = @stream_engine.SumAggregate::new()
  let state = agg.create_initial_state()

  // 测试添加元素
  let state1 = agg.add(state, @realtime_db.Int(10))
  let state2 = agg.add(state1, @realtime_db.Int(20))
  let state3 = agg.add(state2, @realtime_db.Int(30))

  // 测试结果
  let result = agg.get_result(state3)
  match result {
    @realtime_db.Int(sum) => assert_eq(sum, 60)
    _ => assert_true(false)
  }
}

///|
test "test_avg_aggregate" {
  let agg = @stream_engine.AvgAggregate::new()
  let state = agg.create_initial_state()

  // 测试添加元素
  let state1 = agg.add(state, @realtime_db.Int(10))
  let state2 = agg.add(state1, @realtime_db.Int(20))
  let state3 = agg.add(state2, @realtime_db.Int(30))

  // 测试结果
  let result = agg.get_result(state3)
  match result {
    @realtime_db.Float(avg) => assert_true(avg > 19.9 && avg < 20.1)
    _ => assert_true(false)
  }
}

///|
test "test_max_aggregate" {
  let agg = @stream_engine.MaxAggregate::new()
  let state = agg.create_initial_state()

  // 测试添加元素
  let state1 = agg.add(state, @realtime_db.Int(10))
  let state2 = agg.add(state1, @realtime_db.Int(30))
  let state3 = agg.add(state2, @realtime_db.Int(20))

  // 测试结果
  let result = agg.get_result(state3)
  match result {
    @realtime_db.Int(max) => assert_eq(max, 30)
    _ => assert_true(false)
  }
}

///|
test "test_min_aggregate" {
  let agg = @stream_engine.MinAggregate::new()
  let state = agg.create_initial_state()

  // 测试添加元素
  let state1 = agg.add(state, @realtime_db.Int(30))
  let state2 = agg.add(state1, @realtime_db.Int(10))
  let state3 = agg.add(state2, @realtime_db.Int(20))

  // 测试结果
  let result = agg.get_result(state3)
  match result {
    @realtime_db.Int(min) => assert_eq(min, 10)
    _ => assert_true(false)
  }

  // 测试负数场景（回归：初始值不能当作最小值）
  let neg_state = agg.create_initial_state()
  let neg_state = agg.add(neg_state, @realtime_db.Int(-5))
  let neg_state = agg.add(neg_state, @realtime_db.Int(-10))
  let neg_state = agg.add(neg_state, @realtime_db.Int(-3))
  match agg.get_result(neg_state) {
    @realtime_db.Int(min) => assert_eq(min, -10)
    _ => assert_true(false)
  }
}

///|
test "test_filter_parser" {
  let parser = @stream_engine.FilterParser::new()

  // 测试等值条件
  let cond1 = parser.parse_condition("age", "=", @realtime_db.Int(25))
  assert_true(cond1 is Ok(_))
  match cond1 {
    Ok(c) => assert_eq(c.op, @stream_engine.Equal)
    _ => ()
  }

  // 测试范围条件
  let cond2 = parser.parse_condition("age", ">", @realtime_db.Int(18))
  assert_true(cond2 is Ok(_))
  match cond2 {
    Ok(c) => assert_eq(c.op, @stream_engine.GreaterThan)
    _ => ()
  }

  // 测试前缀条件
  let cond3 = parser.parse_condition("name", "like", @realtime_db.Str("张"))
  assert_true(cond3 is Ok(_))
  match cond3 {
    Ok(c) => assert_eq(c.op, @stream_engine.Prefix)
    _ => ()
  }
}

///|
test "test_condition_evaluator" {
  let evaluator = @stream_engine.ConditionEvaluator::new()
  let parser = @stream_engine.FilterParser::new()

  // 创建测试事件
  let event = @stream_engine.StreamEvent::{
    key: "user1",
    value: vmap([
      ("name", @realtime_db.Str("张三")),
      ("age", @realtime_db.Int(25)),
    ]),
    event_type: @stream_engine.Set,
    timestamp: 1000,
  }

  // 测试等值条件
  let cond = parser.parse_condition("age", "=", @realtime_db.Int(25))
  match cond {
    Ok(c) => assert_true(evaluator.evaluate_condition(c, { ..event, }))
    _ => assert_true(false)
  }

  // 测试范围条件
  let cond2 = parser.parse_condition("age", ">", @realtime_db.Int(18))
  match cond2 {
    Ok(c) => assert_true(evaluator.evaluate_condition(c, { ..event, }))
    _ => assert_true(false)
  }

  // 测试不匹配条件
  let cond3 = parser.parse_condition("age", "=", @realtime_db.Int(30))
  match cond3 {
    Ok(c) => assert_true(!evaluator.evaluate_condition(c, { ..event, }))
    _ => assert_true(false)
  }
}

///|
test "test_subscription_manager" {
  let config = @stream_engine.SubscriptionConfig::default()
  let manager = @stream_engine.SubscriptionManager::new(config)

  // 创建过滤表达式
  let parser = @stream_engine.FilterParser::new()
  let conditions = [("age", ">", @realtime_db.Int(18))]
  let filter = parser.parse_filter_expr(conditions, @stream_engine.And)
  assert_true(filter is Ok(_))

  // 创建订阅
  let callback = fn(event) { let _ = event }

  match filter {
    Ok(f) => {
      let sub_id = manager.subscribe(f, callback)
      assert_true(sub_id is Ok(_))

      match sub_id {
        Ok(id) => {
          // 测试获取订阅状态
          let state = manager.get_subscription_state(id.to_string())
          assert_true(state is Some(_))

          // 测试取消订阅
          let _ = manager.unsubscribe(id)
          let state2 = manager.get_subscription_state("sub_0")
          assert_true(state2 is None)
        }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_state_store" {
  let store = @stream_engine.MemoryStateStore::new()

  // 测试存储
  let _ = store.put("key1", @realtime_db.Int(100))
  let _ = store.put("key2", @realtime_db.Str("value2"))

  // 测试获取
  let value1 = store.get("key1")
  assert_true(value1 is Ok(_))
  match value1 {
    Ok(v) =>
      match v {
        @realtime_db.Int(i) => assert_eq(i, 100)
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }

  // 测试查询
  let result = store.query("key")
  assert_true(result is Ok(_))
  match result {
    Ok(r) => assert_eq(r.length(), 2)
    _ => ()
  }

  // 测试删除
  let _ = store.delete("key1")
  let value2 = store.get("key1")
  assert_true(value2 is Err(_))
}

///|
test "test_watermark_service" {
  let service = @stream_engine.WatermarkService::new(1000)

  // 测试推进水位线
  let wm1 = service.advance_watermark(5000, 1000)
  assert_eq(wm1.timestamp, 4000)

  // 测试乱序数据
  let wm2 = service.advance_watermark(4500, 2000)
  assert_eq(wm2.timestamp, 4000)

  // 测试新数据
  let wm3 = service.advance_watermark(6000, 3000)
  assert_eq(wm3.timestamp, 5000)
}

///|
test "test_pipeline_manager" {
  let manager = @stream_engine.PipelineManager::new()

  // 创建配置
  let pipeline_config = @stream_engine.PipelineConfig::default()
  let window_config = @stream_engine.WindowConfig::{
    name: "test_window",
    window_type: @stream_engine.Tumbling,
    size_ms: 1000,
    slide_ms: 0,
    timeout_ms: 0,
    late_data_policy: @stream_engine.Drop,
  }
  let checkpoint_config = @stream_engine.CheckpointConfig::default()
  let subscription_config = @stream_engine.SubscriptionConfig::default()

  let stream_config = @stream_engine.StreamConfig::{
    name: "test_pipeline",
    pipeline_config,
    window_configs: [window_config],
    checkpoint_config,
    subscription_config,
  }

  // 测试创建管道
  let result = manager.create_pipeline("test", stream_config)
  assert_true(result is Ok(_))

  // 测试获取管道
  let pipeline = manager.get_pipeline("test")
  assert_true(pipeline is Some(_))

  // 测试管道初始状态
  match pipeline {
    Some(p) => assert_eq(p.status, @stream_engine.Created)
    None => assert_true(false)
  }

  // 测试获取所有管道
  let pipelines = manager.get_all_pipelines()
  assert_eq(pipelines.length(), 1)
}

///|
test "test_aggregate_processor" {
  let processor = @stream_engine.AggregateProcessor::new()

  // 注册聚合函数
  let _ = processor.register_function(
    "test_count",
    @stream_engine.CountAggregate::new() as &@stream_engine.AggregateFunction,
  )

  // 获取聚合函数
  let func = processor.get_function("test_count")
  assert_true(func is Some(_))

  // 创建窗口 ID
  let window_id = @stream_engine.WindowId::{
    pipeline_name: "test",
    window_name: "window1",
    start_time: 0,
  }

  // 执行聚合计算
  let result = processor.compute_aggregate(
    "test_count",
    window_id,
    @realtime_db.Int(1),
  )
  assert_true(result is Ok(_))

  // 获取聚合结果
  let result2 = processor.get_result("test_count", { ..window_id, })
  assert_true(result2 is Ok(_))
  match result2 {
    Ok(v) =>
      match v {
        @realtime_db.Int(count) => assert_eq(count, 1)
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}
