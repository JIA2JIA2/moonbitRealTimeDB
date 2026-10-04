// 转换配置模块
//
// 定义数据转换相关的配置结构。

///|
/// 转换动作类型
pub enum TransformAction {
  /// 重命名字段
  Rename
  /// 类型转换
  Cast
  /// 过滤
  Filter
  /// 聚合
  Aggregate
}

///|
/// 聚合函数类型
pub enum AggregateFunction {
  /// 计数
  Count
  /// 求和
  Sum
  /// 平均值
  Avg
  /// 最大值
  Max
  /// 最小值
  Min
}

///|
/// 转换规则结构
pub struct TransformRule {
  /// 源字段
  field : String
  /// 目标类型（可选）
  target_type : String?
  /// 目标字段名（可选）
  target : String?
  /// 条件（可选）
  condition : String?
  /// 动作类型
  action : TransformAction
}

///|
/// 转换配置结构
pub struct TransformConfig {
  /// 转换规则列表
  rules : Array[TransformRule]
  /// 最大转换规则数
  max_transforms : Int
  /// 转换超时时间（毫秒）
  transform_timeout : Int
}

///|
/// 创建默认转换配置
pub fn TransformConfig::default() -> TransformConfig {
  {
    rules: [],
    max_transforms: 10,
    transform_timeout: 5000,
  }
}

///|
/// 创建转换规则
pub fn TransformRule::new(
  field : String,
  action : TransformAction
) -> TransformRule {
  {
    field,
    target_type: None,
    target: None,
    condition: None,
    action,
  }
}

///|
/// 设置目标类型
pub fn TransformRule::set_target_type(self : TransformRule, target_type : String) -> Unit {
  self.target_type = Some(target_type)
}

///|
/// 设置目标字段
pub fn TransformRule::set_target(self : TransformRule, target : String) -> Unit {
  self.target = Some(target)
}

///|
/// 设置条件
pub fn TransformRule::set_condition(self : TransformRule, condition : String) -> Unit {
  self.condition = Some(condition)
}

///|
/// 添加转换规则
pub fn TransformConfig::add_rule(self : TransformConfig, rule : TransformRule) -> Unit {
  self.rules.push(rule)
}

///|
/// 验证配置
pub fn TransformConfig::validate(self : TransformConfig) -> Result[Unit, String] {
  if self.rules.length() > self.max_transforms {
    return Err("Too many transform rules")
  }
  if self.transform_timeout < 1 {
    return Err("Transform timeout must be positive")
  }
  Ok(())
}

///|
/// 设置最大转换规则数
pub fn TransformConfig::set_max_transforms(self : TransformConfig, max : Int) -> Unit {
  self.max_transforms = max
}

///|
/// 设置转换超时时间
pub fn TransformConfig::set_transform_timeout(self : TransformConfig, timeout : Int) -> Unit {
  self.transform_timeout = timeout
}

///|
/// 获取规则列表
pub fn TransformConfig::rules(self : TransformConfig) -> Array[TransformRule] {
  self.rules
}

///|
/// 获取动作名称
pub fn TransformAction::to_string(self : TransformAction) -> String {
  match self {
    Rename => "rename"
    Cast => "cast"
    Filter => "filter"
    Aggregate => "aggregate"
  }
}

///|
/// 获取聚合函数名称
pub fn AggregateFunction::to_string(self : AggregateFunction) -> String {
  match self {
    Count => "count"
    Sum => "sum"
    Avg => "avg"
    Max => "max"
    Min => "min"
  }
}

///|
/// 从字符串解析动作类型
pub fn parse_transform_action(s : String) -> TransformAction? {
  match s {
    "rename" => Some(Rename)
    "cast" => Some(Cast)
    "filter" => Some(Filter)
    "aggregate" => Some(Aggregate)
    _ => None
  }
}

///|
/// 从字符串解析聚合函数
pub fn parse_aggregate_function(s : String) -> AggregateFunction? {
  match s {
    "count" => Some(Count)
    "sum" => Some(Sum)
    "avg" => Some(Avg)
    "max" => Some(Max)
    "min" => Some(Min)
    _ => None
  }
}