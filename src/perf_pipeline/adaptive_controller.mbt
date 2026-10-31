// 自适应控制器模块
//
// 实现自适应批处理，动态调整批次大小。
// 目标：负载感知，平滑过渡

///|
/// 负载信息结构
pub struct LoadInfo {
  /// 吞吐量（条/秒）
  throughput : Double
  /// 延迟（微秒）
  latency_us : Int32
  /// 错误率
  error_rate : Double
  /// 时间戳
  timestamp : Int32
}

///|
/// 自适应统计
pub struct AdaptiveStats {
  /// 当前批次大小
  mut current_batch_size : Int32
  /// 调整次数
  mut adjust_count : Int32
  /// 上次调整时间
  last_adjust_time : Int32
  /// 平均吞吐量
  mut avg_throughput : Double
}

///|
/// 自适应控制器结构
pub struct AdaptiveController {
  /// 配置
  config : AdaptiveConfig
  /// 当前批次大小
  mut current_batch_size : Int32
  /// 负载历史
  load_history : Array[LoadInfo]
  /// 统计信息
  mut stats : AdaptiveStats
  /// 震荡检测计数器
  mut oscillation_count : Int32
}

///|
/// 创建负载信息
pub fn LoadInfo::new(
  throughput : Double,
  latency_us : Int32,
  error_rate : Double,
  timestamp : Int32,
) -> LoadInfo {
  { throughput, latency_us, error_rate, timestamp, }
}

///|
/// 创建自适应统计
pub fn AdaptiveStats::new(initial_size : Int32) -> AdaptiveStats {
  {
    current_batch_size: initial_size,
    adjust_count: 0,
    last_adjust_time: 0,
    avg_throughput: 0.0,
  }
}

///|
/// 创建自适应控制器
pub fn AdaptiveController::new(config : AdaptiveConfig) -> AdaptiveController {
  {
    config,
    current_batch_size: config.initial_batch_size,
    load_history: [],
    stats: AdaptiveStats::new(config.initial_batch_size),
    oscillation_count: 0,
  }
}

///|
/// 监控负载
///
// 记录负载信息。
pub fn AdaptiveController::monitor_load(
  self : AdaptiveController,
  throughput : Double,
  latency_us : Int32,
  error_rate : Double,
) -> Unit {
  let load = LoadInfo::new(
    throughput,
    latency_us,
    error_rate,
    get_current_time(),
  )
  self.load_history.push(load)

  // 保持窗口大小
  while self.load_history.length() > self.config.monitor_window {
    ignore(self.load_history.pop())
  }
}

///|
/// 计算平均吞吐量
///
// 返回平均吞吐量。
pub fn AdaptiveController::calculate_avg_throughput(
  self : AdaptiveController,
) -> Double {
  if self.load_history.is_empty() {
    return 0.0
  }

  let mut total = 0.0
  for load in self.load_history {
    total = total + load.throughput
  }
  total / self.load_history.length().to_double()
}

///|
/// 调整批次大小
///
// 动态调整批次大小，负载感知。
pub fn AdaptiveController::adjust_batch_size(
  self : AdaptiveController,
) -> Int32 {
  if self.load_history.is_empty() {
    return self.current_batch_size
  }

  // 计算平均吞吐量
  let avg_throughput = self.calculate_avg_throughput()

  // 根据吞吐量调整批次大小
  let target_size = if avg_throughput > 1000000.0 {
    // 高负载：增加批次大小
    self.current_batch_size + self.current_batch_size / 4
  } else if avg_throughput < 500000.0 {
    // 低负载：减少批次大小
    self.current_batch_size - self.current_batch_size / 4
  } else {
    // 正常负载：保持
    self.current_batch_size
  }

  // 震荡检测
  if (
      target_size > self.current_batch_size &&
      self.stats.avg_throughput > avg_throughput
    ) ||
    (
      target_size < self.current_batch_size &&
      self.stats.avg_throughput < avg_throughput
    ) {
    self.oscillation_count = self.oscillation_count + 1
  }

  // 限制在范围内
  let new_size = target_size
    .min(self.config.max_batch_size)
    .max(self.config.min_batch_size)

  // 平滑过渡：每次调整幅度不超过当前大小的 25%
  let current = self.current_batch_size
  let max_change = (current / 4).max(1)
  let actual_new_size = if new_size > current {
    // 上调：目标值与 current + max_change 中取较小者
    new_size.min(current + max_change)
  } else if new_size < current {
    // 下调：目标值与 current - max_change 中取较大者
    new_size.max(current - max_change)
  } else {
    new_size
  }

  // 更新状态
  self.current_batch_size = actual_new_size
  self.stats.current_batch_size = actual_new_size
  self.stats.adjust_count = self.stats.adjust_count + 1
  self.stats.avg_throughput = avg_throughput

  actual_new_size
}

///|
/// 获取当前批次大小
pub fn AdaptiveController::current_batch_size(
  self : AdaptiveController,
) -> Int32 {
  self.current_batch_size
}

///|
/// 获取统计信息
pub fn AdaptiveController::stats(self : AdaptiveController) -> AdaptiveStats {
  self.stats
}

///|
/// 重置
pub fn AdaptiveController::reset(self : AdaptiveController) -> Unit {
  self.current_batch_size = self.config.initial_batch_size
  self.load_history.clear()
  self.oscillation_count = 0
  self.stats = AdaptiveStats::new(self.config.initial_batch_size)
}

///|
/// 获取震荡次数
pub fn AdaptiveController::oscillation_count(
  self : AdaptiveController,
) -> Int32 {
  self.oscillation_count
}
