// 索引构建器模块
//
// 实现全量数据扫描与初始索引构建
// 支持批次处理和进度回调

///|
/// 构建进度回调类型：(已处理数, 总条目数, 进度百分比)
pub type BuildProgressCallback = (Int, Int, Double) -> Unit

///|
/// 索引构建器结构体
pub struct IndexBuilder {
  /// 数据库引用
  mut db : @realtime_db.DB?
  /// 索引管理器引用
  mut manager : IndexManager?
  /// 批次大小
  mut batch_size : Int
  /// 是否在构建中
  mut is_building : Bool
  /// 已处理条目数
  mut processed : Int
  /// 总条目数
  mut total : Int
}

///|
/// 默认批次大小
pub const DEFAULT_BATCH_SIZE : Int = 1000

///|
/// 创建索引构建器
pub fn IndexBuilder::new() -> IndexBuilder {
  {
    db: None,
    manager: None,
    batch_size: DEFAULT_BATCH_SIZE,
    is_building: false,
    processed: 0,
    total: 0,
  }
}

///|
/// 指定批次大小创建索引构建器
pub fn IndexBuilder::with_batch_size(batch_size : Int) -> IndexBuilder {
  {
    db: None,
    manager: None,
    batch_size,
    is_building: false,
    processed: 0,
    total: 0,
  }
}

///|
/// 设置数据库引用
pub fn IndexBuilder::set_db(self : IndexBuilder, db : @realtime_db.DB?) -> Unit {
  self.db = db
}

///|
/// 设置索引管理器引用
pub fn IndexBuilder::set_manager(
  self : IndexBuilder,
  manager : IndexManager?,
) -> Unit {
  self.manager = manager
}

///|
/// 从全量扫描构建索引
pub fn IndexBuilder::build_from_scan(
  self : IndexBuilder,
  index_name : String,
  progress_callback : BuildProgressCallback?,
) -> Result[Int, IndexError] {
  let db = match self.db {
    Some(d) => d
    None => return Err(Internal_Error("Database not set"))
  }

  let manager = match self.manager {
    Some(m) => m
    None => return Err(Internal_Error("Index manager not set"))
  }

  let def = match manager.indices.get(index_name) {
    Some(d) => d
    None => return Err(Index_Not_Found)
  }

  let storage = match def.storage {
    Some(s) => s
    None => return Err(Internal_Error("Index storage not initialized"))
  }

  let keys = db.keys()
  let total = keys.length()
  self.total = total
  self.processed = 0
  self.is_building = true

  let parser = FieldParser::new()

  let mut batch_count = 0
  let mut batch_inserts : Array[(@realtime_db.Value, String)] = []

  for key in keys {
    match db.get(key) {
      Some(value) => {
        let field_values = parser.extract_fields(value, def.field_paths)
        if def.index_type is Composite {
          // 复合索引：将存在的字段值收集为 Arr，一条记录对应一个条目
          let present : Array[@realtime_db.Value] = []
          for v in field_values {
            match v {
              Some(fv) => present.push(fv)
              None => ()
            }
          }
          batch_inserts.push((@realtime_db.Arr(present), key))
        } else {
          for v in field_values {
            match v {
              Some(fv) => batch_inserts.push((fv, key))
              None => ()
            }
          }
        }
      }
      None => ()
    }

    batch_count = batch_count + 1
    self.processed = self.processed + 1

    if batch_count >= self.batch_size {
      if batch_inserts.length() > 0 {
        let _ = storage.batch_update(batch_inserts, [])
        batch_inserts = []
      }
      batch_count = 0

      match progress_callback {
        Some(cb) => {
          let progress = self.processed.to_double() / total.to_double() * 100.0
          cb(self.processed, total, progress)
        }
        None => ()
      }
    }
  }

  if batch_inserts.length() > 0 {
    let _ = storage.batch_update(batch_inserts, [])
  }

  match progress_callback {
    Some(cb) => cb(total, total, 100.0)
    None => ()
  }

  self.is_building = false
  Ok(self.processed)
}

///|
/// 构建单个索引
pub fn IndexBuilder::build_index(
  self : IndexBuilder,
  index_name : String,
) -> Result[Int, IndexError] {
  self.build_from_scan(index_name, None)
}

///|
/// 批量构建多个索引
pub fn IndexBuilder::build_multiple_indices(
  self : IndexBuilder,
  index_names : Array[String],
  progress_callback : BuildProgressCallback?,
) -> Result[Int, IndexError] {
  let mut total_built = 0
  for name in index_names {
    match self.build_from_scan(name, progress_callback) {
      Ok(built) => total_built = total_built + built
      Err(e) => return Err(e)
    }
  }
  Ok(total_built)
}

///|
/// 取消构建
pub fn IndexBuilder::cancel(self : IndexBuilder) -> Unit {
  self.is_building = false
}

///|
/// 检查是否在构建中
pub fn IndexBuilder::is_building_flag(self : IndexBuilder) -> Bool {
  self.is_building
}

///|
/// 获取已处理条目数
pub fn IndexBuilder::processed_count(self : IndexBuilder) -> Int {
  self.processed
}

///|
/// 获取总条目数
pub fn IndexBuilder::total_count(self : IndexBuilder) -> Int {
  self.total
}

///|
/// 获取构建进度（百分比）
pub fn IndexBuilder::progress(self : IndexBuilder) -> Double {
  if self.total == 0 {
    0.0
  } else {
    self.processed.to_double() / self.total.to_double() * 100.0
  }
}

///|
/// 设置批次大小
pub fn IndexBuilder::set_batch_size(self : IndexBuilder, size : Int) -> Unit {
  if size > 0 {
    self.batch_size = size
  }
}
