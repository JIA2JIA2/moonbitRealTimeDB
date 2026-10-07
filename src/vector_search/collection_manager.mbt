// 向量集合管理器
//
// 提供集合创建、删除、查询等生命周期管理功能

///|
pub struct CollectionManager {
  collections : Map[String, VectorCollectionMeta]
  tenant_collections : Map[String, Array[String]]
  mut next_id : Int
}

///|
pub fn CollectionManager::new() -> CollectionManager {
  CollectionManager::{
    collections: Map([], capacity=0),
    tenant_collections: Map([], capacity=0),
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
