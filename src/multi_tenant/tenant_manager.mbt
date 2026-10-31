// 租户管理器模块
//
// 实现租户生命周期管理、命名空间解析

///|
/// 租户状态机
pub(all) struct TenantStateMachine {
  /// 当前状态
  mut status : TenantStatus
  /// 状态转换历史
  mut state_history : Array[(Int32, TenantStatus)]
}

///|
/// 创建租户状态机
pub fn TenantStateMachine::new() -> TenantStateMachine {
  { status: Creating, state_history: [], }
}

///|
/// 转换状态
pub fn TenantStateMachine::transition_to(
  self : TenantStateMachine,
  new_status : TenantStatus,
) -> Result[Unit, TenantError] {
  if !self.can_transition_to(new_status) {
    return Err(Tenant_Invalid_State)
  }

  self.state_history.push((0, new_status))
  self.status = new_status

  Ok(())
}

///|
/// 获取当前状态
pub fn TenantStateMachine::get_status(
  self : TenantStateMachine,
) -> TenantStatus {
  self.status
}

///|
/// 检查是否可以转换到目标状态
pub fn TenantStateMachine::can_transition_to(
  self : TenantStateMachine,
  new_status : TenantStatus,
) -> Bool {
  match (self.status, new_status) {
    (Creating, Active) => true
    (Creating, Deleting) => true
    (Active, Isolated) => true
    (Active, Maintenance) => true
    (Active, Deleting) => true
    (Isolated, Active) => true
    (Isolated, Deleting) => true
    (Maintenance, Active) => true
    (Maintenance, Deleting) => true
    (Deleting, Deleted) => true
    // 保持当前状态
    (s1, s2) if s1 == s2 => true
    _ => false
  }
}

///|
/// 判断是否活跃
pub fn TenantStateMachine::is_active(self : TenantStateMachine) -> Bool {
  self.status == Active
}

///|
/// 判断是否已删除
pub fn TenantStateMachine::is_deleted(self : TenantStateMachine) -> Bool {
  self.status == Deleted
}

///|
/// 租户管理器
pub(all) struct TenantManager {
  /// 租户映射
  mut tenants : Map[String, Tenant]
  /// 租户状态机映射
  mut tenant_state_machines : Map[String, TenantStateMachine]
  /// 默认配置
  default_config : TenantConfig
  /// 下一个租户 ID
  mut next_id : Int32
}

///|
/// 创建租户管理器
pub fn TenantManager::new() -> TenantManager {
  {
    tenants: Map([]),
    tenant_state_machines: Map([]),
    default_config: TenantConfig::default(),
    next_id: 0,
  }
}

///|
/// 创建租户
pub fn TenantManager::create_tenant(
  self : TenantManager,
  tenant_name : String,
  config : TenantConfig?,
) -> Result[String, TenantError] {
  // 生成租户 ID
  let tenant_id = "tenant_" + self.next_id.to_string()
  self.next_id = self.next_id + 1

  // 检查租户是否已存在
  if self.tenants.contains(tenant_id.to_string()) {
    return Err(Tenant_Already_Exists)
  }

  // 使用配置或默认配置
  let tenant_config = match config {
    Some(c) => c
    None => { ..self.default_config, }
  }

  // 验证配置
  if !self.validate_config(tenant_config) {
    return Err(Invalid_Config)
  }

  // 创建命名空间
  let namespaces : Map[String, Namespace] = Map([])

  // 创建租户
  let tenant = Tenant::{
    tenant_id: tenant_id.to_string(),
    tenant_name,
    status: Creating,
    config: tenant_config,
    namespaces,
    resource_usage: ResourceUsage::default(),
    created_at: 0,
    updated_at: 0,
    deleted_at: None,
  }

  // 创建状态机，并转换到 Active 状态
  let state_machine = TenantStateMachine::new()
  let _ = state_machine.transition_to(Active)

  // 保存租户
  self.tenants.set(tenant_id.to_string(), tenant)
  self.tenant_state_machines.set(tenant_id, state_machine)

  Ok(tenant_id)
}

///|
/// 删除租户
pub fn TenantManager::delete_tenant(
  self : TenantManager,
  tenant_id : String,
) -> Result[Unit, TenantError] {
  // 检查租户是否存在
  if !self.tenants.contains(tenant_id.to_string()) {
    return Err(Tenant_Not_Found)
  }

  // 获取状态机
  let state_machine = match
    self.tenant_state_machines.get(tenant_id.to_string()) {
    Some(sm) => sm
    None => return Err(Tenant_Invalid_State)
  }

  // 检查是否可以删除
  if !state_machine.can_transition_to(Deleting) {
    return Err(Tenant_Invalid_State)
  }

  // 转换到 Deleting 状态
  let _ = state_machine.transition_to(Deleting)

  // 清理租户资源
  self.tenants.remove(tenant_id.to_string())
  self.tenant_state_machines.remove(tenant_id)

  Ok(())
}

///|
/// 获取租户信息
pub fn TenantManager::get_tenant(
  self : TenantManager,
  tenant_id : String,
) -> Tenant? {
  self.tenants.get(tenant_id)
}

///|
/// 获取所有租户
pub fn TenantManager::list_tenants(self : TenantManager) -> Array[Tenant] {
  let result : Array[Tenant] = []
  for (_, tenant) in self.tenants {
    result.push(tenant)
  }
  result
}

///|
/// 更新租户配置
pub fn TenantManager::update_tenant_config(
  self : TenantManager,
  tenant_id : String,
  config : TenantConfig,
) -> Result[Unit, TenantError] {
  // 检查租户是否存在
  let tenant = match self.tenants.get(tenant_id) {
    Some(t) => t
    None => return Err(Tenant_Not_Found)
  }

  // 验证配置
  if !self.validate_config(config) {
    return Err(Invalid_Config)
  }

  // 更新配置
  tenant.config = config
  tenant.updated_at = 0

  Ok(())
}

///|
/// 验证配置
fn TenantManager::validate_config(
  self : TenantManager,
  config : TenantConfig,
) -> Bool {
  let _ = self
  if config.cpu_quota <= 0.0 {
    return false
  }
  if config.memory_quota <= 0 {
    return false
  }
  if config.storage_quota <= 0 {
    return false
  }
  if config.connection_quota <= 0 {
    return false
  }
  if config.max_namespaces <= 0 {
    return false
  }
  if config.max_tables <= 0 {
    return false
  }
  true
}

///|
/// 命名空间解析器
pub(all) struct NamespaceResolver {
  /// 租户管理器
  tenant_manager : TenantManager
}

///|
/// 创建命名空间解析器
pub fn NamespaceResolver::new(
  tenant_manager : TenantManager,
) -> NamespaceResolver {
  { tenant_manager, }
}

///|
/// 解析命名空间
pub fn NamespaceResolver::resolve(
  self : NamespaceResolver,
  tenant_id : String,
  namespace_id : String,
) -> Result[Namespace, TenantError] {
  // 获取租户
  let tenant = match self.tenant_manager.get_tenant(tenant_id) {
    Some(t) => t
    None => return Err(Tenant_Not_Found)
  }

  // 获取命名空间
  match tenant.namespaces.get(namespace_id) {
    Some(ns) => Ok({ ..ns, })
    None => Err(Namespace_Not_Found)
  }
}

///|
/// 创建命名空间
pub fn NamespaceResolver::create_namespace(
  self : NamespaceResolver,
  tenant_id : String,
  namespace_id : String,
) -> Result[Unit, TenantError] {
  // 获取租户
  let tenant = match self.tenant_manager.get_tenant(tenant_id.to_string()) {
    Some(t) => t
    None => return Err(Tenant_Not_Found)
  }

  // 检查命名空间是否已存在
  if tenant.namespaces.contains(namespace_id.to_string()) {
    return Err(Namespace_Already_Exists)
  }

  // 检查命名空间数量限制
  if tenant.namespaces.length() >= tenant.config.max_namespaces {
    return Err(Quota_Exceeded)
  }

  // 创建命名空间
  let ns = Namespace::{
    namespace_id: namespace_id.to_string(),
    tenant_id: tenant_id.to_string(),
    tables: Map([]),
    feature_tables: Map([]),
    created_at: 0,
    updated_at: 0,
  }

  // 添加命名空间
  tenant.namespaces.set(namespace_id, ns)
  tenant.updated_at = 0

  Ok(())
}

///|
/// 获取租户的命名空间列表
pub fn NamespaceResolver::list_namespaces(
  self : NamespaceResolver,
  tenant_id : String,
) -> Result[Array[Namespace], TenantError] {
  // 获取租户
  let tenant = match self.tenant_manager.get_tenant(tenant_id) {
    Some(t) => t
    None => return Err(Tenant_Not_Found)
  }

  let result : Array[Namespace] = []
  for (_, ns) in tenant.namespaces {
    result.push(ns)
  }

  Ok(result)
}

///|
/// 创建默认租户管理器
pub fn create_tenant_manager() -> TenantManager {
  TenantManager::new()
}

///|
/// 创建命名空间解析器
pub fn create_namespace_resolver(
  tenant_manager : TenantManager,
) -> NamespaceResolver {
  NamespaceResolver::new(tenant_manager)
}
