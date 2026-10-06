// 数据湖集成模块测试
//
// 测试同步任务、Schema 同步、数据读写

test "test_lake_types" {
  // 测试数据湖格式
  assert_eq(LakeFormat::Parquet, LakeFormat::Parquet)
  assert_true(LakeFormat::Orc != LakeFormat::Parquet)

  // 测试同步模式
  assert_eq(SyncMode::Full, SyncMode::Full)
  assert_true(SyncMode::Incremental != SyncMode::Full)

  // 测试同步状态
  assert_eq(SyncStatus::Pending, SyncStatus::Pending)
  assert_true(SyncStatus::Running != SyncStatus::Pending)

  // 测试压缩类型
  assert_eq(CompressionType::Snappy, CompressionType::Snappy)
  assert_true(CompressionType::Gzip != CompressionType::Snappy)

  // 测试写入模式
  assert_eq(WriteMode::Append, WriteMode::Append)
  assert_true(WriteMode::Overwrite != WriteMode::Append)
}

test "test_lake_config" {
  let config = LakeConfig::default()
  assert_eq(config.format, LakeFormat::Parquet)
  assert_eq(config.batch_size, 10000)
  assert_eq(config.compression, CompressionType::Snappy)
  assert_true(config.schema_evolution)
}

test "test_lake_error" {
  let err = LakeError::Task_Already_Exists
  assert_eq(err.code(), 4001)
  assert_true(err.message().length() > 0)

  let err2 = LakeError::Task_Not_Found
  assert_eq(err2.code(), 4002)

  let err3 = LakeError::Internal_Error("test error")
  assert_eq(err3.code(), 4099)
  assert_true(err3.message().contains("test error"))
}

test "test_create_sync_task" {
  let config = LakeConfig::default()
  let syncer = LakeSyncer::new(config)

  let task_config = SyncTaskConfig {
    task_name: "test_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users".to_string(),
    format: LakeFormat::Parquet,
    sync_mode: SyncMode::Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let task_id = syncer.create_sync_task(task_config)
  assert_true(task_id is Ok)

  match task_id {
    Ok(id) => {
      assert_true(id.length() > 0)

      // 验证任务存在
      let task = syncer.get_task_status(id)
      assert_true(task is Some)
    }
    Err(_) => assert_true(false)
  }
}

test "test_create_duplicate_task" {
  let config = LakeConfig::default()
  let syncer = LakeSyncer::new(config)

  let task_config = SyncTaskConfig {
    task_name: "duplicate_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users".to_string(),
    format: LakeFormat::Parquet,
    sync_mode: SyncMode::Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  // 创建第一个任务
  let result1 = syncer.create_sync_task(task_config)
  assert_true(result1 is Ok)

  // 创建重复任务
  let result2 = syncer.create_sync_task(task_config)
  assert_true(result2 is Err)

  match result2 {
    Err(LakeError::Task_Already_Exists) => assert_true(true)
    _ => assert_true(false)
  }
}

test "test_list_tasks" {
  let config = LakeConfig::default()
  let syncer = LakeSyncer::new(config)

  // 创建多个任务
  let task_config1 = SyncTaskConfig {
    task_name: "task1".to_string(),
    source_table: "table1".to_string(),
    target_path: "/data/lake/table1".to_string(),
    format: LakeFormat::Parquet,
    sync_mode: SyncMode::Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let task_config2 = SyncTaskConfig {
    task_name: "task2".to_string(),
    source_table: "table2".to_string(),
    target_path: "/data/lake/table2".to_string(),
    format: LakeFormat::Orc,
    sync_mode: Incremental,
    batch_size: 5000,
    sync_interval: 1800,
    incremental_checkpoint: true,
  }

  let _ = syncer.create_sync_task(task_config1)
  let _ = syncer.create_sync_task(task_config2)

  // 列出任务
  let tasks = syncer.list_tasks()
  assert_eq(tasks.length(), 2)
}

test "test_delete_task" {
  let config = LakeConfig::default()
  let syncer = LakeSyncer::new(config)

  let task_config = SyncTaskConfig {
    task_name: "delete_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users".to_string(),
    format: LakeFormat::Parquet,
    sync_mode: SyncMode::Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let task_id = syncer.create_sync_task(task_config)
  assert_true(task_id is Ok)

  match task_id {
    Ok(id) => {
      // 删除任务
      let result = syncer.delete_sync_task(id)
      assert_true(result is Ok)

      // 验证任务已删除
      let task = syncer.get_task_status(id)
      assert_true(task is None)
    }
    Err(_) => assert_true(false)
  }
}

test "test_delete_nonexistent_task" {
  let config = LakeConfig::default()
  let syncer = LakeSyncer::new(config)

  let result = syncer.delete_sync_task("nonexistent")
  assert_true(result is Err)

  match result {
    Err(LakeError::Task_Not_Found) => assert_true(true)
    _ => assert_true(false)
  }
}

test "test_schema_mapping" {
  let config = LakeConfig::default()
  let syncer = LakeSyncer::new(config)
  let schema_sync = SchemaSynchronizer::new(syncer)

  // 创建表结构
  let schema = TableSchema {
    columns: [
      Column {
        name: "id".to_string(),
        column_type: ColumnType::Int,
        nullable: false,
        default_value: None,
        length: None,
        alias: None,
      },
      Column {
        name: "name".to_string(),
        column_type: ColumnType::String,
        nullable: true,
        default_value: None,
        length: Some(255),
        alias: None,
      },
    ],
    primary_key: ["id".to_string()],
    constraints: [],
  }

  // 同步 Schema
  let result = schema_sync.sync_schema("users", schema)
  assert_true(result is Ok)
}

test "test_schema_change_detection" {
  let config = LakeConfig::default()
  let syncer = LakeSyncer::new(config)
  let schema_sync = SchemaSynchronizer::new(syncer)

  // 创建初始表结构
  let schema1 = TableSchema {
    columns: [
      Column {
        name: "id".to_string(),
        column_type: ColumnType::Int,
        nullable: false,
        default_value: None,
        length: None,
        alias: None,
      },
    ],
    primary_key: ["id".to_string()],
    constraints: [],
  }

  let _ = schema_sync.sync_schema("test_table", schema1)

  // 创建新表结构（添加一列）
  let schema2 = TableSchema {
    columns: [
      Column {
        name: "id".to_string(),
        column_type: ColumnType::Int,
        nullable: false,
        default_value: None,
        length: None,
        alias: None,
      },
      Column {
        name: "name".to_string(),
        column_type: ColumnType::String,
        nullable: true,
        default_value: None,
        length: Some(255),
        alias: None,
      },
    ],
    primary_key: ["id".to_string()],
    constraints: [],
  }

  // 检测 Schema 变更
  let changes = schema_sync.detect_schema_changes("test_table", schema2)
  assert_true(changes.length() > 0)
}

test "test_lake_format_conversion" {
  // 测试格式转换
  let config = LakeConfig::default()
  let syncer = LakeSyncer::new(config)

  // 创建 Parquet 格式任务
  let parquet_config = SyncTaskConfig {
    task_name: "parquet_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users.parquet".to_string(),
    format: LakeFormat::Parquet,
    sync_mode: SyncMode::Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let parquet_task_id = syncer.create_sync_task(parquet_config)
  assert_true(parquet_task_id is Ok)

  // 创建 ORC 格式任务
  let orc_config = SyncTaskConfig {
    task_name: "orc_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users.orc".to_string(),
    format: LakeFormat::Orc,
    sync_mode: SyncMode::Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let orc_task_id = syncer.create_sync_task(orc_config)
  assert_true(orc_task_id is Ok)
}

test "test_read_config" {
  let config = LakeReadConfig::default()
  assert_true(config.predicate_pushdown)
  assert_true(config.column_pruning)
  assert_true(config.partition_pruning)
  assert_eq(config.batch_size, 10000)
}