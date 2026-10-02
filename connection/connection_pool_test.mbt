// 连接池模块黑盒测试。

///|
test "pool_create_and_reach_limit" {
  let pool = @realtime_db.ConnectionPool::new(2)
  assert_eq(pool.current_count(), 0)
  assert_eq(pool.idle_count(), 0)
  assert_eq(pool.max_connections(), 2)

  let c1 = match pool.get("a", 0) {
    Ok(c) => c
    Err(_) => abort("c1")
  }
  let c2 = match pool.get("b", 0) {
    Ok(c) => c
    Err(_) => abort("c2")
  }
  assert_eq(pool.current_count(), 2)
  // 池满且无空闲连接
  assert_true(pool.get("c", 0) is Err(@realtime_db.Pool_Exhausted))

  // 连接访问器
  assert_eq(c1.addr(), "a")
  assert_true(c1.is_healthy())
  assert_eq(c2.last_used(), 0)
}

///|
test "pool_reuse_idle_connection" {
  let pool = @realtime_db.ConnectionPool::new(3)
  let c1 = match pool.get("a", 0) {
    Ok(c) => c
    Err(_) => abort("c1")
  }
  pool.return_connection(c1, 5)
  assert_eq(pool.idle_count(), 1)

  // 再次获取应复用同一个连接，且 last_used 被刷新
  let c1b = match pool.get("a", 9) {
    Ok(c) => c
    Err(_) => abort("c1b")
  }
  assert_eq(c1b.id(), c1.id())
  assert_eq(c1b.last_used(), 9)
  assert_eq(pool.idle_count(), 0)
  assert_eq(pool.current_count(), 1) // 复用，不新建
}

///|
test "pool_double_return_is_ignored" {
  let pool = @realtime_db.ConnectionPool::new(3)
  let c1 = match pool.get("a", 0) {
    Ok(c) => c
    Err(_) => abort("c1")
  }
  pool.return_connection(c1, 1)
  pool.return_connection(c1, 2) // 重复归还不重复入队
  assert_eq(pool.idle_count(), 1)
}

///|
test "pool_destroys_unhealthy_on_return" {
  let pool = @realtime_db.ConnectionPool::new(2)
  let c1 = match pool.get("a", 0) {
    Ok(c) => c
    Err(_) => abort("c1")
  }
  let _ = match pool.get("b", 0) {
    Ok(c) => c
    Err(_) => abort("c2")
  }
  assert_eq(pool.current_count(), 2)
  // c1 不健康，归还时被销毁并释放名额
  assert_true(pool.mark_unhealthy(c1.id()))
  pool.return_connection(c1, 1)
  assert_eq(pool.idle_count(), 0)
  assert_eq(pool.current_count(), 1)
  // 名额已释放：新建成功
  let c3 = match pool.get("d", 3) {
    Ok(c) => c
    Err(_) => abort("c3")
  }
  assert_eq(c3.id(), 2)
  assert_eq(pool.current_count(), 2)
  // 不存在的 id 无法标记
  assert_false(pool.mark_unhealthy(999))
}

///|
test "pool_unhealthy_idle_is_skipped" {
  // 空闲中的坏连接在 get 时被跳过并销毁
  let pool = @realtime_db.ConnectionPool::new(1)
  let c1 = match pool.get("a", 0) {
    Ok(c) => c
    Err(_) => abort("c1")
  }
  // 直接操作：先归还（健康，入队），再标记坏
  pool.return_connection(c1, 1)
  assert_true(pool.mark_unhealthy(c1.id()))
  // get 时销毁坏连接并新建
  let c2 = match pool.get("a", 2) {
    Ok(c) => c
    Err(_) => abort("c2")
  }
  assert_true(c2.is_healthy())
  assert_eq(pool.current_count(), 1)
  assert_eq(pool.idle_count(), 0)
}
