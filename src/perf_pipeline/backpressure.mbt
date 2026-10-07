// 背压控制器模块
//
// 实现背压控制机制，当缓冲区使用率超过阈值时触发背压。
// 目标：响应时间 <= 10ms

///|
/// 背压控制器结构
///
/// 监控缓冲区使用率，触发背压机制。
pub struct BackpressureController {
  /// 背压阈值（百分比）
  threshold : Int
  /// 是否触发背压
  mut triggered : Bool
  /// 触发时间（逻辑时钟）
  mut trigger_time : Int
  /// 背压超时时间（毫秒），默认 30000
  mut timeout_ms : Int
}

///|
/// 创建背压控制器
///
/// 默认阈值为 80%。
pub fn BackpressureController::new(threshold : Int) -> BackpressureController {
  { threshold, triggered: false, trigger_time: 0, timeout_ms: 30000, }
}

///|
/// 检查缓冲区使用率
///
/// 当缓冲区使用率 > threshold 时触发背压。
/// 返回是否应该触发背压（仅在状态从未触发转为触发的边沿返回 true）。
pub fn BackpressureController::check(
  self : BackpressureController,
  buffer_usage : Int,
) -> Bool {
  self.check_at(buffer_usage, 0)
}

///|
/// 检查缓冲区使用率（带逻辑时钟）
///
/// 与 `check` 相同，但记录触发时刻，使 `is_timeout` 可以判定背压是否超时。
pub fn BackpressureController::check_at(
  self : BackpressureController,
  buffer_usage : Int,
  current_time : Int,
) -> Bool {
  if buffer_usage > self.threshold {
    if !self.triggered {
      self.triggered = true
      self.trigger_time = current_time
      return true
    }
  } else if self.triggered {
    self.triggered = false
    self.trigger_time = 0
  }
  false
}

///|
/// 触发背压
///
/// 手动触发背压。
pub fn BackpressureController::trigger(self : BackpressureController) -> Unit {
  self.triggered = true
}

///|
/// 重置背压状态
///
/// 重置背压状态为未触发。
pub fn BackpressureController::reset(self : BackpressureController) -> Unit {
  self.triggered = false
  self.trigger_time = 0
}

///|
/// 获取背压触发时间（逻辑时钟），未触发或手动触发时为 0
pub fn BackpressureController::trigger_time(
  self : BackpressureController,
) -> Int {
  self.trigger_time
}

///|
/// 检查背压状态
///
/// 返回当前是否处于背压状态。
pub fn BackpressureController::is_backpressured(
  self : BackpressureController,
) -> Bool {
  self.triggered
}

///|
/// 设置背压超时时间（毫秒）
pub fn BackpressureController::set_timeout(
  self : BackpressureController,
  timeout_ms : Int,
) -> Unit {
  self.timeout_ms = timeout_ms
}

///|
/// 检查背压是否超时
///
/// 返回背压持续时间是否已超过 timeout_ms。
/// 注意：需通过 `check_at` 触发并记录时间后该判定才会生效。
pub fn BackpressureController::is_timeout(
  self : BackpressureController,
  current_time : Int,
) -> Bool {
  self.triggered &&
  self.trigger_time > 0 &&
  current_time - self.trigger_time > self.timeout_ms
}
