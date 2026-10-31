// 索引类型定义模块
//
// 定义二级索引组件所需的核心枚举类型

///|
/// 索引类型
pub(all) enum IndexType {
  /// Hash 索引：等值查询 O(1)
  Hash
  /// B+树索引：范围查询 O(log n)
  BTree
  /// 前缀树索引：前缀匹配 O(m)
  Fulltext
  /// 复合索引：多字段组合
  Composite
}

///|
pub impl Eq for IndexType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Hash, Hash) => true
    (BTree, BTree) => true
    (Fulltext, Fulltext) => true
    (Composite, Composite) => true
    _ => false
  }
}

///|
pub extend IndexType with Eq::{equal, not_equal}

///|
pub impl Debug for IndexType with fn to_repr(self) -> Repr {
  match self {
    Hash => Repr::ctor("Hash", [])
    BTree => Repr::ctor("BTree", [])
    Fulltext => Repr::ctor("Fulltext", [])
    Composite => Repr::ctor("Composite", [])
  }
}

///|
pub extend IndexType with Debug::{to_repr}

///|
/// 索引状态
pub(all) enum IndexStatus {
  /// 已创建
  Created
  /// 构建中
  Building
  /// 活跃（可查询）
  Active
  /// 删除中
  Dropping
  /// 重建中
  Rebuilding
  /// 失败
  Failed
}

///|
pub impl Eq for IndexStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Created, Created) => true
    (Building, Building) => true
    (Active, Active) => true
    (Dropping, Dropping) => true
    (Rebuilding, Rebuilding) => true
    (Failed, Failed) => true
    _ => false
  }
}

///|
pub extend IndexStatus with Eq::{equal, not_equal}

///|
pub impl Debug for IndexStatus with fn to_repr(self) -> Repr {
  match self {
    Created => Repr::ctor("Created", [])
    Building => Repr::ctor("Building", [])
    Active => Repr::ctor("Active", [])
    Dropping => Repr::ctor("Dropping", [])
    Rebuilding => Repr::ctor("Rebuilding", [])
    Failed => Repr::ctor("Failed", [])
  }
}

///|
pub extend IndexStatus with Debug::{to_repr}

///|
/// 索引重建模式
pub(all) enum RebuildMode {
  /// 全量重建
  Full
  /// 增量重建
  Incremental
}

///|
pub impl Eq for RebuildMode with fn equal(self, other) -> Bool {
  match (self, other) {
    (Full, Full) => true
    (Incremental, Incremental) => true
    _ => false
  }
}

///|
pub extend RebuildMode with Eq::{equal, not_equal}

///|
pub impl Debug for RebuildMode with fn to_repr(self) -> Repr {
  match self {
    Full => Repr::ctor("Full", [])
    Incremental => Repr::ctor("Incremental", [])
  }
}

///|
pub extend RebuildMode with Debug::{to_repr}

///|
/// 索引元数据
pub(all) struct IndexMeta {
  /// 索引名称
  name : String
  /// 字段路径数组
  field_paths : Array[String]
  /// 索引类型
  index_type : IndexType
  /// 是否唯一
  is_unique : Bool
  /// 当前状态
  status : IndexStatus
  /// 创建时间（逻辑时钟）
  created_at : Int32
  /// 更新时间（逻辑时钟）
  updated_at : Int32
}

///|
/// 索引统计信息
pub(all) struct IndexStats {
  /// 索引名称
  name : String
  /// 基数（唯一值数量）
  cardinality : Int32
  /// 总条目数
  total_entries : Int32
  /// 内存占用（字节）
  memory_usage : Int32
  /// 碎片率（0.0-1.0）
  fragmentation_rate : Double
  /// 命中率（0.0-1.0）
  hit_rate : Double
  /// 查询延迟 P99（微秒）
  query_latency_p99 : Int32
  /// 更新延迟 P99（微秒）
  update_latency_p99 : Int32
}

///|
/// 索引配置选项
pub struct IndexOptions {
  /// 缓存大小（条目数）
  cache_size : Int32
  /// 并发度
  concurrency : Int32
  /// 是否启用统计收集
  enable_stats : Bool
  /// 统计收集间隔（秒）
  stats_interval : Int32
}

///|
/// 默认配置
pub fn IndexOptions::default() -> IndexOptions {
  {
    cache_size: 1000,
    concurrency: 1,
    enable_stats: true,
    stats_interval: 3600,
  }
}
