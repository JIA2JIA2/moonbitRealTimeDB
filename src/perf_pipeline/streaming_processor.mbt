// 流式处理器模块
//
// 实现流式数据处理，支持背压控制和并发处理。
// 目标：P99 延迟 <= 100μs，并发度 1~16

///|
/// 流式处理器结构
///
/// 管理流式写入、背压和并发处理。
pub struct StreamingProcessor {
  /// 数据库引用
  mut db : @realtime_db.DB?
  /// WAL 引用
  wal : @persistence.WAL?
  /// 内存池引用
  mempool : MemoryPool?
  /// 缓冲区
  buffer : Array[(@realtime_db.Value, Int)]
  /// 背压控制器
  backpressure : BackpressureController?
  /// 配置
  config : PipelineConfig
}

///|
/// 创建流式处理器
pub fn StreamingProcessor::new(
  db : @realtime_db.DB?,
  wal : @persistence.WAL?,
  mempool : MemoryPool?,
  config : PipelineConfig,
) -> StreamingProcessor {
  let bp = BackpressureController::new(config.backpressure_threshold)
  { db, wal, mempool, buffer: [], backpressure: Some(bp), config, }
}

///|
/// 同步流式写入
///
/// 检查缓冲区使用率，超过阈值触发背压并拒绝整批；
/// 缓冲区有硬容量上限（buffer_size），超出同样拒绝整批。
/// 被接纳的批次按并发度上限从队首消费。
pub fn StreamingProcessor::stream_write(
  self : StreamingProcessor,
  records : Array[(@realtime_db.Value, Int)],
) -> StreamResult {
  let result = StreamResult::new()
  result.set_total_records(records.length())

  // 检查背压：按电平判定（is_backpressured）。
  // 修复前使用 bp.check() 的边沿返回值：持续高压下仅第一次拒绝，
  // 之后每轮都放行并把全部记录压入缓冲区，内存无限增长。
  let buffer_usage = self.buffer_usage()
  let mut rejected = false
  match self.backpressure {
    Some(bp) => {
      let _ = bp.check(buffer_usage) // 维持状态机与超时计时
      if bp.is_backpressured() {
        rejected = true
      }
    }
    None => ()
  }

  // 缓冲区容量硬上限：buffer_size 从仅参与百分比计算改为实际
  // 入队上限，剩余空间不足容纳整批时拒绝（调用方应分批重试）
  if !rejected &&
    (
      self.config.buffer_size <= 0 ||
      self.buffer.length() + records.length() > self.config.buffer_size
    ) {
    rejected = true
  }

  if rejected {
    result.set_completed(false)
    let mut f = 0
    while f < records.length() {
      result.add_failure()
      f = f + 1
    }
    return result
  }

  // 写入缓冲区
  for record in records {
    self.buffer.push(record)
  }

  // 批量处理（每轮消费上限由并发度决定，至少消费 1 条）
  let effective_concurrency = if self.config.concurrency < 1 {
    1
  } else {
    self.config.concurrency
  }
  let batch_size = if effective_concurrency < self.buffer.length() {
    effective_concurrency
  } else {
    self.buffer.length()
  }
  if batch_size > 0 {
    let succeeded = self.process_batch(batch_size)
    let mut s = 0
    while s < succeeded {
      result.add_success()
      s = s + 1
    }
    let mut f = 0
    while f < batch_size - succeeded {
      result.add_failure()
      f = f + 1
    }
    result.set_completed(true)
  } else {
    // 空批次也算完成
    result.set_completed(true)
  }

  result
}

///|
/// 处理批次
///
/// 按先进先出顺序处理多条记录（并发度上限），支持重试，
/// 返回成功处理的条数。
fn StreamingProcessor::process_batch(
  self : StreamingProcessor,
  batch_size : Int,
) -> Int {
  let mut processed = 0
  let mut i = 0
  while i < batch_size {
    if self.buffer.length() == 0 {
      break
    }
    // FIFO：从队首取出。修复前 buffer.pop() 弹队尾（LIFO），
    // 持续写入时队首的老记录永远轮不到处理而被饿死
    let record = self.buffer.remove(0)
    if self.process_with_retry(record) >= 0 {
      processed = processed + 1
    }
    i = i + 1
  }
  processed
}

///|
/// 带重试的处理
///
/// 单条失败重试最多 retry_count 次，返回成功时的重试次数，全部失败返回 -1。
fn StreamingProcessor::process_with_retry(
  self : StreamingProcessor,
  record : (@realtime_db.Value, Int),
) -> Int {
  let mut retries = 0
  while retries < self.config.retry_count {
    match self.process_record(record) {
      Ok(_) => return retries
      Err(_) => retries = retries + 1
    }
  }
  -1 // 重试失败
}

///|
/// 处理单条记录
///
/// 记录为 (值, TTL 秒)；当前管道阶段不直接落库，仅做可处理性占位。
fn StreamingProcessor::process_record(
  self : StreamingProcessor,
  record : (@realtime_db.Value, Int),
) -> Result[Unit, String] {
  ignore(self)
  let (value, ttl) = record
  if ttl < 0 {
    return Err("Invalid TTL")
  }
  ignore(value)
  Ok(())
}

///|
/// 获取缓冲区使用率
pub fn StreamingProcessor::buffer_usage(self : StreamingProcessor) -> Int {
  if self.config.buffer_size <= 0 {
    return 100 // 无容量配置视为满载，拒绝写入而非除零 panic
  }
  self.buffer.length() * 100 / self.config.buffer_size
}

///|
/// 获取飞行中记录数（当前缓冲区待处理记录）
pub fn StreamingProcessor::in_flight(self : StreamingProcessor) -> Int {
  self.buffer.length()
}

///|
/// 设置数据库
pub fn StreamingProcessor::set_db(
  self : StreamingProcessor,
  db : @realtime_db.DB?,
) -> Unit {
  self.db = db
}
