// 版本管理器模块
//
// 实现版本快照、分支管理、版本历史、时间点查询

///|
/// 深拷贝数据库值
fn clone_value(value : @realtime_db.Value) -> @realtime_db.Value {
  match value {
    @realtime_db.Str(s) => @realtime_db.Str(s.to_string())
    @realtime_db.Int(i) => @realtime_db.Int(i)
    @realtime_db.Float(f) => @realtime_db.Float(f)
    @realtime_db.Bool(b) => @realtime_db.Bool(b)
    @realtime_db.Null => @realtime_db.Null
    @realtime_db.Arr(items) => {
      let copied : Array[@realtime_db.Value] = []
      for item in items {
        copied.push(clone_value(item))
      }
      @realtime_db.Arr(copied)
    }
    @realtime_db.Map(items) => {
      let copied : Map[String, @realtime_db.Value] = Map([])
      for (k, v) in items {
        copied.set(k.to_string(), clone_value(v))
      }
      @realtime_db.Map(copied)
    }
  }
}

///|
/// 版本管理器
pub(all) struct VersionManager {
  /// 快照映射
  mut snapshots : Map[String, Snapshot]
  /// 版本历史
  version_history : VersionHistory
  /// 配置
  config : VersioningConfig
  /// 数据库引用
  mut db : @realtime_db.DB?
  /// 下一个快照 ID
  mut next_snapshot_id : Int32
  /// 下一个分支 ID
  mut next_branch_id : Int32
  /// 下一个版本 ID
  mut next_version_id : Int32
}

///|
/// 创建版本管理器
pub fn VersionManager::new(config : VersioningConfig) -> VersionManager {
  {
    snapshots: Map([]),
    version_history: VersionHistory::{
      history_id: "history_0".to_string(),
      versions: [],
      branches: Map([]),
      current_branch: "main".to_string(),
    },
    config,
    db: None,
    next_snapshot_id: 0,
    next_branch_id: 0,
    next_version_id: 0,
  }
}

///|
/// 设置数据库
pub fn VersionManager::set_db(
  self : VersionManager,
  db : @realtime_db.DB?,
) -> Unit {
  self.db = db
}

///|
/// 创建快照
pub fn VersionManager::create_snapshot(
  self : VersionManager,
  name : String,
  snapshot_type : SnapshotType,
  data : @realtime_db.Value,
) -> Result[String, VersioningError] {
  // 检查快照名是否已存在
  for (_, snapshot) in self.snapshots {
    if snapshot.snapshot_name == name {
      return Err(Snapshot_Already_Exists)
    }
  }

  // 检查快照数量限制
  if self.snapshots.length() >= self.config.max_snapshots {
    return Err(Snapshot_Limit_Exceeded)
  }

  // 生成快照 ID
  let snapshot_id = "snap_" + self.next_snapshot_id.to_string()
  self.next_snapshot_id = self.next_snapshot_id + 1

  // 创建快照
  let snapshot = Snapshot::{
    snapshot_id: snapshot_id.to_string(),
    snapshot_name: name,
    snapshot_type,
    data,
    metadata: Map([]),
    created_at: 0,
    expire_at: None,
    size_bytes: 0,
  }

  // 保存快照
  self.snapshots.set(snapshot_id.to_string(), snapshot)

  Ok(snapshot_id)
}

///|
/// 获取快照
pub fn VersionManager::get_snapshot(
  self : VersionManager,
  snapshot_id : String,
) -> Snapshot? {
  self.snapshots.get(snapshot_id)
}

///|
/// 列出所有快照
pub fn VersionManager::list_snapshots(self : VersionManager) -> Array[Snapshot] {
  let result : Array[Snapshot] = []
  for (_, snapshot) in self.snapshots {
    result.push(snapshot)
  }
  result
}

///|
/// 删除快照
pub fn VersionManager::delete_snapshot(
  self : VersionManager,
  snapshot_id : String,
) -> Result[Unit, VersioningError] {
  if !self.snapshots.contains(snapshot_id.to_string()) {
    return Err(Snapshot_Not_Found)
  }

  self.snapshots.remove(snapshot_id)

  Ok(())
}

///|
/// 创建分支
pub fn VersionManager::create_branch(
  self : VersionManager,
  branch_name : String,
  branch_type : BranchType,
  parent_branch : String?,
) -> Result[String, VersioningError] {
  // 检查分支名是否已存在
  for (_, branch) in self.version_history.branches {
    if branch.branch_name == branch_name {
      return Err(Branch_Already_Exists)
    }
  }

  // 检查分支数量限制
  if self.version_history.branches.length() >= self.config.max_branches {
    return Err(Branch_Limit_Exceeded)
  }

  // 生成分支 ID
  let branch_id = "branch_" + self.next_branch_id.to_string()
  self.next_branch_id = self.next_branch_id + 1

  // 获取父分支的当前版本
  let parent_name = match parent_branch {
    Some(pb) => pb
    None => "main".to_string()
  }
  let parent_version = match self.get_branch_by_name(parent_name) {
    Some(b) => b.current_version.to_string()
    None => "".to_string()
  }

  // 创建分支
  let branch = Branch::{
    branch_id: branch_id.to_string(),
    branch_name,
    branch_type,
    current_version: parent_version,
    parent_branch,
    created_at: 0,
    updated_at: 0,
  }

  // 保存分支
  self.version_history.branches.set(branch_id.to_string(), branch)

  Ok(branch_id)
}

///|
/// 获取分支
pub fn VersionManager::get_branch(
  self : VersionManager,
  branch_id : String,
) -> Branch? {
  self.version_history.branches.get(branch_id)
}

///|
/// 根据名称获取分支
fn VersionManager::get_branch_by_name(
  self : VersionManager,
  branch_name : String,
) -> Branch? {
  for (_, branch) in self.version_history.branches {
    if branch.branch_name == branch_name {
      return Some(branch)
    }
  }
  None
}

///|
/// 列出所有分支
pub fn VersionManager::list_branches(self : VersionManager) -> Array[Branch] {
  let result : Array[Branch] = []
  for (_, branch) in self.version_history.branches {
    result.push(branch)
  }
  result
}

///|
/// 删除分支
pub fn VersionManager::delete_branch(
  self : VersionManager,
  branch_id : String,
) -> Result[Unit, VersioningError] {
  // 检查分支是否存在
  let branch = match self.version_history.branches.get(branch_id.to_string()) {
    Some(b) => b
    None => return Err(Branch_Not_Found)
  }

  // 检查是否是主分支
  if branch.branch_type == Main {
    return Err(Branch_Protected)
  }

  // 删除分支
  self.version_history.branches.remove(branch_id)

  Ok(())
}

///|
/// 提交版本
pub fn VersionManager::commit(
  self : VersionManager,
  branch_name : String,
  commit_message : String,
  author : String,
  snapshot_id : String,
) -> Result[String, VersioningError] {
  // 检查分支是否存在
  let branch = match self.get_branch_by_name(branch_name) {
    Some(b) => b
    None => return Err(Branch_Not_Found)
  }

  // 检查快照是否存在
  if !self.snapshots.contains(snapshot_id.to_string()) {
    return Err(Snapshot_Not_Found)
  }

  // 生成版本 ID
  let version_id = "ver_" + self.next_version_id.to_string()
  self.next_version_id = self.next_version_id + 1

  // 记录父版本
  let parent_version = branch.current_version.to_string()

  // 更新分支当前版本
  branch.current_version = version_id.to_string()
  branch.updated_at = 0

  // 创建版本条目
  let version_entry = VersionEntry::{
    version_id: version_id.to_string(),
    version: self.version_history.versions.length(),
    snapshot_id,
    commit_message,
    author,
    timestamp: 0,
    parent_version: Some(parent_version),
    branch_name,
  }

  // 保存版本
  self.version_history.versions.push(version_entry)

  Ok(version_id)
}

///|
/// 获取版本
pub fn VersionManager::get_version(
  self : VersionManager,
  version_id : String,
) -> VersionEntry? {
  for version in self.version_history.versions {
    if version.version_id == version_id {
      return Some(version)
    }
  }
  None
}

///|
/// 获取版本历史
pub fn VersionManager::get_version_history(
  self : VersionManager,
  branch_name : String?,
) -> Array[VersionEntry] {
  let result : Array[VersionEntry] = []
  let has_filter = branch_name != None
  let filter_name = match branch_name {
    Some(name) => name
    None => "".to_string()
  }

  for version in self.version_history.versions {
    if !has_filter || version.branch_name == filter_name {
      result.push(version)
    }
  }

  result
}

///|
/// 比较版本差异
pub fn VersionManager::diff(
  self : VersionManager,
  source_version : String,
  target_version : String,
) -> Result[VersionDiff, VersioningError] {
  // 获取源版本
  let src_ver = match self.get_version(source_version) {
    Some(v) => v
    None => return Err(Version_Not_Found)
  }

  // 获取目标版本
  let tgt_ver = match self.get_version(target_version) {
    Some(v) => v
    None => return Err(Version_Not_Found)
  }

  // 检查两端快照均存在
  match self.snapshots.get(src_ver.snapshot_id) {
    Some(_) => ()
    None => return Err(Snapshot_Not_Found)
  }
  match self.snapshots.get(tgt_ver.snapshot_id) {
    Some(_) => ()
    None => return Err(Snapshot_Not_Found)
  }

  // 简化实现：返回空差异
  Ok(VersionDiff::{ source_version, target_version, changes: [], })
}

///|
/// 合并分支
pub fn VersionManager::merge(
  self : VersionManager,
  source_branch : String,
  target_branch : String,
  strategy : MergeStrategy,
  commit_message : String,
) -> Result[String, VersioningError] {
  // 检查源分支是否存在
  match self.get_branch_by_name(source_branch.to_string()) {
    Some(_) => ()
    None => return Err(Branch_Not_Found)
  }

  // 检查目标分支是否存在
  match self.get_branch_by_name(target_branch.to_string()) {
    Some(_) => ()
    None => return Err(Branch_Not_Found)
  }

  let _ = strategy
  // 简化实现：四种策略均按快进合并处理
  self.fast_forward_merge(source_branch, target_branch, commit_message)
}

///|
/// 快进合并
fn VersionManager::fast_forward_merge(
  self : VersionManager,
  source_name : String,
  target_name : String,
  commit_message : String,
) -> Result[String, VersioningError] {
  // 读取源分支当前版本
  let source_version = match self.get_branch_by_name(source_name) {
    Some(b) => b.current_version.to_string()
    None => return Err(Branch_Not_Found)
  }

  // 更新目标分支版本
  let target_branch_name = match self.get_branch_by_name(target_name) {
    Some(b) => {
      let name = b.branch_name.to_string()
      b.current_version = source_version.to_string()
      b.updated_at = 0
      name
    }
    None => return Err(Branch_Not_Found)
  }

  // 创建合并提交
  let version_id = "ver_" + self.next_version_id.to_string()
  self.next_version_id = self.next_version_id + 1

  let version_entry = VersionEntry::{
    version_id: version_id.to_string(),
    version: self.version_history.versions.length(),
    snapshot_id: "".to_string(),
    commit_message,
    author: "merge".to_string(),
    timestamp: 0,
    parent_version: Some(source_version),
    branch_name: target_branch_name,
  }

  self.version_history.versions.push(version_entry)

  Ok(version_id)
}

///|
/// 回滚到指定版本
pub fn VersionManager::rollback(
  self : VersionManager,
  request : RollbackRequest,
) -> Result[String, VersioningError] {
  // 获取目标版本
  let target_version = match
    self.get_version(request.target_version.to_string()) {
    Some(v) => v
    None => return Err(Version_Not_Found)
  }

  // 获取快照数据的拷贝
  let snapshot_data = match self.snapshots.get(target_version.snapshot_id) {
    Some(s) => clone_value(s.data)
    None => return Err(Snapshot_Not_Found)
  }

  // 如果需要创建新版本
  if request.create_new_version {
    // 创建新快照
    let snapshot_id = match
      self.create_snapshot(
        "rollback_" + request.target_version.to_string(),
        Manual,
        snapshot_data,
      ) {
      Ok(id) => id
      Err(e) => return Err(e)
    }

    // 创建新版本
    self.commit(
      target_version.branch_name.to_string(),
      request.commit_message,
      "rollback".to_string(),
      snapshot_id,
    )
  } else {
    // 直接更新分支
    match self.get_branch_by_name(target_version.branch_name.to_string()) {
      Some(branch) => {
        branch.current_version = request.target_version.to_string()
        branch.updated_at = 0
      }
      None => return Err(Branch_Not_Found)
    }

    Ok(request.target_version)
  }
}

///|
/// 时间点查询
pub fn VersionManager::point_in_time_query(
  self : VersionManager,
  query : PointInTimeQuery,
) -> Result[@realtime_db.Value, VersioningError] {
  let branch_name = match query.branch_name {
    Some(name) => name
    None => "".to_string()
  }

  // 查找最接近的版本
  let target_version = self.find_closest_version(query.timestamp, branch_name)

  match target_version {
    Some(v) =>
      // 获取快照数据
      match self.snapshots.get(v.snapshot_id) {
        Some(snapshot) => Ok(clone_value(snapshot.data))
        None => Err(Snapshot_Not_Found)
      }
    None => Err(Version_Not_Found)
  }
}

///|
/// 查找最接近的版本
fn VersionManager::find_closest_version(
  self : VersionManager,
  timestamp : Int32,
  branch_name : String,
) -> VersionEntry? {
  let mut closest : VersionEntry? = None
  let mut min_diff : Int32? = None

  for version in self.version_history.versions {
    if version.branch_name == branch_name {
      let diff = if version.timestamp > timestamp {
        version.timestamp - timestamp
      } else {
        timestamp - version.timestamp
      }

      match min_diff {
        None => {
          min_diff = Some(diff)
          closest = Some(version)
        }
        Some(m) =>
          if diff < m {
            min_diff = Some(diff)
            closest = Some(version)
          }
      }
    }
  }

  closest
}

///|
/// 清理过期快照
pub fn VersionManager::cleanup_expired_snapshots(
  self : VersionManager,
) -> Int32 {
  let expired : Array[String] = []

  for (snapshot_id, snapshot) in self.snapshots {
    match snapshot.expire_at {
      Some(expire) => if expire <= 0 { expired.push(snapshot_id.to_string()) }
      None => ()
    }
  }

  for snapshot_id in expired {
    self.snapshots.remove(snapshot_id)
  }

  expired.length()
}

///|
/// 获取快照数量
pub fn VersionManager::snapshot_count(self : VersionManager) -> Int32 {
  self.snapshots.length()
}

///|
/// 获取分支数量
pub fn VersionManager::branch_count(self : VersionManager) -> Int32 {
  self.version_history.branches.length()
}

///|
/// 创建版本管理器
pub fn create_version_manager(config : VersioningConfig) -> VersionManager {
  VersionManager::new(config)
}

///|
/// 创建默认版本管理器
pub fn create_default_version_manager() -> VersionManager {
  VersionManager::new(VersioningConfig::default())
}
