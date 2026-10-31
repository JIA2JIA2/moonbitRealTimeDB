// 特征存储管理器模块
//
// 实现特征表管理、特征向量读写、特征视图管理

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
/// 深拷贝特征值映射
fn clone_value_map(
  values : Map[String, @realtime_db.Value],
) -> Map[String, @realtime_db.Value] {
  let copied : Map[String, @realtime_db.Value] = Map([])
  for (k, v) in values {
    copied.set(k.to_string(), clone_value(v))
  }
  copied
}

///|
/// 深拷贝特征向量
fn clone_vector(vector : FeatureVector) -> FeatureVector {
  FeatureVector::{
    vector_id: vector.vector_id.to_string(),
    entity_id: vector.entity_id.to_string(),
    table_id: vector.table_id.to_string(),
    values: clone_value_map(vector.values),
    version: vector.version,
    timestamp: vector.timestamp,
    is_valid: vector.is_valid,
  }
}

///|
/// 特征存储管理器
pub(all) struct FeatureStoreManager {
  /// 特征表映射
  mut tables : Map[String, FeatureTable]
  /// 特征视图映射
  mut views : Map[String, FeatureView]
  /// 在线存储
  online_storage : MemoryOnlineStorage
  /// 离线存储
  offline_storage : DeltaLakeOfflineStorage
  /// 缓存
  cache : FeatureCache
  /// 配置
  config : FeatureStoreConfig
  /// 下一个表 ID
  mut next_table_id : Int32
  /// 下一个视图 ID
  mut next_view_id : Int32
}

///|
/// 在线存储接口
pub trait OnlineStorage {
  /// 获取特征向量
  fn get_vector(self : Self, table_id : String, entity_id : String) -> Result[
    FeatureVector,
    FeatureError,
  ]
  /// 写入特征向量
  fn put_vector(self : Self, vector : FeatureVector) -> Result[
    Unit,
    FeatureError,
  ]
  /// 删除特征向量
  fn delete_vector(self : Self, table_id : String, entity_id : String) -> Result[
    Unit,
    FeatureError,
  ]
  /// 批量获取
  fn batch_get(self : Self, table_id : String, entity_ids : Array[String]) -> Result[
    Array[FeatureVector],
    FeatureError,
  ]
  /// 批量写入
  fn batch_put(self : Self, vectors : Array[FeatureVector]) -> Result[
    Unit,
    FeatureError,
  ]
  /// 获取内存占用
  fn memory_usage(self : Self) -> Int32
}

///|
/// 离线存储接口
pub trait OfflineStorage {
  /// 写入特征向量
  fn write_vector(self : Self, vector : FeatureVector) -> Result[
    Unit,
    FeatureError,
  ]
  /// 批量写入
  fn batch_write(self : Self, vectors : Array[FeatureVector]) -> Result[
    Unit,
    FeatureError,
  ]
  /// 读取历史版本
  fn read_history(
    self : Self,
    table_id : String,
    entity_id : String,
    version : Int32,
  ) -> Result[FeatureVector, FeatureError]
  /// 导出数据
  fn export_data(self : Self, table_id : String, format : String) -> Result[
    Array[FeatureVector],
    FeatureError,
  ]
}

///|
/// 内存在线存储
pub(all) struct MemoryOnlineStorage {
  /// 数据存储：表ID -> 实体ID -> 特征向量
  mut data : Map[String, Map[String, FeatureVector]]
  /// 内存限制
  memory_limit : Int32
}

///|
/// 创建内存在线存储
pub fn MemoryOnlineStorage::new(memory_limit : Int32) -> MemoryOnlineStorage {
  { data: Map([]), memory_limit, }
}

///|
pub impl OnlineStorage for MemoryOnlineStorage with fn get_vector(
  self : MemoryOnlineStorage,
  table_id : String,
  entity_id : String,
) -> Result[FeatureVector, FeatureError] {
  match self.data.get(table_id) {
    Some(table_data) =>
      match table_data.get(entity_id) {
        Some(vector) => Ok({ ..vector, })
        None => Err(Vector_Not_Found)
      }
    None => Err(Table_Not_Found)
  }
}

///|
pub impl OnlineStorage for MemoryOnlineStorage with fn put_vector(
  self : MemoryOnlineStorage,
  vector : FeatureVector,
) -> Result[Unit, FeatureError] {
  let table_id = vector.table_id.to_string()
  match self.data.get(table_id) {
    Some(table_data) => table_data.set(vector.entity_id.to_string(), vector)
    None => {
      let new_data : Map[String, FeatureVector] = Map([])
      new_data.set(vector.entity_id.to_string(), { ..vector, })
      self.data.set(table_id, new_data)
    }
  }
  Ok(())
}

///|
pub impl OnlineStorage for MemoryOnlineStorage with fn delete_vector(
  self : MemoryOnlineStorage,
  table_id : String,
  entity_id : String,
) -> Result[Unit, FeatureError] {
  match self.data.get(table_id) {
    Some(table_data) => {
      table_data.remove(entity_id)
      Ok(())
    }
    None => Err(Table_Not_Found)
  }
}

///|
pub impl OnlineStorage for MemoryOnlineStorage with fn batch_get(
  self : MemoryOnlineStorage,
  table_id : String,
  entity_ids : Array[String],
) -> Result[Array[FeatureVector], FeatureError] {
  let result : Array[FeatureVector] = []
  match self.data.get(table_id) {
    Some(table_data) => {
      for entity_id in entity_ids {
        match table_data.get(entity_id) {
          Some(vector) => result.push({ ..vector, })
          None => ()
        }
      }
      Ok(result)
    }
    None => Err(Table_Not_Found)
  }
}

///|
pub impl OnlineStorage for MemoryOnlineStorage with fn batch_put(
  self : MemoryOnlineStorage,
  vectors : Array[FeatureVector],
) -> Result[Unit, FeatureError] {
  for vector in vectors {
    let _ = self.put_vector(vector)
  }
  Ok(())
}

///|
pub impl OnlineStorage for MemoryOnlineStorage with fn memory_usage(
  self : MemoryOnlineStorage,
) -> Int32 {
  let mut total = 0
  for (_, table_data) in self.data {
    total = total + table_data.length() * 1024 // 估算每个向量 1KB
  }
  total
}

///|
pub extend MemoryOnlineStorage with OnlineStorage::{
  get_vector,
  put_vector,
  delete_vector,
  batch_get,
  batch_put,
  memory_usage,
}

///|
/// 特征缓存
pub(all) struct FeatureCache {
  /// 缓存数据
  mut cache : Map[String, FeatureVector]
  /// 缓存大小
  max_size : Int32
  /// 缓存 TTL（秒）
  ttl : Int32
  /// 命中次数
  mut hit_count : Int32
  /// 总查询次数
  mut query_count : Int32
}

///|
/// 创建特征缓存
pub fn FeatureCache::new(max_size : Int32, ttl : Int32) -> FeatureCache {
  { cache: Map([]), max_size, ttl, hit_count: 0, query_count: 0, }
}

///|
/// 获取特征向量
pub fn FeatureCache::get(self : FeatureCache, key : String) -> FeatureVector? {
  self.query_count = self.query_count + 1
  match self.cache.get(key) {
    Some(vector) => {
      self.hit_count = self.hit_count + 1
      Some({ ..vector, })
    }
    None => None
  }
}

///|
/// 写入特征向量
pub fn FeatureCache::put(
  self : FeatureCache,
  key : String,
  vector : FeatureVector,
) -> Unit {
  // 检查缓存大小
  if self.cache.length() >= self.max_size {
    // 简化实现：淘汰第一个条目（先找出键再删除，避免遍历时修改）
    let mut evict_key : String? = None
    for (k, _) in self.cache {
      evict_key = Some(k.to_string())
      break
    }
    match evict_key {
      Some(k) => self.cache.remove(k)
      None => ()
    }
  }

  self.cache.set(key, vector)
}

///|
/// 删除特征向量
pub fn FeatureCache::remove(self : FeatureCache, key : String) -> Unit {
  self.cache.remove(key)
}

///|
/// 清空缓存
pub fn FeatureCache::clear(self : FeatureCache) -> Unit {
  self.cache = Map([])
}

///|
/// 获取命中率
pub fn FeatureCache::hit_rate(self : FeatureCache) -> Double {
  if self.query_count == 0 {
    0.0
  } else {
    self.hit_count.to_double() / self.query_count.to_double()
  }
}

///|
/// 创建特征存储管理器
pub fn FeatureStoreManager::new(
  config : FeatureStoreConfig,
) -> FeatureStoreManager {
  {
    tables: Map([]),
    views: Map([]),
    online_storage: MemoryOnlineStorage::new(1073741824),
    offline_storage: DeltaLakeOfflineStorage::{ _placeholder: (), },
    cache: FeatureCache::new(config.cache_size, config.cache_ttl),
    config,
    next_table_id: 0,
    next_view_id: 0,
  }
}

///|
/// 创建特征表
pub fn FeatureStoreManager::create_table(
  self : FeatureStoreManager,
  table_name : String,
  primary_key : String,
  features : Array[Feature],
) -> Result[String, FeatureError] {
  // 检查表是否已存在
  for (_, table) in self.tables {
    if table.table_name == table_name {
      return Err(Table_Already_Exists)
    }
  }

  // 生成表 ID
  let table_id = "table_" + self.next_table_id.to_string()
  self.next_table_id = self.next_table_id + 1

  // 创建表
  let table = FeatureTable::{
    table_id: table_id.to_string(),
    table_name,
    features,
    primary_key,
    created_at: 0,
    updated_at: 0,
  }

  // 保存表
  self.tables.set(table_id.to_string(), table)

  Ok(table_id)
}

///|
/// 获取特征表
pub fn FeatureStoreManager::get_table(
  self : FeatureStoreManager,
  table_id : String,
) -> FeatureTable? {
  self.tables.get(table_id)
}

///|
/// 获取特征表 ID
pub fn FeatureStoreManager::get_table_id(
  self : FeatureStoreManager,
  table_name : String,
) -> String? {
  for (table_id, table) in self.tables {
    if table.table_name == table_name {
      return Some(table_id.to_string())
    }
  }
  None
}

///|
/// 列出所有特征表
pub fn FeatureStoreManager::list_tables(
  self : FeatureStoreManager,
) -> Array[FeatureTable] {
  let result : Array[FeatureTable] = []
  for (_, table) in self.tables {
    result.push(table)
  }
  result
}

///|
/// 更新特征表
pub fn FeatureStoreManager::update_table(
  self : FeatureStoreManager,
  table_id : String,
  features : Array[Feature],
) -> Result[Unit, FeatureError] {
  match self.tables.get(table_id) {
    Some(table) => {
      table.features = features
      table.updated_at = 0
      Ok(())
    }
    None => Err(Table_Not_Found)
  }
}

///|
/// 删除特征表
pub fn FeatureStoreManager::delete_table(
  self : FeatureStoreManager,
  table_id : String,
) -> Result[Unit, FeatureError] {
  if !self.tables.contains(table_id.to_string()) {
    return Err(Table_Not_Found)
  }

  self.tables.remove(table_id)

  Ok(())
}

///|
/// 添加特征
pub fn FeatureStoreManager::add_feature(
  self : FeatureStoreManager,
  table_id : String,
  feature : Feature,
) -> Result[Unit, FeatureError] {
  match self.tables.get(table_id) {
    Some(table) => {
      // 检查特征是否已存在
      for existing_feature in table.features {
        if existing_feature.feature_name == feature.feature_name {
          return Err(Feature_Already_Exists)
        }
      }

      table.features.push(feature)
      table.updated_at = 0
      Ok(())
    }
    None => Err(Table_Not_Found)
  }
}

///|
/// 写入特征向量
pub fn FeatureStoreManager::write_vector(
  self : FeatureStoreManager,
  request : FeatureWriteRequest,
) -> Result[Unit, FeatureError] {
  // 检查表是否存在
  if !self.tables.contains(request.table_id.to_string()) {
    return Err(Table_Not_Found)
  }

  // 创建特征向量（在线存储、离线存储、缓存各持一份独立拷贝）
  let vector = FeatureVector::{
    vector_id: request.table_id.to_string() +
    "_" +
    request.entity_id.to_string(),
    entity_id: request.entity_id.to_string(),
    table_id: request.table_id.to_string(),
    values: request.values,
    version: 1,
    timestamp: 0,
    is_valid: true,
  }

  // 写入在线存储
  let _ = self.online_storage.put_vector(clone_vector(vector))

  // 写入离线存储
  let _ = self.offline_storage.write_vector(clone_vector(vector))

  // 更新缓存
  let cache_key = vector.table_id.to_string() +
    ":" +
    vector.entity_id.to_string()
  self.cache.put(cache_key, clone_vector(vector))

  Ok(())
}

///|
/// 读取特征向量
pub fn FeatureStoreManager::read_vector(
  self : FeatureStoreManager,
  request : FeatureQueryRequest,
) -> Result[FeatureVector, FeatureError] {
  // 检查缓存
  let cache_key = request.table_id.to_string() +
    ":" +
    request.entity_id.to_string()
  if request.use_cache {
    match self.cache.get(cache_key) {
      Some(vector) => return Ok(vector)
      None => ()
    }
  }

  // 从在线存储获取
  let vector = match
    self.online_storage.get_vector(request.table_id, request.entity_id) {
    Ok(v) => v
    Err(e) => return Err(e)
  }

  // 更新缓存
  if request.use_cache {
    self.cache.put(cache_key, clone_vector(vector))
  }

  Ok(vector)
}

///|
/// 批量读取特征向量
pub fn FeatureStoreManager::batch_read(
  self : FeatureStoreManager,
  table_id : String,
  entity_ids : Array[String],
  use_cache : Bool,
) -> Result[Array[FeatureVector], FeatureError] {
  let _ = use_cache
  // 从在线存储批量获取
  self.online_storage.batch_get(table_id, entity_ids)
}

///|
/// 批量写入特征向量
pub fn FeatureStoreManager::batch_write(
  self : FeatureStoreManager,
  requests : Array[FeatureWriteRequest],
) -> Result[Unit, FeatureError] {
  let online_vectors : Array[FeatureVector] = []
  let offline_vectors : Array[FeatureVector] = []

  for request in requests {
    let vector = FeatureVector::{
      vector_id: request.table_id.to_string() +
      "_" +
      request.entity_id.to_string(),
      entity_id: request.entity_id.to_string(),
      table_id: request.table_id.to_string(),
      values: request.values,
      version: 1,
      timestamp: 0,
      is_valid: true,
    }
    online_vectors.push(clone_vector(vector))
    offline_vectors.push(vector)
  }

  // 批量写入在线存储
  let _ = self.online_storage.batch_put(online_vectors)

  // 批量写入离线存储
  self.offline_storage.batch_write(offline_vectors)
}

///|
/// 创建特征视图
pub fn FeatureStoreManager::create_view(
  self : FeatureStoreManager,
  view_name : String,
  view_type : FeatureViewType,
  table_id : String,
  feature_names : Array[String],
) -> Result[String, FeatureError] {
  // 检查表是否存在
  if !self.tables.contains(table_id.to_string()) {
    return Err(Table_Not_Found)
  }

  // 检查视图是否已存在
  for (_, view) in self.views {
    if view.view_name == view_name {
      return Err(View_Already_Exists)
    }
  }

  // 生成视图 ID
  let view_id = "view_" + self.next_view_id.to_string()
  self.next_view_id = self.next_view_id + 1

  // 创建视图
  let view = FeatureView::{
    view_id: view_id.to_string(),
    view_name,
    view_type,
    table_id: table_id.to_string(),
    feature_names,
    created_at: 0,
  }

  // 保存视图
  self.views.set(view_id.to_string(), view)

  Ok(view_id)
}

///|
/// 获取特征视图
pub fn FeatureStoreManager::get_view(
  self : FeatureStoreManager,
  view_id : String,
) -> FeatureView? {
  self.views.get(view_id)
}

///|
/// 列出所有特征视图
pub fn FeatureStoreManager::list_views(
  self : FeatureStoreManager,
) -> Array[FeatureView] {
  let result : Array[FeatureView] = []
  for (_, view) in self.views {
    result.push(view)
  }
  result
}

///|
/// 删除特征视图
pub fn FeatureStoreManager::delete_view(
  self : FeatureStoreManager,
  view_id : String,
) -> Result[Unit, FeatureError] {
  if !self.views.contains(view_id.to_string()) {
    return Err(View_Not_Found)
  }

  self.views.remove(view_id)
  Ok(())
}

///|
/// 获取缓存命中率
pub fn FeatureStoreManager::cache_hit_rate(
  self : FeatureStoreManager,
) -> Double {
  self.cache.hit_rate()
}

///|
/// 清空缓存
pub fn FeatureStoreManager::clear_cache(self : FeatureStoreManager) -> Unit {
  self.cache.clear()
}

///|
/// Delta Lake 离线存储（简化实现）
pub(all) struct DeltaLakeOfflineStorage {
  _placeholder : Unit
}

///|
pub impl OfflineStorage for DeltaLakeOfflineStorage with fn write_vector(
  self : DeltaLakeOfflineStorage,
  vector : FeatureVector,
) -> Result[Unit, FeatureError] {
  let _ = self
  // 简化实现：实际需要写入 Delta Lake
  let _ = vector
  Ok(())
}

///|
pub impl OfflineStorage for DeltaLakeOfflineStorage with fn batch_write(
  self : DeltaLakeOfflineStorage,
  vectors : Array[FeatureVector],
) -> Result[Unit, FeatureError] {
  let _ = self
  // 简化实现：实际需要批量写入 Delta Lake
  let _ = vectors
  Ok(())
}

///|
pub impl OfflineStorage for DeltaLakeOfflineStorage with fn read_history(
  self : DeltaLakeOfflineStorage,
  table_id : String,
  entity_id : String,
  version : Int32,
) -> Result[FeatureVector, FeatureError] {
  let _ = self
  let _ = table_id
  let _ = entity_id
  let _ = version
  Err(Internal_Error("Not implemented"))
}

///|
pub impl OfflineStorage for DeltaLakeOfflineStorage with fn export_data(
  self : DeltaLakeOfflineStorage,
  table_id : String,
  format : String,
) -> Result[Array[FeatureVector], FeatureError] {
  let _ = self
  let _ = table_id
  let _ = format
  Ok([])
}

///|
pub extend DeltaLakeOfflineStorage with OfflineStorage::{
  write_vector,
  batch_write,
  read_history,
  export_data,
}

///|
/// 创建特征存储管理器
pub fn create_feature_store_manager(
  config : FeatureStoreConfig,
) -> FeatureStoreManager {
  FeatureStoreManager::new(config)
}

///|
/// 创建默认特征存储管理器
pub fn create_default_feature_store_manager() -> FeatureStoreManager {
  FeatureStoreManager::new(FeatureStoreConfig::default())
}
