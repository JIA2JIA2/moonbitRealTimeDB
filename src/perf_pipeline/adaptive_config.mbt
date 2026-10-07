// 自适应配置模块
//
// 定义自适应批处理相关的配置结构。

///|
/// 自适应批处理配置结构
pub struct AdaptiveConfig {
  /// 最小批次大小
  mut min_batch_size : Int
  /// 最大批次大小
  mut max_batch_size : Int
  /// 初始批次大小
  mut initial_batch_size : Int
  /// 负载监控窗口
  monitor_window : Int
  /// 调整间隔（毫秒）
  mut adjust_interval : Int
}

///|
/// 创建默认自适应配置
///
// 最小 100，最大 10000，初始 1000
pub fn AdaptiveConfig::default() -> AdaptiveConfig {
  {
    min_batch_size: 100,
    max_batch_size: 10000,
    initial_batch_size: 1000,
    monitor_window: 10,
    adjust_interval: 5000,
  }
}

///|
/// 验证配置
///
// 返回 Ok(()) 如果配置有效。
pub fn AdaptiveConfig::validate(self : AdaptiveConfig) -> Result[Unit, String] {
  if self.min_batch_size < 1 {
    return Err("Min batch size must be positive")
  }
  if self.max_batch_size < self.min_batch_size {
    return Err("Max batch size must be >= min batch size")
  }
  if self.initial_batch_size < self.min_batch_size ||
    self.initial_batch_size > self.max_batch_size {
    return Err("Initial batch size must be between min and max")
  }
  if self.adjust_interval < 1 {
    return Err("Adjust interval must be positive")
  }
  Ok(())
}

///|
/// 设置最小批次大小
pub fn AdaptiveConfig::set_min_batch_size(
  self : AdaptiveConfig,
  size : Int,
) -> Unit {
  self.min_batch_size = size
}

///|
/// 设置最大批次大小
pub fn AdaptiveConfig::set_max_batch_size(
  self : AdaptiveConfig,
  size : Int,
) -> Unit {
  self.max_batch_size = size
}

///|
/// 设置初始批次大小
pub fn AdaptiveConfig::set_initial_batch_size(
  self : AdaptiveConfig,
  size : Int,
) -> Unit {
  self.initial_batch_size = size
}

///|
/// 设置调整间隔
pub fn AdaptiveConfig::set_adjust_interval(
  self : AdaptiveConfig,
  interval : Int,
) -> Unit {
  self.adjust_interval = interval
}
