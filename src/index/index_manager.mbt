// 索引管理器模块
//
// 实现索引生命周期管理（创建、删除、重建、列表）
// 与主存储的事件订阅机制集成

///|
/// 索引定义
pub(all) struct IndexDef {
  /// 索引名称
  name : String
  /// 字段路径数组
  field_paths : Array[String]
  /// 索引类型
  index_type : IndexType
  /// 是否唯一
  is_unique : Bool
  /// 索引状态
  mut status : IndexStatus
  /// 索引存储实例
  mut storage : IndexStorageHandle?
  /// 创建时间
  created_at : Int32
  /// 更新时间
  mut updated_at : Int32
  /// 事件订阅 ID
  mut watch_id : Int32?
}

///|
/// 索引管理器结构体
pub struct IndexManager {
  /// 索引注册表：索引名称 -> 索引定义
  indices : Map[String, IndexDef]
  /// 数据库引用
  mut db : @realtime_db.DB?
  /// 字段路径解析器
  parser : FieldParser
  /// 下一个索引 ID
  next_id : Int32
  /// 单表最大索引数
  max_indices_per_table : Int32
  /// 配置
  config : IndexManagerConfig
}

///|
/// 索引管理器配置
pub struct IndexManagerConfig {
  /// 单表最大索引数
  max_indices_per_table : Int32
  /// 是否自动重建失败的索引
  auto_rebuild : Bool
  /// 重建重试间隔（秒）
  rebuild_retry_interval : Int32
}

///|
/// 默认配置
pub fn IndexManagerConfig::default() -> IndexManagerConfig {
  {
    max_indices_per_table: 16,
    auto_rebuild: true,
    rebuild_retry_interval: 300,
  }
}

///|
/// 创建索引管理器
pub fn IndexManager::new() -> IndexManager {
  IndexManager::with_config(IndexManagerConfig::default())
}

///|
/// 使用配置创建索引管理器
pub fn IndexManager::with_config(config : IndexManagerConfig) -> IndexManager {
  {
    indices: Map([]),
    db: None,
    parser: FieldParser::new(),
    next_id: 0,
    max_indices_per_table: config.max_indices_per_table,
    config,
  }
}

///|
/// 设置数据库引用
pub fn IndexManager::set_db(self : IndexManager, db : @realtime_db.DB?) -> Unit {
  self.db = db
}

///|
/// 创建索引
pub fn IndexManager::create_index(
  self : IndexManager,
  name : String,
  field_paths : Array[String],
  index_type : IndexType,
  is_unique : Bool,
) -> Result[IndexMeta, IndexError] {
  // 检查索引名称是否已存在
  if self.indices.contains(name) {
    return Err(Index_Already_Exists)
  }

  // 检查索引数量限制
  if self.indices.length() >= self.max_indices_per_table {
    return Err(Index_Limit_Exceeded)
  }

  // 验证字段路径
  for path in field_paths {
    if path.length() == 0 {
      return Err(Invalid_Field_Path)
    }
  }

  // 创建索引存储
  let storage = match self.create_storage(name, index_type, field_paths) {
    Some(s) => s
    None => return Err(Unsupported_Type)
  }

  let now = match self.db {
    Some(db) => db.clock()
    None => 0
  }

  let def = {
    name,
    field_paths: field_paths.copy(),
    index_type,
    is_unique,
    status: Created,
    storage: Some(storage),
    created_at: now,
    updated_at: now,
    watch_id: None,
  }

  self.indices.set(name, def)

  // 订阅数据变更事件（先订阅，避免构建期间的变更丢失）
  self.subscribe_events(name)

  // 触发初始构建
  self.build_index(name)

  let meta = {
    name,
    field_paths,
    index_type,
    is_unique,
    status: Active,
    created_at: now,
    updated_at: now,
  }

  Ok(meta)
}

///|
/// 删除索引
pub fn IndexManager::drop_index(
  self : IndexManager,
  name : String,
) -> Result[Unit, IndexError] {
  match self.indices.get(name) {
    Some(def) => {
      // 取消事件订阅
      match def.watch_id {
        Some(watch_id) =>
          match self.db {
            Some(db) => {
              let _ = db.unwatch(watch_id)
            }
            None => ()
          }
        None => ()
      }

      // 清空索引存储
      match def.storage {
        Some(storage) => storage.clear()
        None => ()
      }

      self.indices.remove(name)
      Ok(())
    }
    None => Err(Index_Not_Found)
  }
}

///|
/// 重建索引
pub fn IndexManager::rebuild_index(
  self : IndexManager,
  name : String,
  mode : RebuildMode,
) -> Result[Unit, IndexError] {
  match self.indices.get(name) {
    Some(def) => {
      if def.status is Rebuilding {
        return Err(Index_Rebuilding)
      }
      if def.status is Dropping {
        return Err(Index_Dropped)
      }

      def.status = Rebuilding
      self.indices.set(name, def)

      let result = match mode {
        Full => self.full_rebuild(name)
        Incremental => self.incremental_rebuild(name)
      }

      match result {
        Ok(_) => {
          match self.indices.get(name) {
            Some(d) => {
              d.status = Active
              d.updated_at = self.current_clock()
              self.indices.set(name, d)
            }
            None => ()
          }
          Ok(())
        }
        Err(e) => {
          match self.indices.get(name) {
            Some(d) => {
              d.status = Failed
              self.indices.set(name, d)
            }
            None => ()
          }
          Err(e)
        }
      }
    }
    None => Err(Index_Not_Found)
  }
}

///|
/// 列出所有索引
pub fn IndexManager::list_indexes(self : IndexManager) -> Array[IndexMeta] {
  let result : Array[IndexMeta] = []
  for (name, def) in self.indices {
    result.push({
      name,
      field_paths: def.field_paths.copy(),
      index_type: def.index_type,
      is_unique: def.is_unique,
      status: def.status,
      created_at: def.created_at,
      updated_at: def.updated_at,
    })
  }
  result
}

///|
/// 获取索引元数据
pub fn IndexManager::get_index_meta(
  self : IndexManager,
  name : String,
) -> IndexMeta? {
  match self.indices.get(name) {
    Some(def) =>
      Some({
        name,
        field_paths: def.field_paths.copy(),
        index_type: def.index_type,
        is_unique: def.is_unique,
        status: def.status,
        created_at: def.created_at,
        updated_at: def.updated_at,
      })
    None => None
  }
}

///|
/// 获取索引存储
pub fn IndexManager::get_index_storage(
  self : IndexManager,
  name : String,
) -> IndexStorageHandle? {
  match self.indices.get(name) {
    Some(def) => if def.status is Active { def.storage } else { None }
    None => None
  }
}

///|
/// 当前逻辑时钟
fn IndexManager::current_clock(self : IndexManager) -> Int32 {
  match self.db {
    Some(db) => db.clock()
    None => 0
  }
}

///|
/// 创建索引存储（内部方法）
fn IndexManager::create_storage(
  self : IndexManager,
  name : String,
  index_type : IndexType,
  field_paths : Array[String],
) -> IndexStorageHandle? {
  let _ = self
  match index_type {
    Hash => Some(IndexStorageHandle::Hash(HashIndex::new(name)))
    BTree => Some(IndexStorageHandle::BTree(BTreeIndex::new(name)))
    Fulltext => Some(IndexStorageHandle::Fulltext(FulltextIndex::new(name)))
    Composite => {
      let composite = CompositeIndex::new(name, field_paths.copy())
      let sub : Array[IndexStorageHandle] = []
      for path in field_paths {
        sub.push(IndexStorageHandle::Hash(HashIndex::new(name + "." + path)))
      }
      composite.set_sub_indices(sub)
      Some(IndexStorageHandle::Composite(composite))
    }
  }
}

///|
/// 订阅数据变更事件（内部方法）
fn IndexManager::subscribe_events(self : IndexManager, name : String) -> Unit {
  match self.db {
    Some(db) => {
      let manager = self
      let idx_name = name
      let callback = fn(event : @realtime_db.Event) {
        manager.on_data_change(idx_name, event)
      }
      let watch_id = db.watch_all(callback)
      match self.indices.get(name) {
        Some(def) => {
          def.watch_id = Some(watch_id)
          self.indices.set(name, def)
        }
        None => ()
      }
    }
    None => ()
  }
}

///|
/// 提取记录中存在的字段值（保持字段顺序，跳过不存在的字段）
fn IndexManager::extract_present(
  self : IndexManager,
  value : @realtime_db.Value,
  paths : Array[String],
) -> Array[@realtime_db.Value] {
  let extracted = self.parser.extract_fields(value, paths)
  let present : Array[@realtime_db.Value] = []
  for v in extracted {
    match v {
      Some(fv) => present.push(fv)
      None => ()
    }
  }
  present
}

///|
/// 数据变更回调（内部方法）
fn IndexManager::on_data_change(
  self : IndexManager,
  name : String,
  event : @realtime_db.Event,
) -> Unit {
  match self.indices.get(name) {
    Some(def) =>
      if def.status is Active || def.status is Building {
        match def.storage {
          Some(storage) =>
            match event {
              @realtime_db.Set(key, value, old) => {
                // 先删除旧值
                match old {
                  Some(old_value) =>
                    self.apply_to_storage(def, storage, old_value, key, false)
                  None => ()
                }
                // 再插入新值
                self.apply_to_storage(def, storage, value, key, true)
              }
              @realtime_db.Delete(key, value) =>
                self.apply_to_storage(def, storage, value, key, false)
              @realtime_db.Expire(key, value) =>
                self.apply_to_storage(def, storage, value, key, false)
            }
          None => ()
        }
      }
    None => ()
  }
}

///|
/// 把一条记录的字段值应用到索引存储
fn IndexManager::apply_to_storage(
  self : IndexManager,
  def : IndexDef,
  storage : IndexStorageHandle,
  value : @realtime_db.Value,
  key : String,
  is_insert : Bool,
) -> Unit {
  let field_values = self.extract_present(value, def.field_paths)
  if def.index_type is Composite {
    if is_insert {
      let _ = storage.insert(@realtime_db.Arr(field_values), key)
    } else {
      let _ = storage.delete(@realtime_db.Null, key)
    }
  } else {
    for fv in field_values {
      if is_insert {
        let _ = storage.insert(fv, key)
      } else {
        let _ = storage.delete(fv, key)
      }
    }
  }
}

///|
/// 全量重建（内部方法）
fn IndexManager::full_rebuild(
  self : IndexManager,
  name : String,
) -> Result[Unit, IndexError] {
  match self.indices.get(name) {
    Some(def) =>
      match def.storage {
        Some(storage) => storage.clear()
        None => ()
      }
    None => return Err(Index_Not_Found)
  }

  match self.db {
    Some(db) => {
      let keys = db.keys()
      for key in keys {
        match db.get(key) {
          Some(value) =>
            match self.indices.get(name) {
              Some(def) =>
                match def.storage {
                  Some(storage) =>
                    self.apply_to_storage(def, storage, value, key, true)
                  None => ()
                }
              None => return Err(Index_Not_Found)
            }
          None => ()
        }
      }
      Ok(())
    }
    None => Err(Internal_Error("Database not set"))
  }
}

///|
/// 增量重建（内部方法）
fn IndexManager::incremental_rebuild(
  self : IndexManager,
  name : String,
) -> Result[Unit, IndexError] {
  // 当前实现回退为全量重建
  self.full_rebuild(name)
}

///|
/// 构建索引（初始构建）
fn IndexManager::build_index(self : IndexManager, name : String) -> Unit {
  match self.indices.get(name) {
    Some(def) => {
      def.status = Building
      self.indices.set(name, def)
    }
    None => return
  }

  let result = self.full_rebuild(name)
  match self.indices.get(name) {
    Some(def) => {
      def.status = match result {
        Ok(_) => Active
        Err(_) => Failed
      }
      def.updated_at = self.current_clock()
      self.indices.set(name, def)
    }
    None => ()
  }
}

///|
/// 获取索引数量
pub fn IndexManager::index_count(self : IndexManager) -> Int32 {
  self.indices.length()
}

///|
/// 清除所有索引
pub fn IndexManager::clear_all(self : IndexManager) -> Unit {
  let names : Array[String] = []
  for name, _ in self.indices {
    names.push(name)
  }
  for name in names {
    let _ = self.drop_index(name)
  }
}
