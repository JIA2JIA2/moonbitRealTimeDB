// 并行导入配置模块
//
// 定义并行导入相关的配置结构。

///|
/// 并行导入配置结构
pub struct ParallelImportConfig {
  /// 并行度（1~16）
  mut parallelism : Int32
  /// 分片大小（100~10000）
  mut shard_size : Int32
  /// 分片超时时间（毫秒）
  mut shard_timeout : Int32
}

///|
/// 创建默认并行导入配置
///
// 默认并行度为 4，分片大小为 1000
pub fn ParallelImportConfig::default() -> ParallelImportConfig {
  { parallelism: 4, shard_size: 1000, shard_timeout: 30000, }
}

///|
/// 验证配置
///
// 返回 Ok(()) 如果配置有效。
pub fn ParallelImportConfig::validate(
  self : ParallelImportConfig,
) -> Result[Unit, String] {
  if self.parallelism < 1 || self.parallelism > 16 {
    return Err("Parallelism must be between 1 and 16")
  }
  if self.shard_size < 100 || self.shard_size > 10000 {
    return Err("Shard size must be between 100 and 10000")
  }
  if self.shard_timeout < 1 {
    return Err("Shard timeout must be positive")
  }
  Ok(())
}

///|
/// 设置并行度
pub fn ParallelImportConfig::set_parallelism(
  self : ParallelImportConfig,
  parallelism : Int32,
) -> Unit {
  self.parallelism = parallelism
}

///|
/// 设置分片大小
pub fn ParallelImportConfig::set_shard_size(
  self : ParallelImportConfig,
  size : Int32,
) -> Unit {
  self.shard_size = size
}

///|
/// 设置分片超时时间
pub fn ParallelImportConfig::set_shard_timeout(
  self : ParallelImportConfig,
  timeout : Int32,
) -> Unit {
  self.shard_timeout = timeout
}
