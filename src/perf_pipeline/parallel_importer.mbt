// 并行导入器模块
//
// 实现并行批量导入，支持分片并行执行。
// 目标：并行度 1~16，吞吐量提升 3 倍以上

///|
/// 并行结果结构
pub struct ParallelResult {
  /// 分片结果列表
  shard_results : Array[BatchResult]
  /// 总成功数
  mut total_success : Int32
  /// 总失败数
  mut total_failed : Int32
  /// 分片数量
  mut shard_count : Int32
}

///|
/// 并行导入器结构
pub struct ParallelImporter {
  /// 批量导入器
  mut importer : BatchImporter?
  /// 配置
  config : ParallelImportConfig
  /// 分片策略
  sharding_strategy : ShardingStrategy
  /// 统计信息
  mut stats : ParallelResult
}

///|
/// 并行错误类型
pub(all) enum ParallelError {
  /// 导入器未初始化
  Importer_Not_Initialized
  /// 分片失败
  Sharding_Failed
  /// 并行超时
  Parallel_Timeout
  /// 分片失败
  Shard_Failed
}

///|
/// 创建并行结果
pub fn ParallelResult::new() -> ParallelResult {
  { shard_results: [], total_success: 0, total_failed: 0, shard_count: 0, }
}

///|
/// 创建并行导入器
pub fn ParallelImporter::new(
  importer : BatchImporter?,
  config : ParallelImportConfig,
) -> ParallelImporter {
  {
    importer,
    config,
    sharding_strategy: ShardingStrategy::new(config.shard_size),
    stats: ParallelResult::new(),
  }
}

///|
/// 并行导入数据
///
// 调用分片策略拆分数据，并行执行分片导入。
pub fn ParallelImporter::parallel_import(
  self : ParallelImporter,
  data : Array[(String, @realtime_db.Value)],
  parallelism : Int32?,
) -> Result[ParallelResult, ParallelError] {
  let actual_parallelism = match parallelism {
    Some(p) => p.min(self.config.parallelism)
    None => self.config.parallelism
  }
  let _ = actual_parallelism

  // 检查导入器
  match self.importer {
    None => return Err(Importer_Not_Initialized)
    Some(_) => ()
  }

  // 分片数据
  let shards = self.sharding_strategy.split_data(data)
  if shards.is_empty() {
    return Err(Sharding_Failed)
  }

  // 并行导入（简化实现：顺序执行）
  let result = ParallelResult::new()
  result.shard_count = shards.length()

  for shard in shards {
    match self.import_shard(shard) {
      Ok(batch_result) => {
        result.shard_results.push(batch_result)
        result.total_success = result.total_success +
          batch_result.success_count()
        result.total_failed = result.total_failed + batch_result.failed_count()
      }
      Err(_) => return Err(Shard_Failed)
    }
  }

  self.stats = result
  Ok(result)
}

///|
/// 导入单个分片
///
// 导入单个分片的数据。
pub fn ParallelImporter::import_shard(
  self : ParallelImporter,
  shard : Shard,
) -> Result[BatchResult, ParallelError] {
  match self.importer {
    None => Err(Importer_Not_Initialized)
    Some(importer) => {
      let batch_result = importer.import_batch(shard.data(), None)
      Ok(batch_result)
    }
  }
}

///|
/// 合并分片结果
///
// 合并所有分片结果。
pub fn ParallelImporter::merge_results(
  self : ParallelImporter,
  results : Array[BatchResult],
) -> ParallelResult {
  let _ = self
  let merged = ParallelResult::new()
  for result in results {
    merged.shard_results.push(result)
    merged.total_success = merged.total_success + result.success_count()
    merged.total_failed = merged.total_failed + result.failed_count()
  }
  merged.shard_count = results.length()
  merged
}

///|
/// 获取统计信息
pub fn ParallelImporter::stats(self : ParallelImporter) -> ParallelResult {
  self.stats
}

///|
/// 设置批量导入器
pub fn ParallelImporter::set_importer(
  self : ParallelImporter,
  importer : BatchImporter?,
) -> Unit {
  self.importer = importer
}

///|
/// 获取总成功数
pub fn ParallelResult::total_success(self : ParallelResult) -> Int32 {
  self.total_success
}

///|
/// 获取总失败数
pub fn ParallelResult::total_failed(self : ParallelResult) -> Int32 {
  self.total_failed
}

///|
/// 获取分片数量
pub fn ParallelResult::shard_count(self : ParallelResult) -> Int32 {
  self.shard_count
}
