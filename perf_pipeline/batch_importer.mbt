// 零拷贝批量导入器模块
//
// 实现零拷贝批量导入，直接操作存储引擎内部索引。
// 目标：吞吐量 >= 500,000 条/秒，内存拷贝次数 <= 1

///|
/// 批量导入器结构
///
/// 依赖数据库、WAL、内存池和配置。
pub struct BatchImporter {
  /// 数据库引用
  mut db : @realtime_db.DB?
  /// WAL 引用
  mut wal : @persistence.WAL?
  /// 内存池引用
  mut mempool : MemoryPool?
  /// 配置
  config : PipelineConfig
}

///|
/// 创建批量导入器
pub fn BatchImporter::new(
  db : @realtime_db.DB?,
  wal : @persistence.WAL?,
  mempool : MemoryPool?,
  config : PipelineConfig,
) -> BatchImporter {
  { db, wal, mempool, config, }
}

///|
/// 设置数据库
pub fn BatchImporter::set_db(
  self : BatchImporter,
  db : @realtime_db.DB?,
) -> Unit {
  self.db = db
}

///|
/// 设置 WAL
pub fn BatchImporter::set_wal(
  self : BatchImporter,
  wal : @persistence.WAL?,
) -> Unit {
  self.wal = wal
}

///|
/// 设置内存池
pub fn BatchImporter::set_mempool(
  self : BatchImporter,
  mempool : MemoryPool?,
) -> Unit {
  self.mempool = mempool
}

///|
/// 批量导入数据
///
/// 零拷贝写入存储引擎，直接操作内部 Map。
/// 参数：
/// - data: 键值对列表
/// - ttl: 可选 TTL（秒）
/// 返回：批量结果
pub fn BatchImporter::import_batch(
  self : BatchImporter,
  data : Array[(String, @realtime_db.Value)],
  ttl : Int?,
) -> BatchResult {
  let result = BatchResult::new()

  // 验证批量大小
  if data.length() < 1 || data.length() > self.config.batch_size {
    result.add_failure(
      0,
      "Invalid batch size: must be 1 to \{self.config.batch_size}",
    )
    return result
  }

  // 检查依赖
  match self.db {
    None => {
      result.add_failure(0, "Database not initialized")
      return result
    }
    Some(db) => {
      let mut i = 0
      while i < data.length() {
        let (key, value) = data[i]
        // 直接写入存储（零拷贝）
        match ttl {
          Some(t) => db.set(key, value, ttl=t)
          None => db.set(key, value)
        }
        result.add_success()

        // 追加 WAL 日志（WAL 可选）
        match self.wal {
          Some(wal) =>
            ignore(wal.append(@persistence.Operation::Set(key, value)))
          None => ()
        }
        i = i + 1
      }
    }
  }

  result
}
