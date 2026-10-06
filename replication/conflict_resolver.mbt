// 冲突检测与解决模块
//
// 实现冲突检测、冲突解决、向量时钟

///|
/// 向量时钟
pub(all) struct VectorClock {
  /// 时钟映射：节点ID -> 时间戳
  clocks : Map[String, Int]
}

///|
/// 创建向量时钟
pub fn VectorClock::new() -> VectorClock {
  { clocks: Map([]) }
}

///|
/// 更新时钟
pub fn VectorClock::update(self : VectorClock, node_id : String, timestamp : Int) -> Unit {
  self.clocks.set(node_id, timestamp)
}

///|
/// 获取时钟值
pub fn VectorClock::get(self : VectorClock, node_id : String) -> Int {
  match self.clocks.get(node_id) {
    Some(t) => t
    None => 0
  }
}

///|
/// 比较向量时钟
pub fn VectorClock::compare(self : VectorClock, other : VectorClock) -> ClockOrder {
  var all_less = true
  var all_greater = true

  // 检查所有节点
  for (node_id, time) in self.clocks {
    let other_time = other.get(node_id)
    if time > other_time {
      all_less = false
    } else if time < other_time {
      all_greater = false
    }
  }

  for (node_id, time) in other.clocks {
    if not self.clocks.contains_key(node_id) {
      if time > 0 {
        all_less = false
      }
    }
  }

  if all_less and not all_greater {
    ClockOrder::Before
  } else if all_greater and not all_less {
    ClockOrder::After
  } else {
    ClockOrder::Concurrent
  }
}

///|
/// 时钟顺序
pub(all) enum ClockOrder {
  /// 之前
  Before
  /// 之后
  After
  /// 并发
  Concurrent
}

///|
/// 版本向量
pub(all) struct VersionVector {
  /// 版本映射：节点ID -> 版本号
  versions : Map[String, Int]
}

///|
/// 创建版本向量
pub fn VersionVector::new() -> VersionVector {
  { versions: Map([]) }
}

///|
/// 增加版本
pub fn VersionVector::increment(self : VersionVector, node_id : String) -> Int {
  let current = self.get(node_id)
  let new_version = current + 1
  self.versions.set(node_id, new_version)
  new_version
}

///|
/// 获取版本号
pub fn VersionVector::get(self : VersionVector, node_id : String) -> Int {
  match self.versions.get(node_id) {
    Some(v) => v
    None => 0
  }
}

///|
/// 合并版本向量
pub fn VersionVector::merge(self : VersionVector, other : VersionVector) -> Unit {
  for (node_id, version) in other.versions {
    let current = self.get(node_id)
    if version > current {
      self.versions.set(node_id, version)
    }
  }
}

///|
/// 冲突检测器
pub(all) struct ConflictDetector {
  /// 向量时钟
  vector_clock : VectorClock
  /// 版本向量
  version_vector : VersionVector
  /// 冲突解决策略
  strategy : ConflictResolutionStrategy
}

///|
/// 创建冲突检测器
pub fn ConflictDetector::new(strategy : ConflictResolutionStrategy) -> ConflictDetector {
  {
    vector_clock: VectorClock::new(),
    version_vector: VersionVector::new(),
    strategy,
  }
}

///|
/// 检测冲突
pub fn ConflictDetector::detect(
  self : ConflictDetector,
  key : String,
  source_value : @realtime_db.Value,
  source_timestamp : Int,
  source_node : String,
  target_value : @realtime_db.Value,
  target_timestamp : Int,
  target_node : String,
) -> Bool {
  // 检查值是否相同
  if source_value == target_value {
    return false
  }

  // 检查时间戳
  if source_timestamp == target_timestamp {
    // 时间戳相同，可能是冲突
    return true
  }

  // 检查向量时钟
  let source_clock = self.vector_clock.get(source_node)
  let target_clock = self.vector_clock.get(target_node)

  if source_clock == target_clock {
    // 时钟相同，可能是冲突
    return true
  }

  // 检查版本向量
  let source_version = self.version_vector.get(source_node)
  let target_version = self.version_vector.get(target_node)

  if source_version == target_version {
    // 版本相同，可能是冲突
    return true
  }

  false
}

///|
/// 解决冲突
pub fn ConflictDetector::resolve(
  self : ConflictDetector,
  key : String,
  source_value : @realtime_db.Value,
  source_timestamp : Int,
  source_version : Int,
  source_node : String,
  target_value : @realtime_db.Value,
  target_timestamp : Int,
  target_version : Int,
  target_node : String,
) -> ConflictResolutionResult {
  let resolved_value = match self.strategy {
    ConflictResolutionStrategy::Timestamp => {
      if source_timestamp >= target_timestamp {
        source_value
      } else {
        target_value
      }
    }
    ConflictResolutionStrategy::Version => {
      if source_version >= target_version {
        source_value
      } else {
        target_value
      }
    }
    ConflictResolutionStrategy::Source_Priority => {
      source_value
    }
    ConflictResolutionStrategy::Target_Priority => {
      target_value
    }
    ConflictResolutionStrategy::Custom => {
      // 自定义策略：选择最新值
      if source_timestamp >= target_timestamp {
        source_value
      } else {
        target_value
      }
    }
  }

  ConflictResolutionResult {
    key,
    resolved_value,
    resolution_strategy: self.strategy,
    resolved_at: 0,
  }
}

///|
/// 冲突解决结果
pub(all) struct ConflictResolutionResult {
  /// 键
  key : String
  /// 解决后的值
  resolved_value : @realtime_db.Value
  /// 解决策略
  resolution_strategy : ConflictResolutionStrategy
  /// 解决时间
  resolved_at : Int
}

///|
/// 冲突解决器
pub(all) struct ConflictResolver {
  /// 策略映射：表名 -> 策略
  strategies : Map[String, ConflictResolutionStrategy]
  /// 默认策略
  default_strategy : ConflictResolutionStrategy
}

///|
/// 创建冲突解决器
pub fn ConflictResolver::new(default_strategy : ConflictResolutionStrategy) -> ConflictResolver {
  {
    strategies: Map([]),
    default_strategy,
  }
}

///|
/// 设置策略
pub fn ConflictResolver::set_strategy(
  self : ConflictResolver,
  table_name : String,
  strategy : ConflictResolutionStrategy,
) -> Unit {
  self.strategies.set(table_name, strategy)
}

///|
/// 获取策略
pub fn ConflictResolver::get_strategy(self : ConflictResolver, table_name : String) -> ConflictResolutionStrategy {
  match self.strategies.get(table_name) {
    Some(s) => s
    None => self.default_strategy
  }
}

///|
/// 解决冲突
pub fn ConflictResolver::resolve(
  self : ConflictResolver,
  table_name : String,
  key : String,
  source_value : @realtime_db.Value,
  source_timestamp : Int,
  source_version : Int,
  source_node : String,
  target_value : @realtime_db.Value,
  target_timestamp : Int,
  target_version : Int,
  target_node : String,
) -> ConflictResolutionResult {
  let strategy = self.get_strategy(table_name)
  let detector = ConflictDetector::new(strategy)

  detector.resolve(
    key,
    source_value,
    source_timestamp,
    source_version,
    source_node,
    target_value,
    target_timestamp,
    target_version,
    target_node,
  )
}

///|
/// 创建冲突检测器
pub fn create_conflict_detector(strategy : ConflictResolutionStrategy) -> ConflictDetector {
  ConflictDetector::new(strategy)
}

///|
/// 创建冲突解决器
pub fn create_conflict_resolver(default_strategy : ConflictResolutionStrategy) -> ConflictResolver {
  ConflictResolver::new(default_strategy)
}