// 连接池模块
//
// 提供连接管理、复用和回收功能。

///|
/// 连接结构体
pub struct Connection {
  /// 连接 ID
  id : Int
  /// 连接地址
  addr : String
  /// 最后使用时间
  mut last_used : Int
  /// 是否健康
  mut healthy : Bool
}

///|
/// 连接池结构体
pub struct ConnectionPool {
  /// 连接列表
  connections : Array[Connection]
  /// 空闲连接队列（存连接 ID）
  idle_queue : Array[Int]
  /// 最大连接数
  max_connections : Int
  /// 当前连接数
  mut current_count : Int
  /// 下一个连接 ID（单调递增，销毁的连接 ID 不回收）
  mut next_id : Int
}

///|
/// 连接池错误类型
pub(all) enum PoolError {
  /// 连接池耗尽
  Pool_Exhausted
}

///|
/// 创建连接
pub fn Connection::new(id : Int, addr : String, last_used : Int) -> Connection {
  { id, addr, last_used, healthy: true, }
}

///|
/// 获取连接 ID
pub fn Connection::id(self : Connection) -> Int {
  self.id
}

///|
/// 获取连接地址
pub fn Connection::addr(self : Connection) -> String {
  self.addr
}

///|
/// 获取最后使用时间
pub fn Connection::last_used(self : Connection) -> Int {
  self.last_used
}

///|
/// 检查连接是否健康
pub fn Connection::is_healthy(self : Connection) -> Bool {
  self.healthy
}

///|
/// 标记连接不健康
pub fn Connection::mark_unhealthy(self : Connection) -> Unit {
  self.healthy = false
}

///|
/// 创建连接池
pub fn ConnectionPool::new(max_connections : Int) -> ConnectionPool {
  {
    connections: [],
    idle_queue: [],
    max_connections,
    current_count: 0,
    next_id: 0,
  }
}

///|
/// 获取连接
/// 优先复用空闲连接（跳过不健康连接），没有则创建新连接。
///
/// ## 返回
/// - Ok(Connection): 成功获取连接
/// - Err(PoolError): 连接池已满且无空闲连接
pub fn ConnectionPool::get(
  self : ConnectionPool,
  addr : String,
  current_time : Int,
) -> Result[Connection, PoolError] {
  // 不断从空闲队列队首取出，直到拿到健康连接
  while self.idle_queue.length() > 0 {
    let conn_id = self.idle_queue.remove(0)
    let idx = self.find_index(conn_id)
    guard idx >= 0 else { continue } // 理论上不会发生
    let conn = self.connections[idx]
    if !conn.is_healthy() {
      // 不健康连接直接销毁
      let _ = self.connections.remove(idx)
      self.current_count = self.current_count - 1
      continue
    }
    conn.last_used = current_time
    return Ok(conn)
  }
  // 没有空闲连接，尝试新建
  if self.current_count < self.max_connections {
    let conn = Connection::new(self.next_id, addr, current_time)
    self.next_id = self.next_id + 1
    self.connections.push(conn)
    self.current_count = self.current_count + 1
    Ok(conn)
  } else {
    Err(Pool_Exhausted)
  }
}

///|
/// 归还连接
/// 健康连接放回空闲队列；不健康连接直接销毁并释放池名额。
/// 已在空闲队列中的连接不会重复入队。
pub fn ConnectionPool::return_connection(
  self : ConnectionPool,
  conn : Connection,
  current_time : Int,
) -> Unit {
  let idx = self.find_index(conn.id())
  guard idx >= 0 else { return } // 不属于本池
  if !conn.is_healthy() {
    // 销毁坏连接并释放名额
    let _ = self.connections.remove(idx)
    self.current_count = self.current_count - 1
    self.remove_idle(conn.id())
    return
  }
  if self.find_idle(conn.id()) >= 0 {
    return // 已在空闲队列，防止重复归还
  }
  conn.last_used = current_time
  self.idle_queue.push(conn.id())
}

///|
/// 按 ID 标记连接不健康
pub fn ConnectionPool::mark_unhealthy(self : ConnectionPool, id : Int) -> Bool {
  let idx = self.find_index(id)
  guard idx >= 0 else { return false }
  self.connections[idx].mark_unhealthy()
  true
}

///|
/// 查找连接在数组中的下标，不存在返回 -1。
fn ConnectionPool::find_index(self : ConnectionPool, id : Int) -> Int {
  let mut i = 0
  while i < self.connections.length() {
    if self.connections[i].id() == id {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 查找连接在空闲队列中的下标，不存在返回 -1。
fn ConnectionPool::find_idle(self : ConnectionPool, id : Int) -> Int {
  let mut i = 0
  while i < self.idle_queue.length() {
    if self.idle_queue[i] == id {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 从空闲队列中移除指定连接 ID（若存在）。
fn ConnectionPool::remove_idle(self : ConnectionPool, id : Int) -> Unit {
  let i = self.find_idle(id)
  if i >= 0 {
    let _ = self.idle_queue.remove(i)
  }
}

///|
/// 获取连接数
pub fn ConnectionPool::current_count(self : ConnectionPool) -> Int {
  self.current_count
}

///|
/// 获取空闲连接数
pub fn ConnectionPool::idle_count(self : ConnectionPool) -> Int {
  self.idle_queue.length()
}

///|
/// 获取最大连接数
pub fn ConnectionPool::max_connections(self : ConnectionPool) -> Int {
  self.max_connections
}
