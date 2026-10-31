// 调度配置模块
//
// 定义优先级调度相关的配置结构。

///|
/// 调度配置结构
pub struct SchedulerConfig {
  /// 默认优先级（1~10）
  mut default_priority : Int32
  /// 高优先级资源预留（10~50%）
  mut high_priority_reserve : Int32
  /// 饥饿超时时间（毫秒）
  mut starvation_timeout : Int32
  /// 最大队列大小
  mut max_queue_size : Int32
}

///|
/// 创建默认调度配置
///
/// 默认优先级为 5，高优先级资源预留 20%，饥饿超时 30000ms
pub fn SchedulerConfig::default() -> SchedulerConfig {
  {
    default_priority: 5,
    high_priority_reserve: 20,
    starvation_timeout: 30000,
    max_queue_size: 10000,
  }
}

///|
/// 验证配置
///
// 返回 Ok(()) 如果配置有效。
pub fn SchedulerConfig::validate(
  self : SchedulerConfig,
) -> Result[Unit, String] {
  if self.default_priority < 1 || self.default_priority > 10 {
    return Err("Default priority must be between 1 and 10")
  }
  if self.high_priority_reserve < 10 || self.high_priority_reserve > 50 {
    return Err("High priority reserve must be between 10 and 50")
  }
  if self.starvation_timeout < 1 {
    return Err("Starvation timeout must be positive")
  }
  if self.max_queue_size < 1 {
    return Err("Max queue size must be positive")
  }
  Ok(())
}

///|
/// 设置默认优先级
pub fn SchedulerConfig::set_default_priority(
  self : SchedulerConfig,
  priority : Int32,
) -> Unit {
  self.default_priority = priority
}

///|
/// 设置高优先级资源预留
pub fn SchedulerConfig::set_high_priority_reserve(
  self : SchedulerConfig,
  reserve : Int32,
) -> Unit {
  self.high_priority_reserve = reserve
}

///|
/// 设置饥饿超时时间
pub fn SchedulerConfig::set_starvation_timeout(
  self : SchedulerConfig,
  timeout : Int32,
) -> Unit {
  self.starvation_timeout = timeout
}

///|
/// 设置最大队列大小
pub fn SchedulerConfig::set_max_queue_size(
  self : SchedulerConfig,
  size : Int32,
) -> Unit {
  self.max_queue_size = size
}
