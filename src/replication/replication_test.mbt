// 跨集群复制模块测试
//
// 测试复制任务、冲突检测、向量时钟

///|
/// 构造测试用集群信息
fn make_cluster(id : String, addr : String) -> @replication.ClusterInfo {
  @replication.ClusterInfo::{
    cluster_id: id,
    cluster_name: "Cluster " + id,
    cluster_addr: addr,
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }
}

///|
/// 构造测试用复制任务配置
fn make_task_config(
  name : String,
  topology : @replication.ReplicationTopology,
  mode : @replication.ReplicationMode,
  strategy : @replication.ConflictResolutionStrategy,
) -> @replication.ReplicationTaskConfig {
  @replication.ReplicationTaskConfig::{
    task_name: name,
    source_cluster_id: "cluster1".to_string(),
    target_cluster_id: "cluster2".to_string(),
    topology,
    mode,
    conflict_strategy: strategy,
    batch_size: 1000,
    replication_interval_ms: 1000,
    enable_checkpoint: true,
    max_retries: 3,
    retry_interval_ms: 5000,
  }
}

///|
test "test_replication_types" {
  // 测试复制拓扑
  assert_eq(@replication.Primary_Replica, @replication.Primary_Replica)
  assert_true(@replication.Multi_Master != @replication.Primary_Replica)

  // 测试复制模式
  assert_eq(@replication.Sync, @replication.Sync)
  assert_true(@replication.Async != @replication.Sync)

  // 测试复制状态
  assert_eq(@replication.Running, @replication.Running)
  assert_true(@replication.Error != @replication.Running)

  // 测试冲突解决策略
  assert_eq(@replication.Timestamp, @replication.Timestamp)
  assert_true(@replication.Version != @replication.Timestamp)
}

///|
test "test_replication_error" {
  let err = @replication.Task_Already_Exists
  assert_eq(err.code(), 5001)
  assert_true(err.message().length() > 0)

  let err2 = @replication.Task_Not_Found
  assert_eq(err2.code(), 5002)

  let err3 = @replication.Internal_Error("test error")
  assert_eq(err3.code(), 5099)
  assert_true(err3.message().contains("test error"))
}

///|
test "test_vector_clock" {
  let vc = @replication.VectorClock::new()

  // 更新时钟
  vc.update("node1", 100)
  vc.update("node2", 200)

  // 获取时钟值
  assert_eq(vc.get("node1"), 100)
  assert_eq(vc.get("node2"), 200)
  assert_eq(vc.get("node3"), 0)
}

///|
test "test_vector_clock_compare" {
  let vc1 = @replication.VectorClock::new()
  let vc2 = @replication.VectorClock::new()

  vc1.update("node1", 100)
  vc2.update("node1", 200)

  // vc1 应该在 vc2 之前
  let order = vc1.compare(vc2)
  assert_eq(order, @replication.Before)
  assert_eq(vc2.compare(vc1), @replication.After)
}

///|
test "test_vector_clock_compare_missing_components" {
  // 空时钟应视为最小，缺失分量按 0 处理
  let empty = @replication.VectorClock::new()
  let filled = @replication.VectorClock::new()
  filled.update("node1", 5)

  assert_eq(empty.compare(filled), @replication.Before)
  assert_eq(filled.compare(empty), @replication.After)

  // 各自持有对方缺失的节点，互不可比，应为并发
  let left = @replication.VectorClock::new()
  left.update("node1", 5)
  let right = @replication.VectorClock::new()
  right.update("node2", 5)

  assert_eq(left.compare(right), @replication.Concurrent)
  assert_eq(right.compare(left), @replication.Concurrent)
}

///|
test "test_version_vector" {
  let vv = @replication.VersionVector::new()

  // 增加版本
  let v1 = vv.increment("node1")
  assert_eq(v1, 1)

  let v2 = vv.increment("node1")
  assert_eq(v2, 2)

  let v3 = vv.increment("node2")
  assert_eq(v3, 1)

  // 获取版本
  assert_eq(vv.get("node1"), 2)
  assert_eq(vv.get("node2"), 1)
}

///|
test "test_version_vector_merge" {
  let vv1 = @replication.VersionVector::new()
  let vv2 = @replication.VersionVector::new()

  vv1.update("node1", 100)
  vv2.update("node2", 200)

  vv1.merge(vv2)

  assert_eq(vv1.get("node1"), 100)
  assert_eq(vv1.get("node2"), 200)
}

///|
test "test_create_replication_task" {
  let manager = @replication.ReplicationManager::new()

  // 注册集群
  let _ = manager.register_cluster(make_cluster("cluster1", "127.0.0.1:8080"))
  let _ = manager.register_cluster(make_cluster("cluster2", "127.0.0.1:8081"))

  // 创建任务
  let config = make_task_config(
    "test_task",
    @replication.Primary_Replica,
    @replication.Async,
    @replication.Timestamp,
  )

  let task_id = manager.create_replication_task(config)
  assert_true(task_id is Ok(_))

  match task_id {
    Ok(id) => {
      assert_true(id.length() > 0)

      // 验证任务存在
      let task = manager.get_task_status(id)
      assert_true(task is Some(_))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_create_task_nonexistent_cluster" {
  let manager = @replication.ReplicationManager::new()

  let base_config = make_task_config(
    "invalid_task",
    @replication.Primary_Replica,
    @replication.Async,
    @replication.Timestamp,
  )
  let config = { ..base_config, source_cluster_id: "nonexistent".to_string(), }

  let task_id = manager.create_replication_task(config)
  assert_true(task_id is Err(_))

  match task_id {
    Err(@replication.Cluster_Not_Found) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "test_duplicate_task_name" {
  let manager = @replication.ReplicationManager::new()

  // 注册集群
  let _ = manager.register_cluster(make_cluster("cluster1", "127.0.0.1:8080"))
  let _ = manager.register_cluster(make_cluster("cluster2", "127.0.0.1:8081"))

  let config = make_task_config(
    "duplicate_task",
    @replication.Primary_Replica,
    @replication.Async,
    @replication.Timestamp,
  )

  // 创建第一个任务
  let result1 = manager.create_replication_task({ ..config, })
  assert_true(result1 is Ok(_))

  // 创建重复任务
  let result2 = manager.create_replication_task(config)
  assert_true(result2 is Err(_))

  match result2 {
    Err(@replication.Task_Already_Exists) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "test_list_tasks" {
  let manager = @replication.ReplicationManager::new()

  // 注册集群
  let _ = manager.register_cluster(make_cluster("cluster1", "127.0.0.1:8080"))
  let _ = manager.register_cluster(make_cluster("cluster2", "127.0.0.1:8081"))

  // 创建多个任务
  let config1 = make_task_config(
    "task1",
    @replication.Primary_Replica,
    @replication.Async,
    @replication.Timestamp,
  )

  let base_config2 = make_task_config(
    "task2",
    @replication.Multi_Master,
    @replication.Sync,
    @replication.Version,
  )
  let config2 = {
    ..base_config2,
    batch_size: 500,
    replication_interval_ms: 2000,
    max_retries: 5,
    retry_interval_ms: 3000,
  }

  let _ = manager.create_replication_task(config1)
  let _ = manager.create_replication_task(config2)

  // 列出任务
  let tasks = manager.list_tasks()
  assert_eq(tasks.length(), 2)
}

///|
test "test_delete_task" {
  let manager = @replication.ReplicationManager::new()

  // 注册集群
  let _ = manager.register_cluster(make_cluster("cluster1", "127.0.0.1:8080"))
  let _ = manager.register_cluster(make_cluster("cluster2", "127.0.0.1:8081"))

  let config = make_task_config(
    "delete_task",
    @replication.Primary_Replica,
    @replication.Async,
    @replication.Timestamp,
  )

  let task_id = manager.create_replication_task(config)
  assert_true(task_id is Ok(_))

  match task_id {
    Ok(id) => {
      // 删除任务
      let result = manager.delete_replication_task(id)
      assert_true(result is Ok(_))

      // 验证任务已删除
      let task = manager.get_task_status(id)
      assert_true(task is None)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_conflict_detection" {
  let detector = @replication.ConflictDetector::new(@replication.Timestamp)

  // 检测相同值（无冲突）
  let has_conflict = detector.detect(
    "key1",
    @realtime_db.Str("value1"),
    1000,
    "node1",
    @realtime_db.Str("value1"),
    1000,
    "node2",
  )
  assert_true(!has_conflict)

  // 检测不同值（有冲突）
  let has_conflict2 = detector.detect(
    "key2",
    @realtime_db.Str("value1"),
    1000,
    "node1",
    @realtime_db.Str("value2"),
    1000,
    "node2",
  )
  assert_true(has_conflict2)
}

///|
test "test_conflict_resolution_timestamp" {
  let detector = @replication.ConflictDetector::new(@replication.Timestamp)

  // 源时间戳更新，选择源值
  let result = detector.resolve(
    "key1",
    @realtime_db.Str("source_value"),
    2000,
    1,
    "node1",
    @realtime_db.Str("target_value"),
    1000,
    1,
    "node2",
  )

  match result.resolved_value {
    @realtime_db.Str(v) => assert_eq(v, "source_value")
    _ => assert_true(false)
  }
}

///|
test "test_conflict_resolution_version" {
  let detector = @replication.ConflictDetector::new(@replication.Version)

  // 源版本更新，选择源值
  let result = detector.resolve(
    "key1",
    @realtime_db.Str("source_value"),
    1000,
    2,
    "node1",
    @realtime_db.Str("target_value"),
    1000,
    1,
    "node2",
  )

  match result.resolved_value {
    @realtime_db.Str(v) => assert_eq(v, "source_value")
    _ => assert_true(false)
  }
}

///|
test "test_conflict_resolver" {
  let resolver = @replication.ConflictResolver::new(@replication.Timestamp)

  // 设置表级策略
  resolver.set_strategy("users", @replication.Version)

  // 获取策略
  let strategy = resolver.get_strategy("users")
  assert_eq(strategy, @replication.Version)

  // 获取默认策略
  let default_strategy = resolver.get_strategy("orders")
  assert_eq(default_strategy, @replication.Timestamp)
}

///|
test "test_cluster_registration" {
  let manager = @replication.ReplicationManager::new()

  let cluster = make_cluster("test_cluster", "127.0.0.1:8080")

  // 注册集群
  let result = manager.register_cluster(cluster)
  assert_true(result is Ok(_))

  // 获取集群
  let retrieved = manager.get_cluster("test_cluster")
  assert_true(retrieved is Some(_))

  match retrieved {
    Some(c) => assert_eq(c.cluster_name, "Cluster test_cluster")
    None => assert_true(false)
  }
}

///|
test "test_list_clusters" {
  let manager = @replication.ReplicationManager::new()

  let _ = manager.register_cluster(make_cluster("cluster1", "127.0.0.1:8080"))
  let _ = manager.register_cluster(make_cluster("cluster2", "127.0.0.1:8081"))

  let clusters = manager.list_clusters()
  assert_eq(clusters.length(), 2)
}
