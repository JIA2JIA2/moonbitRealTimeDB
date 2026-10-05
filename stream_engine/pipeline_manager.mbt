// 管道管理器模块
//
// 实现管道生命周期管理、管道配置管理

///|
/// 管道配置
pub(all) struct Pipeline {
  /// 管道名称
  name : String
  /// 当前状态
  mut status : PipelineStatus
  /// 配置
  config : StreamConfig
  /// 窗口引擎
  mut window_engine : WindowStateManager?
  /// 聚合处理器
  mut aggregate_processor : AggregateProcessor?
  /// 过滤订阅器
  mut filter_subscriber : SubscriptionManager?
  /// 状态存储
  mut state_store : MemoryStateStore?
  /// 检查点服务
  mut checkpoint_service : CheckpointService?
  /// 水位线服务
  mut watermark_service : WatermarkService?
  /// 创建时间
  created_at : Int
  /// 更新时间
  mut updated_at : Int
  /// 错误计数
  mut error_count : Int
  /// 最后错误
  mut last_error : StreamError?
}

///|
/// 管道管理器
pub(all) struct PipelineManager {
  /// 管道映射
  mut pipelines : Map[String, Pipeline]
  /// 配置
  config : PipelineConfig
  /// 下一个管道 ID
  mut next_id : Int
  /// 最大管道数
  max_pipelines : Int
}

///|
/// 默认最大管道数
pub const DEFAULT_MAX_PIPELINES : Int = 100

///|
/// 创建管道管理器
pub fn PipelineManager::new() -> PipelineManager {
  PipelineManager::with_config(PipelineConfig::default(), DEFAULT_MAX_PIPELINES)
}

///|
/// 配置创建管道管理器
pub fn PipelineManager::with_config(
  config : PipelineConfig,
  max_pipelines : Int,
) -> PipelineManager {
  { pipelines: Map([]), config, next_id: 0, max_pipelines, }
}

///|
/// 创建管道
pub fn PipelineManager::create_pipeline(
  self : PipelineManager,
  name : String,
  stream_config : StreamConfig,
) -> Result[Pipeline, StreamError] {
  // 检查管道数量限制
  if self.pipelines.length() >= self.max_pipelines {
    return Err(Pipeline_Invalid_Config)
  }

  // 检查管道是否已存在
  if self.pipelines.contains(name) {
    return Err(Pipeline_Already_Exists)
  }

  // 验证配置
  if !self.validate_config(stream_config) {
    return Err(Pipeline_Invalid_Config)
  }

  // 创建管道
  let pipeline = Pipeline::{
    name,
    status: Created,
    config: stream_config,
    window_engine: None,
    aggregate_processor: None,
    filter_subscriber: None,
    state_store: None,
    checkpoint_service: None,
    watermark_service: None,
    created_at: 0,
    updated_at: 0,
    error_count: 0,
    last_error: None,
  }

  let stored = { ..pipeline, }
  self.pipelines.set(stored.name.to_string(), stored)
  Ok(pipeline)
}

///|
/// 启动管道
pub fn PipelineManager::start_pipeline(
  self : PipelineManager,
  name : String,
) -> Result[Unit, StreamError] {
  let pipeline = match self.pipelines.get(name) {
    Some(p) => p
    None => return Err(Pipeline_Not_Found)
  }

  // 检查状态
  if pipeline.status != Created && pipeline.status != Paused {
    return Err(Pipeline_Invalid_State)
  }

  // 初始化组件
  self.initialize_components(pipeline)

  // 更新状态
  pipeline.status = Running
  pipeline.updated_at = 0

  Ok(())
}

///|
/// 停止管道
pub fn PipelineManager::stop_pipeline(
  self : PipelineManager,
  name : String,
) -> Result[Unit, StreamError] {
  let pipeline = match self.pipelines.get(name) {
    Some(p) => p
    None => return Err(Pipeline_Not_Found)
  }

  // 检查状态
  if pipeline.status == Stopped {
    return Ok(())
  }

  // 更新状态
  pipeline.status = Stopped
  pipeline.updated_at = 0

  Ok(())
}

///|
/// 暂停管道
pub fn PipelineManager::pause_pipeline(
  self : PipelineManager,
  name : String,
) -> Result[Unit, StreamError] {
  let pipeline = match self.pipelines.get(name) {
    Some(p) => p
    None => return Err(Pipeline_Not_Found)
  }

  // 检查状态
  if pipeline.status != Running {
    return Err(Pipeline_Invalid_State)
  }

  // 更新状态
  pipeline.status = Paused
  pipeline.updated_at = 0

  Ok(())
}

///|
/// 恢复管道
pub fn PipelineManager::resume_pipeline(
  self : PipelineManager,
  name : String,
) -> Result[Unit, StreamError] {
  let pipeline = match self.pipelines.get(name) {
    Some(p) => p
    None => return Err(Pipeline_Not_Found)
  }

  // 检查状态
  if pipeline.status != Paused {
    return Err(Pipeline_Invalid_State)
  }

  // 更新状态
  pipeline.status = Running
  pipeline.updated_at = 0

  Ok(())
}

///|
/// 删除管道
pub fn PipelineManager::delete_pipeline(
  self : PipelineManager,
  name : String,
) -> Result[Unit, StreamError] {
  let pipeline = match self.pipelines.get(name) {
    Some(p) => p
    None => return Err(Pipeline_Not_Found)
  }

  // 检查状态
  if pipeline.status == Running {
    return Err(Pipeline_Invalid_State)
  }

  // 删除管道
  self.pipelines.remove(name)

  Ok(())
}

///|
/// 获取管道
pub fn PipelineManager::get_pipeline(
  self : PipelineManager,
  name : String,
) -> Pipeline? {
  self.pipelines.get(name)
}

///|
/// 获取所有管道
pub fn PipelineManager::get_all_pipelines(
  self : PipelineManager,
) -> Array[Pipeline] {
  let result : Array[Pipeline] = []
  for (_, pipeline) in self.pipelines {
    result.push(pipeline)
  }
  result
}

///|
/// 获取管道数量
pub fn PipelineManager::pipeline_count(self : PipelineManager) -> Int {
  self.pipelines.length()
}

///|
/// 验证配置
fn PipelineManager::validate_config(
  self : PipelineManager,
  config : StreamConfig,
) -> Bool {
  let _ = self
  // 验证管道配置
  if config.pipeline_config.batch_size <= 0 {
    return false
  }

  if config.pipeline_config.buffer_size <= 0 {
    return false
  }

  if config.pipeline_config.backpressure_threshold <= 0.0 ||
    config.pipeline_config.backpressure_threshold >= 1.0 {
    return false
  }

  // 验证窗口配置
  for window_config in config.window_configs {
    if window_config.size_ms <= 0 {
      return false
    }
  }

  true
}

///|
/// 初始化组件
fn PipelineManager::initialize_components(
  self : PipelineManager,
  pipeline : Pipeline,
) -> Unit {
  let _ = self
  // 创建状态存储
  let state_store = MemoryStateStore::new()
  pipeline.state_store = Some(state_store)

  // 创建快照管理器
  let snapshot_manager = SnapshotManager::new(
    pipeline.config.checkpoint_config.max_retained_checkpoints,
    pipeline.config.checkpoint_config.interval_ms,
  )

  // 创建检查点服务
  let checkpoint_service = CheckpointService::new(
    pipeline.config.checkpoint_config,
    state_store,
    snapshot_manager,
  )
  pipeline.checkpoint_service = Some(checkpoint_service)

  // 创建水位线服务
  let watermark_service = WatermarkService::new(1000)
  pipeline.watermark_service = Some(watermark_service)

  // 创建聚合处理器
  let aggregate_processor = init_builtin_aggregates(AggregateProcessor::new())
  pipeline.aggregate_processor = Some(aggregate_processor)

  // 创建过滤订阅器
  let subscription_manager = SubscriptionManager::new(
    pipeline.config.subscription_config,
  )
  pipeline.filter_subscriber = Some(subscription_manager)
}

///|
/// 处理数据变更事件
pub fn PipelineManager::process_event(
  self : PipelineManager,
  pipeline_name : String,
  event : StreamEvent,
) -> Result[Unit, StreamError] {
  let pipeline = match self.pipelines.get(pipeline_name) {
    Some(p) => p
    None => return Err(Pipeline_Not_Found)
  }

  // 检查状态
  if pipeline.status != Running {
    return Err(Pipeline_Invalid_State)
  }

  // 推进水位线
  match pipeline.watermark_service {
    Some(watermark_service) => {
      let _ = watermark_service.advance_watermark(event.timestamp, 0)
    }
    None => ()
  }

  // 处理过滤订阅
  match pipeline.filter_subscriber {
    Some(subscriber) => {
      let _ = subscriber.process_event(event)
    }
    None => ()
  }

  Ok(())
}

///|
/// 获取管道状态
pub fn PipelineManager::get_pipeline_status(
  self : PipelineManager,
  name : String,
) -> PipelineStatus? {
  match self.pipelines.get(name) {
    Some(pipeline) => Some(pipeline.status)
    None => None
  }
}

///|
/// 创建默认管道管理器
pub fn create_default_pipeline_manager() -> PipelineManager {
  PipelineManager::new()
}

///|
/// 创建管道
pub fn create_pipeline(
  name : String,
  pipeline_config : PipelineConfig,
  window_configs : Array[WindowConfig],
  checkpoint_config : CheckpointConfig,
  subscription_config : SubscriptionConfig,
) -> StreamConfig {
  StreamConfig::{
    name,
    pipeline_config,
    window_configs,
    checkpoint_config,
    subscription_config,
  }
}
