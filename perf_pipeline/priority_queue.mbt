// 优先级队列模块
//
// 实现优先级队列，支持 1~10 级优先级。

///|
/// 任务状态枚举
pub enum TaskStatus {
  /// 等待中
  Pending
  /// 执行中
  Running
  /// 已暂停
  Paused
  /// 已完成
  Completed
  /// 已失败
  Failed
}

///|
/// 优先级任务结构
pub struct PriorityTask {
  /// 任务 ID
  id : Int
  /// 任务数据
  data : @realtime_db.Value
  /// 优先级（1 最高，10 最低）
  priority : Int
  /// 提交时间
  submit_time : Int
  /// 任务状态
  status : TaskStatus
}

///|
/// 优先级队列结构
pub struct PriorityQueue {
  /// 任务列表
  mut tasks : Array[PriorityTask]
  /// 优先级索引
  mut priorities : Array[Int]
  /// 时间戳列表
  mut timestamps : Array[Int]
  /// 当前大小
  mut size : Int
  /// 最大大小
  max_size : Int
}

///|
/// 创建优先级任务
pub fn PriorityTask::new(
  id : Int,
  data : @realtime_db.Value,
  priority : Int,
  submit_time : Int
) -> PriorityTask {
  {
    id,
    data,
    priority,
    submit_time,
    status: Pending,
  }
}

///|
/// 获取任务状态
pub fn PriorityTask::status(self : PriorityTask) -> TaskStatus {
  self.status
}

///|
/// 设置任务状态
pub fn PriorityTask::set_status(self : PriorityTask, status : TaskStatus) -> Unit {
  self.status = status
}

///|
/// 获取优先级
pub fn PriorityTask::priority(self : PriorityTask) -> Int {
  self.priority
}

///|
/// 创建优先级队列
pub fn PriorityQueue::new(max_size : Int) -> PriorityQueue {
  {
    tasks: [],
    priorities: [],
    timestamps: [],
    size: 0,
    max_size,
  }
}

///|
/// 按优先级插入队列
///
// 1 为最高优先级，插入到对应位置。
pub fn PriorityQueue::push(self : PriorityQueue, task : PriorityTask) -> Unit {
  if self.size >= self.max_size {
    return
  }
  
  // 找到插入位置
  let mut index = 0
  while index < self.size {
    if self.priorities[index] > task.priority() {
      break
    }
    index = index + 1
  }
  
  // 插入到指定位置
  self.tasks.insert_at(index, task)
  self.priorities.insert_at(index, task.priority())
  self.timestamps.insert_at(index, task.submit_time)
  self.size = self.size + 1
}

///|
/// 取出最高优先级任务
pub fn PriorityQueue::pop(self : PriorityQueue) -> PriorityTask? {
  if self.size == 0 {
    return None
  }
  
  self.size = self.size - 1
  let task = self.tasks[0]
  self.tasks.remove_at(0)
  self.priorities.remove_at(0)
  self.timestamps.remove_at(0)
  Some(task)
}

///|
/// 查看下一个任务但不取出
pub fn PriorityQueue::peek(self : PriorityQueue) -> PriorityTask? {
  if self.size == 0 {
    return None
  }
  Some(self.tasks[0])
}

///|
/// 移除指定任务
pub fn PriorityQueue::remove(self : PriorityQueue, id : Int) -> Bool {
  var i = 0
  while i < self.size {
    if self.tasks[i].id == id {
      self.tasks.remove_at(i)
      self.priorities.remove_at(i)
      self.timestamps.remove_at(i)
      self.size = self.size - 1
      return true
    }
    i = i + 1
  }
  false
}

///|
/// 获取队列大小
pub fn PriorityQueue::size(self : PriorityQueue) -> Int {
  self.size
}

///|
/// 检查队列是否为空
pub fn PriorityQueue::is_empty(self : PriorityQueue) -> Bool {
  self.size == 0
}

///|
/// 检查队列是否已满
pub fn PriorityQueue::is_full(self : PriorityQueue) -> Bool {
  self.size >= self.max_size
}

///|
/// 清空队列
pub fn PriorityQueue::clear(self : PriorityQueue) -> Unit {
  self.tasks.clear()
  self.priorities.clear()
  self.timestamps.clear()
  self.size = 0
}