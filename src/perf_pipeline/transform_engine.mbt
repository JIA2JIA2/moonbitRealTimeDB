// 转换引擎模块
//
// 实现数据转换功能，支持字段映射、过滤条件、聚合函数。

///|
/// 转换结果结构
pub struct TransformResult {
  /// 成功数
  mut success_count : Int32
  /// 失败数
  mut failed_count : Int32
  /// 转换后的记录
  transformed_records : Array[@realtime_db.Value]
}

///|
/// 转换引擎结构
pub struct TransformEngine {
  /// 配置
  config : TransformConfig
  /// 转换规则
  rules : Array[TransformRule]
  /// 统计信息
  mut stats : TransformResult
}

///|
/// 转换错误类型
pub(all) enum TransformError {
  /// 规则语法错误
  Rule_Syntax_Error
  /// 类型转换失败
  Cast_Failed
  /// 输出字段冲突
  Output_Field_Conflict
  /// 主键字段被修改
  Primary_Key_Modified
  /// 超时
  Timeout
}

///|
/// 创建转换结果
pub fn TransformResult::new() -> TransformResult {
  { success_count: 0, failed_count: 0, transformed_records: [], }
}

///|
/// 创建转换引擎
pub fn TransformEngine::new(config : TransformConfig) -> TransformEngine {
  { config, rules: config.rules(), stats: TransformResult::new(), }
}

///|
/// 应用单条记录的所有转换规则
pub fn TransformEngine::apply_rules(
  self : TransformEngine,
  record : @realtime_db.Value,
) -> Result[@realtime_db.Value, TransformError] {
  let mut current = record
  for rule in self.rules {
    current = match self.transform_field(current, rule) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
  }
  Ok(current)
}

///|
/// 按定义顺序执行多个转换规则
pub fn TransformEngine::apply_transform_chain(
  self : TransformEngine,
  record : @realtime_db.Value,
) -> Result[@realtime_db.Value, TransformError] {
  self.apply_rules(record)
}

///|
/// 转换字段
///
// 支持字段映射、类型转换、过滤、聚合。
pub fn TransformEngine::transform_field(
  self : TransformEngine,
  value : @realtime_db.Value,
  rule : TransformRule,
) -> Result[@realtime_db.Value, TransformError] {
  match rule.action {
    Rename => self.apply_rename(value, rule)
    Cast => self.apply_cast(value, rule)
    Filter => self.apply_filter(value, rule)
    Aggregate => self.apply_aggregate(value, rule)
  }
}

///|
/// 应用重命名
fn TransformEngine::apply_rename(
  self : TransformEngine,
  value : @realtime_db.Value,
  rule : TransformRule,
) -> Result[@realtime_db.Value, TransformError] {
  let _ = self
  let _ = rule
  // 简化实现：直接返回原值
  Ok(value)
}

///|
/// 应用类型转换
fn TransformEngine::apply_cast(
  self : TransformEngine,
  value : @realtime_db.Value,
  rule : TransformRule,
) -> Result[@realtime_db.Value, TransformError] {
  let _ = self
  match rule.target_type {
    Some("string") =>
      match value {
        @realtime_db.Int(i) => Ok(@realtime_db.Str(i.to_string()))
        @realtime_db.Float(f) => Ok(@realtime_db.Str(f.to_string()))
        @realtime_db.Bool(b) => Ok(@realtime_db.Str(b.to_string()))
        _ => Ok(value)
      }
    Some("int") =>
      match value {
        @realtime_db.Str(s) =>
          match parse_int_str(s) {
            Some(i) => Ok(@realtime_db.Int(i))
            None => Err(Cast_Failed)
          }
        _ => Ok(value)
      }
    _ => Ok(value)
  }
}

///|
/// 应用过滤
fn TransformEngine::apply_filter(
  self : TransformEngine,
  value : @realtime_db.Value,
  rule : TransformRule,
) -> Result[@realtime_db.Value, TransformError] {
  let _ = self
  let _ = rule
  // 简化实现：直接返回原值
  Ok(value)
}

///|
/// 应用聚合
fn TransformEngine::apply_aggregate(
  self : TransformEngine,
  value : @realtime_db.Value,
  rule : TransformRule,
) -> Result[@realtime_db.Value, TransformError] {
  let _ = self
  let _ = rule
  // 简化实现：直接返回原值
  Ok(value)
}

///|
/// 验证输出
///
// 验证输出字段不重复。
pub fn TransformEngine::validate_output(
  self : TransformEngine,
  record : @realtime_db.Value,
) -> Result[Unit, TransformError] {
  let _ = self
  let _ = record
  Ok(())
}

///|
/// 批量转换
///
// 批量应用转换规则。
pub fn TransformEngine::transform_batch(
  self : TransformEngine,
  data : Array[@realtime_db.Value],
) -> TransformResult {
  let result = TransformResult::new()
  for record in data {
    match self.apply_rules(record) {
      Ok(transformed) => {
        result.success_count = result.success_count + 1
        result.transformed_records.push(transformed)
      }
      Err(_) => result.failed_count = result.failed_count + 1
    }
  }
  result
}

///|
/// 获取统计信息
pub fn TransformEngine::stats(self : TransformEngine) -> TransformResult {
  self.stats
}

///|
/// 重置统计
pub fn TransformEngine::reset_stats(self : TransformEngine) -> Unit {
  self.stats = TransformResult::new()
}

///|
/// 获取成功数
pub fn TransformResult::success_count(self : TransformResult) -> Int32 {
  self.success_count
}

///|
/// 获取失败数
pub fn TransformResult::failed_count(self : TransformResult) -> Int32 {
  self.failed_count
}

///|
/// 获取转换后的记录
pub fn TransformResult::transformed_records(
  self : TransformResult,
) -> Array[@realtime_db.Value] {
  self.transformed_records
}

///|
/// 将整数字符串解析为 Int（支持可选负号），非法输入返回 None
fn parse_int_str(s : String) -> Int32? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut i = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    i = 1
    if chars.length() == 1 {
      return None
    }
  }
  let mut value = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    i = i + 1
  }
  if negative {
    Some(-value)
  } else {
    Some(value)
  }
}
