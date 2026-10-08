// 向量集合管理器
//
// 提供集合创建、删除、查询等生命周期管理功能

///|
pub struct CollectionManager {
  collections : Map[String, VectorCollectionMeta]
  tenant_collections : Map[String, Array[String]]
  records : Map[String, Map[String, VectorRecord]]
  mut next_id : Int
}

///|
pub fn CollectionManager::new() -> CollectionManager {
  CollectionManager::{
    collections: Map([], capacity=0),
    tenant_collections: Map([], capacity=0),
    records: Map([], capacity=0),
    next_id: 0,
  }
}

///|
pub fn CollectionManager::create_collection(
  self : CollectionManager,
  collection_name : String,
  dimension : Int,
  distance_metric : DistanceMetric,
  index_strategy : IndexStrategy,
  filterable_fields : Array[String],
  tenant_id : String,
) -> Unit {
  let key = tenant_id + ":" + collection_name
  if self.collections.contains(key) {
    return ()
  }
  if dimension < 1 || dimension > 8192 {
    return ()
  }
  let meta = VectorCollectionMeta::{
    collection_name,
    dimension,
    distance_metric,
    index_strategy,
    filterable_fields,
    record_count: 0,
    tenant_id,
    created_at: 0,
  }
  self.collections.set(key, meta)
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
  self.collections.remove(key)
  self.records.remove(key)
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
pub fn CollectionManager::validate_dimension(dimension : Int) -> Unit {
  if dimension < 1 || dimension > 8192 {
    ()
  } else {
    ()
  }
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
  delta : Int,
) -> Unit {
  let key = tenant_id + ":" + collection_name
  match self.collections.get(key) {
    Some(meta) => {
      let updated = VectorCollectionMeta::{
        collection_name: meta.collection_name,
        dimension: meta.dimension,
        distance_metric: meta.distance_metric,
        index_strategy: meta.index_strategy,
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
