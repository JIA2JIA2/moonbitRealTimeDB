// 窗口引擎模块
//
// 实现窗口分配、触发、状态管理
// 支持滚动窗口、滑动窗口、会话窗口

///|
/// 窗口分配器接口
pub trait WindowAssigner {
  /// 分配窗口
  fn assign_windows(self : Self, timestamp : Int, window_config : WindowConfig) -> Array[
    WindowId,
  ]

  /// 获取窗口触发时间
  fn get_window_trigger_time(self : Self, window_id : WindowId) -> Int

  /// 判断是否是迟到数据
  fn is_late(self : Self, timestamp : Int, watermark : Int) -> Bool
}

///|
/// 滚动窗口分配器
pub(all) struct TumblingWindowAssigner {
  /// 窗口大小（毫秒）
  window_size : Int
}

///|
/// 创建滚动窗口分配器
pub fn TumblingWindowAssigner::new(window_size : Int) -> TumblingWindowAssigner {
  { window_size, }
}

///|
pub impl WindowAssigner for TumblingWindowAssigner with fn assign_windows(
  self : TumblingWindowAssigner,
  timestamp : Int,
  window_config : WindowConfig,
) -> Array[WindowId] {
  let _ = self
  let window_size = window_config.size_ms
  if window_size <= 0 || window_size > 86400000 {
    return []
  }

  // 滚动窗口：window_start = timestamp - (timestamp % window_size)
  let window_start = timestamp - timestamp % window_size
  let window_id = WindowId::{
    pipeline_name: "",
    window_name: "tumbling",
    start_time: window_start,
  }
  [window_id]
}

///|
pub impl WindowAssigner for TumblingWindowAssigner with fn get_window_trigger_time(
  self : TumblingWindowAssigner,
  window_id : WindowId,
) -> Int {
  window_id.start_time + self.window_size
}

///|
pub impl WindowAssigner for TumblingWindowAssigner with fn is_late(
  self : TumblingWindowAssigner,
  timestamp : Int,
  watermark : Int,
) -> Bool {
  let _ = self
  timestamp <= watermark
}

///|
pub extend TumblingWindowAssigner with WindowAssigner::{
  assign_windows,
  get_window_trigger_time,
  is_late,
}

///|
/// 滑动窗口分配器
pub(all) struct SlidingWindowAssigner {
  /// 窗口大小（毫秒）
  window_size : Int
  /// 滑动步长（毫秒）
  slide_size : Int
}

///|
/// 创建滑动窗口分配器
pub fn SlidingWindowAssigner::new(
  window_size : Int,
  slide_size : Int,
) -> SlidingWindowAssigner {
  { window_size, slide_size, }
}

///|
pub impl WindowAssigner for SlidingWindowAssigner with fn assign_windows(
  self : SlidingWindowAssigner,
  timestamp : Int,
  window_config : WindowConfig,
) -> Array[WindowId] {
  let _ = self
  let window_size = window_config.size_ms
  let slide_size = window_config.slide_ms

  if window_size <= 0 || slide_size <= 0 || slide_size > window_size {
    return []
  }

  // 滑动窗口：从 latest_start 向下遍历到 window_size 范围
  let latest_start = timestamp - timestamp % slide_size
  let result : Array[WindowId] = []

  let mut window_start = latest_start
  while window_start > timestamp - window_size {
    let window_id = WindowId::{
      pipeline_name: "",
      window_name: "sliding",
      start_time: window_start,
    }
    result.push(window_id)
    window_start = window_start - slide_size
  }

  result
}

///|
pub impl WindowAssigner for SlidingWindowAssigner with fn get_window_trigger_time(
  self : SlidingWindowAssigner,
  window_id : WindowId,
) -> Int {
  window_id.start_time + self.window_size
}

///|
pub impl WindowAssigner for SlidingWindowAssigner with fn is_late(
  self : SlidingWindowAssigner,
  timestamp : Int,
  watermark : Int,
) -> Bool {
  let _ = self
  timestamp <= watermark
}

///|
pub extend SlidingWindowAssigner with WindowAssigner::{
  assign_windows,
  get_window_trigger_time,
  is_late,
}

///|
/// 会话窗口分配器
pub(all) struct SessionWindowAssigner {
  /// 会话超时时间（毫秒）
  timeout : Int
  /// 活跃会话映射
  mut active_sessions : Map[String, WindowId]
}

///|
/// 创建会话窗口分配器
pub fn SessionWindowAssigner::new(timeout : Int) -> SessionWindowAssigner {
  { timeout, active_sessions: Map([]), }
}

///|
pub impl WindowAssigner for SessionWindowAssigner with fn assign_windows(
  self : SessionWindowAssigner,
  timestamp : Int,
  window_config : WindowConfig,
) -> Array[WindowId] {
  let _ = self
  let timeout = window_config.timeout_ms
  if timeout <= 0 {
    return []
  }

  // 会话窗口：按活跃度划分
  // 简化实现：使用时间戳作为会话标识
  let session_id = WindowId::{
    pipeline_name: "",
    window_name: "session",
    start_time: timestamp - timestamp % timeout,
  }
  [session_id]
}

///|
pub impl WindowAssigner for SessionWindowAssigner with fn get_window_trigger_time(
  self : SessionWindowAssigner,
  window_id : WindowId,
) -> Int {
  window_id.start_time + self.timeout
}

///|
pub impl WindowAssigner for SessionWindowAssigner with fn is_late(
  self : SessionWindowAssigner,
  timestamp : Int,
  watermark : Int,
) -> Bool {
  let _ = self
  timestamp <= watermark
}

///|
pub extend SessionWindowAssigner with WindowAssigner::{
  assign_windows,
  get_window_trigger_time,
  is_late,
}

///|
/// 窗口触发器类型枚举
pub(all) enum WindowTrigger {
  /// 水位线触发
  WatermarkTrigger
  /// 计数触发
  CountTrigger(Int)
  /// 时间触发
  TimeTrigger(Int)
} derive(Eq)

///|
/// 窗口触发器接口
pub trait Trigger {
  /// 判断是否触发
  fn is_triggered(
    self : Self,
    window_state : WindowState,
    trigger : WindowTrigger,
  ) -> Bool

  /// 获取触发时间
  fn get_trigger_time(self : Self, trigger : WindowTrigger) -> Int
}

///|
/// 默认触发器实现
pub(all) struct DefaultTrigger {}

///|
pub impl Trigger for DefaultTrigger with fn is_triggered(
  self : DefaultTrigger,
  window_state : WindowState,
  trigger : WindowTrigger,
) -> Bool {
  let _ = self
  match trigger {
    WatermarkTrigger =>
      // 水位线触发：窗口结束时间 <= 水位线
      window_state.status == Open && window_state.end_time > 0
    CountTrigger(count) =>
      // 计数触发：元素数量 >= 阈值
      window_state.elements >= count
    TimeTrigger(time) =>
      // 时间触发：当前时间 >= 触发时间
      window_state.end_time > 0 && window_state.end_time <= time
  }
}

///|
pub impl Trigger for DefaultTrigger with fn get_trigger_time(
  self : DefaultTrigger,
  trigger : WindowTrigger,
) -> Int {
  let _ = self
  match trigger {
    WatermarkTrigger => 0
    CountTrigger(_) => 0
    TimeTrigger(time) => time
  }
}

///|
pub extend DefaultTrigger with Trigger::{is_triggered, get_trigger_time}

///|
/// 迟到数据处理策略
pub(all) struct LateDataHandler {
  /// 策略
  policy : LateDataPolicy
  /// 侧输出流
  mut side_output : Array[StreamEvent]
}

///|
/// 创建迟到数据处理器
pub fn LateDataHandler::new(policy : LateDataPolicy) -> LateDataHandler {
  { policy, side_output: [], }
}

///|
/// 处理迟到数据
pub fn LateDataHandler::handle_late_data(
  self : LateDataHandler,
  event : StreamEvent,
  watermark : Int,
  window_state : WindowState,
) -> Bool {
  let _ = window_state
  if event.timestamp > watermark {
    return false
  }

  match self.policy {
    Drop =>
      // 直接丢弃
      true
    SideOutput => {
      // 重定向到侧输出流
      self.side_output.push(event)
      true
    }
    Merge =>
      // 合并到已输出窗口
      // 简化实现：返回 true 表示已处理
      true
  }
}

///|
/// 获取侧输出流
pub fn LateDataHandler::get_side_output(
  self : LateDataHandler,
) -> Array[StreamEvent] {
  self.side_output
}

///|
/// 窗口状态管理器
pub(all) struct WindowStateManager {
  /// 窗口状态映射
  mut window_states : Map[WindowId, WindowState]
  /// 状态 TTL（毫秒）
  state_ttl : Int
}

///|
/// 创建窗口状态管理器
pub fn WindowStateManager::new(state_ttl : Int) -> WindowStateManager {
  { window_states: Map([]), state_ttl, }
}

///|
/// 创建窗口状态
pub fn WindowStateManager::create_window_state(
  self : WindowStateManager,
  window_id : WindowId,
  start_time : Int,
  end_time : Int,
) -> Result[WindowState, StreamError] {
  if self.window_states.contains(window_id) {
    return Err(Window_Already_Exists)
  }

  let state = WindowState::{
    window_id,
    status: Open,
    start_time,
    end_time,
    elements: 0,
    aggregate_state: None,
  }

  self.window_states.set(window_id, state)
  Ok(state)
}

///|
/// 获取窗口状态
pub fn WindowStateManager::get_window_state(
  self : WindowStateManager,
  window_id : WindowId,
) -> WindowState? {
  self.window_states.get(window_id)
}

///|
/// 更新窗口状态
pub fn WindowStateManager::update_window_state(
  self : WindowStateManager,
  window_id : WindowId,
  status : WindowStatus,
) -> Result[Unit, StreamError] {
  match self.window_states.get(window_id) {
    Some(state) => {
      state.status = status
      Ok(())
    }
    None => Err(Window_Not_Found)
  }
}

///|
/// 添加元素到窗口
pub fn WindowStateManager::add_element(
  self : WindowStateManager,
  window_id : WindowId,
) -> Result[Unit, StreamError] {
  match self.window_states.get(window_id) {
    Some(state) => {
      state.elements = state.elements + 1
      Ok(())
    }
    None => Err(Window_Not_Found)
  }
}

///|
/// 清理过期窗口状态
pub fn WindowStateManager::cleanup_expired(
  self : WindowStateManager,
  current_time : Int,
) -> Int {
  let expired : Array[WindowId] = []
  for (window_id, state) in self.window_states {
    if state.status == Closed && current_time - state.end_time > self.state_ttl {
      expired.push(window_id)
    }
  }

  for window_id in expired {
    self.window_states.remove(window_id)
  }

  expired.length()
}

///|
/// 获取所有窗口状态
pub fn WindowStateManager::get_all_window_states(
  self : WindowStateManager,
) -> Array[(WindowId, WindowState)] {
  let result : Array[(WindowId, WindowState)] = []
  for (window_id, state) in self.window_states {
    result.push((window_id, state))
  }
  result
}

///|
/// 创建窗口分配器
pub fn create_window_assigner(
  window_type : WindowType,
  config : WindowConfig,
) -> &WindowAssigner? {
  match window_type {
    Tumbling =>
      Some(TumblingWindowAssigner::new(config.size_ms) as &WindowAssigner)
    Sliding =>
      Some(
        SlidingWindowAssigner::new(config.size_ms, config.slide_ms)
        as &WindowAssigner,
      )
    Session =>
      Some(SessionWindowAssigner::new(config.timeout_ms) as &WindowAssigner)
  }
}

///|
pub extend WindowTrigger with Eq::{equal, not_equal}
