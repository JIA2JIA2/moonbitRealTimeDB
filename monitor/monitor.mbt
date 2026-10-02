// 监控指标模块
//
// 提供指标采集和 Prometheus 格式暴露功能。

///|
/// 指标类型
pub(all) enum MetricType {
  /// 计数器：只增不减
  Counter
  /// 仪表：可增可减
  Gauge
  /// 直方图：分布统计（当前实现记录最近一次观测值）
  Histogram
}

///|
/// 指标结构体
pub struct Metric {
  /// 指标名称
  name : String
  /// 指标类型
  metric_type : MetricType
  /// 标签
  labels : Map[String, String]
  /// 指标值
  mut value : Double
}

///|
/// 指标集合
pub struct Metrics {
  /// 采集时间
  collection_time : Int
  /// 指标列表
  metrics : Array[Metric]
}

///|
/// 监控错误类型
pub(all) enum MonitorError {
  /// 指标重复
  Metric_Duplicate
  /// 指标不存在
  Metric_Not_Found
  /// 类型不允许该操作（如 Counter 不能 set）
  Metric_Type_Mismatch
}

///|
/// 创建指标
pub fn Metric::new(
  name : String,
  metric_type : MetricType,
  labels : Map[String, String],
  value : Double,
) -> Metric {
  { name, metric_type, labels, value, }
}

///|
/// 获取指标名称
pub fn Metric::name(self : Metric) -> String {
  self.name
}

///|
/// 获取指标类型
pub fn Metric::metric_type(self : Metric) -> MetricType {
  self.metric_type
}

///|
/// 获取指标值
pub fn Metric::value(self : Metric) -> Double {
  self.value
}

///|
/// 指标转 Prometheus 格式字符串
pub fn Metric::to_prometheus(self : Metric) -> String {
  let mut label_str = ""
  if self.labels.length() > 0 {
    let parts : Array[String] = []
    for k, v in self.labels {
      parts.push(k + "=\"" + v + "\"")
    }
    label_str = "{" + parts.join(", ") + "}"
  }

  self.name + label_str + " " + self.value.to_string()
}

///|
/// 创建指标集合
pub fn Metrics::new(collection_time : Int) -> Metrics {
  { collection_time, metrics: [], }
}

///|
/// 添加指标
pub fn Metrics::add_metric(self : Metrics, metric : Metric) -> Unit {
  self.metrics.push(metric)
}

///|
/// 获取指标列表
pub fn Metrics::metrics(self : Metrics) -> Array[Metric] {
  self.metrics
}

///|
/// 监控器
/// 管理指标的注册、更新和暴露
pub struct Monitor {
  /// 指标注册表（名称 -> 指标）
  registry : Map[String, Metric]
  /// 采集间隔（秒）
  interval : Int
}

///|
/// 创建监控器
pub fn Monitor::new(interval : Int) -> Monitor {
  { registry: Map([]), interval, }
}

///|
/// 注册指标。重名返回 Metric_Duplicate。
pub fn Monitor::register(
  self : Monitor,
  metric : Metric,
) -> Result[Unit, MonitorError] {
  if self.registry.contains(metric.name()) {
    Err(Metric_Duplicate)
  } else {
    self.registry.set(metric.name(), metric)
    Ok(())
  }
}

///|
/// 注销指标。
pub fn Monitor::unregister(
  self : Monitor,
  name : String,
) -> Result[Unit, MonitorError] {
  if self.registry.contains(name) {
    let _ = self.registry.remove(name)
    Ok(())
  } else {
    Err(Metric_Not_Found)
  }
}

///|
/// Counter 递增（delta 默认 1）。指标必须是 Counter 类型。
pub fn Monitor::incr(
  self : Monitor,
  name : String,
  delta? : Double,
) -> Result[Unit, MonitorError] {
  guard self.registry.get(name) is Some(m) else { return Err(Metric_Not_Found) }
  match m.metric_type() {
    Counter => {
      let d = match delta {
        Some(x) => x
        None => 1.0
      }
      m.value = m.value + d
      Ok(())
    }
    _ => Err(Metric_Type_Mismatch)
  }
}

///|
/// 设置 Gauge 的值。指标必须是 Gauge 类型。
pub fn Monitor::set_gauge(
  self : Monitor,
  name : String,
  value : Double,
) -> Result[Unit, MonitorError] {
  guard self.registry.get(name) is Some(m) else { return Err(Metric_Not_Found) }
  match m.metric_type() {
    Gauge => {
      m.value = value
      Ok(())
    }
    _ => Err(Metric_Type_Mismatch)
  }
}

///|
/// Histogram 记录一次观测值。指标必须是 Histogram 类型。
pub fn Monitor::observe(
  self : Monitor,
  name : String,
  value : Double,
) -> Result[Unit, MonitorError] {
  guard self.registry.get(name) is Some(m) else { return Err(Metric_Not_Found) }
  match m.metric_type() {
    Histogram => {
      m.value = value
      Ok(())
    }
    _ => Err(Metric_Type_Mismatch)
  }
}

///|
/// 采集指标
pub fn Monitor::collect(self : Monitor) -> Metrics {
  let metrics = Metrics::new(0)

  for _, metric in self.registry {
    metrics.add_metric(metric)
  }

  metrics
}

///|
/// 暴露指标（Prometheus 格式）
pub fn Monitor::expose(self : Monitor) -> String {
  let metrics = self.collect()
  let output : Array[String] = []

  for metric in metrics.metrics() {
    output.push(metric.to_prometheus())
  }

  output.join("\n")
}

///|
/// 获取指标数量
pub fn Monitor::metric_count(self : Monitor) -> Int {
  self.registry.length()
}

///|
/// 获取采集间隔
pub fn Monitor::interval(self : Monitor) -> Int {
  self.interval
}
