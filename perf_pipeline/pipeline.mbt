// 管道管理器模块
//
// 管理所有管道组件的生命周期。

///|
/// 管道状态
pub(all) enum PipelineStatus {
  /// 已创建
  Created
  /// 运行中
  Running
  /// 已暂停
  Paused
  /// 已停止
  Stopped
}

///|
pub impl Eq for PipelineStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Created, Created)
    | (Running, Running)
    | (Paused, Paused)
    | (Stopped, Stopped) => true
    _ => false
  }
}

///|
pub extend PipelineStatus with Eq::{equal, not_equal}

///|
pub impl Debug for PipelineStatus with fn to_repr(self) -> Repr {
  match self {
    Created => Repr::ctor("Created", [])
    Running => Repr::ctor("Running", [])
    Paused => Repr::ctor("Paused", [])
    Stopped => Repr::ctor("Stopped", [])
  }
}

///|
pub extend PipelineStatus with Debug::{to_repr}

///|
/// 管道结构
///
/// 管理所有管道组件。
pub struct Pipeline {
  /// 配置
  config : PipelineConfig
  /// 批量导入器
  mut importer : BatchImporter?
  /// 流式处理器
  mut streamer : StreamingProcessor?
  /// 批量聚合器
  mut aggregator : BatchAggregator?
  /// 监控器
  mut monitor : PipelineMonitor?
  /// 压缩处理器
  mut compressor : CompressionProcessor?
  /// 转换引擎
  mut transformer : TransformEngine?
  /// 调度器
  mut scheduler : PriorityScheduler?
  /// 并行导入器
  mut parallel_importer : ParallelImporter?
  /// 自适应控制器
  mut adaptive_controller : AdaptiveController?
  /// 零拷贝读取器
  mut zero_copy_reader : ZeroCopyReader?
  /// 状态
  mut status : PipelineStatus
  /// 内存池
  mut mempool : MemoryPool?
}

///|
/// 创建管道
pub fn Pipeline::new(config : PipelineConfig) -> Pipeline {
  {
    config,
    importer: None,
    streamer: None,
    aggregator: None,
    monitor: None,
    compressor: None,
    transformer: None,
    scheduler: None,
    parallel_importer: None,
    adaptive_controller: None,
    zero_copy_reader: None,
    status: Created,
    mempool: None,
  }
}

///|
/// 启动管道
///
/// 初始化所有组件。
pub fn Pipeline::start(self : Pipeline) -> Result[Unit, String] {
  match self.status {
    Created => {
      // 初始化内存池
      self.mempool = Some(MemoryPool::new(1000, 10000, 1.5))

      // 初始化批量导入器
      self.importer = Some(
        BatchImporter::new(None, None, self.mempool, self.config),
      )

      // 初始化流式处理器
      self.streamer = Some(
        StreamingProcessor::new(None, None, self.mempool, self.config),
      )

      // 初始化批量聚合器
      self.aggregator = Some(BatchAggregator::new(self.config))

      // 初始化监控器
      self.monitor = Some(PipelineMonitor::new(None, self.config))

      // 初始化压缩处理器
      let compression_config = CompressionConfig::default()
      self.compressor = Some(CompressionProcessor::new(compression_config, self.mempool))

      // 初始化转换引擎
      let transform_config = TransformConfig::default()
      self.transformer = Some(TransformEngine::new(transform_config))

      // 初始化调度器
      let scheduler_config = SchedulerConfig::default()
      self.scheduler = Some(PriorityScheduler::new(scheduler_config))

      // 初始化并行导入器
      let parallel_config = ParallelImportConfig::default()
      self.parallel_importer = Some(ParallelImporter::new(self.importer, parallel_config))

      // 初始化自适应控制器
      let adaptive_config = AdaptiveConfig::default()
      self.adaptive_controller = Some(AdaptiveController::new(adaptive_config))

      // 初始化零拷贝读取器
      self.zero_copy_reader = Some(ZeroCopyReader::new(None, self.mempool))

      self.status = Running
      Ok(())
    }
    _ => Err("Pipeline is not in Created state")
  }
}

///|
/// 停止管道
///
/// 释放所有资源。
pub fn Pipeline::stop(self : Pipeline) -> Unit {
  self.status = Stopped
  self.importer = None
  self.streamer = None
  self.aggregator = None
  self.monitor = None
  self.compressor = None
  self.transformer = None
  self.scheduler = None
  self.parallel_importer = None
  self.adaptive_controller = None
  self.zero_copy_reader = None
  self.mempool = None
}

///|
/// 暂停管道
///
/// 暂停处理，保留状态。
pub fn Pipeline::pause(self : Pipeline) -> Unit {
  match self.status {
    Running => self.status = Paused
    _ => ()
  }
}

///|
/// 恢复管道
///
/// 从暂停状态恢复。
pub fn Pipeline::unpause(self : Pipeline) -> Unit {
  match self.status {
    Paused => self.status = Running
    _ => ()
  }
}

///|
/// 检查管道是否在运行
pub fn Pipeline::is_running(self : Pipeline) -> Bool {
  match self.status {
    Running => true
    _ => false
  }
}

///|
/// 获取管道状态
pub fn Pipeline::status(self : Pipeline) -> PipelineStatus {
  self.status
}

///|
/// 获取批量导入器
pub fn Pipeline::importer(self : Pipeline) -> BatchImporter? {
  self.importer
}

///|
/// 获取流式处理器
pub fn Pipeline::streamer(self : Pipeline) -> StreamingProcessor? {
  self.streamer
}

///|
/// 获取批量聚合器
pub fn Pipeline::aggregator(self : Pipeline) -> BatchAggregator? {
  self.aggregator
}

///|
/// 获取监控器
pub fn Pipeline::monitor(self : Pipeline) -> PipelineMonitor? {
  self.monitor
}

///|
/// 获取压缩处理器
pub fn Pipeline::compressor(self : Pipeline) -> CompressionProcessor? {
  self.compressor
}

///|
/// 获取转换引擎
pub fn Pipeline::transformer(self : Pipeline) -> TransformEngine? {
  self.transformer
}

///|
/// 获取调度器
pub fn Pipeline::scheduler(self : Pipeline) -> PriorityScheduler? {
  self.scheduler
}

///|
/// 获取并行导入器
pub fn Pipeline::parallel_importer(self : Pipeline) -> ParallelImporter? {
  self.parallel_importer
}

///|
/// 获取自适应控制器
pub fn Pipeline::adaptive_controller(self : Pipeline) -> AdaptiveController? {
  self.adaptive_controller
}

///|
/// 获取零拷贝读取器
pub fn Pipeline::zero_copy_reader(self : Pipeline) -> ZeroCopyReader? {
  self.zero_copy_reader
}

///|
/// 获取内存池
pub fn Pipeline::mempool(self : Pipeline) -> MemoryPool? {
  self.mempool
}

///|
/// 设置数据库连接
pub fn Pipeline::set_db(self : Pipeline, db : @realtime_db.DB?) -> Unit {
  match self.importer {
    Some(importer) => importer.set_db(db)
    None => ()
  }
  match self.streamer {
    Some(streamer) => streamer.set_db(db)
    None => ()
  }
  match self.zero_copy_reader {
    Some(reader) => reader.set_db(db)
    None => ()
  }
}

///|
/// 设置 WAL 连接
pub fn Pipeline::set_wal(self : Pipeline, wal : @persistence.WAL?) -> Unit {
  match self.importer {
    Some(importer) => importer.set_wal(wal)
    None => ()
  }
}
