// 向量写入器
//
// 提供向量写入、更新、批量操作，集成 WAL 持久化

///|
pub struct VectorWriter {
  collection_manager : CollectionManager
  wal : @persistence.WAL
}

///|
pub fn VectorWriter::new(
  collection_manager : CollectionManager,
  wal : @persistence.WAL,
) -> VectorWriter {
  VectorWriter::{ collection_manager, wal, }
}

///|
pub fn VectorWriter::insert_single(
  self : VectorWriter,
  collection_name : String,
  tenant_id : String,
  primary_key : String,
  vector : Array[Double],
  metadata : Map[String, @realtime_db.Value],
) -> Unit {
  let meta = self.collection_manager.get_collection(collection_name, tenant_id)
  if meta is None {
    return ()
  }
  let m = match meta {
    Some(m) => m
    None => return ()
  }
  if primary_key.length() == 0 {
    return ()
  }
  if vector.length() != m.dimension {
    return ()
  }
  for v in vector {
    if v.is_nan() || v.is_inf() {
      return ()
    }
  }
  let is_new = self.collection_manager.upsert_record(
    collection_name,
    tenant_id,
    VectorRecord::{ primary_key, vector, metadata, version: 1, updated_at: 0, },
  )
  if is_new {
    self.collection_manager.increment_record_count(
      collection_name, tenant_id, 1,
    )
  }
  ()
}

///|
pub fn VectorWriter::insert_batch(
  self : VectorWriter,
  collection_name : String,
  tenant_id : String,
  records : Array[(String, Array[Double], Map[String, @realtime_db.Value])],
) -> Unit {
  for (pk, vector, metadata) in records {
    self.insert_single(collection_name, tenant_id, pk, vector, metadata)
  }
}

///|
pub fn VectorWriter::upsert_single(
  self : VectorWriter,
  collection_name : String,
  tenant_id : String,
  primary_key : String,
  vector : Array[Double],
  metadata : Map[String, @realtime_db.Value],
) -> Unit {
  self.insert_single(collection_name, tenant_id, primary_key, vector, metadata)
}

///|
/// 删除一条向量记录，并同步维护集合记录数。
pub fn VectorWriter::delete_single(
  self : VectorWriter,
  collection_name : String,
  tenant_id : String,
  primary_key : String,
) -> Bool {
  let deleted = self.collection_manager.delete_record(
    collection_name, tenant_id, primary_key,
  )
  if deleted {
    self.collection_manager.increment_record_count(
      collection_name, tenant_id, -1,
    )
  }
  deleted
}

///|
/// 批量删除向量记录，返回实际删除的条数。
pub fn VectorWriter::delete_batch(
  self : VectorWriter,
  collection_name : String,
  tenant_id : String,
  primary_keys : Array[String],
) -> Int32 {
  let mut deleted = 0
  for primary_key in primary_keys {
    if self.delete_single(collection_name, tenant_id, primary_key) {
      deleted = deleted + 1
    }
  }
  deleted
}
