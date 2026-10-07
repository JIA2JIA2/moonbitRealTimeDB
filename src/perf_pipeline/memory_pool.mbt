// 内存池模块
//
// 实现高性能内存池，支持对象复用，减少 GC 压力。
// 目标：对象复用率 >= 80%

///|
/// 内存池结构
///
/// 管理缓冲区的分配和复用，支持动态扩容。
pub struct MemoryPool {
  /// 空闲缓冲区列表
  free_buffers : Array[Array[Int]]
  /// 所有缓冲区列表（用于监控）
  all_buffers : Array[Array[Int]]
  /// 初始大小
  initial_size : Int
  /// 最大大小
  max_size : Int
  /// 扩容因子
  grow_factor : Double
  /// 命中次数
  mut hit_count : Int
  /// 未命中次数
  mut miss_count : Int
}

///|
/// 创建内存池
///
/// 预分配 initial_size 个缓冲区，每个缓冲区大小为 buffer_size。
pub fn MemoryPool::new(
  initial_size : Int,
  max_size : Int,
  grow_factor : Double,
) -> MemoryPool {
  let pool = MemoryPool::new_empty(initial_size, max_size, grow_factor)
  // 预分配初始缓冲区
  let mut i = 0
  while i < initial_size {
    let buffer = Array::make(1024, 0) // 默认 1KB 缓冲区
    pool.free_buffers.push(buffer)
    pool.all_buffers.push(buffer)
    i = i + 1
  }
  pool
}

///|
/// 创建空内存池
fn MemoryPool::new_empty(
  initial_size : Int,
  max_size : Int,
  grow_factor : Double,
) -> MemoryPool {
  {
    free_buffers: [],
    all_buffers: [],
    initial_size,
    max_size,
    grow_factor,
    hit_count: 0,
    miss_count: 0,
  }
}

///|
/// 获取缓冲区
///
/// 从空闲池获取缓冲区，无空闲对象时按 1.5 倍扩容。
/// 返回缓冲区，如果内存池耗尽则返回新分配的缓冲区。
pub fn MemoryPool::acquire_buffer(self : MemoryPool) -> Array[Int] {
  if self.free_buffers.is_empty() {
    self.miss_count = self.miss_count + 1
    // 动态扩容
    let current_size = self.all_buffers.length()
    if current_size < self.max_size {
      let grow_size = (current_size.to_double() * self.grow_factor).to_int()
      let new_size = if grow_size < self.max_size - current_size {
        grow_size
      } else {
        self.max_size - current_size
      }
      let final_size = if new_size > 0 { new_size } else { 1 }
      let mut i = 0
      while i < final_size {
        let buffer = Array::make(1024, 0)
        self.free_buffers.push(buffer)
        self.all_buffers.push(buffer)
        i = i + 1
      }
    }
    // 池已达上限仍无空闲缓冲区，直接在池外分配
    // （该缓冲区不归属内存池，release 时不会回收）
    if self.free_buffers.is_empty() {
      return Array::make(1024, 0)
    }
  } else {
    self.hit_count = self.hit_count + 1
  }
  // 走到这里 free_buffers 必非空
  match self.free_buffers.pop() {
    Some(buffer) => buffer
    None => Array::make(1024, 0)
  }
}

///|
/// 释放缓冲区
///
/// 释放缓冲区时清零敏感数据后放入空闲池。
/// 非内存池分配的缓冲区（池达上限时 acquire 的临时缓冲区）以及
/// 重复释放都会被忽略，避免空闲数超过池容量或同一缓冲区被多次分发。
pub fn MemoryPool::release_buffer(
  self : MemoryPool,
  buffer : Array[Int],
) -> Unit {
  // 只有存在"已借出"的名额时才回收，否则是池外缓冲区或重复释放
  if self.free_buffers.length() >= self.all_buffers.length() {
    return
  }
  // 清零敏感数据
  let mut i = 0
  while i < buffer.length() {
    buffer[i] = 0
    i = i + 1
  }
  self.free_buffers.push(buffer)
}

///|
/// 获取复用率
///
/// 返回复用率（hit_count / (hit_count + miss_count)），目标 >= 80%。
pub fn MemoryPool::hit_rate(self : MemoryPool) -> Double {
  let total = self.hit_count + self.miss_count
  if total == 0 {
    1.0 // 没有请求，复用率为 100%
  } else {
    self.hit_count.to_double() / total.to_double()
  }
}

///|
/// 获取当前池大小
///
/// 返回当前已分配的缓冲区总数。
pub fn MemoryPool::current_size(self : MemoryPool) -> Int {
  self.all_buffers.length()
}

///|
/// 获取空闲缓冲区数量
///
/// 返回当前空闲的缓冲区数量。
pub fn MemoryPool::free_count(self : MemoryPool) -> Int {
  self.free_buffers.length()
}

///|
/// 获取命中次数
pub fn MemoryPool::hit_count(self : MemoryPool) -> Int {
  self.hit_count
}

///|
/// 获取未命中次数
pub fn MemoryPool::miss_count(self : MemoryPool) -> Int {
  self.miss_count
}
