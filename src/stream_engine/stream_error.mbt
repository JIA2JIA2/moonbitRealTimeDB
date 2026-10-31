// 流引擎错误类型定义
//
// 定义流处理相关的所有错误类型和错误码

///|
/// 流处理错误类型
pub(all) enum StreamError {
  // 管道相关错误 (1001-1004)
  /// 管道已存在
  Pipeline_Already_Exists
  /// 管道不存在
  Pipeline_Not_Found
  /// 管道配置无效
  Pipeline_Invalid_Config
  /// 管道状态错误
  Pipeline_Invalid_State

  // 窗口相关错误 (2001-2004)
  /// 窗口已存在
  Window_Already_Exists
  /// 窗口不存在
  Window_Not_Found
  /// 窗口配置无效
  Window_Invalid_Config
  /// 窗口状态错误
  Window_Invalid_State

  // 聚合相关错误 (3001-3002)
  /// 聚合函数不存在
  Aggregate_Function_Not_Found
  /// 聚合计算失败
  Aggregate_Computation_Failed

  // 订阅相关错误 (4001-4004)
  /// 订阅已存在
  Subscription_Already_Exists
  /// 订阅不存在
  Subscription_Not_Found
  /// 订阅配置无效
  Subscription_Invalid_Config
  /// 订阅限制超限
  Subscription_Limit_Exceeded

  // 状态相关错误 (5001-5002)
  /// 状态存储错误
  State_Storage_Error
  /// 状态恢复失败
  State_Recovery_Failed

  // 检查点相关错误 (6001-6003)
  /// 检查点创建失败
  Checkpoint_Creation_Failed
  /// 检查点恢复失败
  Checkpoint_Recovery_Failed
  /// 检查点超时
  Checkpoint_Timeout

  // 水位线相关错误 (7001)
  /// 水位线停滞
  Watermark_Stalled

  // 通用错误
  /// 内部错误
  Internal_Error(String)
  /// 超时
  Timeout
  /// 资源不足
  Resource_Exhausted
} derive(Eq)

///|
/// 获取错误码
pub fn StreamError::code(self : StreamError) -> Int32 {
  match self {
    Pipeline_Already_Exists => 1001
    Pipeline_Not_Found => 1002
    Pipeline_Invalid_Config => 1003
    Pipeline_Invalid_State => 1004
    Window_Already_Exists => 2001
    Window_Not_Found => 2002
    Window_Invalid_Config => 2003
    Window_Invalid_State => 2004
    Aggregate_Function_Not_Found => 3001
    Aggregate_Computation_Failed => 3002
    Subscription_Already_Exists => 4001
    Subscription_Not_Found => 4002
    Subscription_Invalid_Config => 4003
    Subscription_Limit_Exceeded => 4004
    State_Storage_Error => 5001
    State_Recovery_Failed => 5002
    Checkpoint_Creation_Failed => 6001
    Checkpoint_Recovery_Failed => 6002
    Checkpoint_Timeout => 6003
    Watermark_Stalled => 7001
    Internal_Error(_) => 9001
    Timeout => 9002
    Resource_Exhausted => 9003
  }
}

///|
/// 获取错误消息
pub fn StreamError::message(self : StreamError) -> String {
  match self {
    Pipeline_Already_Exists => "Pipeline already exists"
    Pipeline_Not_Found => "Pipeline not found"
    Pipeline_Invalid_Config => "Invalid pipeline configuration"
    Pipeline_Invalid_State => "Invalid pipeline state"
    Window_Already_Exists => "Window already exists"
    Window_Not_Found => "Window not found"
    Window_Invalid_Config => "Invalid window configuration"
    Window_Invalid_State => "Invalid window state"
    Aggregate_Function_Not_Found => "Aggregate function not found"
    Aggregate_Computation_Failed => "Aggregate computation failed"
    Subscription_Already_Exists => "Subscription already exists"
    Subscription_Not_Found => "Subscription not found"
    Subscription_Invalid_Config => "Invalid subscription configuration"
    Subscription_Limit_Exceeded => "Subscription limit exceeded (max 1000)"
    State_Storage_Error => "State storage error"
    State_Recovery_Failed => "State recovery failed"
    Checkpoint_Creation_Failed => "Checkpoint creation failed"
    Checkpoint_Recovery_Failed => "Checkpoint recovery failed"
    Checkpoint_Timeout => "Checkpoint timeout"
    Watermark_Stalled => "Watermark stalled"
    Internal_Error(msg) => "Internal error: " + msg
    Timeout => "Operation timeout"
    Resource_Exhausted => "Resource exhausted"
  }
}

///|
/// 转为字符串
pub fn StreamError::to_string(self : StreamError) -> String {
  "[Error " + self.code().to_string() + "] " + self.message()
}

///|
/// 判断是否是可重试错误
pub fn StreamError::is_retryable(self : StreamError) -> Bool {
  match self {
    State_Storage_Error => true
    Checkpoint_Creation_Failed => true
    Checkpoint_Recovery_Failed => true
    Timeout => true
    Resource_Exhausted => true
    _ => false
  }
}

///|
/// 判断是否是致命错误
pub fn StreamError::is_fatal(self : StreamError) -> Bool {
  match self {
    Pipeline_Already_Exists => true
    Pipeline_Not_Found => true
    Subscription_Limit_Exceeded => true
    Internal_Error(_) => true
    _ => false
  }
}

///|
pub extend StreamError with Eq::{equal, not_equal}
