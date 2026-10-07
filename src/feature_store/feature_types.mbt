// 特征存储模块 - 核心类型定义
//
// 定义特征表、特征向量、特征版本等核心数据结构

///|
/// 特征类型枚举
pub(all) enum FeatureType {
  /// 整数特征
  Int
  /// 浮点数特征
  Float
  /// 字符串特征
  String
  /// 布尔特征
  Boolean
  /// 向量特征
  Vector
  /// 数组特征
  Array
  /// 映射特征
  Map
}

///|
pub impl Eq for FeatureType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Int, Int) => true
    (Float, Float) => true
    (String, String) => true
    (Boolean, Boolean) => true
    (Vector, Vector) => true
    (Array, Array) => true
    (Map, Map) => true
    _ => false
  }
}

///|
pub extend FeatureType with Eq::{equal, not_equal}

///|
pub impl Debug for FeatureType with fn to_repr(self) -> Repr {
  match self {
    Int => Repr::ctor("Int", [])
    Float => Repr::ctor("Float", [])
    String => Repr::ctor("String", [])
    Boolean => Repr::ctor("Boolean", [])
    Vector => Repr::ctor("Vector", [])
    Array => Repr::ctor("Array", [])
    Map => Repr::ctor("Map", [])
  }
}

///|
pub extend FeatureType with Debug::{to_repr}

///|
/// 特征状态枚举
pub(all) enum FeatureStatus {
  /// 创建中
  Creating
  /// 活跃
  Active
  /// 已禁用
  Disabled
  /// 已删除
  Deleted
} derive(Debug)

///|
pub extend FeatureStatus with Debug::{to_repr}

///|
pub impl Eq for FeatureStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Creating, Creating) => true
    (Active, Active) => true
    (Disabled, Disabled) => true
    (Deleted, Deleted) => true
    _ => false
  }
}

///|
pub extend FeatureStatus with Eq::{equal, not_equal}

///|
/// 特征来源枚举
pub(all) enum FeatureSource {
  /// 批计算
  Batch
  /// 流计算
  Streaming
  /// 实时计算
  Realtime
  /// 手动
  Manual
} derive(Debug)

///|
pub extend FeatureSource with Debug::{to_repr}

///|
pub impl Eq for FeatureSource with fn equal(self, other) -> Bool {
  match (self, other) {
    (Batch, Batch) => true
    (Streaming, Streaming) => true
    (Realtime, Realtime) => true
    (Manual, Manual) => true
    _ => false
  }
}

///|
pub extend FeatureSource with Eq::{equal, not_equal}

///|
/// 特征视图类型
pub(all) enum FeatureViewType {
  /// 批视图
  BatchView
  /// 流视图
  StreamingView
  /// 实时视图
  RealtimeView
} derive(Debug)

///|
pub extend FeatureViewType with Debug::{to_repr}

///|
pub impl Eq for FeatureViewType with fn equal(self, other) -> Bool {
  match (self, other) {
    (BatchView, BatchView) => true
    (StreamingView, StreamingView) => true
    (RealtimeView, RealtimeView) => true
    _ => false
  }
}

///|
pub extend FeatureViewType with Eq::{equal, not_equal}

///|
/// 特征表
pub(all) struct FeatureTable {
  /// 表 ID
  table_id : String
  /// 表名
  table_name : String
  /// 特征列表
  mut features : Array[Feature]
  /// 主键
  primary_key : String
  /// 创建时间
  created_at : Int
  /// 更新时间
  mut updated_at : Int
}

///|
/// 特征定义
pub(all) struct Feature {
  /// 特征 ID
  feature_id : String
  /// 特征名
  feature_name : String
  /// 特征类型
  feature_type : FeatureType
  /// 特征状态
  status : FeatureStatus
  /// 特征来源
  source : FeatureSource
  /// 描述
  description : String?
  /// 默认值
  default_value : @realtime_db.Value?
  /// 元数据
  metadata : Map[String, @realtime_db.Value]
  /// 创建时间
  created_at : Int
  /// 更新时间
  updated_at : Int
}

///|
/// 特征向量
pub(all) struct FeatureVector {
  /// 向量 ID
  vector_id : String
  /// 实体 ID
  entity_id : String
  /// 特征表 ID
  table_id : String
  /// 特征值映射：特征ID -> 值
  values : Map[String, @realtime_db.Value]
  /// 特征版本
  version : Int
  /// 时间戳
  timestamp : Int
  /// 是否有效
  is_valid : Bool
}

///|
/// 特征版本
pub(all) struct FeatureVersion {
  /// 版本 ID
  version_id : String
  /// 特征 ID
  feature_id : String
  /// 版本号
  version : Int
  /// 变更描述
  change_description : String
  /// 创建时间
  created_at : Int
  /// 是否当前版本
  is_current : Bool
}

///|
/// 特征视图
pub(all) struct FeatureView {
  /// 视图 ID
  view_id : String
  /// 视图名
  view_name : String
  /// 视图类型
  view_type : FeatureViewType
  /// 特征表 ID
  table_id : String
  /// 特征列表
  feature_names : Array[String]
  /// 创建时间
  created_at : Int
}

///|
/// 特征查询请求
pub(all) struct FeatureQueryRequest {
  /// 特征表 ID
  table_id : String
  /// 实体 ID
  entity_id : String
  /// 特征名列表（None 表示所有特征）
  feature_names : Array[String]?
  /// 版本
  version : Int?
  /// 是否使用缓存
  use_cache : Bool
}

///|
/// 特征写入请求
pub(all) struct FeatureWriteRequest {
  /// 特征表 ID
  table_id : String
  /// 实体 ID
  entity_id : String
  /// 特征值映射
  values : Map[String, @realtime_db.Value]
  /// 来源
  source : FeatureSource
  /// 是否覆盖
  overwrite : Bool
}

///|
/// 特征存储配置
pub(all) struct FeatureStoreConfig {
  /// 在线存储类型
  online_storage_type : StorageType
  /// 离线存储类型
  offline_storage_type : StorageType
  /// 是否启用缓存
  enable_cache : Bool
  /// 缓存大小
  cache_size : Int
  /// 缓存 TTL（秒）
  cache_ttl : Int
  /// 是否启用版本管理
  enable_versioning : Bool
  /// 最大版本数
  max_versions : Int
}

///|
/// 默认特征存储配置
pub fn FeatureStoreConfig::default() -> FeatureStoreConfig {
  {
    online_storage_type: Memory,
    offline_storage_type: DeltaLake,
    enable_cache: true,
    cache_size: 100000,
    cache_ttl: 300,
    enable_versioning: true,
    max_versions: 10,
  }
}

///|
/// 存储类型枚举
pub(all) enum StorageType {
  /// 内存存储
  Memory
  /// Redis 存储
  Redis
  /// Parquet 存储
  Parquet
  /// Delta Lake 存储
  DeltaLake
  /// MySQL 存储
  Mysql
} derive(Debug)

///|
pub extend StorageType with Debug::{to_repr}

///|
pub impl Eq for StorageType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Memory, Memory) => true
    (Redis, Redis) => true
    (Parquet, Parquet) => true
    (DeltaLake, DeltaLake) => true
    (Mysql, Mysql) => true
    _ => false
  }
}

///|
pub extend StorageType with Eq::{equal, not_equal}

///|
/// 特征错误类型
pub(all) enum FeatureError {
  /// 表已存在
  Table_Already_Exists
  /// 表不存在
  Table_Not_Found
  /// 特征已存在
  Feature_Already_Exists
  /// 特征不存在
  Feature_Not_Found
  /// 向量不存在
  Vector_Not_Found
  /// 视图已存在
  View_Already_Exists
  /// 视图不存在
  View_Not_Found
  /// 无效类型
  Invalid_Type
  /// 无效值
  Invalid_Value
  /// 存储错误
  Storage_Error
  /// 缓存错误
  Cache_Error
  /// 版本错误
  Version_Error
  /// 内部错误
  Internal_Error(String)
}

///|
pub impl Eq for FeatureError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Table_Already_Exists, Table_Already_Exists) => true
    (Table_Not_Found, Table_Not_Found) => true
    (Feature_Already_Exists, Feature_Already_Exists) => true
    (Feature_Not_Found, Feature_Not_Found) => true
    (Vector_Not_Found, Vector_Not_Found) => true
    (View_Already_Exists, View_Already_Exists) => true
    (View_Not_Found, View_Not_Found) => true
    (Invalid_Type, Invalid_Type) => true
    (Invalid_Value, Invalid_Value) => true
    (Storage_Error, Storage_Error) => true
    (Cache_Error, Cache_Error) => true
    (Version_Error, Version_Error) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend FeatureError with Eq::{equal, not_equal}

///|
pub impl Debug for FeatureError with fn to_repr(self) -> Repr {
  match self {
    Table_Already_Exists => Repr::ctor("Table_Already_Exists", [])
    Table_Not_Found => Repr::ctor("Table_Not_Found", [])
    Feature_Already_Exists => Repr::ctor("Feature_Already_Exists", [])
    Feature_Not_Found => Repr::ctor("Feature_Not_Found", [])
    Vector_Not_Found => Repr::ctor("Vector_Not_Found", [])
    View_Already_Exists => Repr::ctor("View_Already_Exists", [])
    View_Not_Found => Repr::ctor("View_Not_Found", [])
    Invalid_Type => Repr::ctor("Invalid_Type", [])
    Invalid_Value => Repr::ctor("Invalid_Value", [])
    Storage_Error => Repr::ctor("Storage_Error", [])
    Cache_Error => Repr::ctor("Cache_Error", [])
    Version_Error => Repr::ctor("Version_Error", [])
    Internal_Error(msg) => Repr::ctor("Internal_Error", [(None, Repr(msg))])
  }
}

///|
pub extend FeatureError with Debug::{to_repr}

///|
/// 获取错误码
pub fn FeatureError::code(self : FeatureError) -> Int {
  match self {
    Table_Already_Exists => 6001
    Table_Not_Found => 6002
    Feature_Already_Exists => 6003
    Feature_Not_Found => 6004
    Vector_Not_Found => 6005
    View_Already_Exists => 6006
    View_Not_Found => 6007
    Invalid_Type => 6008
    Invalid_Value => 6009
    Storage_Error => 6010
    Cache_Error => 6011
    Version_Error => 6012
    Internal_Error(_) => 6099
  }
}

///|
/// 获取错误消息
pub fn FeatureError::message(self : FeatureError) -> String {
  match self {
    Table_Already_Exists => "Feature table already exists"
    Table_Not_Found => "Feature table not found"
    Feature_Already_Exists => "Feature already exists"
    Feature_Not_Found => "Feature not found"
    Vector_Not_Found => "Feature vector not found"
    View_Already_Exists => "Feature view already exists"
    View_Not_Found => "Feature view not found"
    Invalid_Type => "Invalid feature type"
    Invalid_Value => "Invalid feature value"
    Storage_Error => "Storage error"
    Cache_Error => "Cache error"
    Version_Error => "Version error"
    Internal_Error(msg) => "Internal error: " + msg
  }
}

///|
/// 转为字符串
pub fn FeatureError::to_string(self : FeatureError) -> String {
  "[Error " + self.code().to_string() + "] " + self.message()
}
