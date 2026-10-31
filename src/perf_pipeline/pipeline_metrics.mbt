// 管道性能指标模块
//
// 定义管道性能指标结构。

///|
/// 管道性能指标结构
///
/// 包含吞吐量、延迟、缓冲区使用率、内存池命中率、背压次数。
pub struct PipelineMetrics {
  /// 吞吐量（条/秒）
  mut throughput : Double
  /// P99 延迟（微秒）
  mut latency_p99 : Int32
  /// 缓冲区使用率（百分比）
  mut buffer_usage : Int32
  /// 内存池命中率（百分比）
  mut pool_hit_rate : Double
  /// 背压次数
  mut backpressure_count : Int32
}

///|
/// 创建管道性能指标
pub fn PipelineMetrics::new() -> PipelineMetrics {
  {
    throughput: 0.0,
    latency_p99: 0,
    buffer_usage: 0,
    pool_hit_rate: 0.0,
    backpressure_count: 0,
  }
}

///|
/// 设置吞吐量
pub fn PipelineMetrics::set_throughput(
  self : PipelineMetrics,
  throughput : Double,
) -> Unit {
  self.throughput = throughput
}

///|
/// 设置 P99 延迟
pub fn PipelineMetrics::set_latency_p99(
  self : PipelineMetrics,
  latency_us : Int32,
) -> Unit {
  self.latency_p99 = latency_us
}

///|
/// 设置缓冲区使用率
pub fn PipelineMetrics::set_buffer_usage(
  self : PipelineMetrics,
  usage : Int32,
) -> Unit {
  self.buffer_usage = usage
}

///|
/// 设置内存池命中率
pub fn PipelineMetrics::set_pool_hit_rate(
  self : PipelineMetrics,
  rate : Double,
) -> Unit {
  self.pool_hit_rate = rate
}

///|
/// 增加背压次数
pub fn PipelineMetrics::incr_backpressure(self : PipelineMetrics) -> Unit {
  self.backpressure_count = self.backpressure_count + 1
}

///|
/// 获取吞吐量
pub fn PipelineMetrics::throughput(self : PipelineMetrics) -> Double {
  self.throughput
}

///|
/// 获取 P99 延迟
pub fn PipelineMetrics::latency_p99(self : PipelineMetrics) -> Int32 {
  self.latency_p99
}

///|
/// 获取缓冲区使用率
pub fn PipelineMetrics::buffer_usage(self : PipelineMetrics) -> Int32 {
  self.buffer_usage
}

///|
/// 获取内存池命中率
pub fn PipelineMetrics::pool_hit_rate(self : PipelineMetrics) -> Double {
  self.pool_hit_rate
}

///|
/// 获取背压次数
pub fn PipelineMetrics::backpressure_count(self : PipelineMetrics) -> Int32 {
  self.backpressure_count
}
