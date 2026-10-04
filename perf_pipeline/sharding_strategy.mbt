// 分片策略模块
//
// 实现数据分片策略，支持自动分片。

///|
/// 分片结构
pub struct Shard {
  /// 分片 ID
  id : Int
  /// 分片数据
  data : Array[(String, @realtime_db.Value)]
  /// 分片偏移
  offset : Int
  /// 分片大小
  size : Int
}

///|
/// 分片策略结构
pub struct ShardingStrategy {
  /// 分片大小
  mut shard_size : Int
  /// 分片数量
  mut shard_count : Int
}

///|
/// 创建分片
pub fn Shard::new(
  id : Int,
  data : Array[(String, @realtime_db.Value)],
  offset : Int,
  size : Int,
) -> Shard {
  { id, data, offset, size, }
}

///|
/// 获取分片数据
pub fn Shard::data(self : Shard) -> Array[(String, @realtime_db.Value)] {
  self.data
}

///|
/// 获取分片大小
pub fn Shard::size(self : Shard) -> Int {
  self.size
}

///|
/// 创建分片策略
pub fn ShardingStrategy::new(shard_size : Int) -> ShardingStrategy {
  { shard_size, shard_count: 0, }
}

///|
/// 拆分数据
///
// 自动将大数据集按记录数分片。
pub fn ShardingStrategy::split_data(
  self : ShardingStrategy,
  data : Array[(String, @realtime_db.Value)],
) -> Array[Shard] {
  let shards : Array[Shard] = []
  let total = data.length()

  if total == 0 {
    return shards
  }

  // 计算分片数量
  let shard_count = self.calculate_shard_count(total)
  self.shard_count = shard_count

  // 拆分数据
  let mut i = 0
  while i < shard_count {
    let offset = i * self.shard_size
    let remaining = total - offset
    let shard_size = if remaining < self.shard_size {
      remaining
    } else {
      self.shard_size
    }

    // 提取分片数据
    let shard_data : Array[(String, @realtime_db.Value)] = []
    let mut j = 0
    while j < shard_size {
      shard_data.push(data[offset + j])
      j = j + 1
    }

    shards.push(Shard::new(i, shard_data, offset, shard_size))
    i = i + 1
  }

  shards
}

///|
/// 计算分片数量
///
// 返回分片数量。
pub fn ShardingStrategy::calculate_shard_count(
  self : ShardingStrategy,
  total_records : Int,
) -> Int {
  if total_records <= self.shard_size {
    return 1
  }
  let count = total_records / self.shard_size
  if total_records % self.shard_size != 0 {
    count + 1
  } else {
    count
  }
}

///|
/// 获取分片数量
pub fn ShardingStrategy::shard_count(self : ShardingStrategy) -> Int {
  self.shard_count
}

///|
/// 设置分片大小
pub fn ShardingStrategy::set_shard_size(
  self : ShardingStrategy,
  size : Int,
) -> Unit {
  self.shard_size = size
}
