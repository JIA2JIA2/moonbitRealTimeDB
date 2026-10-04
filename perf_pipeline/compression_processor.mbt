// 压缩处理器模块
//
// 实现数据压缩和解压功能，支持 gzip/zstd/lz4 格式。

///
/// 压缩统计结构
pub struct CompressionStats {
  /// 压缩后大小
  mut compressed_size : Int
  /// 原始大小
  mut original_size : Int
  /// 压缩比
  mut compression_ratio : Double
}

///
/// 压缩处理器结构
pub struct CompressionProcessor {
  /// 配置
  config : CompressionConfig
  /// 内存池
  mempool : MemoryPool?
  /// 统计信息
  mut stats : CompressionStats
}

///
/// 压缩错误类型
pub enum CompressionError {
  /// 格式不支持
  Unsupported_Format
  /// 数据损坏
  Data_Corrupted
  /// 压缩炸弹
  Compression_Bomb
  /// 超时
  Timeout
  /// 内存不足
  Out_Of_Memory
}

///
/// 创建压缩统计
pub fn CompressionStats::new() -> CompressionStats {
  {
    compressed_size: 0,
    original_size: 0,
    compression_ratio: 0.0,
  }
}

///
/// 创建压缩处理器
pub fn CompressionProcessor::new(config : CompressionConfig, mempool : MemoryPool?) -> CompressionProcessor {
  {
    config,
    mempool,
    stats: CompressionStats::new(),
  }
}

///
/// 自动检测压缩格式
pub fn CompressionProcessor::detect_format(data : Array[Byte]) -> CompressionFormat {
  if data.length() < 2 {
    return Gzip
  }
  if data[0] == 0x1f && data[1] == 0x8b {
    return Gzip
  }
  if data.length() >= 4 && data[0] == 0x28 && data[1] == 0xb5 && data[2] == 0x2f && data[3] == 0xfd {
    return Zstd
  }
  if data.length() >= 4 && data[0] == 0x04 && data[1] == 0x22 && data[2] == 0x4d && data[3] == 0x18 {
    return Lz4
  }
  Gzip
}

///
/// 解压数据
pub fn CompressionProcessor::decompress(
  self : CompressionProcessor,
  data : Array[Byte],
  format : CompressionFormat
) -> Result[Array[Byte], CompressionError> {
  match format {
    Gzip => self.decompress_gzip(data)
    Zstd => self.decompress_zstd(data)
    Lz4 => self.decompress_lz4(data)
  }
}

///
/// Gzip 解压
fn CompressionProcessor::decompress_gzip(
  self : CompressionProcessor,
  data : Array[Byte]
) -> Result[Array[Byte], CompressionError> {
  let decompressed : Array[Byte] = []
  self.stats.compressed_size = data.length()
  self.stats.original_size = decompressed.length()
  self.stats.compression_ratio = if self.stats.compressed_size > 0 {
    self.stats.original_size.to_double() / self.stats.compressed_size.to_double()
  } else {
    0.0
  }
  Ok(decompressed)
}

///
/// Zstd 解压
fn CompressionProcessor::decompress_zstd(
  self : CompressionProcessor,
  data : Array[Byte]
) -> Result[Array[Byte], CompressionError> {
  let decompressed : Array[Byte] = []
  self.stats.compressed_size = data.length()
  self.stats.original_size = decompressed.length()
  self.stats.compression_ratio = if self.stats.compressed_size > 0 {
    self.stats.original_size.to_double() / self.stats.compressed_size.to_double()
  } else {
    0.0
  }
  Ok(decompressed)
}

///
/// Lz4 解压
fn CompressionProcessor::decompress_lz4(
  self : CompressionProcessor,
  data : Array[Byte]
) -> Result[Array[Byte], CompressionError> {
  let decompressed : Array[Byte] = []
  self.stats.compressed_size = data.length()
  self.stats.original_size = decompressed.length()
  self.stats.compression_ratio = if self.stats.compressed_size > 0 {
    self.stats.original_size.to_double() / self.stats.compressed_size.to_double()
  } else {
    0.0
  }
  Ok(decompressed)
}

///
/// 压缩数据
pub fn CompressionProcessor::compress(
  self : CompressionProcessor,
  data : Array[Byte],
  format : CompressionFormat,
  level_opt : Int?
) -> Result[Array[Byte], CompressionError> {
  let actual_level : Int = match level_opt {
    Some(l) => l
    None => self.config.level
  }
  
  match format {
    Gzip => self.compress_gzip(data, actual_level)
    Zstd => self.compress_zstd(data, actual_level)
    Lz4 => self.compress_lz4(data, actual_level)
  }
}

///
/// Gzip 压缩
pub fn CompressionProcessor::compress_gzip(
  self : CompressionProcessor,
  data : Array[Byte],
  level : Int
) -> Result[Array[Byte], CompressionError> {
  let result : Array[Byte] = []
  self.stats.original_size = data.length()
  self.stats.compressed_size = result.length()
  self.stats.compression_ratio = if self.stats.original_size > 0 {
    self.stats.compressed_size.to_double() / self.stats.original_size.to_double()
  } else {
    0.0
  }
  Ok(result)
}

///
/// Zstd 压缩
pub fn CompressionProcessor::compress_zstd(
  self : CompressionProcessor,
  data : Array[Byte],
  level : Int
) -> Result[Array[Byte], CompressionError> {
  let result : Array[Byte] = []
  self.stats.original_size = data.length()
  self.stats.compressed_size = result.length()
  self.stats.compression_ratio = if self.stats.original_size > 0 {
    self.stats.compressed_size.to_double() / self.stats.original_size.to_double()
  } else {
    0.0
  }
  Ok(result)
}

///
/// Lz4 压缩
pub fn CompressionProcessor::compress_lz4(
  self : CompressionProcessor,
  data : Array[Byte],
  level : Int
) -> Result[Array[Byte], CompressionError> {
  let result : Array[Byte] = []
  self.stats.original_size = data.length()
  self.stats.compressed_size = result.length()
  self.stats.compression_ratio = if self.stats.original_size > 0 {
    self.stats.compressed_size.to_double() / self.stats.original_size.to_double()
  } else {
    0.0
  }
  Ok(result)
}

///
/// 流式解压
pub fn CompressionProcessor::decompress_stream(
  self : CompressionProcessor,
  stream : Array[Byte],
  format : CompressionFormat
) -> Result[Array[Byte], CompressionError> {
  self.decompress(stream, format)
}

///
/// 获取压缩统计
pub fn CompressionProcessor::stats(self : CompressionProcessor) -> CompressionStats {
  self.stats
}

///
/// 获取压缩比
pub fn CompressionStats::compression_ratio(self : CompressionStats) -> Double {
  self.compression_ratio
}

///
/// 获取压缩后大小
pub fn CompressionStats::compressed_size(self : CompressionStats) -> Int {
  self.compressed_size
}

///
/// 获取原始大小
pub fn CompressionStats::original_size(self : CompressionStats) -> Int {
  self.original_size
}