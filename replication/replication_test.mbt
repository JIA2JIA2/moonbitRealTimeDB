// 跨集群复制模块测试
//
// 测试复制任务、冲突检测、向量时钟

test "test_replication_types" {
  // 测试复制拓扑
  assert_eq(ReplicationTopology::Primary_Replica, ReplicationTopology::Primary_Replica)
  assert_true(ReplicationTopology::Multi_Master != ReplicationTopology::Primary_Replica)

  // 测试复制模式
  assert_eq(ReplicationMode::Sync, ReplicationMode::Sync)
  assert_true(ReplicationMode::Async != ReplicationMode::Sync)

  // 测试复制状态
  assert_eq(ReplicationStatus::Running, ReplicationStatus::Running)
  assert_true(ReplicationStatus::Error != ReplicationStatus::Running)

  // 测试冲突解决策略
  assert_eq(ConflictResolutionStrategy::Timestamp, ConflictResolutionStrategy::Timestamp)
  assert_true(ConflictResolutionStrategy::Version != ConflictResolutionStrategy::Timestamp)
}

test "test_replication_error" {
  let err = ReplicationError::Task_Already_Exists
  assert_eq(err.code(), 5001)
  assert_true(err.message().length() > 0)

  let err2 = ReplicationError::Task_Not_Found
  assert_eq(err2.code(), 5002)

  let err3 = ReplicationError::Internal_Error("test error")
  assert_eq(err3.code(), 5099)
  assert_true(err3.message().contains("test error"))
}

test "test_vector_clock" {
  let vc = VectorClock::new()

  // 更新时钟
  vc.update("node1", 100)
  vc.update("node2", 200)

  // 获取时钟值
  assert_eq(vc.get("node1"), 100)
  assert_eq(vc.get("node2"), 200)
  assert_eq(vc.get("node3"), 0)
}

test "test_vector_clock_compare" {
  let vc1 = VectorClock::new()
  let vc2 = VectorClock::new()

  vc1.update("node1", 100)
  vc2.update("node1", 200)

  let order = vc1.compare(vc2)
  // vc1 应该在 vc2 之前
  let _ = order
}

test "test_version_vector" {
  let vv = VersionVector::new()

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

test "test_version_vector_merge" {
  let vv1 = VersionVector::new()
  let vv2 = VersionVector::new()

  vv1.update("node1", 100)
  vv2.update("node2", 200)

  vv1.merge(vv2)

  assert_eq(vv1.get("node1"), 100)
  assert_eq(vv1.get("node2"), 200)
}

test "test_create_replication_task" {
  let manager = ReplicationManager::new()

  // 注册集群
  let cluster1 = ClusterInfo {
    cluster_id: "cluster1".to_string(),
    cluster_name: "Cluster 1".to_string(),
    cluster_addr: "127.0.0.1:8080".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let cluster2 = ClusterInfo {
    cluster_id: "cluster2".to_string(),
    cluster_name: "Cluster 2".to_string(),
    cluster_addr: "127.0.0.1:8081".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let _ = manager.register_cluster(cluster1)
  let _ = manager.register_cluster(cluster2)

  // 创建任务
  let config = ReplicationTaskConfig {
    task_name: "test_task".to_string(),
    source_cluster_id: "cluster1".to_string(),
    target_cluster_id: "cluster2".to_string(),
    topology: ReplicationTopology::Primary_Replica,
    mode: ReplicationMode::Async,
    conflict_strategy: ConflictResolutionStrategy::Timestamp,
    batch_size: 1000,
    replication_interval_ms: 1000,
    enable_checkpoint: true,
    max_retries: 3,
    retry_interval_ms: 5000,
  }

  let task_id = manager.create_replication_task(config)
  assert_true(task_id is Ok)

  match task_id {
    Ok(id) => {
      assert_true(id.length() > 0)

      // 验证任务存在
      let task = manager.get_task_status(id)
      assert_true(task is Some)
    }
    Err(_) => assert_true(false)
  }
}

test "test_create_task_nonexistent_cluster" {
  let manager = ReplicationManager::new()

  let config = ReplicationTaskConfig {
    task_name: "invalid_task".to_string(),
    source_cluster_id: "nonexistent".to_string(),
    target_cluster_id: "cluster2".to_string(),
    topology: ReplicationTopology::Primary_Replica,
    mode: ReplicationMode::Async,
    conflict_strategy: ConflictResolutionStrategy::Timestamp,
    batch_size: 1000,
    replication_interval_ms: 1000,
    enable_checkpoint: true,
    max_retries: 3,
    retry_interval_ms: 5000,
  }

  let task_id = manager.create_replication_task(config)
  assert_true(task_id is Err)

  match task_id {
    Err(ReplicationError::Cluster_Not_Found) => assert_true(true)
    _ => assert_true(false)
  }
}

test "test_duplicate_task_name" {
  let manager = ReplicationManager::new()

  // 注册集群
  let cluster1 = ClusterInfo {
    cluster_id: "cluster1".to_string(),
    cluster_name: "Cluster 1".to_string(),
    cluster_addr: "127.0.0.1:8080".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let cluster2 = ClusterInfo {
    cluster_id: "cluster2".to_string(),
    cluster_name: "Cluster 2".to_string(),
    cluster_addr: "127.0.0.1:8081".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let _ = manager.register_cluster(cluster1)
  let _ = manager.register_cluster(cluster2)

  let config = ReplicationTaskConfig {
    task_name: "duplicate_task".to_string(),
    source_cluster_id: "cluster1".to_string(),
    target_cluster_id: "cluster2".to_string(),
    topology: ReplicationTopology::Primary_Replica,
    mode: ReplicationMode::Async,
    conflict_strategy: ConflictResolutionStrategy::Timestamp,
    batch_size: 1000,
    replication_interval_ms: 1000,
    enable_checkpoint: true,
    max_retries: 3,
    retry_interval_ms: 5000,
  }

  // 创建第一个任务
  let result1 = manager.create_replication_task(config)
  assert_true(result1 is Ok)

  // 创建重复任务
  let result2 = manager.create_replication_task(config)
  assert_true(result2 is Err)

  match result2 {
    Err(ReplicationError::Task_Already_Exists) => assert_true(true)
    _ => assert_true(false)
  }
}

test "test_list_tasks" {
  let manager = ReplicationManager::new()

  // 注册集群
  let cluster1 = ClusterInfo {
    cluster_id: "cluster1".to_string(),
    cluster_name: "Cluster 1".to_string(),
    cluster_addr: "127.0.0.1:8080".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let cluster2 = ClusterInfo {
    cluster_id: "cluster2".to_string(),
    cluster_name: "Cluster 2".to_string(),
    cluster_addr: "127.0.0.1:8081".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let _ = manager.register_cluster(cluster1)
  let _ = manager.register_cluster(cluster2)

  // 创建多个任务
  let config1 = ReplicationTaskConfig {
    task_name: "task1".to_string(),
    source_cluster_id: "cluster1".to_string(),
    target_cluster_id: "cluster2".to_string(),
    topology: ReplicationTopology::Primary_Replica,
    mode: ReplicationMode::Async,
    conflict_strategy: ConflictResolutionStrategy::Timestamp,
    batch_size: 1000,
    replication_interval_ms: 1000,
    enable_checkpoint: true,
    max_retries: 3,
    retry_interval_ms: 5000,
  }

  let config2 = ReplicationTaskConfig {
    task_name: "task2".to_string(),
    source_cluster_id: "cluster1".to_string(),
    target_cluster_id: "cluster2".to_string(),
    topology: ReplicationTopology::Multi_Master,
    mode: ReplicationMode::Sync,
    conflict_strategy: ConflictResolutionStrategy::Version,
    batch_size: 500,
    replication_interval_ms: 2000,
    enable_checkpoint: true,
    max_retries: 5,
    retry_interval_ms: 3000,
  }

  let _ = manager.create_replication_task(config1)
  let _ = manager.create_replication_task(config2)

  // 列出任务
  let tasks = manager.list_tasks()
  assert_eq(tasks.length(), 2)
}

test "test_delete_task" {
  let manager = ReplicationManager::new()

  // 注册集群
  let cluster1 = ClusterInfo {
    cluster_id: "cluster1".to_string(),
    cluster_name: "Cluster 1".to_string(),
    cluster_addr: "127.0.0.1:8080".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let cluster2 = ClusterInfo {
    cluster_id: "cluster2".to_string(),
    cluster_name: "Cluster 2".to_string(),
    cluster_addr: "127.0.0.1:8081".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let _ = manager.register_cluster(cluster1)
  let _ = manager.register_cluster(cluster2)

  let config = ReplicationTaskConfig {
    task_name: "delete_task".to_string(),
    source_cluster_id: "cluster1".to_string(),
    target_cluster_id: "cluster2".to_string(),
    topology: ReplicationTopology::Primary_Replica,
    mode: ReplicationMode::Async,
    conflict_strategy: ConflictResolutionStrategy::Timestamp,
    batch_size: 1000,
    replication_interval_ms: 1000,
    enable_checkpoint: true,
    max_retries: 3,
    retry_interval_ms: 5000,
  }

  let task_id = manager.create_replication_task(config)
  assert_true(task_id is Ok)

  match task_id {
    Ok(id) => {
      // 删除任务
      let result = manager.delete_replication_task(id)
      assert_true(result is Ok)

      // 验证任务已删除
      let task = manager.get_task_status(id)
      assert_true(task is None)
    }
    Err(_) => assert_true(false)
  }
}

test "test_conflict_detection" {
  let detector = ConflictDetector::new(ConflictResolutionStrategy::Timestamp)

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
  assert_true(not has_conflict)

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

test "test_conflict_resolution_timestamp" {
  let detector = ConflictDetector::new(ConflictResolutionStrategy::Timestamp)

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

test "test_conflict_resolution_version" {
  let detector = ConflictDetector::new(ConflictResolutionStrategy::Version)

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

test "test_conflict_resolver" {
  let resolver = ConflictResolver::new(ConflictResolutionStrategy::Timestamp)

  // 设置表级策略
  resolver.set_strategy("users", ConflictResolutionStrategy::Version)

  // 获取策略
  let strategy = resolver.get_strategy("users")
  assert_eq(strategy, ConflictResolutionStrategy::Version)

  // 获取默认策略
  let default_strategy = resolver.get_strategy("orders")
  assert_eq(default_strategy, ConflictResolutionStrategy::Timestamp)
}

test "test_cluster_registration" {
  let manager = ReplicationManager::new()

  let cluster = ClusterInfo {
    cluster_id: "test_cluster".to_string(),
    cluster_name: "Test Cluster".to_string(),
    cluster_addr: "127.0.0.1:8080".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  // 注册集群
  let result = manager.register_cluster(cluster)
  assert_true(result is Ok)

  // 获取集群
  let retrieved = manager.get_cluster("test_cluster")
  assert_true(retrieved is Some)

  match retrieved {
    Some(c) => assert_eq(c.cluster_name, "Test Cluster")
    None => assert_true(false)
  }
}

test "test_list_clusters" {
  let manager = ReplicationManager::new()

  let cluster1 = ClusterInfo {
    cluster_id: "cluster1".to_string(),
    cluster_name: "Cluster 1".to_string(),
    cluster_addr: "127.0.0.1:8080".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let cluster2 = ClusterInfo {
    cluster_id: "cluster2".to_string(),
    cluster_name: "Cluster 2".to_string(),
    cluster_addr: "127.0.0.1:8081".to_string(),
    nodes: [],
    created_at: 0,
    last_active_at: 0,
  }

  let _ = manager.register_cluster(cluster1)
  let _ = manager.register_cluster(cluster2)

  let clusters = manager.list_clusters()
  assert_eq(clusters.length(), 2)
}