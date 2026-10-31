// 数据版本控制模块 - 核心类型定义
//
// 定义版本快照、分支、版本历史等核心数据结构

///|
/// 版本状态枚举
pub(all) enum VersionStatus {
  /// 活跃
  Active
  /// 已删除
  Deleted
  /// 已合并
  Merged
} derive(Debug)

///|
pub impl Eq for VersionStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (Active, Active) => true
    (Deleted, Deleted) => true
    (Merged, Merged) => true
    _ => false
  }
}

///|
pub extend VersionStatus with Eq::{equal, not_equal}

///|
pub extend VersionStatus with Debug::{to_repr}

///|
/// 快照类型枚举
pub(all) enum SnapshotType {
  /// 自动快照
  Auto
  /// 手动快照
  Manual
  /// 定时快照
  Scheduled
} derive(Debug)

///|
pub impl Eq for SnapshotType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Auto, Auto) => true
    (Manual, Manual) => true
    (Scheduled, Scheduled) => true
    _ => false
  }
}

///|
pub extend SnapshotType with Eq::{equal, not_equal}

///|
pub extend SnapshotType with Debug::{to_repr}

///|
/// 分支类型枚举
pub(all) enum BranchType {
  /// 主分支
  Main
  /// 开发分支
  Dev
  /// 特性分支
  Feature
  /// 发布分支
  Release
  /// 热修复分支
  Hotfix
} derive(Debug)

///|
pub impl Eq for BranchType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Main, Main) => true
    (Dev, Dev) => true
    (Feature, Feature) => true
    (Release, Release) => true
    (Hotfix, Hotfix) => true
    _ => false
  }
}

///|
pub extend BranchType with Eq::{equal, not_equal}

///|
pub extend BranchType with Debug::{to_repr}

///|
/// 合并策略枚举
pub(all) enum MergeStrategy {
  /// 快进合并
  FastForward
  /// 三方合并
  ThreeWay
  /// 压缩合并
  Squash
  /// 变基合并
  Rebase
} derive(Debug)

///|
pub impl Eq for MergeStrategy with fn equal(self, other) -> Bool {
  match (self, other) {
    (FastForward, FastForward) => true
    (ThreeWay, ThreeWay) => true
    (Squash, Squash) => true
    (Rebase, Rebase) => true
    _ => false
  }
}

///|
pub extend MergeStrategy with Eq::{equal, not_equal}

///|
pub extend MergeStrategy with Debug::{to_repr}

///|
/// 版本快照
pub(all) struct Snapshot {
  /// 快照 ID
  snapshot_id : String
  /// 快照名
  snapshot_name : String
  /// 快照类型
  snapshot_type : SnapshotType
  /// 数据
  data : @realtime_db.Value
  /// 元数据
  metadata : Map[String, @realtime_db.Value]
  /// 创建时间
  created_at : Int32
  /// 过期时间
  expire_at : Int32?
  /// 大小
  size_bytes : Int32
}

///|
/// 分支
pub(all) struct Branch {
  /// 分支 ID
  branch_id : String
  /// 分支名
  branch_name : String
  /// 分支类型
  branch_type : BranchType
  /// 当前版本
  mut current_version : String
  /// 父分支
  parent_branch : String?
  /// 创建时间
  created_at : Int32
  /// 更新时间
  mut updated_at : Int32
}

///|
/// 版本历史
pub(all) struct VersionHistory {
  /// 历史 ID
  history_id : String
  /// 版本列表
  mut versions : Array[VersionEntry]
  /// 分支映射
  mut branches : Map[String, Branch]
  /// 当前分支
  mut current_branch : String
}

///|
/// 版本条目
pub(all) struct VersionEntry {
  /// 版本 ID
  version_id : String
  /// 版本号
  version : Int32
  /// 快照 ID
  snapshot_id : String
  /// 提交信息
  commit_message : String
  /// 作者
  author : String
  /// 时间戳
  timestamp : Int32
  /// 父版本
  parent_version : String?
  /// 分支名
  branch_name : String
}

///|
/// 版本差异
pub(all) struct VersionDiff {
  /// 源版本
  source_version : String
  /// 目标版本
  target_version : String
  /// 变更列表
  changes : Array[VersionChange]
}

///|
/// 版本变更
pub(all) struct VersionChange {
  /// 变更类型
  change_type : ChangeType
  /// 键
  key : String
  /// 旧值
  old_value : @realtime_db.Value?
  /// 新值
  new_value : @realtime_db.Value?
}

///|
/// 变更类型枚举
pub(all) enum ChangeType {
  /// 新增
  Added
  /// 删除
  Deleted
  /// 修改
  Modified
} derive(Debug)

///|
pub impl Eq for ChangeType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Added, Added) => true
    (Deleted, Deleted) => true
    (Modified, Modified) => true
    _ => false
  }
}

///|
pub extend ChangeType with Eq::{equal, not_equal}

///|
pub extend ChangeType with Debug::{to_repr}

///|
/// 时间点查询请求
pub(all) struct PointInTimeQuery {
  /// 时间戳
  timestamp : Int32
  /// 分支名
  branch_name : String?
  /// 版本 ID
  version_id : String?
}

///|
/// 回滚请求
pub(all) struct RollbackRequest {
  /// 目标版本
  target_version : String
  /// 是否创建新版本
  create_new_version : Bool
  /// 提交信息
  commit_message : String
}

///|
/// 版本控制配置
pub(all) struct VersioningConfig {
  /// 是否自动创建快照
  auto_snapshot : Bool
  /// 快照间隔（秒）
  snapshot_interval : Int32
  /// 最大快照数
  max_snapshots : Int32
  /// 快照保留天数
  snapshot_retention_days : Int32
  /// 是否启用分支保护
  enable_branch_protection : Bool
  /// 最大分支数
  max_branches : Int32
}

///|
/// 默认版本控制配置
pub fn VersioningConfig::default() -> VersioningConfig {
  {
    auto_snapshot: true,
    snapshot_interval: 3600,
    max_snapshots: 100,
    snapshot_retention_days: 30,
    enable_branch_protection: true,
    max_branches: 50,
  }
}

///|
/// 版本控制错误类型
pub(all) enum VersioningError {
  /// 快照已存在
  Snapshot_Already_Exists
  /// 快照不存在
  Snapshot_Not_Found
  /// 分支已存在
  Branch_Already_Exists
  /// 分支不存在
  Branch_Not_Found
  /// 版本不存在
  Version_Not_Found
  /// 版本冲突
  Version_Conflict
  /// 合并冲突
  Merge_Conflict
  /// 分支已保护
  Branch_Protected
  /// 分支数超限
  Branch_Limit_Exceeded
  /// 快照数超限
  Snapshot_Limit_Exceeded
  /// 无效操作
  Invalid_Operation
  /// 内部错误
  Internal_Error(String)
} derive(Debug)

///|
pub extend VersioningError with Debug::{to_repr}

///|
pub impl Eq for VersioningError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Snapshot_Already_Exists, Snapshot_Already_Exists) => true
    (Snapshot_Not_Found, Snapshot_Not_Found) => true
    (Branch_Already_Exists, Branch_Already_Exists) => true
    (Branch_Not_Found, Branch_Not_Found) => true
    (Version_Not_Found, Version_Not_Found) => true
    (Version_Conflict, Version_Conflict) => true
    (Merge_Conflict, Merge_Conflict) => true
    (Branch_Protected, Branch_Protected) => true
    (Branch_Limit_Exceeded, Branch_Limit_Exceeded) => true
    (Snapshot_Limit_Exceeded, Snapshot_Limit_Exceeded) => true
    (Invalid_Operation, Invalid_Operation) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend VersioningError with Eq::{equal, not_equal}

///|
/// 获取错误码
pub fn VersioningError::code(self : VersioningError) -> Int32 {
  match self {
    Snapshot_Already_Exists => 8001
    Snapshot_Not_Found => 8002
    Branch_Already_Exists => 8003
    Branch_Not_Found => 8004
    Version_Not_Found => 8005
    Version_Conflict => 8006
    Merge_Conflict => 8007
    Branch_Protected => 8008
    Branch_Limit_Exceeded => 8009
    Snapshot_Limit_Exceeded => 8010
    Invalid_Operation => 8011
    Internal_Error(_) => 8099
  }
}

///|
/// 获取错误消息
pub fn VersioningError::message(self : VersioningError) -> String {
  match self {
    Snapshot_Already_Exists => "Snapshot already exists"
    Snapshot_Not_Found => "Snapshot not found"
    Branch_Already_Exists => "Branch already exists"
    Branch_Not_Found => "Branch not found"
    Version_Not_Found => "Version not found"
    Version_Conflict => "Version conflict"
    Merge_Conflict => "Merge conflict"
    Branch_Protected => "Branch is protected"
    Branch_Limit_Exceeded => "Branch limit exceeded"
    Snapshot_Limit_Exceeded => "Snapshot limit exceeded"
    Invalid_Operation => "Invalid operation"
    Internal_Error(msg) => "Internal error: " + msg
  }
}

///|
/// 转为字符串
pub fn VersioningError::to_string(self : VersioningError) -> String {
  "[Error " + self.code().to_string() + "] " + self.message()
}
