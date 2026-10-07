// 数据湖集成模块测试
//
// 测试同步任务、Schema 同步、数据读写

///|
test "test_lake_types" {
  // 测试数据湖格式
  assert_eq(@lake_integration.Parquet, @lake_integration.Parquet)
  assert_true(@lake_integration.Orc != @lake_integration.Parquet)

  // 测试同步模式
  assert_eq(@lake_integration.Full, @lake_integration.Full)
  assert_true(@lake_integration.Incremental != @lake_integration.Full)

  // 测试同步状态
  assert_eq(@lake_integration.Pending, @lake_integration.Pending)
  assert_true(@lake_integration.Running != @lake_integration.Pending)

  // 测试压缩类型
  assert_eq(@lake_integration.Snappy, @lake_integration.Snappy)
  assert_true(@lake_integration.Gzip != @lake_integration.Snappy)

  // 测试写入模式
  assert_eq(@lake_integration.Append, @lake_integration.Append)
  assert_true(@lake_integration.Overwrite != @lake_integration.Append)
}

///|
test "test_lake_config" {
  let config = @lake_integration.LakeConfig::default()
  assert_eq(config.format, @lake_integration.Parquet)
  assert_eq(config.batch_size, 10000)
  assert_eq(config.compression, @lake_integration.Snappy)
  assert_true(config.schema_evolution)
}

///|
test "test_lake_error" {
  let err = @lake_integration.Task_Already_Exists
  assert_eq(err.code(), 4001)
  assert_true(err.message().length() > 0)

  let err2 = @lake_integration.Task_Not_Found
  assert_eq(err2.code(), 4002)

  let err3 = @lake_integration.Internal_Error("test error")
  assert_eq(err3.code(), 4099)
  assert_true(err3.message().contains("test error"))
}

///|
test "test_create_sync_task" {
  let config = @lake_integration.LakeConfig::default()
  let syncer = @lake_integration.LakeSyncer::new(config)

  let task_config = @lake_integration.SyncTaskConfig::{
    task_name: "test_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users".to_string(),
    format: @lake_integration.Parquet,
    sync_mode: @lake_integration.Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let task_id = syncer.create_sync_task(task_config)
  assert_true(task_id is Ok(_))

  match task_id {
    Ok(id) => {
      assert_true(id.length() > 0)

      // 验证任务存在
      let task = syncer.get_task_status(id)
      assert_true(task is Some(_))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_create_duplicate_task" {
  let config = @lake_integration.LakeConfig::default()
  let syncer = @lake_integration.LakeSyncer::new(config)

  let task_config = @lake_integration.SyncTaskConfig::{
    task_name: "duplicate_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users".to_string(),
    format: @lake_integration.Parquet,
    sync_mode: @lake_integration.Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  // 创建第一个任务
  let result1 = syncer.create_sync_task({ ..task_config, })
  assert_true(result1 is Ok(_))

  // 创建重复任务
  let result2 = syncer.create_sync_task({ ..task_config, })
  assert_true(result2 is Err(_))

  match result2 {
    Err(@lake_integration.Task_Already_Exists) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "test_list_tasks" {
  let config = @lake_integration.LakeConfig::default()
  let syncer = @lake_integration.LakeSyncer::new(config)

  // 创建多个任务
  let task_config1 = @lake_integration.SyncTaskConfig::{
    task_name: "task1".to_string(),
    source_table: "table1".to_string(),
    target_path: "/data/lake/table1".to_string(),
    format: @lake_integration.Parquet,
    sync_mode: @lake_integration.Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let task_config2 = @lake_integration.SyncTaskConfig::{
    task_name: "task2".to_string(),
    source_table: "table2".to_string(),
    target_path: "/data/lake/table2".to_string(),
    format: @lake_integration.Orc,
    sync_mode: @lake_integration.Incremental,
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

///|
test "test_delete_task" {
  let config = @lake_integration.LakeConfig::default()
  let syncer = @lake_integration.LakeSyncer::new(config)

  let task_config = @lake_integration.SyncTaskConfig::{
    task_name: "delete_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users".to_string(),
    format: @lake_integration.Parquet,
    sync_mode: @lake_integration.Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let task_id = syncer.create_sync_task(task_config)
  assert_true(task_id is Ok(_))

  match task_id {
    Ok(id) => {
      // 删除任务
      let result = syncer.delete_sync_task(id)
      assert_true(result is Ok(_))

      // 验证任务已删除
      let task = syncer.get_task_status(id)
      assert_true(task is None)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_delete_nonexistent_task" {
  let config = @lake_integration.LakeConfig::default()
  let syncer = @lake_integration.LakeSyncer::new(config)

  let result = syncer.delete_sync_task("nonexistent")
  assert_true(result is Err(_))

  match result {
    Err(@lake_integration.Task_Not_Found) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
/// 构造测试用表结构
fn make_schema(with_name : Bool) -> @multi_tenant.TableSchema {
  let id_column = @multi_tenant.Column::{
    name: "id".to_string(),
    column_type: @multi_tenant.Int,
    nullable: false,
    default_value: None,
    length: None,
  }
  let columns = if with_name {
    let name_column = @multi_tenant.Column::{
      name: "name".to_string(),
      column_type: @multi_tenant.String,
      nullable: true,
      default_value: None,
      length: Some(255),
    }
    [id_column, name_column]
  } else {
    [id_column]
  }
  @multi_tenant.TableSchema::{
    columns,
    primary_key: ["id".to_string()],
    constraints: [],
  }
}

///|
test "test_schema_mapping" {
  let config = @lake_integration.LakeConfig::default()
  let syncer = @lake_integration.LakeSyncer::new(config)
  let schema_sync = @lake_integration.SchemaSynchronizer::new(syncer)

  // 同步 Schema
  let result = schema_sync.sync_schema("users", make_schema(true))
  assert_true(result is Ok(_))
}

///|
test "test_schema_change_detection" {
  let config = @lake_integration.LakeConfig::default()
  let syncer = @lake_integration.LakeSyncer::new(config)
  let schema_sync = @lake_integration.SchemaSynchronizer::new(syncer)

  // 先同步初始表结构
  let _ = schema_sync.sync_schema("test_table", make_schema(false))

  // 检测 Schema 变更（新表结构多了 name 列）
  let changes = schema_sync.detect_schema_changes(
    "test_table",
    make_schema(true),
  )
  assert_true(changes.length() > 0)
}

///|
test "test_lake_format_conversion" {
  // 测试不同格式任务的创建
  let config = @lake_integration.LakeConfig::default()
  let syncer = @lake_integration.LakeSyncer::new(config)

  // 创建 Parquet 格式任务
  let parquet_config = @lake_integration.SyncTaskConfig::{
    task_name: "parquet_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users.parquet".to_string(),
    format: @lake_integration.Parquet,
    sync_mode: @lake_integration.Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let parquet_task_id = syncer.create_sync_task(parquet_config)
  assert_true(parquet_task_id is Ok(_))

  // 创建 ORC 格式任务
  let orc_config = @lake_integration.SyncTaskConfig::{
    task_name: "orc_task".to_string(),
    source_table: "users".to_string(),
    target_path: "/data/lake/users.orc".to_string(),
    format: @lake_integration.Orc,
    sync_mode: @lake_integration.Full,
    batch_size: 10000,
    sync_interval: 3600,
    incremental_checkpoint: true,
  }

  let orc_task_id = syncer.create_sync_task(orc_config)
  assert_true(orc_task_id is Ok(_))
}

///|
test "test_read_config" {
  let config = @lake_integration.LakeReadConfig::default()
  assert_true(config.predicate_pushdown)
  assert_true(config.column_pruning)
  assert_true(config.partition_pruning)
  assert_eq(config.batch_size, 10000)
}
