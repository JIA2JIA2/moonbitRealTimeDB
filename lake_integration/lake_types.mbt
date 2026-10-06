// 数据湖集成模块 - 核心类型定义
//
// 定义数据湖格式、同步策略、Schema 映射等核心数据结构

///|
/// 数据湖格式枚举
pub(all) enum LakeFormat {
  /// Parquet 格式
  Parquet
  /// ORC 格式
  Orc
  /// Delta Lake 格式
  DeltaLake
  /// Avro 格式
  Avro
  /// JSON 格式
  Json
}

///|
pub impl Eq for LakeFormat with fn equal(self, other) -> Bool {
  match (self, other) {
    (Parquet, Parquet) => true
    (Orc, Orc) => true
    (DeltaLake, DeltaLake) => true
    (Avro, Avro) => true
    (Json, Json) => true
    _ => false
  }
}

///|
pub extend LakeFormat with Eq::{equal, not_equal}

///|
pub impl Debug for LakeFormat with fn to_repr(self) -> Repr {
  match self {
    Parquet => Repr::ctor("Parquet", [])
    Orc => Repr::ctor("Orc", [])
    DeltaLake => Repr::ctor("DeltaLake", [])
    Avro => Repr::ctor("Avro", [])
    Json => Repr::ctor("Json", [])
  }
}

///|
pub extend LakeFormat with Debug::{to_repr}

///|
/// 同步模式枚举
pub(all) enum SyncMode {
  /// 全量同步
  Full
  /// 增量同步
  Incremental
  /// 实时同步
  Realtime
} derive(Debug)

///|
pub extend SyncMode with Debug::{to_repr}

///|
pub impl Eq for SyncMode with fn equal(self, other) -> Bool {
  match (self, other) {
    (Full, Full) => true
    (Incremental, Incremental) => true
    (Realtime, Realtime) => true
    _ => false
  }
}

///|
pub extend SyncMode with Eq::{equal, not_equal}

///|
/// 同步状态枚举
pub(all) enum SyncStatus {
  /// 等待中
  Pending
  /// 运行中
  Running
  /// 已完成
  Completed
  /// 失败
  Failed
  /// 已暂停
  Paused
} derive(Debug)

///|
pub extend SyncStatus with Debug::{to_repr}

///|
pub impl Eq for SyncStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Pending, Pending) => true
    (Running, Running) => true
    (Completed, Completed) => true
    (Failed, Failed) => true
    (Paused, Paused) => true
    _ => false
  }
}

///|
pub extend SyncStatus with Eq::{equal, not_equal}

///|
/// 数据湖配置
pub(all) struct LakeConfig {
  /// 数据湖格式
  format : LakeFormat
  /// 路径
  path : String
  /// 批次大小
  batch_size : Int
  /// 压缩类型
  compression : CompressionType
  /// 是否启用 Schema 演化
  schema_evolution : Bool
  /// 写入模式
  write_mode : WriteMode
}

///|
/// 默认数据湖配置
pub fn LakeConfig::default() -> LakeConfig {
  {
    format: Parquet,
    path: "".to_string(),
    batch_size: 10000,
    compression: Snappy,
    schema_evolution: true,
    write_mode: Append,
  }
}

///|
/// 压缩类型枚举
pub(all) enum CompressionType {
  /// 无压缩
  None
  /// Snappy 压缩
  Snappy
  /// Gzip 压缩
  Gzip
  /// Zstd 压缩
  Zstd
  /// Lz4 压缩
  Lz4
} derive(Debug)

///|
pub extend CompressionType with Debug::{to_repr}

///|
pub impl Eq for CompressionType with fn equal(self, other) -> Bool {
  match (self, other) {
    (None, None) => true
    (Snappy, Snappy) => true
    (Gzip, Gzip) => true
    (Zstd, Zstd) => true
    (Lz4, Lz4) => true
    _ => false
  }
}

///|
pub extend CompressionType with Eq::{equal, not_equal}

///|
/// 写入模式枚举
pub(all) enum WriteMode {
  /// 追加写入
  Append
  /// 覆盖写入
  Overwrite
  /// 错误如果存在
  ErrorIfExists
  /// 忽略如果存在
  Ignore
} derive(Debug)

///|
pub extend WriteMode with Debug::{to_repr}

///|
pub impl Eq for WriteMode with fn equal(self, other) -> Bool {
  match (self, other) {
    (Append, Append) => true
    (Overwrite, Overwrite) => true
    (ErrorIfExists, ErrorIfExists) => true
    (Ignore, Ignore) => true
    _ => false
  }
}

///|
pub extend WriteMode with Eq::{equal, not_equal}

///|
/// 同步任务
pub(all) struct SyncTask {
  /// 任务 ID
  task_id : String
  /// 任务名称
  task_name : String
  /// 源表名
  source_table : String
  /// 目标路径
  target_path : String
  /// 数据湖格式
  format : LakeFormat
  /// 同步模式
  sync_mode : SyncMode
  /// 同步状态
  mut status : SyncStatus
  /// 同步配置
  config : LakeConfig
  /// 创建时间
  created_at : Int
  /// 更新时间
  mut updated_at : Int
  /// 最后同步时间
  mut last_sync_at : Int
  /// 已同步记录数
  mut synced_records : Int
  /// 总记录数
  mut total_records : Int
  /// 错误信息
  mut error_message : String?
}

///|
/// 同步任务配置
pub(all) struct SyncTaskConfig {
  /// 任务名称
  task_name : String
  /// 源表名
  source_table : String
  /// 目标路径
  target_path : String
  /// 数据湖格式
  format : LakeFormat
  /// 同步模式
  sync_mode : SyncMode
  /// 批次大小
  batch_size : Int
  /// 同步间隔（秒）
  sync_interval : Int
  /// 是否启用增量检查点
  incremental_checkpoint : Bool
}

///|
/// Schema 映射
pub(all) struct SchemaMapping {
  /// 源表名
  source_table : String
  /// 目标表名
  target_table : String
  /// 列映射
  mut column_mappings : Array[ColumnMapping]
  /// 是否自动同步 Schema
  auto_sync : Bool
  /// 最后同步时间
  mut last_sync_time : Int
}

///|
/// 列映射
pub(all) struct ColumnMapping {
  /// 源列名
  source_column : String
  /// 目标列名
  target_column : String
  /// 目标类型
  target_type : @multi_tenant.ColumnType
  /// 是否可空
  nullable : Bool
  /// 默认值
  default_value : @realtime_db.Value?
  /// 转换表达式
  transformation : String?
}

///|
/// Schema 变更
pub(all) struct SchemaChange {
  /// 变更 ID
  change_id : String
  /// 表名
  table_name : String
  /// 变更类型
  change_type : SchemaChangeType
  /// 列定义
  column : @multi_tenant.Column?
  /// 旧列名
  old_column_name : String?
  /// 时间戳
  timestamp : Int
}

///|
/// Schema 变更类型枚举
pub(all) enum SchemaChangeType {
  /// 添加列
  AddColumn
  /// 删除列
  DropColumn
  /// 修改列类型
  ModifyColumnType
  /// 重命名列
  RenameColumn
  /// 添加约束
  AddConstraint
  /// 删除约束
  DropConstraint
}

///|
pub impl Eq for SchemaChangeType with fn equal(self, other) -> Bool {
  match (self, other) {
    (AddColumn, AddColumn) => true
    (DropColumn, DropColumn) => true
    (ModifyColumnType, ModifyColumnType) => true
    (RenameColumn, RenameColumn) => true
    (AddConstraint, AddConstraint) => true
    (DropConstraint, DropConstraint) => true
    _ => false
  }
}

///|
pub extend SchemaChangeType with Eq::{equal, not_equal}

///|
/// 数据湖错误类型
pub(all) enum LakeError {
  /// 任务已存在
  Task_Already_Exists
  /// 任务不存在
  Task_Not_Found
  /// 无效配置
  Invalid_Config
  /// 路径不存在
  Path_Not_Found
  /// 权限被拒绝
  Permission_Denied
  /// Schema 不匹配
  Schema_Mismatch
  /// 写入失败
  Write_Failed
  /// 读取失败
  Read_Failed
  /// 压缩失败
  Compression_Failed
  /// 同步进行中
  Sync_In_Progress
  /// 内部错误
  Internal_Error(String)
}

///|
pub impl Eq for LakeError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Task_Already_Exists, Task_Already_Exists) => true
    (Task_Not_Found, Task_Not_Found) => true
    (Invalid_Config, Invalid_Config) => true
    (Path_Not_Found, Path_Not_Found) => true
    (Permission_Denied, Permission_Denied) => true
    (Schema_Mismatch, Schema_Mismatch) => true
    (Write_Failed, Write_Failed) => true
    (Read_Failed, Read_Failed) => true
    (Compression_Failed, Compression_Failed) => true
    (Sync_In_Progress, Sync_In_Progress) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend LakeError with Eq::{equal, not_equal}

///|
pub impl Debug for LakeError with fn to_repr(self) -> Repr {
  match self {
    Task_Already_Exists => Repr::ctor("Task_Already_Exists", [])
    Task_Not_Found => Repr::ctor("Task_Not_Found", [])
    Invalid_Config => Repr::ctor("Invalid_Config", [])
    Path_Not_Found => Repr::ctor("Path_Not_Found", [])
    Permission_Denied => Repr::ctor("Permission_Denied", [])
    Schema_Mismatch => Repr::ctor("Schema_Mismatch", [])
    Write_Failed => Repr::ctor("Write_Failed", [])
    Read_Failed => Repr::ctor("Read_Failed", [])
    Compression_Failed => Repr::ctor("Compression_Failed", [])
    Sync_In_Progress => Repr::ctor("Sync_In_Progress", [])
    Internal_Error(msg) => Repr::ctor("Internal_Error", [(None, Repr(msg))])
  }
}

///|
pub extend LakeError with Debug::{to_repr}

///|
/// 获取错误码
pub fn LakeError::code(self : LakeError) -> Int {
  match self {
    Task_Already_Exists => 4001
    Task_Not_Found => 4002
    Invalid_Config => 4003
    Path_Not_Found => 4004
    Permission_Denied => 4005
    Schema_Mismatch => 4006
    Write_Failed => 4007
    Read_Failed => 4008
    Compression_Failed => 4009
    Sync_In_Progress => 4010
    Internal_Error(_) => 4099
  }
}

///|
/// 获取错误消息
pub fn LakeError::message(self : LakeError) -> String {
  match self {
    Task_Already_Exists => "Sync task already exists"
    Task_Not_Found => "Sync task not found"
    Invalid_Config => "Invalid configuration"
    Path_Not_Found => "Path not found"
    Permission_Denied => "Permission denied"
    Schema_Mismatch => "Schema mismatch"
    Write_Failed => "Write failed"
    Read_Failed => "Read failed"
    Compression_Failed => "Compression failed"
    Sync_In_Progress => "Sync in progress"
    Internal_Error(msg) => "Internal error: " + msg
  }
}

///|
/// 转为字符串
pub fn LakeError::to_string(self : LakeError) -> String {
  "[Error " + self.code().to_string() + "] " + self.message()
}
