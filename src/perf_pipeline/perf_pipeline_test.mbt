// 高性能数据管道黑盒测试

///|
test "memory_pool_create_and_acquire" {
  let pool = @perf_pipeline.MemoryPool::new(1000, 10000, 1.5)
  assert_eq(pool.current_size(), 1000)
  assert_eq(pool.free_count(), 1000)
  assert_eq(pool.hit_rate(), 1.0)
}

///|
test "memory_pool_acquire_release" {
  let pool = @perf_pipeline.MemoryPool::new(10, 100, 1.5)
  let buffer = pool.acquire_buffer()
  assert_eq(pool.free_count(), 9)
  assert_eq(pool.hit_count(), 1)

  pool.release_buffer(buffer)
  assert_eq(pool.free_count(), 10)
}

///|
test "memory_pool_hit_rate" {
  let pool = @perf_pipeline.MemoryPool::new(10, 100, 1.5)
  // 获取 5 次
  let mut i = 0
  while i < 5 {
    let buffer = pool.acquire_buffer()
    pool.release_buffer(buffer)
    i = i + 1
  }
  // 命中率应该是 100%（所有获取都从空闲池获取）
  assert_true(pool.hit_rate() >= 0.5)
}

///|
test "memory_pool_grow_on_demand" {
  // 初始 1、上限 2：第二次获取触发扩容，第三次在上限外分配
  let pool = @perf_pipeline.MemoryPool::new(1, 2, 1.5)
  let b1 = pool.acquire_buffer()
  let b2 = pool.acquire_buffer()
  assert_eq(pool.current_size(), 2)
  assert_eq(pool.miss_count(), 1)
  // 池达上限，池外分配，不计入池大小
  let b3 = pool.acquire_buffer()
  assert_eq(pool.current_size(), 2)

  // 归还两个池内缓冲区后，池外缓冲区被拒绝回收，空闲数不得超过池容量
  pool.release_buffer(b1)
  pool.release_buffer(b2)
  assert_eq(pool.free_count(), 2)
  pool.release_buffer(b3)
  assert_eq(pool.free_count(), 2)
  // 重复归还同一缓冲区也被忽略
  pool.release_buffer(b1)
  assert_eq(pool.free_count(), 2)
}

///|
test "backpressure_controller_create" {
  let bp = @perf_pipeline.BackpressureController::new(80)
  assert_eq(bp.is_backpressured(), false)
}

///|
test "backpressure_trigger" {
  let bp = @perf_pipeline.BackpressureController::new(80)
  let triggered = bp.check(85) // 超过阈值
  assert_true(triggered)
  assert_true(bp.is_backpressured())

  // 重置
  bp.reset()
  assert_false(bp.is_backpressured())
}

///|
test "backpressure_reset" {
  let bp = @perf_pipeline.BackpressureController::new(80)
  ignore(bp.check(85))
  assert_true(bp.is_backpressured())

  // 低于阈值时自动重置
  ignore(bp.check(70))
  assert_false(bp.is_backpressured())
}

///|
test "backpressure_edge_fires_once" {
  let bp = @perf_pipeline.BackpressureController::new(80)
  assert_true(bp.check_at(85, 1000))
  // 持续高压不重复触发
  assert_false(bp.check_at(90, 2000))
  assert_true(bp.is_backpressured())
  assert_eq(bp.trigger_time(), 1000)
  // 超时判定（默认 30000ms）
  assert_false(bp.is_timeout(31000))
  assert_true(bp.is_timeout(31001))
  // 解除后触发时间清零
  ignore(bp.check_at(10, 32000))
  assert_eq(bp.trigger_time(), 0)
  assert_false(bp.is_timeout(99999))
}

///|
test "pipeline_config_default" {
  let config = @perf_pipeline.PipelineConfig::default()
  assert_eq(config.batch_size(), 1000)
  assert_eq(config.concurrency(), 4)
  assert_eq(config.backpressure_threshold(), 80)
  assert_eq(config.aggregate_window(), 100)
}

///|
test "pipeline_config_validate" {
  let config = @perf_pipeline.PipelineConfig::default()
  assert_true(config.validate() is Ok(_))

  config.set_batch_size(0)
  assert_true(config.validate() is Err(@perf_pipeline.Invalid_Batch_Size))

  config.set_batch_size(10001)
  assert_true(config.validate() is Err(@perf_pipeline.Invalid_Batch_Size))

  config.set_batch_size(1000)
  config.set_concurrency(0)
  assert_true(config.validate() is Err(@perf_pipeline.Invalid_Concurrency))
}

///|
test "batch_result_create" {
  let result = @perf_pipeline.BatchResult::new()
  assert_eq(result.success_count(), 0)
  assert_eq(result.failed_count(), 0)
  assert_eq(result.failed_records().length(), 0)
}

///|
test "batch_result_add_success" {
  let result = @perf_pipeline.BatchResult::new()
  result.add_success()
  result.add_success()
  assert_eq(result.success_count(), 2)
}

///|
test "batch_result_add_failure" {
  let result = @perf_pipeline.BatchResult::new()
  result.add_failure(1, "test error")
  assert_eq(result.failed_count(), 1)
  assert_eq(result.failed_records().length(), 1)
  assert_eq(result.failed_records()[0].0, 1)
  assert_eq(result.failed_records()[0].1, "test error")
}

///|
test "batch_result_merge" {
  let a = @perf_pipeline.BatchResult::new()
  a.add_success()
  let b = @perf_pipeline.BatchResult::new()
  b.add_success()
  b.add_failure(0, "bad")
  a.merge(b)
  assert_eq(a.success_count(), 2)
  assert_eq(a.failed_count(), 1)
  assert_eq(a.failed_records().length(), 1)
}

///|
test "batch_importer_writes_to_db_and_wal" {
  let db = @realtime_db.DB::new()
  let wal = @persistence.WAL::new("/tmp/perf_importer_test.wal", 100)
  let config = @perf_pipeline.PipelineConfig::default()
  let importer = @perf_pipeline.BatchImporter::new(
    Some(db),
    Some(wal),
    None,
    config,
  )
  let data : Array[(String, @realtime_db.Value)] = [
    ("a", @realtime_db.Int(1)),
    ("b", @realtime_db.Str("x")),
  ]
  let result = importer.import_batch(data, None)
  assert_eq(result.success_count(), 2)
  assert_eq(result.failed_count(), 0)
  assert_eq(db.get("a"), Some(@realtime_db.Int(1)))
  assert_eq(db.get("b"), Some(@realtime_db.Str("x")))
  // 每条写入都追加了 WAL
  assert_eq(wal.buffer_size(), 2)
}

///|
test "batch_importer_rejects_oversized_batch" {
  let db = @realtime_db.DB::new()
  let config = @perf_pipeline.PipelineConfig::default()
  config.set_batch_size(2)
  let importer = @perf_pipeline.BatchImporter::new(Some(db), None, None, config)
  let data : Array[(String, @realtime_db.Value)] = [
    ("a", @realtime_db.Int(1)),
    ("b", @realtime_db.Int(2)),
    ("c", @realtime_db.Int(3)),
  ]
  let result = importer.import_batch(data, None)
  assert_eq(result.success_count(), 0)
  assert_eq(result.failed_count(), 1)
  // 超限批次不得写入任何数据
  assert_eq(db.get("a"), None)
}

///|
test "batch_importer_without_db_fails" {
  let config = @perf_pipeline.PipelineConfig::default()
  let importer = @perf_pipeline.BatchImporter::new(None, None, None, config)
  let data : Array[(String, @realtime_db.Value)] = [("a", @realtime_db.Int(1))]
  let result = importer.import_batch(data, None)
  assert_eq(result.success_count(), 0)
  assert_eq(result.failed_count(), 1)
}

///|
test "stream_result_create" {
  let result = @perf_pipeline.StreamResult::new()
  assert_eq(result.total_records(), 0)
  assert_eq(result.latency_p99(), 0)
  result.set_latency_p99(100)
  assert_eq(result.latency_p99(), 100)
}

///|
test "streaming_processor_processes_records" {
  let config = @perf_pipeline.PipelineConfig::default()
  let sp = @perf_pipeline.StreamingProcessor::new(None, None, None, config)
  let records = [(@realtime_db.Int(1), 0), (@realtime_db.Str("ok"), 10)]
  let result = sp.stream_write(records)
  assert_true(result.completed())
  assert_eq(result.total_records(), 2)
  assert_eq(result.success_count(), 2)
  assert_eq(result.failed_count(), 0)
  // 处理完后缓冲区清空
  assert_eq(sp.in_flight(), 0)
  assert_eq(result.latency_p99(), 100)
}

///|
test "streaming_processor_counts_invalid_ttl_failure" {
  let config = @perf_pipeline.PipelineConfig::default()
  let sp = @perf_pipeline.StreamingProcessor::new(None, None, None, config)
  let records = [(@realtime_db.Int(1), 0), (@realtime_db.Int(2), -1)]
  let result = sp.stream_write(records)
  assert_true(result.completed())
  assert_eq(result.success_count(), 1)
  assert_eq(result.failed_count(), 1)
}

///|
test "pipeline_metrics_create" {
  let metrics = @perf_pipeline.PipelineMetrics::new()
  assert_eq(metrics.throughput(), 0.0)
  assert_eq(metrics.latency_p99(), 0)
  metrics.set_throughput(500000.0)
  metrics.set_buffer_usage(75)
  assert_eq(metrics.throughput(), 500000.0)
  assert_eq(metrics.buffer_usage(), 75)
}

///|
test "pipeline_metrics_backpressure" {
  let metrics = @perf_pipeline.PipelineMetrics::new()
  assert_eq(metrics.backpressure_count(), 0)
  metrics.incr_backpressure()
  assert_eq(metrics.backpressure_count(), 1)
  metrics.incr_backpressure()
  assert_eq(metrics.backpressure_count(), 2)
}

///|
test "pipeline_monitor_alert_and_expose" {
  let config = @perf_pipeline.PipelineConfig::default()
  let monitor = @perf_pipeline.PipelineMonitor::new(None, config)
  monitor.set_buffer_usage(90)
  assert_eq(monitor.alert_count(), 1)
  // 恢复正常不再告警
  monitor.set_buffer_usage(50)
  assert_eq(monitor.alert_count(), 1)
  monitor.incr_backpressure()
  let text = monitor.expose()
  assert_true(text.contains("pipeline_backpressure_count 1"))
  assert_true(text.contains("pipeline_throughput"))
}

///|
test "pipeline_create" {
  let config = @perf_pipeline.PipelineConfig::default()
  let pipeline = @perf_pipeline.Pipeline::new(config)
  assert_eq(pipeline.status(), @perf_pipeline.Created)
  assert_false(pipeline.is_running())
}

///|
test "pipeline_start_stop" {
  let config = @perf_pipeline.PipelineConfig::default()
  let pipeline = @perf_pipeline.Pipeline::new(config)
  assert_true(pipeline.start() is Ok(_))
  assert_true(pipeline.is_running())
  // 启动后所有组件就绪
  assert_true(pipeline.importer() is Some(_))
  assert_true(pipeline.streamer() is Some(_))
  assert_true(pipeline.aggregator() is Some(_))
  assert_true(pipeline.monitor() is Some(_))
  assert_true(pipeline.mempool() is Some(_))

  pipeline.stop()
  assert_eq(pipeline.status(), @perf_pipeline.Stopped)
  // 停止后组件释放
  assert_true(pipeline.importer() is None)
  assert_true(pipeline.mempool() is None)
}

///|
test "pipeline_start_twice_fails" {
  let config = @perf_pipeline.PipelineConfig::default()
  let pipeline = @perf_pipeline.Pipeline::new(config)
  assert_true(pipeline.start() is Ok(_))
  assert_true(pipeline.start() is Err(_))
}

///|
test "pipeline_pause_resume" {
  let config = @perf_pipeline.PipelineConfig::default()
  let pipeline = @perf_pipeline.Pipeline::new(config)
  assert_true(pipeline.start() is Ok(_))

  pipeline.pause()
  assert_eq(pipeline.status(), @perf_pipeline.Paused)

  pipeline.unpause()
  assert_eq(pipeline.status(), @perf_pipeline.Running)

  pipeline.stop()
}

///|
test "batch_notification_create" {
  let events : Array[@realtime_db.Event] = []
  let notification = @perf_pipeline.BatchNotification::new(events, 12345, 1)
  assert_eq(notification.timestamp(), 12345)
  assert_eq(notification.batch_id(), 1)
}

///|
test "batch_aggregator_dedup_keeps_last_state" {
  // 原 bug：同键事件被判重后直接丢弃，缓冲里留下的是最早的旧值。
  let config = @perf_pipeline.PipelineConfig::default()
  let aggregator = @perf_pipeline.BatchAggregator::new(config)
  let received : Array[@perf_pipeline.BatchNotification] = []
  let id = aggregator.subscribe_batch(
    fn(notification) { received.push(notification) },
    None,
  )
  aggregator.notify(@realtime_db.Set("k", @realtime_db.Int(1), None))
  aggregator.notify(@realtime_db.Set("k", @realtime_db.Int(2), None))
  aggregator.notify(@realtime_db.Delete("k", @realtime_db.Null))
  aggregator.flush(id)

  assert_eq(received.length(), 1)
  let events = received[0].events()
  assert_eq(events.length(), 1)
  // 最后状态应为 Delete，而不是最早的 Set(1)
  assert_true(events[0] is @realtime_db.Delete("k", @realtime_db.Null))
}

///|
test "batch_aggregator_without_dedup_keeps_all" {
  let config = @perf_pipeline.PipelineConfig::default()
  let aggregator = @perf_pipeline.BatchAggregator::new(config)
  let received : Array[@perf_pipeline.BatchNotification] = []
  // window_ms 给 None，去重通过专用订阅暂不可关——默认配置去重开启
  let id = aggregator.subscribe_batch(
    fn(notification) { received.push(notification) },
    None,
  )
  // 不同键的事件全部保留
  aggregator.notify(@realtime_db.Set("a", @realtime_db.Int(1), None))
  aggregator.notify(@realtime_db.Set("b", @realtime_db.Int(2), None))
  aggregator.flush(id)
  assert_eq(received[0].events().length(), 2)
}

///|
test "batch_aggregator_expire_is_immediate" {
  let config = @perf_pipeline.PipelineConfig::default()
  let aggregator = @perf_pipeline.BatchAggregator::new(config)
  let received : Array[@perf_pipeline.BatchNotification] = []
  let id = aggregator.subscribe_batch(
    fn(notification) { received.push(notification) },
    None,
  )
  aggregator.notify(@realtime_db.Expire("k", @realtime_db.Int(1)))
  // Expire 不走缓冲，立即送达
  assert_eq(received.length(), 1)
  aggregator.flush(id)
  assert_eq(received.length(), 1)
}

///|
test "batch_aggregator_flush_keeps_remainder" {
  // 原 bug：缓冲超过 max_batch_size 时只发首批，其余被清空丢弃。
  let config = @perf_pipeline.PipelineConfig::default()
  config.set_max_batch_size(2)
  let aggregator = @perf_pipeline.BatchAggregator::new(config)
  let received : Array[@perf_pipeline.BatchNotification] = []
  let id = aggregator.subscribe_batch(
    fn(notification) { received.push(notification) },
    None,
  )
  aggregator.notify(@realtime_db.Set("a", @realtime_db.Int(1), None))
  aggregator.notify(@realtime_db.Set("b", @realtime_db.Int(2), None))
  aggregator.notify(@realtime_db.Set("c", @realtime_db.Int(3), None))

  aggregator.flush(id)
  assert_eq(received.length(), 1)
  assert_eq(received[0].events().length(), 2)
  // 剩余事件仍在缓冲，再次 flush 才能发出
  aggregator.flush(id)
  assert_eq(received.length(), 2)
  assert_eq(received[1].events().length(), 1)
}

///|
test "batch_aggregator_flush_due_by_window" {
  let config = @perf_pipeline.PipelineConfig::default()
  config.set_aggregate_window(100)
  let aggregator = @perf_pipeline.BatchAggregator::new(config)
  let received : Array[@perf_pipeline.BatchNotification] = []
  let _id = aggregator.subscribe_batch(
    fn(notification) { received.push(notification) },
    None,
  )
  aggregator.notify_at(@realtime_db.Set("a", @realtime_db.Int(1), None), 1)
  // 窗口未满
  aggregator.flush_due(100)
  assert_eq(received.length(), 0)
  // 窗口到期（1 + 100 = 101）
  aggregator.flush_due(101)
  assert_eq(received.length(), 1)
  assert_eq(received[0].timestamp(), 101)
}

///|
test "batch_aggregator_unsubscribe" {
  let config = @perf_pipeline.PipelineConfig::default()
  let aggregator = @perf_pipeline.BatchAggregator::new(config)
  let received : Array[@perf_pipeline.BatchNotification] = []
  let id = aggregator.subscribe_batch(
    fn(notification) { received.push(notification) },
    None,
  )
  aggregator.unsubscribe_batch(id)
  aggregator.notify(@realtime_db.Set("a", @realtime_db.Int(1), None))
  aggregator.flush(id)
  assert_eq(received.length(), 0)
}

///|
/// 高冗余数据：压缩后体积缩减，解压无损还原，魔数可被识别
test "compression_roundtrip_high_redundancy" {
  let processor = @perf_pipeline.CompressionProcessor::new(
    @perf_pipeline.CompressionConfig::default(),
    None,
  )
  let data : Array[Byte] = []
  let mut i = 0
  while i < 1024 {
    data.push(0x41)
    i = i + 1
  }
  let compressed = processor.compress(data, @perf_pipeline.Gzip, None).unwrap()
  assert_true(compressed.length() < data.length())
  assert_true(@perf_pipeline.CompressionProcessor::detect_format(compressed) is @perf_pipeline.Gzip)
  let restored = processor.decompress(compressed, @perf_pipeline.Gzip).unwrap()
  assert_eq(restored.length(), data.length())
  let mut same = true
  let mut k = 0
  while k < data.length() {
    if restored[k] != data[k] {
      same = false
    }
    k = k + 1
  }
  assert_true(same)
}

///|
/// 低冗余数据：退化为原样存储模式，同样无损往返
test "compression_roundtrip_low_redundancy" {
  let processor = @perf_pipeline.CompressionProcessor::new(
    @perf_pipeline.CompressionConfig::default(),
    None,
  )
  let data : Array[Byte] = []
  let mut i = 0
  while i < 256 {
    data.push(((i * 31 + 7) % 256).to_byte())
    i = i + 1
  }
  let compressed = processor.compress(data, @perf_pipeline.Zstd, None).unwrap()
  // 原样存储：载荷 + 10 字节帧头
  assert_eq(compressed.length(), data.length() + 10)
  let restored = processor.decompress(compressed, @perf_pipeline.Zstd).unwrap()
  let mut same = true
  let mut k = 0
  while k < data.length() {
    if restored[k] != data[k] {
      same = false
    }
    k = k + 1
  }
  assert_true(same)
}

///|
/// 三种格式均可压缩并还原
test "compression_roundtrip_all_formats" {
  let formats : Array[@perf_pipeline.CompressionFormat] = [
    @perf_pipeline.Gzip,
    @perf_pipeline.Zstd,
    @perf_pipeline.Lz4,
  ]
  for format in formats {
    let processor = @perf_pipeline.CompressionProcessor::new(
      @perf_pipeline.CompressionConfig::default(),
      None,
    )
    let data : Array[Byte] = []
    let mut i = 0
    while i < 64 {
      if i % 3 == 0 {
        data.push(0.to_byte())
      } else {
        data.push((i % 256).to_byte())
      }
      i = i + 1
    }
    let compressed = processor.compress(data, format, None).unwrap()
    let restored = processor.decompress(compressed, format).unwrap()
    assert_eq(restored.length(), data.length())
    let mut same = true
    let mut k = 0
    while k < data.length() {
      if restored[k] != data[k] {
        same = false
      }
      k = k + 1
    }
    assert_true(same)
  }
}

///|
/// 空数据也能完整往返
test "compression_roundtrip_empty" {
  let processor = @perf_pipeline.CompressionProcessor::new(
    @perf_pipeline.CompressionConfig::default(),
    None,
  )
  let data : Array[Byte] = []
  let compressed = processor.compress(data, @perf_pipeline.Lz4, None).unwrap()
  let restored = processor.decompress(compressed, @perf_pipeline.Lz4).unwrap()
  assert_eq(restored.length(), 0)
}

///|
/// 损坏与格式不匹配的输入被明确拒绝，而非静默返回空数据
test "compression_rejects_corrupted_input" {
  let processor = @perf_pipeline.CompressionProcessor::new(
    @perf_pipeline.CompressionConfig::default(),
    None,
  )
  // 截断数据（不足帧头长度）
  let short : Array[Byte] = [0x1f.to_byte(), 0x8b.to_byte()]
  assert_true(
    processor.decompress(short, @perf_pipeline.Gzip) is Err(_),
  )
  // 格式不匹配：Gzip 产物用 Zstd 解压
  let data : Array[Byte] = [1.to_byte(), 2.to_byte(), 2.to_byte()]
  let gzip_data = processor.compress(data, @perf_pipeline.Gzip, None).unwrap()
  assert_true(processor.decompress(gzip_data, @perf_pipeline.Zstd) is Err(@perf_pipeline.Unsupported_Format))
  // 篡改声明的原始长度（stored 模式长度校验失败）
  let tampered = gzip_data.copy()
  tampered[6] = (tampered[6].to_int() + 1).to_byte()
  assert_true(processor.decompress(tampered, @perf_pipeline.Gzip) is Err(_))
}

///|
/// 声明超大展开尺寸的帧被解压炸弹防护拒绝
test "compression_rejects_decompression_bomb" {
  let processor = @perf_pipeline.CompressionProcessor::new(
    @perf_pipeline.CompressionConfig::default(),
    None,
  )
  // 手工构造帧：gzip 魔数 + 版本 1 + RLE 模式 + 声明 300MB 展开长度
  let bomb : Array[Byte] = [
    0x1f.to_byte(),
    0x8b.to_byte(),
    0x4d.to_byte(),
    0x42.to_byte(),
    1.to_byte(),
    0.to_byte(),
    0.to_byte(),
    0.to_byte(),
    0x12.to_byte(),
    0.to_byte(),
  ]
  assert_true(processor.decompress(bomb, @perf_pipeline.Gzip) is Err(@perf_pipeline.Compression_Bomb))
}
