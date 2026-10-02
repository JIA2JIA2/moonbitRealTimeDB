// 快照持久化模块
//
// 提供快照创建、加载和定时触发功能，用于数据备份和恢复。

///|
/// 快照元数据
pub struct SnapshotMetadata {
  /// 创建时间
  create_time : Int
  /// 数据大小（字节）
  size : Int
  /// 校验和
  checksum : String
  /// 快照版本号
  version : Int
}

///|
/// 快照结构体
pub struct Snapshot {
  /// 快照元数据
  metadata : SnapshotMetadata
  /// 快照数据（序列化的键值对）
  data : Map[String, String]
}

///|
/// 快照调度器
/// 管理快照的定时触发和保留策略
pub struct SnapshotScheduler {
  /// 快照间隔（秒）
  interval : Int
  /// 上次快照时间
  mut last_snapshot_time : Int
  /// 最大保留快照数
  max_retention : Int
  /// 快照文件列表
  snapshots : Array[String]
}

///|
/// 创建快照元数据
pub fn SnapshotMetadata::new(
  create_time : Int,
  size : Int,
  checksum : String,
  version : Int,
) -> SnapshotMetadata {
  { create_time, size, checksum, version, }
}

///|
/// 获取创建时间
pub fn SnapshotMetadata::create_time(self : SnapshotMetadata) -> Int {
  self.create_time
}

///|
/// 获取数据大小
pub fn SnapshotMetadata::size(self : SnapshotMetadata) -> Int {
  self.size
}

///|
/// 获取校验和
pub fn SnapshotMetadata::checksum(self : SnapshotMetadata) -> String {
  self.checksum
}

///|
/// 获取版本号
pub fn SnapshotMetadata::version(self : SnapshotMetadata) -> Int {
  self.version
}

///|
/// 创建快照
///
/// ## 参数
/// - data: 要快照的数据（键值对）
/// - version: 快照版本号
///
/// ## 返回
/// 创建的快照
pub fn Snapshot::create(data : Map[String, String], version : Int) -> Snapshot {
  let mut size = 0
  for k, v in data {
    size = size + k.length() + v.length()
  }

  let metadata = SnapshotMetadata::new(
    0, // 实际使用时需要传入时间戳
     size, "", // 实际使用时需要计算校验和
     version,
  )

  { metadata, data, }
}

///|
/// 加载快照
///
/// ## 参数
/// - data: 快照数据
/// - metadata: 快照元数据
///
/// ## 返回
/// 加载的快照
pub fn Snapshot::load(
  data : Map[String, String],
  metadata : SnapshotMetadata,
) -> Snapshot {
  { metadata, data, }
}

///|
/// 获取快照元数据
pub fn Snapshot::metadata(self : Snapshot) -> SnapshotMetadata {
  self.metadata
}

///|
/// 获取快照数据
pub fn Snapshot::data(self : Snapshot) -> Map[String, String] {
  self.data
}

///|
/// 创建快照调度器
pub fn SnapshotScheduler::new(
  interval : Int,
  max_retention : Int,
) -> SnapshotScheduler {
  { interval, last_snapshot_time: 0, max_retention, snapshots: [], }
}

///|
/// 检查是否需要创建快照
///
/// ## 参数
/// - current_time: 当前时间
///
/// ## 返回
/// - true: 需要创建快照
/// - false: 不需要创建快照
pub fn SnapshotScheduler::should_snapshot(
  self : SnapshotScheduler,
  current_time : Int,
) -> Bool {
  current_time - self.last_snapshot_time >= self.interval
}

///|
/// 记录快照创建
///
/// ## 参数
/// - snapshot_path: 快照文件路径
/// - current_time: 当前时间
pub fn SnapshotScheduler::record_snapshot(
  self : SnapshotScheduler,
  snapshot_path : String,
  current_time : Int,
) -> Unit {
  self.last_snapshot_time = current_time
  self.snapshots.push(snapshot_path)

  // 超过保留数时淘汰最老的快照（队首）
  while self.snapshots.length() > self.max_retention {
    let _ = self.snapshots.remove(0)
  }
}

///|
/// 获取快照列表
pub fn SnapshotScheduler::snapshots(self : SnapshotScheduler) -> Array[String] {
  self.snapshots
}

///|
/// 获取最大保留数
pub fn SnapshotScheduler::max_retention(self : SnapshotScheduler) -> Int {
  self.max_retention
}
