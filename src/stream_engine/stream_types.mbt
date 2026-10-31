// 流引擎核心类型定义
//
// 定义窗口、水位线、检查点、过滤、聚合等核心数据结构

///|
/// 窗口 ID
pub(all) struct WindowId {
  /// 管道名称
  pipeline_name : String
  /// 窗口名称
  window_name : String
  /// 起始时间
  start_time : Int32
} derive(Eq, Hash)

///|
/// 窗口类型枚举
pub(all) enum WindowType {
  /// 滚动窗口：固定大小，不重叠
  Tumbling
  /// 滑动窗口：固定大小，可重叠
  Sliding
  /// 会话窗口：基于活动时间划分
  Session
} derive(Eq, Debug)

///|
/// 窗口状态枚举
pub(all) enum WindowStatus {
  /// 开放：接受新数据
  Open
  /// 关闭中：准备输出
  Closing
  /// 已关闭：已输出结果
  Closed
  /// 已过期：状态已清理
  Expired
  /// 已驱逐：迟到数据
  Evicted
} derive(Eq, Debug)

///|
/// 窗口状态结构体
pub(all) struct WindowState {
  /// 窗口 ID
  window_id : WindowId
  /// 当前状态
  mut status : WindowStatus
  /// 起始时间
  start_time : Int32
  /// 结束时间
  end_time : Int32
  /// 元素数量
  mut elements : Int32
  /// 聚合状态
  mut aggregate_state : @realtime_db.Value?
}

///|
/// 水位线结构体
pub(all) struct Watermark {
  /// 时间戳
  mut timestamp : Int32
  /// 是否已推进
  mut advanced : Bool
}

///|
/// 检查点 ID
pub(all) struct CheckpointId {
  /// 检查点值
  value : Int32
  /// 创建时间
  created_at : Int32
}

///|
/// 检查点状态
pub(all) struct CheckpointState {
  /// 检查点 ID
  checkpoint_id : CheckpointId
  /// 时间戳
  timestamp : Int32
  /// 窗口状态映射
  window_states : Map[WindowId, WindowState]
  /// 聚合状态映射
  aggregate_states : Map[String, @realtime_db.Value]
  /// 订阅状态映射
  subscription_states : Map[String, @realtime_db.Value]
}

///|
/// 检查点配置
pub(all) struct CheckpointConfig {
  /// 检查点间隔（毫秒）
  interval_ms : Int32
  /// 检查点超时（毫秒）
  timeout_ms : Int32
  /// 是否增量检查点
  incremental : Bool
  /// 最大保留检查点数
  max_retained_checkpoints : Int32
}

///|
/// 默认检查点配置
pub fn CheckpointConfig::default() -> CheckpointConfig {
  {
    interval_ms: 60000,
    timeout_ms: 60000,
    incremental: true,
    max_retained_checkpoints: 3,
  }
}

///|
/// 逻辑运算符枚举
pub(all) enum LogicOp {
  /// 与
  And
  /// 或
  Or
  /// 非
  Not
} derive(Eq, Debug)

///|
/// 操作符枚举
pub(all) enum Operator {
  /// 等于
  Equal
  /// 不等于
  NotEqual
  /// 大于
  GreaterThan
  /// 小于
  LessThan
  /// 前缀匹配
  Prefix
  /// 正则匹配
  Regex
} derive(Eq, Debug)

///|
/// 过滤条件
pub(all) struct Condition {
  /// 字段路径
  field : String
  /// 操作符
  op : Operator
  /// 目标值
  target : @realtime_db.Value
}

///|
/// 过滤表达式
pub(all) struct FilterExpr {
  /// 条件数组
  conditions : Array[Condition]
  /// 逻辑运算符
  logic_op : LogicOp
}

///|
/// 订阅状态
pub(all) struct SubscriptionState {
  /// 订阅 ID
  subscription_id : String
  /// 过滤表达式
  filter_expr : FilterExpr
  /// 最后事件时间
  last_event_time : Int32
  /// 待处理事件数
  pending_events : Int32
  /// 失败计数
  failed_count : Int32
}

///|
/// 订阅配置
pub(all) struct SubscriptionConfig {
  /// 最大重试次数
  max_retries : Int32
  /// 重试超时（毫秒）
  retry_timeout_ms : Int32
  /// 回调超时（毫秒）
  callback_timeout_ms : Int32
  /// 队列深度
  queue_depth : Int32
}

///|
/// 默认订阅配置
pub fn SubscriptionConfig::default() -> SubscriptionConfig {
  {
    max_retries: 3,
    retry_timeout_ms: 1000,
    callback_timeout_ms: 100,
    queue_depth: 1000,
  }
}

///|
/// 聚合状态
pub(all) struct AggregateState {
  /// 聚合函数名称
  fn_name : String
  /// 数据
  data : @realtime_db.Value
  /// 计数
  count : Int32
}

///|
/// 迟到数据策略枚举
pub(all) enum LateDataPolicy {
  /// 丢弃
  Drop
  /// 侧输出
  SideOutput
  /// 合并
  Merge
} derive(Eq, Debug)

///|
/// 窗口配置
pub(all) struct WindowConfig {
  /// 窗口名称
  name : String
  /// 窗口类型
  window_type : WindowType
  /// 窗口大小（毫秒）
  size_ms : Int32
  /// 滑动步长（毫秒）
  slide_ms : Int32
  /// 会话超时（毫秒）
  timeout_ms : Int32
  /// 迟到数据策略
  late_data_policy : LateDataPolicy
}

///|
/// 管道配置
pub(all) struct PipelineConfig {
  /// 批次大小
  batch_size : Int32
  /// 缓冲区大小
  buffer_size : Int32
  /// 背压阈值
  backpressure_threshold : Double
  /// 并发度
  concurrency : Int32
  /// 重试次数
  retry_count : Int32
}

///|
/// 默认管道配置
pub fn PipelineConfig::default() -> PipelineConfig {
  {
    batch_size: 1000,
    buffer_size: 10000,
    backpressure_threshold: 0.8,
    concurrency: 1,
    retry_count: 3,
  }
}

///|
/// 流配置
pub(all) struct StreamConfig {
  /// 配置名称
  name : String
  /// 管道配置
  pipeline_config : PipelineConfig
  /// 窗口配置数组
  window_configs : Array[WindowConfig]
  /// 检查点配置
  checkpoint_config : CheckpointConfig
  /// 订阅配置
  subscription_config : SubscriptionConfig
}

///|
/// 管道状态枚举
pub(all) enum PipelineStatus {
  /// 已创建
  Created
  /// 运行中
  Running
  /// 已暂停
  Paused
  /// 已停止
  Stopped
  /// 错误
  Error
} derive(Eq, Debug)

///|
/// 数据变更事件（与主存储事件兼容）
pub(all) struct StreamEvent {
  /// 键
  key : String
  /// 值
  value : @realtime_db.Value
  /// 事件类型
  event_type : StreamEventType
  /// 时间戳
  timestamp : Int32
}

///|
/// 流事件类型枚举
pub(all) enum StreamEventType {
  /// 设置
  Set
  /// 删除
  Delete
  /// 过期
  Expire
} derive(Eq, Debug)

///|
/// 聚合结果
pub(all) struct AggregateResult {
  /// 窗口 ID
  window_id : WindowId
  /// 聚合函数名称
  fn_name : String
  /// 结果值
  result : @realtime_db.Value
  /// 触发时间
  trigger_time : Int32
}

///|
/// 订阅回调类型
pub type SubscriptionCallback = (StreamEvent) -> Unit

///|
/// 触发器类型枚举
pub(all) enum TriggerType {
  /// 水位线触发
  WatermarkTrigger
  /// 计数触发
  CountTrigger
  /// 时间触发
  TimeTrigger
} derive(Eq, Debug)

///|
pub extend WindowId with Eq::{equal, not_equal}

///|
pub extend WindowId with Hash::{hash, hash_combine}

///|
pub extend WindowType with Eq::{equal, not_equal}

///|
pub extend WindowType with Debug::{to_repr}

///|
pub extend WindowStatus with Eq::{equal, not_equal}

///|
pub extend WindowStatus with Debug::{to_repr}

///|
pub extend LogicOp with Eq::{equal, not_equal}

///|
pub extend LogicOp with Debug::{to_repr}

///|
pub extend Operator with Eq::{equal, not_equal}

///|
pub extend Operator with Debug::{to_repr}

///|
pub extend LateDataPolicy with Eq::{equal, not_equal}

///|
pub extend LateDataPolicy with Debug::{to_repr}

///|
pub extend PipelineStatus with Eq::{equal, not_equal}

///|
pub extend PipelineStatus with Debug::{to_repr}

///|
pub extend StreamEventType with Eq::{equal, not_equal}

///|
pub extend StreamEventType with Debug::{to_repr}

///|
pub extend TriggerType with Eq::{equal, not_equal}

///|
pub extend TriggerType with Debug::{to_repr}
