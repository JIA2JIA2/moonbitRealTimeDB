// 流式处理结果模块
//
// 定义流式处理的结果结构和错误类型。

///|
/// 流式处理结果结构
///
/// 包含处理统计和延迟信息。
pub struct StreamResult {
  /// 是否完成
  mut completed : Bool
  /// 总记录数
  mut total_records : Int
  /// 成功记录数
  mut success_count : Int
  /// 失败记录数
  mut failed_count : Int
  /// P99 延迟（微秒）
  mut latency_p99 : Int
}

///|
/// 创建流式处理结果
pub fn StreamResult::new() -> StreamResult {
  {
    completed: false,
    total_records: 0,
    success_count: 0,
    failed_count: 0,
    latency_p99: 0,
  }
}

///|
/// 设置完成状态
pub fn StreamResult::set_completed(
  self : StreamResult,
  completed : Bool,
) -> Unit {
  self.completed = completed
}

///|
/// 设置总记录数
pub fn StreamResult::set_total_records(
  self : StreamResult,
  total : Int,
) -> Unit {
  self.total_records = total
}

///|
/// 设置 P99 延迟
pub fn StreamResult::set_latency_p99(
  self : StreamResult,
  latency_us : Int,
) -> Unit {
  self.latency_p99 = latency_us
}

///|
/// 添加成功记录
pub fn StreamResult::add_success(self : StreamResult) -> Unit {
  self.success_count = self.success_count + 1
}

///|
/// 添加失败记录
pub fn StreamResult::add_failure(self : StreamResult) -> Unit {
  self.failed_count = self.failed_count + 1
}

///|
/// 获取完成状态
pub fn StreamResult::completed(self : StreamResult) -> Bool {
  self.completed
}

///|
/// 获取总记录数
pub fn StreamResult::total_records(self : StreamResult) -> Int {
  self.total_records
}

///|
/// 获取成功记录数
pub fn StreamResult::success_count(self : StreamResult) -> Int {
  self.success_count
}

///|
/// 获取失败记录数
pub fn StreamResult::failed_count(self : StreamResult) -> Int {
  self.failed_count
}

///|
/// 获取 P99 延迟
pub fn StreamResult::latency_p99(self : StreamResult) -> Int {
  self.latency_p99
}
