// 时间序列引擎测试
//
// 测试度量管理、数据点写入、查询、降采样、连续查询

///|
test "test_timeseries_types" {
  // 测试聚合类型
  assert_eq(@timeseries.Avg, @timeseries.Avg)
  assert_true(@timeseries.Sum != @timeseries.Avg)

  // 测试保留策略类型
  assert_eq(@timeseries.TimeExpired, @timeseries.TimeExpired)
  assert_true(@timeseries.CountLimited != @timeseries.TimeExpired)

  // 测试降采样精度
  assert_eq(@timeseries.Minute, @timeseries.Minute)
  assert_true(@timeseries.Hour != @timeseries.Minute)
}

///|
test "test_timeseries_error" {
  let err = @timeseries.Metric_Already_Exists
  assert_eq(err.code(), 9001)
  assert_true(err.message().length() > 0)

  let err2 = @timeseries.Metric_Not_Found
  assert_eq(err2.code(), 9002)

  let err3 = @timeseries.Internal_Error("test error")
  assert_eq(err3.code(), 9099)
  assert_true(err3.message().contains("test error"))
}

///|
test "test_create_metric" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建度量
  let labels = Map([("region", "beijing"), ("service", "api")])
  let metric_id = engine.create_metric("cpu_usage", labels)

  assert_true(metric_id is Ok(_))

  match metric_id {
    Ok(id) => {
      assert_true(id.length() > 0)

      // 验证度量存在
      let metric = engine.get_metric("cpu_usage")
      assert_true(metric is Some(_))

      match metric {
        Some(m) => {
          assert_eq(m.metric_name, "cpu_usage")
          match m.labels.get("region") {
            Some(v) => assert_eq(v, "beijing")
            None => assert_true(false)
          }
        }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_duplicate_metric_name" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建第一个度量
  let result1 = engine.create_metric("duplicate", Map([]))
  assert_true(result1 is Ok(_))

  // 创建重复度量
  let result2 = engine.create_metric("duplicate", Map([]))
  assert_true(result2 is Err(_))

  match result2 {
    Err(@timeseries.Metric_Already_Exists) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "test_list_metrics" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建多个度量
  let _ = engine.create_metric("metric1", Map([]))
  let _ = engine.create_metric("metric2", Map([]))

  // 列出度量
  let metrics = engine.list_metrics()
  assert_eq(metrics.length(), 2)
}

///|
test "test_delete_metric" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建度量
  let result = engine.create_metric("delete_test", Map([]))
  assert_true(result is Ok(_))

  // 删除度量
  let delete_result = engine.delete_metric("delete_test")
  assert_true(delete_result is Ok(_))

  // 验证度量已删除
  let metric = engine.get_metric("delete_test")
  assert_true(metric is None)
}

///|
test "test_write_data_point" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建度量
  let _ = engine.create_metric("test_metric", Map([]))

  // 写入数据点
  let result = engine.write_data_point("test_metric", 1000, 42.0)
  assert_true(result is Ok(_))

  // 验证数据点
  let metric = engine.get_metric("test_metric")
  assert_true(metric is Some(_))

  match metric {
    Some(m) => assert_eq(m.data_points.length(), 1)
    None => assert_true(false)
  }
}

///|
test "test_batch_write_data_points" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建度量
  let _ = engine.create_metric("batch_test", Map([]))

  // 批量写入数据点
  let data_points = [
    @timeseries.DataPoint::{ timestamp: 1000, value: 10.0, is_valid: true, },
    @timeseries.DataPoint::{ timestamp: 2000, value: 20.0, is_valid: true, },
    @timeseries.DataPoint::{ timestamp: 3000, value: 30.0, is_valid: true, },
  ]

  let result = engine.batch_write_data_points("batch_test", data_points)
  assert_true(result is Ok(_))

  // 验证数据点
  let metric = engine.get_metric("batch_test")
  assert_true(metric is Some(_))

  match metric {
    Some(m) => assert_eq(m.data_points.length(), 3)
    None => assert_true(false)
  }
}

///|
test "test_query" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建度量
  let _ = engine.create_metric("query_test", Map([]))

  // 写入数据点
  let _ = engine.write_data_point("query_test", 1000, 10.0)
  let _ = engine.write_data_point("query_test", 2000, 20.0)
  let _ = engine.write_data_point("query_test", 3000, 30.0)

  // 查询数据
  let request = @timeseries.QueryRequest::{
    metric_name: "query_test",
    label_filters: Map([]),
    start_time: 0,
    end_time: 5000,
    aggregation: @timeseries.Avg,
    window_seconds: None,
    precision: None,
    max_data_points: None,
  }

  let result = engine.query(request)
  assert_true(result is Ok(_))

  match result {
    Ok(r) => assert_eq(r.data_points.length(), 1)
    Err(_) => assert_true(false)
  }
}

///|
test "test_query_aggregation" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建度量
  let _ = engine.create_metric("agg_test", Map([]))

  // 写入数据点
  let _ = engine.write_data_point("agg_test", 1000, 10.0)
  let _ = engine.write_data_point("agg_test", 2000, 20.0)
  let _ = engine.write_data_point("agg_test", 3000, 30.0)

  // 测试求和聚合
  let request = @timeseries.QueryRequest::{
    metric_name: "agg_test",
    label_filters: Map([]),
    start_time: 0,
    end_time: 5000,
    aggregation: @timeseries.Sum,
    window_seconds: None,
    precision: None,
    max_data_points: None,
  }

  let result = engine.query(request)
  assert_true(result is Ok(_))

  match result {
    Ok(r) => {
      let v = r.data_points[0].value
      assert_true(v > 59.9 && v < 60.1)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_create_downsample_policy" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建降采样策略
  let policy_id = engine.create_downsample_policy(
    "test_policy",
    @timeseries.Minute,
    @timeseries.Avg,
    3600,
  )

  assert_true(policy_id is Ok(_))
}

///|
test "test_create_continuous_query" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建源度量
  let _ = engine.create_metric("source_metric", Map([]))

  // 创建连续查询
  let query_id = engine.create_continuous_query(
    "test_cq",
    "source_metric",
    "target_metric",
    60,
    @timeseries.Avg,
    300,
  )

  assert_true(query_id is Ok(_))
}

///|
test "test_create_retention_policy" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建保留策略
  let policy_id = engine.create_retention_policy(
    "test_rp",
    @timeseries.TimeExpired,
    86400,
    1000000,
    1073741824,
  )

  assert_true(policy_id is Ok(_))
}

///|
test "test_timeseries_config" {
  let config = @timeseries.TimeSeriesConfig::default()

  assert_eq(config.default_retention_seconds, 2592000)
  assert_eq(config.max_data_points, 1000000000)
  assert_true(config.auto_downsample)
  assert_eq(config.default_precision, @timeseries.Minute)
  assert_true(config.enable_continuous_query)
  assert_eq(config.flush_interval_ms, 1000)
}

///|
test "test_cleanup_expired_data" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 清理过期数据
  let cleaned = engine.cleanup_expired_data()
  assert_true(cleaned >= 0)
}

///|
test "test_get_stats" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 获取统计
  let stats = engine.get_stats()
  assert_eq(stats.metric_count, 0)
  assert_eq(stats.total_data_points, 0)
}

///|
test "test_query_with_label_filter" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建带标签的度量
  let labels = Map([("region", "beijing")])
  let _ = engine.create_metric("filtered_metric", labels)

  // 写入数据点
  let _ = engine.write_data_point("filtered_metric", 1000, 42.0)

  // 查询数据（带标签过滤）
  let filters = Map([("region", "beijing")])
  let request = @timeseries.QueryRequest::{
    metric_name: "filtered_metric",
    label_filters: filters,
    start_time: 0,
    end_time: 5000,
    aggregation: @timeseries.Avg,
    window_seconds: None,
    precision: None,
    max_data_points: None,
  }

  let result = engine.query(request)
  assert_true(result is Ok(_))
}

///|
test "test_query_with_window" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 创建度量
  let _ = engine.create_metric("window_test", Map([]))

  // 写入数据点
  let _ = engine.write_data_point("window_test", 1000, 10.0)
  let _ = engine.write_data_point("window_test", 2000, 20.0)
  let _ = engine.write_data_point("window_test", 3000, 30.0)

  // 查询数据（带窗口）
  let request = @timeseries.QueryRequest::{
    metric_name: "window_test",
    label_filters: Map([]),
    start_time: 0,
    end_time: 5000,
    aggregation: @timeseries.Avg,
    window_seconds: Some(1000),
    precision: None,
    max_data_points: None,
  }

  let result = engine.query(request)
  assert_true(result is Ok(_))
}

///|
test "test_metric_count" {
  let config = @timeseries.TimeSeriesConfig::default()
  let engine = @timeseries.TimeSeriesEngine::new(config)

  // 初始度量数应该是 0
  let stats = engine.get_stats()
  assert_eq(stats.metric_count, 0)

  // 创建度量
  let _ = engine.create_metric("count_test", Map([]))

  // 度量数应该是 1
  let stats2 = engine.get_stats()
  assert_eq(stats2.metric_count, 1)
}
