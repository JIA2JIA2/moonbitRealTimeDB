// 向量集合管理器
//
// 提供集合创建、删除、查询等生命周期管理功能

///|
pub struct CollectionManager {
  collections : Map[String, VectorCollectionMeta]
  tenant_collections : Map[String, Array[String]]
  records : Map[String, Map[String, VectorRecord]]
  hnsw_indexes : Map[String, HNSWIndex]
  ivf_indexes : Map[String, IVFIndex]
  subscribers : Map[String, Array[Subscriber]]
  subscriber_bindings : Map[String, String]
  mut next_id : Int32
}

///|
pub fn CollectionManager::new() -> CollectionManager {
  CollectionManager::{
    collections: Map([], capacity=0),
    tenant_collections: Map([], capacity=0),
    records: Map([], capacity=0),
    hnsw_indexes: Map([], capacity=0),
    ivf_indexes: Map([], capacity=0),
    subscribers: Map([], capacity=0),
    subscriber_bindings: Map([], capacity=0),
    next_id: 0,
  }
}

///|
pub fn CollectionManager::create_collection(
  self : CollectionManager,
  collection_name : String,
  dimension : Int32,
  distance_metric : DistanceMetric,
  index_strategy : IndexStrategy,
  index_config : IndexConfig?,
  filterable_fields : Array[String],
  tenant_id : String,
) -> Unit {
  let key = tenant_id + ":" + collection_name
  if self.collections.contains(key) {
    return ()
  }
  if CollectionManager::validate_dimension(dimension) is Err(_) {
    return ()
  }
  let meta = VectorCollectionMeta::{
    collection_name,
    dimension,
    distance_metric,
    index_strategy,
    index_config,
    filterable_fields,
    record_count: 0,
    tenant_id,
    created_at: 0,
  }
  self.collections.set(key, meta)
  // Approximate 策略的集合从创建起就持有空 HNSW/IVF 索引，
  // 后续写入由 VectorWriter 逐条同步
  if index_strategy is Approximate {
    match index_config {
      Some(config) =>
        match config.index_type {
          HNSW =>
            self.hnsw_indexes.set(key, HNSWIndex::new(HNSWConfig::default()))
          IVF =>
            match config.ivf_config {
              Some(ivf_config) =>
                self.ivf_indexes.set(key, IVFIndex::new(ivf_config, dimension))
              None => ()
            }
        }
      None => self.hnsw_indexes.set(key, HNSWIndex::new(HNSWConfig::default()))
    }
  }
  let tenant_list = match self.tenant_collections.get(tenant_id) {
    Some(list) => list
    None => {
      let new_list = Array(capacity=0)
      self.tenant_collections.set(tenant_id, new_list)
      new_list
    }
  }
  tenant_list.push(collection_name)
  self.next_id = self.next_id + 1
  ()
}

///|
pub fn CollectionManager::delete_collection(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
) -> Unit {
  let key = tenant_id + ":" + collection_name
  if !self.collections.contains(key) {
    return ()
  }
  self.publish_change(key, collection_name, "", CollectionDropped)
  self.collections.remove(key)
  self.records.remove(key)
  self.hnsw_indexes.remove(key)
  self.ivf_indexes.remove(key)
  self.subscribers.remove(key)
  let stale_subscriptions : Array[String] = Array(capacity=0)
  for sub_id, bound_key in self.subscriber_bindings.copy() {
    if bound_key == key {
      stale_subscriptions.push(sub_id)
    }
  }
  for sub_id in stale_subscriptions {
    self.subscriber_bindings.remove(sub_id)
  }
  match self.tenant_collections.get(tenant_id) {
    Some(list) => {
      let new_list = list.filter(fn(name) { name != collection_name })
      self.tenant_collections.set(tenant_id, new_list)
    }
    None => ()
  }
  ()
}

///|
pub fn CollectionManager::get_collection(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
) -> VectorCollectionMeta? {
  let key = tenant_id + ":" + collection_name
  self.collections.get(key)
}

///|
pub fn CollectionManager::list_collections(
  self : CollectionManager,
  tenant_id : String,
) -> Array[VectorCollectionMeta] {
  match self.tenant_collections.get(tenant_id) {
    Some(names) =>
      names.map(fn(name) {
        let key = tenant_id + ":" + name
        match self.collections.get(key) {
          Some(meta) => meta
          None =>
            VectorCollectionMeta::{
              collection_name: name,
              dimension: 0,
              distance_metric: Cosine,
              index_strategy: Exact,
              index_config: None,
              filterable_fields: Array(capacity=0),
              record_count: 0,
              tenant_id,
              created_at: 0,
            }
        }
      })
    None => Array(capacity=0)
  }
}

///|
/// 校验向量维度是否在 [1, 8192] 内。
pub fn CollectionManager::validate_dimension(
  dimension : Int32,
) -> Result[Unit, String] {
  if dimension < 1 || dimension > 8192 {
    return Err("dimension must be in [1, 8192]")
  }
  Ok(())
}

///|
pub fn CollectionManager::validate_metric(metric : DistanceMetric) -> Bool {
  match metric {
    Cosine | Euclidean | InnerProduct | Manhattan => true
  }
}

///|
pub fn CollectionManager::has_collection(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
) -> Bool {
  let key = tenant_id + ":" + collection_name
  self.collections.contains(key)
}

///|
pub fn CollectionManager::increment_record_count(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
  delta : Int32,
) -> Unit {
  let key = tenant_id + ":" + collection_name
  match self.collections.get(key) {
    Some(meta) => {
      let updated = VectorCollectionMeta::{
        collection_name: meta.collection_name,
        dimension: meta.dimension,
        distance_metric: meta.distance_metric,
        index_strategy: meta.index_strategy,
        index_config: meta.index_config,
        filterable_fields: meta.filterable_fields,
        record_count: meta.record_count + delta,
        tenant_id: meta.tenant_id,
        created_at: meta.created_at,
      }
      self.collections.set(key, updated)
      ()
    }
    None => ()
  }
}

///|
/// 写入或更新一条向量记录。
///
/// 主键已存在时覆盖旧记录，返回 false；主键为新增时返回 true，
/// 由调用方据此维护 record_count。
pub fn CollectionManager::upsert_record(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
  record : VectorRecord,
) -> Bool {
  let key = tenant_id + ":" + collection_name
  match self.records.get(key) {
    Some(store) => {
      let primary_key = record.primary_key
      let is_new = !store.contains(primary_key)
      let next_version = match store.get(primary_key) {
        Some(old) => old.version + 1
        None => 1
      }
      store.set(primary_key, VectorRecord::{
        primary_key,
        vector: record.vector,
        metadata: record.metadata,
        version: next_version,
        updated_at: record.updated_at,
      })
      match self.collections.get(key) {
        Some(meta) =>
          self.sync_upsert_to_index(
            key,
            meta,
            primary_key,
            record.vector,
            is_new,
          )
        None => ()
      }
      let change_type = if is_new { Inserted } else { Updated }
      self.publish_change(key, collection_name, primary_key, change_type)
      is_new
    }
    None => {
      let store : Map[String, VectorRecord] = Map([], capacity=0)
      let primary_key = record.primary_key
      store.set(primary_key, VectorRecord::{
        primary_key,
        vector: record.vector,
        metadata: record.metadata,
        version: 1,
        updated_at: record.updated_at,
      })
      self.records.set(key, store)
      match self.collections.get(key) {
        Some(meta) =>
          self.sync_upsert_to_index(key, meta, primary_key, record.vector, true)
        None => ()
      }
      self.publish_change(key, collection_name, primary_key, Inserted)
      true
    }
  }
}

///|
/// 列出集合内全部向量记录（返回副本，检索引擎据此做全量扫描）
pub fn CollectionManager::list_records(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
) -> Array[VectorRecord] {
  let key = tenant_id + ":" + collection_name
  match self.records.get(key) {
    Some(store) => {
      let out : Array[VectorRecord] = Array(capacity=0)
      for _, record in store.copy() {
        out.push(record)
      }
      out
    }
    None => Array(capacity=0)
  }
}

///|
/// 按主键获取单条向量记录
pub fn CollectionManager::get_record(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
  primary_key : String,
) -> VectorRecord? {
  let key = tenant_id + ":" + collection_name
  match self.records.get(key) {
    Some(store) => store.get(primary_key)
    None => None
  }
}

///|
/// 删除一条向量记录，并同步移除近似索引中的节点。
///
/// 仅当记录存在时返回 true；record_count 由调用方维护（与 upsert_record 一致）。
pub fn CollectionManager::delete_record(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
  primary_key : String,
) -> Bool {
  let key = tenant_id + ":" + collection_name
  match self.records.get(key) {
    Some(store) => {
      if !store.contains(primary_key) {
        return false
      }
      store.remove(primary_key)
      match self.collections.get(key) {
        Some(meta) => self.sync_delete_to_index(key, meta, primary_key)
        None => ()
      }
      self.publish_change(key, collection_name, primary_key, Deleted)
      true
    }
    None => false
  }
}

///|
/// 将删除同步到集合的 HNSW/IVF 索引。
fn CollectionManager::sync_delete_to_index(
  self : CollectionManager,
  key : String,
  meta : VectorCollectionMeta,
  primary_key : String,
) -> Unit {
  if meta.index_strategy is Exact {
    return ()
  }
  match meta.index_config {
    Some(config) =>
      match config.index_type {
        HNSW =>
          match self.hnsw_indexes.get(key) {
            Some(index) => {
              let _ = index.delete(primary_key, meta.distance_metric)
              self.hnsw_indexes.set(key, index)
            }
            None => ()
          }
        IVF =>
          match self.ivf_indexes.get(key) {
            Some(index) => {
              let _ = index.delete(primary_key)
              self.ivf_indexes.set(key, index)
            }
            None => ()
          }
      }
    None =>
      match self.hnsw_indexes.get(key) {
        Some(index) => {
          let _ = index.delete(primary_key, meta.distance_metric)
          self.hnsw_indexes.set(key, index)
        }
        None => ()
      }
  }
}

///|
/// 订阅集合的变更事件，返回订阅 ID。
///
/// 隔离（isolated）的订阅者不会收到回调。
pub fn CollectionManager::subscribe(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
  callback : (ChangeEvent) -> Unit,
) -> String {
  let key = tenant_id + ":" + collection_name
  let subscription_id = "sub-" + self.next_id.to_string()
  self.next_id = self.next_id + 1
  let subscribers = match self.subscribers.get(key) {
    Some(list) => list
    None => {
      let new_list : Array[Subscriber] = Array(capacity=0)
      self.subscribers.set(key, new_list)
      new_list
    }
  }
  subscribers.push(Subscriber::{ subscription_id, callback, isolated: false, })
  self.subscriber_bindings.set(subscription_id, key)
  subscription_id
}

///|
/// 取消订阅，返回是否移除了有效的订阅。
pub fn CollectionManager::unsubscribe(
  self : CollectionManager,
  subscription_id : String,
) -> Bool {
  match self.subscriber_bindings.get(subscription_id) {
    Some(key) =>
      match self.subscribers.get(key) {
        Some(list) => {
          let remaining = list.filter(fn(sub) {
            sub.subscription_id != subscription_id
          })
          let removed = remaining.length() < list.length()
          self.subscribers.set(key, remaining)
          self.subscriber_bindings.remove(subscription_id)
          removed
        }
        None => {
          self.subscriber_bindings.remove(subscription_id)
          false
        }
      }
    None => false
  }
}

///|
/// 向集合的订阅者发布变更事件。
fn CollectionManager::publish_change(
  self : CollectionManager,
  key : String,
  collection_name : String,
  primary_key : String,
  change_type : ChangeEventType,
) -> Unit {
  match self.subscribers.get(key) {
    Some(list) => {
      let event = ChangeEvent::{
        collection_name,
        primary_key,
        change_type,
        occurred_at: 0,
      }
      for subscriber in list.copy() {
        if !subscriber.isolated {
          (subscriber.callback)(event)
        }
      }
    }
    None => ()
  }
}

///|
/// 将已写入的记录同步到集合的 HNSW/IVF 索引。
/// 主键已存在时先删旧节点再插入；入口点字段是值类型，修改后必须整体写回。
fn CollectionManager::sync_upsert_to_index(
  self : CollectionManager,
  key : String,
  meta : VectorCollectionMeta,
  primary_key : String,
  vector : Array[Double],
  is_new : Bool,
) -> Unit {
  if meta.index_strategy is Exact {
    return ()
  }
  match meta.index_config {
    Some(config) =>
      match config.index_type {
        HNSW =>
          match self.hnsw_indexes.get(key) {
            Some(index) => {
              if !is_new {
                let _ = index.delete(primary_key, meta.distance_metric)
              }
              match index.insert(primary_key, vector, meta.distance_metric) {
                Ok(_) => self.hnsw_indexes.set(key, index)
                Err(_) => ()
              }
            }
            None => ()
          }
        IVF =>
          match self.ivf_indexes.get(key) {
            Some(index) => {
              if !is_new {
                let _ = index.delete(primary_key)
              }
              match
                index.insert(VectorRecord::{
                  primary_key,
                  vector,
                  metadata: Map([]),
                  version: 1,
                  updated_at: 0,
                }) {
                Ok(_) => self.ivf_indexes.set(key, index)
                Err(_) => ()
              }
            }
            None => ()
          }
      }
    None =>
      match self.hnsw_indexes.get(key) {
        Some(index) => {
          if !is_new {
            let _ = index.delete(primary_key, meta.distance_metric)
          }
          match index.insert(primary_key, vector, meta.distance_metric) {
            Ok(_) => self.hnsw_indexes.set(key, index)
            Err(_) => ()
          }
        }
        None => ()
      }
  }
}

///|
/// 使用 HNSW/IVF 索引执行近似检索，返回 (主键, 图距离)，距离越小越相似。
///
/// 非 Approximate 集合或索引不存在时返回 None，由调用方回退精确检索。
pub fn CollectionManager::search_index(
  self : CollectionManager,
  collection_name : String,
  tenant_id : String,
  query_vector : Array[Double],
  top_k : Int32,
) -> Array[(String, Double)]? {
  let key = tenant_id + ":" + collection_name
  match self.collections.get(key) {
    Some(meta) => {
      if meta.index_strategy is Exact {
        return None
      }
      match meta.index_config {
        Some(config) =>
          match config.index_type {
            HNSW =>
              match self.hnsw_indexes.get(key) {
                Some(index) =>
                  Some(
                    index.search_top_k(
                      query_vector,
                      top_k,
                      meta.distance_metric,
                    ),
                  )
                None => None
              }
            IVF =>
              match self.ivf_indexes.get(key) {
                Some(index) => {
                  if !index.is_trained() {
                    return None
                  }
                  Some(index.search_top_k(query_vector, top_k))
                }
                None => None
              }
          }
        None =>
          match self.hnsw_indexes.get(key) {
            Some(index) =>
              Some(
                index.search_top_k(query_vector, top_k, meta.distance_metric),
              )
            None => None
          }
      }
    }
    None => None
  }
}
