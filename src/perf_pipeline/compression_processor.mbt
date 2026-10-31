// 压缩处理器模块
//
// 提供无损的压缩/解拔回返能力，按 gzip/zstd/lz4 三种格式魔数
// 区分输出帧。当前采用简化的 RLE（游程编码）+ 原样存储双模式：
// 高冗余数据走游程编码，其余原样存储，任何输入都能完整还原。
// 注意：输出并非真实 gzip/zstd/lz4 位流；外部真实压缩流虽能被
// detect_format 按魔数识别，但解码失败将返回 Data_Corrupted，
// 不会静默丢失数据。

///|
/// 压缩统计结构
pub struct CompressionStats {
  /// 压缩后大小
  mut compressed_size : Int
  /// 原始大小
  mut original_size : Int
  /// 压缩比
  mut compression_ratio : Double
}

///|
/// 压缩处理器结构
pub struct CompressionProcessor {
  /// 配置
  config : CompressionConfig
  /// 内存池
  mempool : MemoryPool?
  /// 统计信息
  stats : CompressionStats
}

///|
/// 压缩错误类型
pub(all) enum CompressionError {
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

///|
/// 创建压缩统计
pub fn CompressionStats::new() -> CompressionStats {
  { compressed_size: 0, original_size: 0, compression_ratio: 0.0, }
}

///|
/// 创建压缩处理器
pub fn CompressionProcessor::new(
  config : CompressionConfig,
  mempool : MemoryPool?,
) -> CompressionProcessor {
  { config, mempool, stats: CompressionStats::new(), }
}

///|
/// 自动检测压缩格式
pub fn CompressionProcessor::detect_format(
  data : Array[Byte],
) -> CompressionFormat {
  if data.length() < 2 {
    return Gzip
  }
  if data[0] == 0x1f && data[1] == 0x8b {
    return Gzip
  }
  if data.length() >= 4 &&
    data[0] == 0x28 &&
    data[1] == 0xb5 &&
    data[2] == 0x2f &&
    data[3] == 0xfd {
    return Zstd
  }
  if data.length() >= 4 &&
    data[0] == 0x04 &&
    data[1] == 0x22 &&
    data[2] == 0x4d &&
    data[3] == 0x18 {
    return Lz4
  }
  Gzip
}

///|
/// 解压数据
pub fn CompressionProcessor::decompress(
  self : CompressionProcessor,
  data : Array[Byte],
  format : CompressionFormat,
) -> Result[Array[Byte], CompressionError] {
  match format {
    Gzip => self.decompress_gzip(data)
    Zstd => self.decompress_zstd(data)
    Lz4 => self.decompress_lz4(data)
  }
}

///|
/// Gzip 解压
fn CompressionProcessor::decompress_gzip(
  self : CompressionProcessor,
  data : Array[Byte],
) -> Result[Array[Byte], CompressionError] {
  self.decode_frame(data, Gzip)
}

///|
/// Zstd 解压
fn CompressionProcessor::decompress_zstd(
  self : CompressionProcessor,
  data : Array[Byte],
) -> Result[Array[Byte], CompressionError] {
  self.decode_frame(data, Zstd)
}

///|
/// Lz4 解压
fn CompressionProcessor::decompress_lz4(
  self : CompressionProcessor,
  data : Array[Byte],
) -> Result[Array[Byte], CompressionError] {
  self.decode_frame(data, Lz4)
}

///|
/// 压缩数据
pub fn CompressionProcessor::compress(
  self : CompressionProcessor,
  data : Array[Byte],
  format : CompressionFormat,
  level_opt : Int?,
) -> Result[Array[Byte], CompressionError] {
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

///|
/// Gzip 压缩
pub fn CompressionProcessor::compress_gzip(
  self : CompressionProcessor,
  data : Array[Byte],
  _level : Int,
) -> Result[Array[Byte], CompressionError] {
  self.encode_frame(data, Gzip)
}

///|
/// Zstd 压缩
pub fn CompressionProcessor::compress_zstd(
  self : CompressionProcessor,
  data : Array[Byte],
  _level : Int,
) -> Result[Array[Byte], CompressionError] {
  self.encode_frame(data, Zstd)
}

///|
/// Lz4 压缩
pub fn CompressionProcessor::compress_lz4(
  self : CompressionProcessor,
  data : Array[Byte],
  _level : Int,
) -> Result[Array[Byte], CompressionError] {
  self.encode_frame(data, Lz4)
}

///|
/// 流式解压
pub fn CompressionProcessor::decompress_stream(
  self : CompressionProcessor,
  stream : Array[Byte],
  format : CompressionFormat,
) -> Result[Array[Byte], CompressionError] {
  self.decompress(stream, format)
}

///|
/// 获取压缩统计
pub fn CompressionProcessor::stats(
  self : CompressionProcessor,
) -> CompressionStats {
  self.stats
}

///|
/// 获取压缩比
pub fn CompressionStats::compression_ratio(self : CompressionStats) -> Double {
  self.compression_ratio
}

///|
/// 获取压缩后大小
pub fn CompressionStats::compressed_size(self : CompressionStats) -> Int {
  self.compressed_size
}

///|
/// 获取原始大小
pub fn CompressionStats::original_size(self : CompressionStats) -> Int {
  self.original_size
}

///|
/// 帧格式魔数（与 detect_format 的判定保持一致）：
/// Gzip 使用真实 gzip 头前缀 + 自定义标记，Zstd/Lz4 使用其真实魔数。
fn compression_magic(format : CompressionFormat) -> Array[Byte] {
  match format {
    Gzip =>
      [
        0x1f.to_byte(),
        0x8b.to_byte(),
        0x4d.to_byte(),
        0x42.to_byte(),
      ]
    Zstd =>
      [
        0x28.to_byte(),
        0xb5.to_byte(),
        0x2f.to_byte(),
        0xfd.to_byte(),
      ]
    Lz4 =>
      [
        0x04.to_byte(),
        0x22.to_byte(),
        0x4d.to_byte(),
        0x18.to_byte(),
      ]
  }
}

///|
/// RLE 编码：输出 [run_len, value] 对，run_len ∈ [1, 255]。
fn rle_encode(data : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  let n = data.length()
  let mut i = 0
  while i < n {
    let v = data[i]
    let mut run = 1
    while run < 255 && i + run < n && data[i + run] == v {
      run = run + 1
    }
    out.push(run.to_byte())
    out.push(v)
    i = i + run
  }
  out
}

///|
/// RLE 解码：展开 [run_len, value] 对并严格校验总长度。
fn rle_decode(
  payload : Array[Byte],
  expected_len : Int,
) -> Result[Array[Byte], CompressionError] {
  let out : Array[Byte] = []
  let n = payload.length()
  let mut i = 0
  while i < n {
    if i + 1 >= n {
      return Err(Data_Corrupted) // 悬空的 run_len 缺少 value
    }
    let run = payload[i].to_int()
    let v = payload[i + 1]
    if run <= 0 {
      return Err(Data_Corrupted)
    }
    if out.length() + run > expected_len {
      return Err(Data_Corrupted)
    }
    let mut k = 0
    while k < run {
      out.push(v)
      k = k + 1
    }
    i = i + 2
  }
  if out.length() != expected_len {
    return Err(Data_Corrupted)
  }
  Ok(out)
}

///|
/// 统一压缩实现。帧结构：
/// [0..4) 格式魔数 | [4] 版本(=1) | [5] 模式(0=RLE, 1=原样)
/// [6..10) 原始长度（小端 32 位）| [10..) 载荷。
/// 高冗余数据走 RLE，否则原样存储，保证任何输入无损往返。
fn CompressionProcessor::encode_frame(
  self : CompressionProcessor,
  data : Array[Byte],
  format : CompressionFormat,
) -> Result[Array[Byte], CompressionError] {
  let rle = rle_encode(data)
  let use_rle = rle.length() < data.length()
  let mode : Int = if use_rle { 0 } else { 1 }
  let result : Array[Byte] = []
  for b in compression_magic(format) {
    result.push(b)
  }
  result.push(1.to_byte())
  result.push(mode.to_byte())
  let len = data.length()
  result.push((len & 0xff).to_byte())
  result.push(((len >> 8) & 0xff).to_byte())
  result.push(((len >> 16) & 0xff).to_byte())
  result.push(((len >> 24) & 0xff).to_byte())
  if use_rle {
    for b in rle {
      result.push(b)
    }
  } else {
    for b in data {
      result.push(b)
    }
  }
  self.stats.original_size = len
  self.stats.compressed_size = result.length()
  self.stats.compression_ratio = if self.stats.original_size > 0 {
    self.stats.compressed_size.to_double() /
    self.stats.original_size.to_double()
  } else {
    0.0
  }
  Ok(result)
}

///|
/// 统一解压实现：校验帧头（魔数、版本、长度一致性）后展开载荷。
/// 防解压炸弹：声明展开大小超过 256MB 绝对上限，或大输出
/// （>1MB）场景下压缩比超过 max_compression_ratio 时拒绝解压。
fn CompressionProcessor::decode_frame(
  self : CompressionProcessor,
  data : Array[Byte],
  format : CompressionFormat,
) -> Result[Array[Byte], CompressionError] {
  if data.length() < 10 {
    return Err(Data_Corrupted)
  }
  let magic = compression_magic(format)
  let mut i = 0
  while i < 4 {
    if data[i] != magic[i] {
      return Err(Unsupported_Format)
    }
    i = i + 1
  }
  if data[4].to_int() != 1 {
    return Err(Data_Corrupted)
  }
  let mode = data[5].to_int()
  let orig_len = data[6].to_int() |
    (data[7].to_int() << 8) |
    (data[8].to_int() << 16) |
    (data[9].to_int() << 24)
  if orig_len < 0 {
    return Err(Data_Corrupted)
  }
  if orig_len > 268435456 {
    return Err(Compression_Bomb)
  }
  if orig_len > 1048576 &&
    data.length() > 0 &&
    orig_len.to_double() / data.length().to_double() >
    self.config.max_compression_ratio {
    return Err(Compression_Bomb)
  }
  let payload : Array[Byte] = []
  let mut j = 10
  while j < data.length() {
    payload.push(data[j])
    j = j + 1
  }
  let out : Array[Byte] = match mode {
    0 =>
      match rle_decode(payload, orig_len) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
    1 => {
      if payload.length() != orig_len {
        return Err(Data_Corrupted)
      }
      payload
    }
    _ => return Err(Data_Corrupted)
  }
  self.stats.compressed_size = data.length()
  self.stats.original_size = out.length()
  self.stats.compression_ratio = if self.stats.compressed_size > 0 {
    self.stats.original_size.to_double() /
    self.stats.compressed_size.to_double()
  } else {
    0.0
  }
  Ok(out)
}
