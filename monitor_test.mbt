// 监控指标模块黑盒测试。

///|
test "metric_accessors_and_prometheus" {
  let m = @realtime_db.Metric::new(
    "qps",
    @realtime_db.Counter,
    Map([("method", "GET")]),
    3.0,
  )
  assert_eq(m.name(), "qps")
  assert_true(m.metric_type() is @realtime_db.Counter)
  assert_eq(m.value(), 3.0)
  let s = m.to_prometheus()
  assert_true(s.contains("qps"))
  assert_true(s.contains("method=\"GET\""))

  // 无标签指标不带花括号
  let g = @realtime_db.Metric::new("mem", @realtime_db.Gauge, Map([]), 0.5)
  assert_eq(g.to_prometheus(), "mem 0.5")
}

///|
test "monitor_register_duplicate_and_count" {
  let mon = @realtime_db.Monitor::new(15)
  assert_eq(mon.interval(), 15)
  assert_eq(mon.metric_count(), 0)

  let c = @realtime_db.Metric::new("qps", @realtime_db.Counter, Map([]), 0.0)
  assert_true(mon.register(c) is Ok(_))
  assert_eq(mon.metric_count(), 1)
  // 重复注册被拒绝（原 bug：register 根本没写入，这里会失败）
  let c2 = @realtime_db.Metric::new("qps", @realtime_db.Counter, Map([]), 0.0)
  assert_true(mon.register(c2) is Err(@realtime_db.Metric_Duplicate))
  assert_eq(mon.metric_count(), 1)
}

///|
test "monitor_counter_incr" {
  let mon = @realtime_db.Monitor::new(1)
  let _ = mon.register(
    @realtime_db.Metric::new("hits", @realtime_db.Counter, Map([]), 0.0),
  )
  assert_true(mon.incr("hits") is Ok(_))
  assert_true(mon.incr("hits", delta=4.0) is Ok(_))
  // 通过暴露的文本验证值为 5
  assert_true(mon.expose().contains("hits 5"))
  // 不存在的指标
  assert_true(mon.incr("nope") is Err(@realtime_db.Metric_Not_Found))
  // 类型不符：Counter 不能 set_gauge
  assert_true(
    mon.set_gauge("hits", 1.0) is Err(@realtime_db.Metric_Type_Mismatch),
  )
}

///|
test "monitor_gauge_and_histogram" {
  let mon = @realtime_db.Monitor::new(1)
  let _ = mon.register(
    @realtime_db.Metric::new("cpu", @realtime_db.Gauge, Map([]), 0.0),
  )
  let _ = mon.register(
    @realtime_db.Metric::new("latency", @realtime_db.Histogram, Map([]), 0.0),
  )
  assert_true(mon.set_gauge("cpu", 0.75) is Ok(_))
  assert_true(mon.observe("latency", 12.5) is Ok(_))
  // Gauge 不能 incr
  assert_true(mon.incr("cpu") is Err(@realtime_db.Metric_Type_Mismatch))
  // Histogram 不能 set_gauge
  assert_true(
    mon.set_gauge("latency", 1.0) is Err(@realtime_db.Metric_Type_Mismatch),
  )
  let out = mon.expose()
  assert_true(out.contains("cpu 0.75"))
  assert_true(out.contains("latency 12.5"))
}

///|
test "monitor_unregister" {
  let mon = @realtime_db.Monitor::new(1)
  let _ = mon.register(
    @realtime_db.Metric::new("x", @realtime_db.Counter, Map([]), 0.0),
  )
  assert_true(mon.unregister("x") is Ok(_))
  assert_eq(mon.metric_count(), 0)
  assert_true(mon.unregister("x") is Err(@realtime_db.Metric_Not_Found))
}
