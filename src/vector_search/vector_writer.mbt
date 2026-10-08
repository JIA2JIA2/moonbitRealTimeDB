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
