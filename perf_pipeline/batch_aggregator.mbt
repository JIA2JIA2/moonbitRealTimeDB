// 批量聚合器模块
//
// 实现批量订阅聚合，将多个事件合并为单个通知。
// 目标：聚合窗口 100ms，最大批量大小 1000

///|
/// 批量订阅者结构
///
/// 包含回调、聚合窗口和去重配置。
pub struct BatchWatcher {
  /// 订阅者 ID
  id : Int
  /// 回调函数
  callback : (BatchNotification) -> Unit
  /// 聚合窗口（毫秒）
  window_ms : Int
  /// 是否去重
  deduplicate : Bool
}

///|
/// 批量聚合器结构
///
/// 管理所有批量订阅者。
pub struct BatchAggregator {
  /// 订阅者映射
  watchers : Map[Int, BatchWatcher]
  /// 每个订阅者的缓冲区
  watcher_buffers : Map[Int, Array[@realtime_db.Event]]
  /// 每个订阅者的窗口开始时间
  watcher_window_starts : Map[Int, Int]
  /// 配置
  config : PipelineConfig
  /// 下一个订阅者 ID
  mut next_watcher_id : Int
}

///|
/// 创建批量订阅者
pub fn BatchWatcher::new(
  id : Int,
  callback : (BatchNotification) -> Unit,
  window_ms : Int,
  deduplicate : Bool,
) -> BatchWatcher {
  { id, callback, window_ms, deduplicate, }
}

///|
/// 创建批量聚合器
pub fn BatchAggregator::new(config : PipelineConfig) -> BatchAggregator {
  {
    watchers: Map([], capacity=10),
    watcher_buffers: Map([], capacity=10),
    watcher_window_starts: Map([], capacity=10),
    config,
    next_watcher_id: 1,
  }
}

///|
/// 批量订阅
///
/// 返回订阅者 ID。
pub fn BatchAggregator::subscribe_batch(
  self : BatchAggregator,
  callback : (BatchNotification) -> Unit,
  window_ms : Int?,
) -> Int {
  let id = self.next_watcher_id
  self.next_watcher_id = self.next_watcher_id + 1
  let window = match window_ms {
    Some(w) => w
    None => self.config.aggregate_window
  }
  let watcher = BatchWatcher::new(id, callback, window, self.config.deduplicate)
  self.watchers.set(id, watcher)
  self.watcher_buffers.set(id, [])
  id
}

///|
/// 取消批量订阅
pub fn BatchAggregator::unsubscribe_batch(
  self : BatchAggregator,
  id : Int,
) -> Unit {
  self.watchers.remove(id)
  self.watcher_buffers.remove(id)
  self.watcher_window_starts.remove(id)
}

///|
/// 通知事件
///
/// 接收存储引擎事件，加入聚合缓冲区。
pub fn BatchAggregator::notify(
  self : BatchAggregator,
  event : @realtime_db.Event,
) -> Unit {
  self.notify_at(event, 0)
}

///|
/// 通知事件（带逻辑时钟）
///
/// `current_time` 用于开启该订阅者的聚合窗口，配合 `flush_due` 实现定时刷新。
pub fn BatchAggregator::notify_at(
  self : BatchAggregator,
  event : @realtime_db.Event,
  current_time : Int,
) -> Unit {
  // 禁止聚合 Expire 事件：立即广播给所有订阅者
  match event {
    @realtime_db.Expire(_, _) => {
      for (_, watcher) in self.watchers {
        (watcher.callback)(
          BatchNotification::new([event], current_time, watcher.id),
        )
      }
      return
    }
    _ => ignore(event)
  }

  // 加入每个订阅者的缓冲区
  for (_, watcher) in self.watchers {
    let buffer = match self.watcher_buffers.get(watcher.id) {
      Some(buf) => buf
      None => []
    }

    // 去重：同一键的多次变更合并为"最后状态"（覆盖旧事件，而非丢弃新事件）
    if watcher.deduplicate {
      upsert_event(buffer, event)
    } else {
      buffer.push(event)
    }
    self.watcher_buffers.set(watcher.id, buffer)

    // 首个缓冲事件开启聚合窗口（start=0 表示尚未开窗）
    match self.watcher_window_starts.get(watcher.id) {
      Some(start) =>
        if start == 0 {
          self.watcher_window_starts.set(watcher.id, current_time)
        }
      None => self.watcher_window_starts.set(watcher.id, current_time)
    }
  }
}

///|
/// 提取事件的键
fn event_key(event : @realtime_db.Event) -> String {
  match event {
    @realtime_db.Set(key, _, _) => key
    @realtime_db.Delete(key, _) => key
    @realtime_db.Expire(key, _) => key
  }
}

///|
/// 同键事件覆盖为最后状态，新键则追加
fn upsert_event(
  buffer : Array[@realtime_db.Event],
  event : @realtime_db.Event,
) -> Unit {
  let key = event_key(event)
  let mut i = 0
  while i < buffer.length() {
    if event_key(buffer[i]) == key {
      buffer[i] = event
      return
    }
    i = i + 1
  }
  buffer.push(event)
}

///|
/// 强制刷新聚合窗口
pub fn BatchAggregator::flush(self : BatchAggregator, id : Int) -> Unit {
  self.internal_flush(id, get_current_time())
}

///|
/// 刷新所有聚合窗口已到期的订阅者
///
/// 窗口长度由各订阅者的 window_ms 决定。
pub fn BatchAggregator::flush_due(
  self : BatchAggregator,
  current_time : Int,
) -> Unit {
  let due : Array[Int] = []
  for (id, watcher) in self.watchers {
    match self.watcher_window_starts.get(id) {
      Some(start) =>
        if start > 0 && current_time - start >= watcher.window_ms {
          due.push(id)
        }
      None => ()
    }
  }
  for id in due {
    self.internal_flush(id, current_time)
  }
}

///|
/// 刷新单个订阅者的内部实现
///
/// 缓冲事件超过 max_batch_size 时只发送首批，剩余事件保留在缓冲区，绝不丢弃。
fn BatchAggregator::internal_flush(
  self : BatchAggregator,
  id : Int,
  timestamp : Int,
) -> Unit {
  match self.watchers.get(id) {
    Some(watcher) => {
      let buffer = match self.watcher_buffers.get(id) {
        Some(buf) => buf
        None => []
      }
      if buffer.is_empty() {
        return
      }
      if buffer.length() <= self.config.max_batch_size {
        (watcher.callback)(BatchNotification::new(buffer, timestamp, id))
        self.watcher_buffers.set(id, [])
        self.watcher_window_starts.set(id, 0)
      } else {
        let max = self.config.max_batch_size
        let chunk : Array[@realtime_db.Event] = []
        let remaining : Array[@realtime_db.Event] = []
        let mut i = 0
        while i < max {
          chunk.push(buffer[i])
          i = i + 1
        }
        while i < buffer.length() {
          remaining.push(buffer[i])
          i = i + 1
        }
        (watcher.callback)(BatchNotification::new(chunk, timestamp, id))
        // 剩余事件保留，窗口不重置，等待下次刷新
        self.watcher_buffers.set(id, remaining)
      }
    }
    None => ()
  }
}

