// 计费计量与监控模块
//
// 实现资源使用统计、计费数据上报、监控指标

///|
/// 计费数据
pub(all) struct BillingData {
  /// 租户 ID
  tenant_id : String
  /// 计费周期
  billing_period : String
  /// CPU 使用量（核时）
  cpu_hours : Double
  /// 内存使用量（GB时）
  memory_gb_hours : Double
  /// 存储使用量（GB时）
  storage_gb_hours : Double
  /// 连接数使用量（连接时）
  connection_hours : Int32
  /// 吞吐量使用量（GB）
  throughput_gb : Double
  /// 计费金额
  amount : Double
  /// 货币单位
  currency : String
}

///|
/// 计费计量器
pub(all) struct BillingMeter {
  /// 租户管理器
  tenant_manager : TenantManager
  /// 计费费率
  rates : BillingRates
  /// 计费数据映射
  mut billing_data : Map[String, BillingData]
}

///|
/// 计费费率
pub(all) struct BillingRates {
  /// CPU 费率（元/核时）
  cpu_rate : Double
  /// 内存费率（元/GB时）
  memory_rate : Double
  /// 存储费率（元/GB时）
  storage_rate : Double
  /// 连接费率（元/连接时）
  connection_rate : Double
  /// 吞吐量费率（元/GB）
  throughput_rate : Double
}

///|
/// 默认计费费率
pub fn BillingRates::default() -> BillingRates {
  {
    cpu_rate: 0.5,
    memory_rate: 0.1,
    storage_rate: 0.01,
    connection_rate: 0.001,
    throughput_rate: 0.05,
  }
}

///|
/// 创建计费计量器
pub fn BillingMeter::new(tenant_manager : TenantManager) -> BillingMeter {
  { tenant_manager, rates: BillingRates::default(), billing_data: Map([]), }
}

///|
/// 计算计费金额
pub fn BillingMeter::calculate_billing(
  self : BillingMeter,
  tenant_id : String,
) -> Result[BillingData, TenantError] {
  // 获取租户
  let tenant = match self.tenant_manager.get_tenant(tenant_id.to_string()) {
    Some(t) => t
    None => return Err(Tenant_Not_Found)
  }

  // 计算资源使用量
  let cpu_hours = tenant.resource_usage.cpu_used
  let memory_gb_hours = tenant.resource_usage.memory_used.to_double() /
    1073741824.0
  let storage_gb_hours = tenant.resource_usage.storage_used.to_double() /
    1073741824.0
  let connection_hours = tenant.resource_usage.connections_used
  let throughput_gb = tenant.resource_usage.throughput_used.to_double() /
    1073741824.0

  // 计算金额
  let amount = cpu_hours * self.rates.cpu_rate +
    memory_gb_hours * self.rates.memory_rate +
    storage_gb_hours * self.rates.storage_rate +
    connection_hours.to_double() * self.rates.connection_rate +
    throughput_gb * self.rates.throughput_rate

  let billing_data = BillingData::{
    tenant_id: tenant_id.to_string(),
    billing_period: "current".to_string(),
    cpu_hours,
    memory_gb_hours,
    storage_gb_hours,
    connection_hours,
    throughput_gb,
    amount,
    currency: "CNY".to_string(),
  }

  // 保存计费数据
  self.billing_data.set(tenant_id, { ..billing_data, })

  Ok(billing_data)
}

///|
/// 生成计费报表
pub fn BillingMeter::generate_report(
  self : BillingMeter,
  tenant_id : String,
) -> Result[String, TenantError] {
  let billing_data = match self.billing_data.get(tenant_id.to_string()) {
    Some(data) => data
    None =>
      match self.calculate_billing(tenant_id) {
        Ok(data) => data
        Err(e) => return Err(e)
      }
  }

  // 生成报表字符串
  let report = "Billing Report for Tenant: " +
    billing_data.tenant_id.to_string() +
    "\n" +
    "CPU Hours: " +
    billing_data.cpu_hours.to_string() +
    "\n" +
    "Memory GB-Hours: " +
    billing_data.memory_gb_hours.to_string() +
    "\n" +
    "Storage GB-Hours: " +
    billing_data.storage_gb_hours.to_string() +
    "\n" +
    "Connection Hours: " +
    billing_data.connection_hours.to_string() +
    "\n" +
    "Throughput GB: " +
    billing_data.throughput_gb.to_string() +
    "\n" +
    "Amount: " +
    billing_data.amount.to_string() +
    " " +
    billing_data.currency.to_string()

  Ok(report)
}

///|
/// 监控指标收集器
pub(all) struct TenantMonitor {
  /// 租户管理器
  tenant_manager : TenantManager
  /// 指标映射
  mut metrics : Map[String, Double]
}

///|
/// 创建监控指标收集器
pub fn TenantMonitor::new(tenant_manager : TenantManager) -> TenantMonitor {
  { tenant_manager, metrics: Map([]), }
}

///|
/// 暴露 Prometheus 格式指标
pub fn TenantMonitor::expose_metrics(self : TenantMonitor) -> String {
  let mut metrics_str = ""

  // 获取所有租户
  let tenants = self.tenant_manager.list_tenants()

  // 租户数量
  metrics_str = metrics_str + "# HELP db_tenant_count Total number of tenants\n"
  metrics_str = metrics_str + "# TYPE db_tenant_count gauge\n"
  metrics_str = metrics_str +
    "db_tenant_count " +
    tenants.length().to_string() +
    "\n"

  // 每个租户的资源使用量
  for tenant in tenants {
    let tenant_id = tenant.tenant_id.to_string()

    metrics_str = metrics_str +
      "# HELP db_tenant_cpu_usage CPU usage for tenant " +
      tenant_id.to_string() +
      "\n"
    metrics_str = metrics_str + "# TYPE db_tenant_cpu_usage gauge\n"
    metrics_str = metrics_str +
      "db_tenant_cpu_usage{tenant_id=\"" +
      tenant_id.to_string() +
      "\"} " +
      tenant.resource_usage.cpu_used.to_string() +
      "\n"

    metrics_str = metrics_str +
      "# HELP db_tenant_memory_usage Memory usage for tenant " +
      tenant_id.to_string() +
      "\n"
    metrics_str = metrics_str + "# TYPE db_tenant_memory_usage gauge\n"
    metrics_str = metrics_str +
      "db_tenant_memory_usage{tenant_id=\"" +
      tenant_id.to_string() +
      "\"} " +
      tenant.resource_usage.memory_used.to_string() +
      "\n"

    metrics_str = metrics_str +
      "# HELP db_tenant_storage_usage Storage usage for tenant " +
      tenant_id.to_string() +
      "\n"
    metrics_str = metrics_str + "# TYPE db_tenant_storage_usage gauge\n"
    metrics_str = metrics_str +
      "db_tenant_storage_usage{tenant_id=\"" +
      tenant_id.to_string() +
      "\"} " +
      tenant.resource_usage.storage_used.to_string() +
      "\n"
  }

  metrics_str
}

///|
/// 更新指标
pub fn TenantMonitor::update_metric(
  self : TenantMonitor,
  name : String,
  value : Double,
) -> Unit {
  self.metrics.set(name, value)
}

///|
/// 获取指标
pub fn TenantMonitor::get_metric(
  self : TenantMonitor,
  name : String,
) -> Double? {
  self.metrics.get(name)
}

///|
/// 创建计费计量器
pub fn create_billing_meter(tenant_manager : TenantManager) -> BillingMeter {
  BillingMeter::new(tenant_manager)
}

///|
/// 创建监控指标收集器
pub fn create_tenant_monitor(tenant_manager : TenantManager) -> TenantMonitor {
  TenantMonitor::new(tenant_manager)
}
