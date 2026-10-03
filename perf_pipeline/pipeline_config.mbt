// 高性能数据管道配置模块
//
// 定义管道配置结构，包含所有可配置参数及其默认值。

///|
/// 管道配置结构
///
/// 包含所有管道相关配置参数，支持运行时动态调整。
pub struct PipelineConfig {
  /// 批量大小（条），默认 1000，范围 1~10000
  mut batch_size : Int
  /// 最大飞行中记录数，默认 10000
  max_in_flight : Int
  /// 导入超时时间（毫秒），默认 30000
  import_timeout : Int
  /// 缓冲区大小，默认 10000
  buffer_size : Int
  /// 背压阈值（百分比），默认 80，范围 0~100
  mut backpressure_threshold : Int
  /// 并发度，默认 4，范围 1~16
  mut concurrency : Int
  /// 重试次数，默认 3
  retry_count : Int
  /// 聚合窗口（毫秒），默认 100
  mut aggregate_window : Int
  /// 最大批量大小，默认 1000
  mut max_batch_size : Int
  /// 是否去重，默认 true
  deduplicate : Bool
}

///|
/// 配置验证错误类型
pub(all) enum ConfigError {
  /// 批量大小无效
  Invalid_Batch_Size
  /// 并发度无效
  Invalid_Concurrency
  /// 背压阈值无效
  Invalid_Backpressure_Threshold
  /// 缓冲区大小无效
  Invalid_Buffer_Size
}

///|
/// 创建默认配置
///
/// 默认值：
/// - batch_size: 1000
/// - max_in_flight: 10000
/// - import_timeout: 30000
/// - buffer_size: 10000
/// - backpressure_threshold: 80
/// - concurrency: 4
/// - retry_count: 3
/// - aggregate_window: 100
/// - max_batch_size: 1000
/// - deduplicate: true
pub fn PipelineConfig::default() -> PipelineConfig {
  {
    batch_size: 1000,
    max_in_flight: 10000,
    import_timeout: 30000,
    buffer_size: 10000,
    backpressure_threshold: 80,
    concurrency: 4,
    retry_count: 3,
    aggregate_window: 100,
    max_batch_size: 1000,
    deduplicate: true,
  }
}

///|
/// 验证配置参数
///
/// 返回 Ok(()) 如果配置有效，否则返回 ConfigError。
pub fn PipelineConfig::validate(
  self : PipelineConfig,
) -> Result[Unit, ConfigError] {
  if self.batch_size < 1 || self.batch_size > 10000 {
    return Err(Invalid_Batch_Size)
  }
  if self.concurrency < 1 || self.concurrency > 16 {
    return Err(Invalid_Concurrency)
  }
  if self.backpressure_threshold < 0 || self.backpressure_threshold > 100 {
    return Err(Invalid_Backpressure_Threshold)
  }
  if self.buffer_size < 1 {
    return Err(Invalid_Buffer_Size)
  }
  Ok(())
}

///|
/// 设置批量大小
///
/// 范围：1~10000
pub fn PipelineConfig::set_batch_size(
  self : PipelineConfig,
  size : Int,
) -> Unit {
  self.batch_size = size
}

///|
/// 设置并发度
///
/// 范围：1~16
pub fn PipelineConfig::set_concurrency(
  self : PipelineConfig,
  concurrency : Int,
) -> Unit {
  self.concurrency = concurrency
}

///|
/// 设置背压阈值
///
/// 范围：0~100（百分比）
pub fn PipelineConfig::set_backpressure_threshold(
  self : PipelineConfig,
  threshold : Int,
) -> Unit {
  self.backpressure_threshold = threshold
}

///|
/// 设置聚合窗口（毫秒）
pub fn PipelineConfig::set_aggregate_window(
  self : PipelineConfig,
  window_ms : Int,
) -> Unit {
  self.aggregate_window = window_ms
}

///|
/// 设置最大批量大小
pub fn PipelineConfig::set_max_batch_size(
  self : PipelineConfig,
  size : Int,
) -> Unit {
  self.max_batch_size = size
}

///|
/// 获取批量大小
pub fn PipelineConfig::batch_size(self : PipelineConfig) -> Int {
  self.batch_size
}

///|
/// 获取并发度
pub fn PipelineConfig::concurrency(self : PipelineConfig) -> Int {
  self.concurrency
}

///|
/// 获取背压阈值
pub fn PipelineConfig::backpressure_threshold(self : PipelineConfig) -> Int {
  self.backpressure_threshold
}

///|
/// 获取聚合窗口（毫秒）
pub fn PipelineConfig::aggregate_window(self : PipelineConfig) -> Int {
  self.aggregate_window
}
