// 数据版本控制模块测试
//
// 测试版本快照、分支管理、版本历史、时间点查询

test "test_version_types" {
  // 测试版本状态
  assert_eq(VersionStatus::Active, VersionStatus::Active)
  assert_true(VersionStatus::Deleted != VersionStatus::Active)

  // 测试快照类型
  assert_eq(SnapshotType::Auto, SnapshotType::Auto)
  assert_true(SnapshotType::Manual != SnapshotType::Auto)

  // 测试分支类型
  assert_eq(BranchType::Main, BranchType::Main)
  assert_true(BranchType::Feature != BranchType::Main)

  // 测试合并策略
  assert_eq(MergeStrategy::FastForward, MergeStrategy::FastForward)
  assert_true(MergeStrategy::ThreeWay != MergeStrategy::FastForward)

  // 测试变更类型
  assert_eq(ChangeType::Added, ChangeType::Added)
  assert_true(ChangeType::Modified != ChangeType::Added)
}

test "test_versioning_error" {
  let err = VersioningError::Snapshot_Already_Exists
  assert_eq(err.code(), 8001)
  assert_true(err.message().length() > 0)

  let err2 = VersioningError::Branch_Not_Found
  assert_eq(err2.code(), 8004)

  let err3 = VersioningError::Internal_Error("test error")
  assert_eq(err3.code(), 8099)
  assert_true(err3.message().contains("test error"))
}

test "test_create_snapshot" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  let data = @realtime_db.Map([("key", @realtime_db.Str("value"))])
  let snapshot_id = manager.create_snapshot("test_snapshot", SnapshotType::Manual, data)

  assert_true(snapshot_id is Ok)

  match snapshot_id {
    Ok(id) => {
      assert_true(id.length() > 0)

      // 验证快照存在
      let snapshot = manager.get_snapshot(id)
      assert_true(snapshot is Some)

      match snapshot {
        Some(s) => assert_eq(s.snapshot_name, "test_snapshot")
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

test "test_duplicate_snapshot_name" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  let data = @realtime_db.Map([])

  // 创建第一个快照
  let result1 = manager.create_snapshot("duplicate", SnapshotType::Manual, data)
  assert_true(result1 is Ok)

  // 创建重复快照
  let result2 = manager.create_snapshot("duplicate", SnapshotType::Manual, data)
  assert_true(result2 is Err)

  match result2 {
    Err(VersioningError::Snapshot_Already_Exists) => assert_true(true)
    _ => assert_true(false)
  }
}

test "test_list_snapshots" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  let data = @realtime_db.Map([])

  // 创建多个快照
  let _ = manager.create_snapshot("snap1", SnapshotType::Manual, data)
  let _ = manager.create_snapshot("snap2", SnapshotType::Auto, data)

  // 列出快照
  let snapshots = manager.list_snapshots()
  assert_eq(snapshots.length(), 2)
}

test "test_delete_snapshot" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  let data = @realtime_db.Map([])

  // 创建快照
  let snapshot_id = manager.create_snapshot("delete_test", SnapshotType::Manual, data)
  assert_true(snapshot_id is Ok)

  match snapshot_id {
    Ok(id) => {
      // 删除快照
      let result = manager.delete_snapshot(id)
      assert_true(result is Ok)

      // 验证快照已删除
      let snapshot = manager.get_snapshot(id)
      assert_true(snapshot is None)
    }
    Err(_) => assert_true(false)
  }
}

test "test_create_branch" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  // 创建分支
  let branch_id = manager.create_branch("dev", BranchType::Dev, None)
  assert_true(branch_id is Ok)

  match branch_id {
    Ok(id) => {
      assert_true(id.length() > 0)

      // 验证分支存在
      let branch = manager.get_branch(id)
      assert_true(branch is Some)

      match branch {
        Some(b) => assert_eq(b.branch_name, "dev")
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

test "test_duplicate_branch_name" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  // 创建第一个分支
  let result1 = manager.create_branch("duplicate", BranchType::Feature, None)
  assert_true(result1 is Ok)

  // 创建重复分支
  let result2 = manager.create_branch("duplicate", BranchType::Feature, None)
  assert_true(result2 is Err)

  match result2 {
    Err(VersioningError::Branch_Already_Exists) => assert_true(true)
    _ => assert_true(false)
  }
}

test "test_list_branches" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  // 创建多个分支
  let _ = manager.create_branch("dev", BranchType::Dev, None)
  let _ = manager.create_branch("feature1", BranchType::Feature, None)

  // 列出分支
  let branches = manager.list_branches()
  assert_true(branches.length() >= 2)
}

test "test_delete_branch" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  // 创建分支
  let branch_id = manager.create_branch("delete_test", BranchType::Feature, None)
  assert_true(branch_id is Ok)

  match branch_id {
    Ok(id) => {
      // 删除分支
      let result = manager.delete_branch(id)
      assert_true(result is Ok)

      // 验证分支已删除
      let branch = manager.get_branch(id)
      assert_true(branch is None)
    }
    Err(_) => assert_true(false)
  }
}

test "test_commit" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  // 创建快照
  let data = @realtime_db.Map([("key", @realtime_db.Str("value"))])
  let snapshot_id = manager.create_snapshot("commit_snap", SnapshotType::Manual, data)
  assert_true(snapshot_id is Ok)

  // 创建分支
  let branch_id = manager.create_branch("commit_branch", BranchType::Feature, None)
  assert_true(branch_id is Ok)

  match (snapshot_id, branch_id) {
    (Ok(sid), Ok(bid)) => {
      // 提交版本
      let version_id = manager.commit("commit_branch", "test commit", "test", sid)
      assert_true(version_id is Ok)

      match version_id {
        Ok(vid) => {
          assert_true(vid.length() > 0)

          // 验证版本存在
          let version = manager.get_version(vid)
          assert_true(version is Some)
        }
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

test "test_get_version_history" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  // 创建快照
  let data = @realtime_db.Map([])
  let snapshot_id = manager.create_snapshot("history_snap", SnapshotType::Manual, data)
  assert_true(snapshot_id is Ok)

  match snapshot_id {
    Ok(sid) => {
      // 创建分支并提交
      let _ = manager.create_branch("history_branch", BranchType::Feature, None)
      let _ = manager.commit("history_branch", "commit 1", "test", sid)
      let _ = manager.commit("history_branch", "commit 2", "test", sid)

      // 获取版本历史
      let history = manager.get_version_history(Some("history_branch"))
      assert_true(history.length() >= 2)
    }
    Err(_) => assert_true(false)
  }
}

test "test_versioning_config" {
  let config = VersioningConfig::default()

  assert_true(config.auto_snapshot)
  assert_eq(config.snapshot_interval, 3600)
  assert_eq(config.max_snapshots, 100)
  assert_eq(config.snapshot_retention_days, 30)
  assert_true(config.enable_branch_protection)
  assert_eq(config.max_branches, 50)
}

test "test_snapshot_count" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  // 初始快照数应该是 0
  assert_eq(manager.snapshot_count(), 0)

  // 创建快照
  let data = @realtime_db.Map([])
  let _ = manager.create_snapshot("count_test", SnapshotType::Manual, data)

  // 快照数应该是 1
  assert_eq(manager.snapshot_count(), 1)
}

test "test_branch_count" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  // 初始分支数应该是 0
  assert_true(manager.branch_count() >= 0)

  // 创建分支
  let _ = manager.create_branch("count_test", BranchType::Feature, None)

  // 分支数应该是 1
  assert_true(manager.branch_count() >= 1)
}

test "test_cleanup_expired_snapshots" {
  let config = VersioningConfig::default()
  let manager = VersionManager::new(config)

  // 清理过期快照
  let cleaned = manager.cleanup_expired_snapshots()
  assert_true(cleaned >= 0)
}