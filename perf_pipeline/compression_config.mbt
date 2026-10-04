// 压缩配置模块
//
// 定义压缩相关的配置结构。

///|
/// 压缩格式枚举
pub enum CompressionFormat {
  /// Gzip 格式
  Gzip
  /// Zstd 格式
  Zstd
  /// Lz4 格式
  Lz4
}

///|
/// 压缩配置结构
pub struct CompressionConfig {
  /// 压缩格式
  mut format : CompressionFormat
  /// 压缩级别（1~9）
  mut level : Int
  /// 解压超时时间（毫秒）
  mut decompress_timeout : Int
  /// 最大压缩比（超过此值拒绝解压）
  mut max_compression_ratio : Double
}

///|
/// 创建默认压缩配置
///
/// 默认格式为 gzip，级别为 6，超时 30000ms，最大压缩比 10.0
pub fn CompressionConfig::default() -> CompressionConfig {
  {
    format: Gzip,
    level: 6,
    decompress_timeout: 30000,
    max_compression_ratio: 10.0,
  }
}

///|
/// 验证配置
///
/// 返回 Ok(()) 如果配置有效。
pub fn CompressionConfig::validate(self : CompressionConfig) -> Result[Unit, String] {
  if self.level < 1 || self.level > 9 {
    return Err("Compression level must be between 1 and 9")
  }
  if self.decompress_timeout < 1 {
    return Err("Decompress timeout must be positive")
  }
  if self.max_compression_ratio < 1.0 {
    return Err("Max compression ratio must be >= 1.0")
  }
  Ok(())
}

///|
/// 设置压缩格式
pub fn CompressionConfig::set_format(self : CompressionConfig, format : CompressionFormat) -> Unit {
  self.format = format
}

///|
/// 设置压缩级别
pub fn CompressionConfig::set_level(self : CompressionConfig, level : Int) -> Unit {
  self.level = level
}

///|
/// 设置解压超时时间
pub fn CompressionConfig::set_decompress_timeout(self : CompressionConfig, timeout : Int) -> Unit {
  self.decompress_timeout = timeout
}

///|
/// 设置最大压缩比
pub fn CompressionConfig::set_max_compression_ratio(self : CompressionConfig, ratio : Double) -> Unit {
  self.max_compression_ratio = ratio
}

///|
/// 获取格式名称
pub fn CompressionFormat::to_string(self : CompressionFormat) -> String {
  match self {
    Gzip => "gzip"
    Zstd => "zstd"
    Lz4 => "lz4"
  }
}

///|
/// 从字符串解析格式
pub fn parse_compression_format(s : String) -> CompressionFormat? {
  match s {
    "gzip" => Some(Gzip)
    "zstd" => Some(Zstd)
    "lz4" => Some(Lz4)
    _ => None
  }
}