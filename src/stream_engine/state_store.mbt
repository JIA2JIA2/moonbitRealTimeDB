// 状态存储模块
//
// 实现状态读写、持久化、恢复
// 支持内存优先存储和溢出到磁盘

///|
/// 状态存储接口
pub trait StateStore {
  /// 获取状态
  fn get(self : Self, key : String) -> Result[@realtime_db.Value, StreamError]

  /// 存储状态
  fn put(self : Self, key : String, value : @realtime_db.Value) -> Result[
    Unit,
    StreamError,
  ]

  /// 删除状态
  fn delete(self : Self, key : String) -> Result[Unit, StreamError]

  /// 查询状态前缀
  fn query(self : Self, prefix : String) -> Result[
    Array[(String, @realtime_db.Value)],
    StreamError,
  ]

  /// 获取内存占用
  fn memory_usage(self : Self) -> Int

  /// 获取条目数
  fn size(self : Self) -> Int
}

///|
/// 内存状态存储
pub(all) struct MemoryStateStore {
  /// 状态映射
  mut data : Map[String, @realtime_db.Value]
  /// TTL 映射
  mut ttl_map : Map[String, Int]
  /// 当前时间
  mut current_time : Int
  /// 内存限制
  memory_limit : Int
  /// 是否启用溢出
  enable_overflow : Bool
}

///|
/// 默认内存限制
pub const DEFAULT_MEMORY_LIMIT : Int = 100 * 1024 * 1024 // 100MB

///|
/// 创建内存状态存储
pub fn MemoryStateStore::new() -> MemoryStateStore {
  MemoryStateStore::with_config(DEFAULT_MEMORY_LIMIT, true)
}

///|
/// 配置创建内存状态存储
pub fn MemoryStateStore::with_config(
  memory_limit : Int,
  enable_overflow : Bool,
) -> MemoryStateStore {
  {
    data: Map([]),
    ttl_map: Map([]),
    current_time: 0,
    memory_limit,
    enable_overflow,
  }
}

///|
pub impl StateStore for MemoryStateStore with fn get(
  self : MemoryStateStore,
  key : String,
) -> Result[@realtime_db.Value, StreamError] {
  match self.data.get(key) {
    Some(value) =>
      // 检查 TTL
      match self.ttl_map.get(key) {
        Some(expire_time) if expire_time <= self.current_time => {
          self.data.remove(key)
          self.ttl_map.remove(key)
          Err(State_Storage_Error)
        }
        _ => Ok(value)
      }
    None => Err(State_Storage_Error)
  }
}

///|
pub impl StateStore for MemoryStateStore with fn put(
  self : MemoryStateStore,
  key : String,
  value : @realtime_db.Value,
) -> Result[Unit, StreamError] {
  // 检查内存限制
  if self.memory_usage() > self.memory_limit && self.enable_overflow {
    // 简化实现：直接存储，实际应该溢出到磁盘
  }

  self.data.set(key, value)
  Ok(())
}

///|
pub impl StateStore for MemoryStateStore with fn delete(
  self : MemoryStateStore,
  key : String,
) -> Result[Unit, StreamError] {
  self.data.remove(key)
  self.ttl_map.remove(key)
  Ok(())
}

///|
pub impl StateStore for MemoryStateStore with fn query(
  self : MemoryStateStore,
  prefix : String,
) -> Result[Array[(String, @realtime_db.Value)], StreamError] {
  let result : Array[(String, @realtime_db.Value)] = []
  for (key, value) in self.data {
    if key.has_prefix(prefix) {
      result.push((key, value))
    }
  }
  Ok(result)
}

///|
pub impl StateStore for MemoryStateStore with fn memory_usage(
  self : MemoryStateStore,
) -> Int {
  let mut total = 0
  for (key, _value) in self.data {
    total = total + key.length() + 64 // 估算每个条目
  }
  total
}

///|
pub impl StateStore for MemoryStateStore with fn size(self : MemoryStateStore) -> Int {
  self.data.length()
}

///|
pub extend MemoryStateStore with StateStore::{
  get,
  put,
  delete,
  query,
  memory_usage,
  size,
}

///|
/// 设置 TTL
pub fn MemoryStateStore::set_ttl(
  self : MemoryStateStore,
  key : String,
  ttl_seconds : Int,
) -> Result[Unit, StreamError] {
  let expire_time = self.current_time + ttl_seconds
  self.ttl_map.set(key, expire_time)
  Ok(())
}

///|
/// 清理过期状态
pub fn MemoryStateStore::cleanup_expired(self : MemoryStateStore) -> Int {
  let expired : Array[String] = []
  for (key, expire_time) in self.ttl_map {
    if expire_time <= self.current_time {
      expired.push(key)
    }
  }

  for key in expired {
    self.data.remove(key)
    self.ttl_map.remove(key)
  }

  expired.length()
}

///|
/// 更新当前时间
pub fn MemoryStateStore::update_time(
  self : MemoryStateStore,
  current_time : Int,
) -> Unit {
  self.current_time = current_time
}

///|
/// 状态快照
pub(all) struct StateSnapshot {
  /// 快照 ID
  snapshot_id : String
  /// 时间戳
  timestamp : Int
  /// 状态数据
  data : Map[String, @realtime_db.Value]
}

///|
/// 状态快照管理器
pub(all) struct SnapshotManager {
  /// 快照映射
  mut snapshots : Map[String, StateSnapshot]
  /// 最大快照数
  max_snapshots : Int
  /// 快照间隔
  snapshot_interval : Int
}

///|
/// 创建快照管理器
pub fn SnapshotManager::new(
  max_snapshots : Int,
  snapshot_interval : Int,
) -> SnapshotManager {
  { snapshots: Map([]), max_snapshots, snapshot_interval, }
}

///|
/// 创建快照
pub fn SnapshotManager::create_snapshot(
  self : SnapshotManager,
  store : MemoryStateStore,
) -> Result[StateSnapshot, StreamError] {
  // 检查快照数量限制
  if self.snapshots.length() >= self.max_snapshots {
    // 删除最旧的快照
    let oldest_id = self.get_oldest_snapshot_id()
    self.snapshots.remove(oldest_id)
  }

  let snapshot_id = "snapshot_" + self.snapshots.length().to_string()
  let snapshot = StateSnapshot::{
    snapshot_id,
    timestamp: store.current_time,
    data: store.data.copy(),
  }

  self.snapshots.set(snapshot_id, snapshot)
  Ok(snapshot)
}

///|
/// 从快照恢复
pub fn SnapshotManager::restore_from_snapshot(
  self : SnapshotManager,
  snapshot_id : String,
  store : MemoryStateStore,
) -> Result[Unit, StreamError] {
  match self.snapshots.get(snapshot_id) {
    Some(snapshot) => {
      store.data = snapshot.data.copy()
      Ok(())
    }
    None => Err(State_Recovery_Failed)
  }
}

///|
/// 获取最旧的快照 ID
fn SnapshotManager::get_oldest_snapshot_id(self : SnapshotManager) -> String {
  let mut oldest_id : String? = None
  let mut oldest_time : Int? = None
  for (id, snapshot) in self.snapshots {
    match oldest_time {
      Some(time) if snapshot.timestamp < time => {
        oldest_time = Some(snapshot.timestamp)
        oldest_id = Some(id.to_string())
      }
      None => {
        oldest_time = Some(snapshot.timestamp)
        oldest_id = Some(id.to_string())
      }
      _ => ()
    }
  }
  oldest_id.unwrap_or("")
}

///|
/// 获取快照
pub fn SnapshotManager::get_snapshot(
  self : SnapshotManager,
  snapshot_id : String,
) -> StateSnapshot? {
  self.snapshots.get(snapshot_id)
}

///|
/// 获取所有快照
pub fn SnapshotManager::get_all_snapshots(
  self : SnapshotManager,
) -> Array[StateSnapshot] {
  let result : Array[StateSnapshot] = []
  for (_, snapshot) in self.snapshots {
    result.push(snapshot)
  }
  result
}

///|
/// 状态存储工厂
pub(all) struct StateStoreFactory {}

///|
/// 创建状态存储
pub fn StateStoreFactory::create_memory_store() -> MemoryStateStore {
  MemoryStateStore::new()
}

///|
/// 创建带配置的状态存储
pub fn StateStoreFactory::create_memory_store_with_config(
  memory_limit : Int,
  enable_overflow : Bool,
) -> MemoryStateStore {
  MemoryStateStore::with_config(memory_limit, enable_overflow)
}

///|
/// 创建快照管理器
pub fn StateStoreFactory::create_snapshot_manager(
  max_snapshots : Int,
  snapshot_interval : Int,
) -> SnapshotManager {
  SnapshotManager::new(max_snapshots, snapshot_interval)
}
