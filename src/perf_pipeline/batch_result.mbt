// 批量导入结果模块
//
// 定义批量导入的结果结构和错误类型。

///|
/// 批量导入结果结构
///
/// 包含成功数、失败数及失败记录。
pub struct BatchResult {
  /// 成功记录数
  mut success_count : Int32
  /// 失败记录数
  mut failed_count : Int32
  /// 失败记录列表（索引，错误原因）
  failed_records : Array[(Int32, String)]
}

///|
/// 创建批量导入结果
pub fn BatchResult::new() -> BatchResult {
  { success_count: 0, failed_count: 0, failed_records: [], }
}

///|
/// 添加成功记录
pub fn BatchResult::add_success(self : BatchResult) -> Unit {
  self.success_count = self.success_count + 1
}

///|
/// 添加失败记录
pub fn BatchResult::add_failure(
  self : BatchResult,
  index : Int32,
  reason : String,
) -> Unit {
  self.failed_count = self.failed_count + 1
  self.failed_records.push((index, reason))
}

///|
/// 合并另一个批量结果
pub fn BatchResult::merge(self : BatchResult, other : BatchResult) -> Unit {
  self.success_count = self.success_count + other.success_count
  self.failed_count = self.failed_count + other.failed_count
  for (index, reason) in other.failed_records {
    self.failed_records.push((index, reason))
  }
}

///|
/// 获取成功记录数
pub fn BatchResult::success_count(self : BatchResult) -> Int32 {
  self.success_count
}

///|
/// 获取失败记录数
pub fn BatchResult::failed_count(self : BatchResult) -> Int32 {
  self.failed_count
}

///|
/// 获取失败记录列表
pub fn BatchResult::failed_records(
  self : BatchResult,
) -> Array[(Int32, String)] {
  self.failed_records
}
