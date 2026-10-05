// 多租户模块测试
//
// 测试租户类型、状态机、生命周期、配额、隔离

test "test_tenant_status_transitions" {
  let sm = TenantStateMachine::new()
  assert_eq(sm.get_status(), Creating)

  // 测试合法转换
  assert_true(sm.can_transition_to(Active))
  let _ = sm.transition_to(Active)
  assert_eq(sm.get_status(), Active)

  // 测试非法转换
  assert_true(not sm.can_transition_to(Creating))
  let result = sm.transition_to(Creating)
  assert_true(result is Err)

  // 测试隔离
  let _ = sm.transition_to(Isolated)
  assert_eq(sm.get_status(), Isolated)

  // 测试恢复
  let _ = sm.transition_to(Active)
  assert_eq(sm.get_status(), Active)

  // 测试删除
  let _ = sm.transition_to(Deleting)
  assert_eq(sm.get_status(), Deleting)
}

test "test_tenant_manager_create_delete" {
  let manager = TenantManager::new()

  // 创建租户
  let tenant_id = manager.create_tenant("test_tenant", None)
  assert_true(tenant_id is Ok)

  match tenant_id {
    Ok(id) => {
      // 验证租户存在
      let tenant = manager.get_tenant(id)
      assert_true(tenant is Some)

      match tenant {
        Some(t) => {
          assert_eq(t.tenant_name, "test_tenant")
          assert_true(t.status == Active or t.status == Creating)
        }
        None => assert_true(false)
      }

      // 删除租户
      let result = manager.delete_tenant(id)
      assert_true(result is Ok)

      // 验证租户已删除
      let tenant2 = manager.get_tenant(id)
      assert_true(tenant2 is None)
    }
    Err(_) => assert_true(false)
  }
}

test "test_tenant_config_validation" {
  let manager = TenantManager::new()

  // 测试有效配置
  let valid_config = TenantConfig {
    cpu_quota: 4.0,
    memory_quota: 1073741824,
    storage_quota: 107374182400,
    connection_quota: 1000,
    throughput_quota: 104857600,
    max_namespaces: 100,
    max_tables: 1000,
    auto_scaling: false,
    isolation_level: IsolationLevel::Namespace,
  }

  let tenant_id = manager.create_tenant("valid_tenant", Some(valid_config))
  assert_true(tenant_id is Ok)

  // 测试无效配置（CPU 为 0）
  let invalid_config = TenantConfig {
    cpu_quota: 0.0,
    memory_quota: 1073741824,
    storage_quota: 107374182400,
    connection_quota: 1000,
    throughput_quota: 104857600,
    max_namespaces: 100,
    max_tables: 1000,
    auto_scaling: false,
    isolation_level: IsolationLevel::Namespace,
  }

  let tenant_id2 = manager.create_tenant("invalid_tenant", Some(invalid_config))
  assert_true(tenant_id2 is Err)
}

test "test_namespace_resolver" {
  let manager = TenantManager::new()
  let resolver = NamespaceResolver::new(manager)

  // 创建租户
  let tenant_id = manager.create_tenant("test_tenant", None)
  assert_true(tenant_id is Ok)

  match tenant_id {
    Ok(id) => {
      // 创建命名空间
      let result = resolver.create_namespace(id, "ns1")
      assert_true(result is Ok)

      // 获取命名空间
      let ns = resolver.resolve(id, "ns1")
      assert_true(ns is Ok)

      // 列出命名空间
      let namespaces = resolver.list_namespaces(id)
      assert_true(namespaces is Ok)

      match namespaces {
        Ok(nss) => assert_eq(nss.length(), 1)
        _ => ()
      }

      // 测试重复创建
      let result2 = resolver.create_namespace(id, "ns1")
      assert_true(result2 is Err)
    }
    Err(_) => assert_true(false)
  }
}

test "test_resource_quota" {
  let manager = TenantManager::new()
  let quota_manager = ResourceQuotaManager::new(manager)

  // 创建租户
  let tenant_id = manager.create_tenant("test_tenant", None)
  assert_true(tenant_id is Ok)

  match tenant_id {
    Ok(id) => {
      // 检查配额
      let result = quota_manager.check_quota(id, ResourceType::Memory, 524288000) // 500MB
      assert_true(result is Ok)

      match result {
        Ok(r) => assert_true(r.passed)
        Err(_) => assert_true(false)
      }

      // 记录使用量
      let record_result = quota_manager.record_usage(id, ResourceType::Memory, 524288000)
      assert_true(record_result is Ok)

      // 释放使用量
      let release_result = quota_manager.release_usage(id, ResourceType::Memory, 524288000)
      assert_true(release_result is Ok)
    }
    Err(_) => assert_true(false)
  }
}

test "test_isolation_guard" {
  let manager = TenantManager::new()
  let guard = IsolationGuard::new(manager)

  // 创建两个租户
  let tenant1 = manager.create_tenant("tenant1", None)
  let tenant2 = manager.create_tenant("tenant2", None)

  assert_true(tenant1 is Ok)
  assert_true(tenant2 is Ok)

  match (tenant1, tenant2) {
    (Ok(id1), Ok(id2)) => {
      // 测试跨租户访问
      let result = guard.check_cross_tenant_access(id1, id2)
      assert_true(result is Err)

      // 测试同租户访问
      let result2 = guard.check_cross_tenant_access(id1, id1)
      assert_true(result2 is Ok)
    }
    _ => assert_true(false)
  }
}

test "test_billing_meter" {
  let manager = TenantManager::new()
  let meter = BillingMeter::new(manager)

  // 创建租户
  let tenant_id = manager.create_tenant("test_tenant", None)
  assert_true(tenant_id is Ok)

  match tenant_id {
    Ok(id) => {
      // 计算计费
      let billing = meter.calculate_billing(id)
      assert_true(billing is Ok)

      // 生成报表
      let report = meter.generate_report(id)
      assert_true(report is Ok)

      match report {
        Ok(r) => assert_true(r.length() > 0)
        Err(_) => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

test "test_tenant_monitor" {
  let manager = TenantManager::new()
  let monitor = TenantMonitor::new(manager)

  // 创建租户
  let tenant_id = manager.create_tenant("test_tenant", None)
  assert_true(tenant_id is Ok)

  // 暴露指标
  let metrics = monitor.expose_metrics()
  assert_true(metrics.length() > 0)
  assert_true(metrics.contains("db_tenant_count"))
}

test "test_tenant_list" {
  let manager = TenantManager::new()

  // 创建多个租户
  let _ = manager.create_tenant("tenant1", None)
  let _ = manager.create_tenant("tenant2", None)
  let _ = manager.create_tenant("tenant3", None)

  // 列出所有租户
  let tenants = manager.list_tenants()
  assert_eq(tenants.length(), 3)
}