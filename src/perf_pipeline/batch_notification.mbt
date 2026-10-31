// 批量通知模块
//
// 定义批量通知结构。

///|
/// 批量通知结构
///
/// 包含聚合后的事件列表和时间戳。
pub struct BatchNotification {
  /// 事件列表
  events : Array[@realtime_db.Event]
  /// 时间戳
  timestamp : Int32
  /// 批次 ID
  batch_id : Int32
}

///|
/// 创建批量通知
pub fn BatchNotification::new(
  events : Array[@realtime_db.Event],
  timestamp : Int32,
  batch_id : Int32,
) -> BatchNotification {
  { events, timestamp, batch_id, }
}

///|
/// 获取事件列表
pub fn BatchNotification::events(
  self : BatchNotification,
) -> Array[@realtime_db.Event] {
  self.events
}

///|
/// 获取时间戳
pub fn BatchNotification::timestamp(self : BatchNotification) -> Int32 {
  self.timestamp
}

///|
/// 获取批次 ID
pub fn BatchNotification::batch_id(self : BatchNotification) -> Int32 {
  self.batch_id
}
