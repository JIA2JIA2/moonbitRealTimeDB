// 管道监控器模块
//
// 实现管道性能监控，支持 Prometheus 格式指标暴露。

///|
/// 管道监控器结构
///
/// 收集和暴露管道性能指标。
pub struct PipelineMonitor {
  /// 监控器引用
  monitor : @monitor.Monitor?
  /// 性能指标
  metrics : PipelineMetrics
  /// 配置
  config : PipelineConfig
  /// 触发的告警记录
  alerts : Array[String]
}

///|
/// 创建管道监控器
pub fn PipelineMonitor::new(
  monitor : @monitor.Monitor?,
  config : PipelineConfig,
) -> PipelineMonitor {
  { monitor, metrics: PipelineMetrics::new(), config, alerts: [], }
}

///|
/// 记录吞吐量
///
/// 参数：
/// - count: 处理的记录数
/// - duration_ms: 耗时（毫秒）
pub fn PipelineMonitor::record_throughput(
  self : PipelineMonitor,
  count : Int,
  duration_ms : Int,
) -> Unit {
  if duration_ms > 0 {
    let throughput = count.to_double() / (duration_ms.to_double() / 1000.0)
    self.metrics.set_throughput(throughput)
  }
}

///|
/// 记录 P99 延迟（微秒）
pub fn PipelineMonitor::record_latency(
  self : PipelineMonitor,
  latency_us : Int,
) -> Unit {
  self.metrics.set_latency_p99(latency_us)
}

///|
/// 设置缓冲区使用率（百分比）
pub fn PipelineMonitor::set_buffer_usage(
  self : PipelineMonitor,
  usage : Int,
) -> Unit {
  self.metrics.set_buffer_usage(usage)

  // 检查告警：缓冲区使用率超过 80%
  if usage > 80 {
    self.alert("Buffer usage exceeds 80%")
  }
}

///|
/// 设置内存池命中率（百分比）
pub fn PipelineMonitor::set_pool_hit_rate(
  self : PipelineMonitor,
  rate : Double,
) -> Unit {
  self.metrics.set_pool_hit_rate(rate)
}

///|
/// 增加背压次数
pub fn PipelineMonitor::incr_backpressure(self : PipelineMonitor) -> Unit {
  self.metrics.incr_backpressure()
}

///|
/// 暴露 Prometheus 格式指标
///
/// 返回 Prometheus 格式的指标字符串。
pub fn PipelineMonitor::expose(self : PipelineMonitor) -> String {
  let mut result = ""

  // 吞吐量
  result = result +
    "# HELP pipeline_throughput Pipeline throughput in records per second\n"
  result = result + "# TYPE pipeline_throughput gauge\n"
  result = result + "pipeline_throughput \{self.metrics.throughput}\n"

  // P99 延迟
  result = result +
    "# HELP pipeline_latency_p99 Pipeline P99 latency in microseconds\n"
  result = result + "# TYPE pipeline_latency_p99 gauge\n"
  result = result + "pipeline_latency_p99 \{self.metrics.latency_p99}\n"

  // 缓冲区使用率
  result = result +
    "# HELP pipeline_buffer_usage Pipeline buffer usage percentage\n"
  result = result + "# TYPE pipeline_buffer_usage gauge\n"
  result = result + "pipeline_buffer_usage \{self.metrics.buffer_usage}\n"

  // 内存池命中率
  result = result +
    "# HELP pipeline_pool_hit_rate Memory pool hit rate percentage\n"
  result = result + "# TYPE pipeline_pool_hit_rate gauge\n"
  result = result + "pipeline_pool_hit_rate \{self.metrics.pool_hit_rate}\n"

  // 背压次数
  result = result +
    "# HELP pipeline_backpressure_count Total backpressure trigger count\n"
  result = result + "# TYPE pipeline_backpressure_count counter\n"
  result = result +
    "pipeline_backpressure_count \{self.metrics.backpressure_count}\n"

  result
}

///|
/// 发送告警
///
/// 记录告警文本；若外部监控器注册了 `pipeline_alerts` Counter，则同步递增。
fn PipelineMonitor::alert(self : PipelineMonitor, message : String) -> Unit {
  self.alerts.push(message)
  match self.monitor {
    Some(monitor) => ignore(monitor.incr("pipeline_alerts"))
    None => ()
  }
}

///|
/// 获取性能指标
pub fn PipelineMonitor::metrics(self : PipelineMonitor) -> PipelineMetrics {
  self.metrics
}

///|
/// 获取告警次数
pub fn PipelineMonitor::alert_count(self : PipelineMonitor) -> Int {
  self.alerts.length()
}

///|
/// 获取所有告警记录
pub fn PipelineMonitor::alerts(self : PipelineMonitor) -> Array[String] {
  self.alerts
}
