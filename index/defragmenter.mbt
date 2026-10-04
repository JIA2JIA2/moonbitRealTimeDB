// 碎片整理器模块
//
// 整理索引碎片空间，优化存储效率
// 支持在线整理，不影响查询服务

///|
/// 碎片整理器结构体
pub struct Defragmenter {
  /// 索引管理器引用
  mut manager : IndexManager?
  /// 碎片率阈值（超过此值触发整理）
  mut fragmentation_threshold : Double
  /// 整理后目标碎片率
  mut target_fragmentation : Double
  /// 是否在整理中
  mut is_defragmenting : Bool
  /// 整理统计
  stats : DefragmentStats
}

///|
/// 默认碎片率阈值（30%）
pub const DEFAULT_FRAGMENTATION_THRESHOLD : Double = 0.3

///|
/// 默认目标碎片率（10%）
pub const DEFAULT_TARGET_FRAGMENTATION : Double = 0.1

///|
/// 整理统计
pub(all) struct DefragmentStats {
  /// 整理次数
  mut total_runs : Int
  /// 整理的索引数
  mut indices_processed : Int
  /// 释放的内存（字节）
  mut memory_freed : Int
  /// 总耗时（微秒）
  mut total_time_us : Int
}

///|
/// 创建碎片整理器
pub fn Defragmenter::new() -> Defragmenter {
  {
    manager: None,
    fragmentation_threshold: DEFAULT_FRAGMENTATION_THRESHOLD,
    target_fragmentation: DEFAULT_TARGET_FRAGMENTATION,
    is_defragmenting: false,
    stats: {
      total_runs: 0,
      indices_processed: 0,
      memory_freed: 0,
      total_time_us: 0,
    },
  }
}

///|
/// 设置索引管理器
pub fn Defragmenter::set_manager(
  self : Defragmenter,
  manager : IndexManager?,
) -> Unit {
  self.manager = manager
}

///|
/// 整理索引碎片。index_name 为 None 时整理所有索引。
pub fn Defragmenter::defragment(
  self : Defragmenter,
  index_name : String?,
) -> Result[Unit, IndexError] {
  let manager = match self.manager {
    Some(m) => m
    None => return Err(Internal_Error("Index manager not set"))
  }

  self.is_defragmenting = true
  let start_time = self.get_time_us()

  match index_name {
    Some(name) =>
      match self.defragment_single(name, manager) {
        Ok(_) => ()
        Err(e) => {
          self.is_defragmenting = false
          return Err(e)
        }
      }
    None =>
      for name, _ in manager.indices {
        let _ = self.defragment_single(name, manager)
      }
  }

  let elapsed = self.get_time_us() - start_time
  self.stats.total_runs = self.stats.total_runs + 1
  self.stats.total_time_us = self.stats.total_time_us + elapsed
  self.is_defragmenting = false

  Ok(())
}

///|
/// 整理单个索引（内部方法）
fn Defragmenter::defragment_single(
  self : Defragmenter,
  name : String,
  manager : IndexManager,
) -> Result[Unit, IndexError] {
  let def = match manager.indices.get(name) {
    Some(d) => d
    None => return Err(Index_Not_Found)
  }

  if !(def.status is Active) {
    return Err(Index_Not_Active)
  }

  let storage = match def.storage {
    Some(s) => s
    None => return Err(Internal_Error("Index storage not initialized"))
  }

  let fragmentation = self.calculate_fragmentation(storage)
  if fragmentation < self.fragmentation_threshold {
    return Ok(())
  }

  match self.perform_defragment(name, def, manager) {
    Ok(_) => {
      self.stats.indices_processed = self.stats.indices_processed + 1
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
/// 执行整理：用全新存储从数据库重建并原子替换（内部方法）
fn Defragmenter::perform_defragment(
  self : Defragmenter,
  name : String,
  def : IndexDef,
  manager : IndexManager,
) -> Result[Unit, IndexError] {
  let storage = match def.storage {
    Some(s) => s
    None => return Err(Internal_Error("Index storage not initialized"))
  }
  let old_memory = storage.memory_usage()

  let new_storage = self.create_new_storage(name + "_new", def)

  let database = match manager.db {
    Some(d) => d
    None => return Err(Internal_Error("Database not set"))
  }

  let keys = database.keys()
  let parser = FieldParser::new()
  for key in keys {
    match database.get(key) {
      Some(value) => {
        let field_values = parser.extract_fields(value, def.field_paths)
        if def.index_type is Composite {
          let present : Array[@realtime_db.Value] = []
          for v in field_values {
            match v {
              Some(fv) => present.push(fv)
              None => ()
            }
          }
          let _ = new_storage.insert(@realtime_db.Arr(present), key)
        } else {
          for v in field_values {
            match v {
              Some(fv) => {
                let _ = new_storage.insert(fv, key)
              }
              None => ()
            }
          }
        }
      }
      None => ()
    }
  }

  // 原子替换索引并写回注册表
  match manager.indices.get(name) {
    Some(current) => {
      current.storage = Some(new_storage)
      manager.indices.set(name, current)
    }
    None => return Err(Index_Not_Found)
  }

  let new_memory = new_storage.memory_usage()
  if old_memory > new_memory {
    self.stats.memory_freed = self.stats.memory_freed +
      (old_memory - new_memory)
  }

  Ok(())
}

///|
/// 按索引类型创建新存储（内部方法）
fn Defragmenter::create_new_storage(
  self : Defragmenter,
  name : String,
  def : IndexDef,
) -> IndexStorageHandle {
  let _ = self
  match def.index_type {
    Hash => IndexStorageHandle::Hash(HashIndex::new(name))
    BTree => IndexStorageHandle::BTree(BTreeIndex::new(name))
    Fulltext => IndexStorageHandle::Fulltext(FulltextIndex::new(name))
    Composite => {
      let composite = CompositeIndex::new(name, def.field_paths.copy())
      let sub : Array[IndexStorageHandle] = []
      for path in def.field_paths {
        sub.push(IndexStorageHandle::Hash(HashIndex::new(name + "." + path)))
      }
      composite.set_sub_indices(sub)
      IndexStorageHandle::Composite(composite)
    }
  }
}

///|
/// 计算碎片率（内部方法，简化估算）
fn Defragmenter::calculate_fragmentation(
  self : Defragmenter,
  storage : IndexStorageHandle,
) -> Double {
  let _ = self
  match storage.index_type() {
    Hash => 0.15
    BTree => 0.1
    Fulltext => 0.2
    Composite => 0.12
  }
}

///|
/// 检查是否需要整理
pub fn Defragmenter::should_defragment(
  self : Defragmenter,
  index_name : String,
) -> Bool {
  let manager = match self.manager {
    Some(m) => m
    None => return false
  }

  match manager.indices.get(index_name) {
    Some(def) =>
      if def.status is Active {
        match def.storage {
          Some(storage) =>
            self.calculate_fragmentation(storage) >=
            self.fragmentation_threshold
          None => false
        }
      } else {
        false
      }
    None => false
  }
}

///|
/// 获取时间（微秒，当前为逻辑时钟占位）
fn Defragmenter::get_time_us(self : Defragmenter) -> Int {
  let _ = self
  0
}

///|
/// 获取整理统计
pub fn Defragmenter::get_stats(self : Defragmenter) -> DefragmentStats {
  self.stats
}

///|
/// 检查是否在整理中
pub fn Defragmenter::is_defragmenting(self : Defragmenter) -> Bool {
  self.is_defragmenting
}

///|
/// 设置碎片率阈值
pub fn Defragmenter::set_fragmentation_threshold(
  self : Defragmenter,
  threshold : Double,
) -> Unit {
  if threshold >= 0.0 && threshold <= 1.0 {
    self.fragmentation_threshold = threshold
  }
}

///|
/// 设置目标碎片率
pub fn Defragmenter::set_target_fragmentation(
  self : Defragmenter,
  target : Double,
) -> Unit {
  if target >= 0.0 && target <= 1.0 {
    self.target_fragmentation = target
  }
}

///|
/// 自动整理（根据碎片率阈值自动触发），返回整理的索引数
pub fn Defragmenter::auto_defragment(
  self : Defragmenter,
) -> Result[Int, IndexError] {
  let manager = match self.manager {
    Some(m) => m
    None => return Err(Internal_Error("Index manager not set"))
  }

  let mut defragmented = 0
  for name, _ in manager.indices {
    if self.should_defragment(name) {
      match self.defragment(Some(name)) {
        Ok(_) => defragmented = defragmented + 1
        Err(_) => ()
      }
    }
  }

  Ok(defragmented)
}
