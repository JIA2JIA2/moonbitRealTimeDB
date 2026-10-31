// 多租户管理模块 - 核心类型定义
//
// 定义租户、命名空间、资源配额等核心数据结构

///|
/// 租户状态枚举
pub(all) enum TenantStatus {
  /// 创建中
  Creating
  /// 活跃
  Active
  /// 已隔离
  Isolated
  /// 维护中
  Maintenance
  /// 删除中
  Deleting
  /// 已删除
  Deleted
}

///|
pub impl Eq for TenantStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Creating, Creating) => true
    (Active, Active) => true
    (Isolated, Isolated) => true
    (Maintenance, Maintenance) => true
    (Deleting, Deleting) => true
    (Deleted, Deleted) => true
    _ => false
  }
}

///|
pub extend TenantStatus with Eq::{equal, not_equal}

///|
pub impl Debug for TenantStatus with fn to_repr(self) -> Repr {
  match self {
    Creating => Repr::ctor("Creating", [])
    Active => Repr::ctor("Active", [])
    Isolated => Repr::ctor("Isolated", [])
    Maintenance => Repr::ctor("Maintenance", [])
    Deleting => Repr::ctor("Deleting", [])
    Deleted => Repr::ctor("Deleted", [])
  }
}

///|
pub extend TenantStatus with Debug::{to_repr}

///|
/// 资源类型枚举
pub(all) enum ResourceType {
  /// CPU 资源
  Cpu
  /// 内存资源
  Memory
  /// 存储资源
  Storage
  /// 连接数资源
  Connections
  /// 吞吐量资源
  Throughput
}

///|
pub impl Eq for ResourceType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Cpu, Cpu) => true
    (Memory, Memory) => true
    (Storage, Storage) => true
    (Connections, Connections) => true
    (Throughput, Throughput) => true
    _ => false
  }
}

///|
pub extend ResourceType with Eq::{equal, not_equal}

///|
pub impl Debug for ResourceType with fn to_repr(self) -> Repr {
  match self {
    Cpu => Repr::ctor("Cpu", [])
    Memory => Repr::ctor("Memory", [])
    Storage => Repr::ctor("Storage", [])
    Connections => Repr::ctor("Connections", [])
    Throughput => Repr::ctor("Throughput", [])
  }
}

///|
pub extend ResourceType with Debug::{to_repr}

///|
/// 资源使用量
pub(all) struct ResourceUsage {
  /// CPU 使用量（核数）
  mut cpu_used : Double
  /// CPU 限制
  cpu_limit : Double
  /// 内存使用量（字节）
  mut memory_used : Int32
  /// 内存限制（字节）
  memory_limit : Int32
  /// 存储使用量（字节）
  mut storage_used : Int64
  /// 存储限制（字节）
  storage_limit : Int64
  /// 连接数
  mut connections_used : Int32
  /// 连接数限制
  connections_limit : Int32
  /// 吞吐量（字节/秒）
  mut throughput_used : Int32
  /// 吞吐量限制
  throughput_limit : Int32
}

///|
/// 创建默认资源使用量
pub fn ResourceUsage::default() -> ResourceUsage {
  {
    cpu_used: 0.0,
    cpu_limit: 4.0,
    memory_used: 0,
    memory_limit: 1073741824, // 1GB
    storage_used: 0L,
    storage_limit: 107374182400L, // 100GB
    connections_used: 0,
    connections_limit: 1000,
    throughput_used: 0,
    throughput_limit: 104857600, // 100MB/s
  }
}

///|
/// 租户配置
pub(all) struct TenantConfig {
  /// CPU 配额（核数）
  cpu_quota : Double
  /// 内存配额（字节）
  memory_quota : Int32
  /// 存储配额（字节）
  storage_quota : Int64
  /// 连接数配额
  connection_quota : Int32
  /// 吞吐量配额（字节/秒）
  throughput_quota : Int32
  /// 最大命名空间数
  max_namespaces : Int32
  /// 最大表数
  max_tables : Int32
  /// 是否启用自动扩展
  auto_scaling : Bool
  /// 隔离级别
  isolation_level : IsolationLevel
}

///|
/// 默认租户配置
pub fn TenantConfig::default() -> TenantConfig {
  {
    cpu_quota: 4.0,
    memory_quota: 1073741824,
    storage_quota: 107374182400L,
    connection_quota: 1000,
    throughput_quota: 104857600,
    max_namespaces: 100,
    max_tables: 1000,
    auto_scaling: false,
    isolation_level: IsolationLevel::Namespace,
  }
}

///|
/// 隔离级别枚举
pub(all) enum IsolationLevel {
  /// 命名空间级别隔离
  Namespace
  /// 表级别隔离
  Table
  /// 行级别隔离
  Row
}

///|
pub impl Eq for IsolationLevel with fn equal(self, other) -> Bool {
  match (self, other) {
    (Namespace, Namespace) => true
    (Table, Table) => true
    (Row, Row) => true
    _ => false
  }
}

///|
pub extend IsolationLevel with Eq::{equal, not_equal}

///|
/// 命名空间
pub(all) struct Namespace {
  /// 命名空间 ID
  namespace_id : String
  /// 租户 ID
  tenant_id : String
  /// 表映射：表名 -> 表
  tables : Map[String, Table]
  /// 特征表映射
  feature_tables : Map[String, FeatureTable]
  /// 创建时间
  created_at : Int32
  /// 更新时间
  updated_at : Int32
}

///|
/// 表
pub(all) struct Table {
  /// 表 ID
  table_id : String
  /// 表名
  name : String
  /// 表结构
  schema : TableSchema
  /// 数据量
  row_count : Int32
  /// 存储大小
  storage_size : Int32
  /// 创建时间
  created_at : Int32
}

///|
/// 特征表
pub(all) struct FeatureTable {
  /// 特征表 ID
  feature_table_id : String
  /// 特征表名
  name : String
  /// 来源表
  source_table : String
  /// 表结构
  schema : TableSchema
  /// 创建时间
  created_at : Int32
}

///|
/// 表结构
pub(all) struct TableSchema {
  /// 列定义
  columns : Array[Column]
  /// 主键列
  primary_key : Array[String]
  /// 约束
  constraints : Array[Constraint]
}

///|
/// 列
pub(all) struct Column {
  /// 列名
  name : String
  /// 列类型
  column_type : ColumnType
  /// 是否可空
  nullable : Bool
  /// 默认值
  default_value : @realtime_db.Value?
  /// 长度（用于字符串类型）
  length : Int32?
}

///|
/// 列类型枚举
pub(all) enum ColumnType {
  Int
  BigInt
  Double
  String
  Boolean
  Timestamp
  Decimal
  Array
  Map
}

///|
pub impl Eq for ColumnType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Int, Int) => true
    (BigInt, BigInt) => true
    (Double, Double) => true
    (String, String) => true
    (Boolean, Boolean) => true
    (Timestamp, Timestamp) => true
    (Decimal, Decimal) => true
    (Array, Array) => true
    (Map, Map) => true
    _ => false
  }
}

///|
pub extend ColumnType with Eq::{equal, not_equal}

///|
pub impl Debug for ColumnType with fn to_repr(self) -> Repr {
  match self {
    Int => Repr::ctor("Int", [])
    BigInt => Repr::ctor("BigInt", [])
    Double => Repr::ctor("Double", [])
    String => Repr::ctor("String", [])
    Boolean => Repr::ctor("Boolean", [])
    Timestamp => Repr::ctor("Timestamp", [])
    Decimal => Repr::ctor("Decimal", [])
    Array => Repr::ctor("Array", [])
    Map => Repr::ctor("Map", [])
  }
}

///|
pub extend ColumnType with Debug::{to_repr}

///|
/// 约束
pub(all) struct Constraint {
  /// 约束名
  name : String
  /// 约束类型
  constraint_type : ConstraintType
  /// 列名
  columns : Array[String]
}

///|
/// 约束类型枚举
pub(all) enum ConstraintType {
  /// 主键
  PrimaryKey
  /// 外键
  ForeignKey
  /// 唯一约束
  Unique
  /// 非空
  NotNull
  /// 检查
  Check
}

///|
pub impl Eq for ConstraintType with fn equal(self, other) -> Bool {
  match (self, other) {
    (PrimaryKey, PrimaryKey) => true
    (ForeignKey, ForeignKey) => true
    (Unique, Unique) => true
    (NotNull, NotNull) => true
    (Check, Check) => true
    _ => false
  }
}

///|
pub extend ConstraintType with Eq::{equal, not_equal}

///|
/// 租户
pub(all) struct Tenant {
  /// 租户 ID
  tenant_id : String
  /// 租户名称
  tenant_name : String
  /// 租户状态
  status : TenantStatus
  /// 租户配置
  mut config : TenantConfig
  /// 命名空间映射
  namespaces : Map[String, Namespace]
  /// 资源使用量
  resource_usage : ResourceUsage
  /// 创建时间
  created_at : Int32
  /// 更新时间
  mut updated_at : Int32
  /// 删除时间
  deleted_at : Int32?
}

///|
/// 租户错误类型
pub(all) enum TenantError {
  /// 租户已存在
  Tenant_Already_Exists
  /// 租户不存在
  Tenant_Not_Found
  /// 租户状态错误
  Tenant_Invalid_State
  /// 配额超限
  Quota_Exceeded
  /// 资源不足
  Resource_Exhausted
  /// 命名空间不存在
  Namespace_Not_Found
  /// 命名空间已存在
  Namespace_Already_Exists
  /// 表不存在
  Table_Not_Found
  /// 表已存在
  Table_Already_Exists
  /// 无效配置
  Invalid_Config
  /// 内部错误
  Internal_Error(String)
}

///|
pub impl Eq for TenantError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Tenant_Already_Exists, Tenant_Already_Exists) => true
    (Tenant_Not_Found, Tenant_Not_Found) => true
    (Tenant_Invalid_State, Tenant_Invalid_State) => true
    (Quota_Exceeded, Quota_Exceeded) => true
    (Resource_Exhausted, Resource_Exhausted) => true
    (Namespace_Not_Found, Namespace_Not_Found) => true
    (Namespace_Already_Exists, Namespace_Already_Exists) => true
    (Table_Not_Found, Table_Not_Found) => true
    (Table_Already_Exists, Table_Already_Exists) => true
    (Invalid_Config, Invalid_Config) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend TenantError with Eq::{equal, not_equal}

///|
pub impl Debug for TenantError with fn to_repr(self) -> Repr {
  match self {
    Tenant_Already_Exists => Repr::ctor("Tenant_Already_Exists", [])
    Tenant_Not_Found => Repr::ctor("Tenant_Not_Found", [])
    Tenant_Invalid_State => Repr::ctor("Tenant_Invalid_State", [])
    Quota_Exceeded => Repr::ctor("Quota_Exceeded", [])
    Resource_Exhausted => Repr::ctor("Resource_Exhausted", [])
    Namespace_Not_Found => Repr::ctor("Namespace_Not_Found", [])
    Namespace_Already_Exists => Repr::ctor("Namespace_Already_Exists", [])
    Table_Not_Found => Repr::ctor("Table_Not_Found", [])
    Table_Already_Exists => Repr::ctor("Table_Already_Exists", [])
    Invalid_Config => Repr::ctor("Invalid_Config", [])
    Internal_Error(msg) => Repr::ctor("Internal_Error", [(None, Repr(msg))])
  }
}

///|
pub extend TenantError with Debug::{to_repr}

///|
/// 获取错误码
pub fn TenantError::code(self : TenantError) -> Int32 {
  match self {
    Tenant_Already_Exists => 2001
    Tenant_Not_Found => 2002
    Tenant_Invalid_State => 2003
    Quota_Exceeded => 2004
    Resource_Exhausted => 2005
    Namespace_Not_Found => 2006
    Namespace_Already_Exists => 2007
    Table_Not_Found => 2008
    Table_Already_Exists => 2009
    Invalid_Config => 2010
    Internal_Error(_) => 2099
  }
}

///|
/// 获取错误消息
pub fn TenantError::message(self : TenantError) -> String {
  match self {
    Tenant_Already_Exists => "Tenant already exists"
    Tenant_Not_Found => "Tenant not found"
    Tenant_Invalid_State => "Invalid tenant state"
    Quota_Exceeded => "Quota exceeded"
    Resource_Exhausted => "Resource exhausted"
    Namespace_Not_Found => "Namespace not found"
    Namespace_Already_Exists => "Namespace already exists"
    Table_Not_Found => "Table not found"
    Table_Already_Exists => "Table already exists"
    Invalid_Config => "Invalid configuration"
    Internal_Error(msg) => "Internal error: " + msg
  }
}

///|
/// 转为字符串
pub fn TenantError::to_string(self : TenantError) -> String {
  "[Error " + self.code().to_string() + "] " + self.message()
}
