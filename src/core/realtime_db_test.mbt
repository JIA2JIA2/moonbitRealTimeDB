// 黑盒测试：针对 @core 公共 API。

///|
test "set_get_contains_size_keys" {
  let db = @core.DB::new()
  assert_eq(db.size(), 0)
  db.set("a", @core.Str("1"))
  db.set("b", @core.Int(2))
  db.set("c", @core.Bool(true))
  assert_eq(db.get("a"), Some(@core.Str("1")))
  assert_eq(db.get("b"), Some(@core.Int(2)))
  assert_eq(db.get("missing"), None)
  assert_true(db.contains("a"))
  assert_false(db.contains("missing"))
  assert_eq(db.size(), 3)
  assert_eq(db.keys().length(), 3)
}

///|
test "delete" {
  let db = @core.DB::new()
  db.set("a", @core.Int(1))
  assert_eq(db.delete("a"), Some(@core.Int(1)))
  assert_eq(db.get("a"), None)
  assert_eq(db.size(), 0)
  assert_eq(db.delete("nope"), None)
}

///|
test "overwrite_preserves_old_in_event" {
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch("counter", fn(e) { events.push(e) })
  db.set("counter", @core.Int(1))
  db.set("counter", @core.Int(2))
  assert_eq(events.length(), 2)
  assert_true(events[0] is @core.Set("counter", @core.Int(1), None))
  assert_true(
    events[1] is @core.Set("counter", @core.Int(2), Some(@core.Int(1))),
  )
}

///|
test "watch_key_receives_delete" {
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch("k", fn(e) { events.push(e) })
  db.set("k", @core.Str("v"))
  let _ = db.delete("k")
  assert_eq(events.length(), 2)
  assert_true(events[1] is @core.Delete("k", @core.Str("v")))
}

///|
test "watch_key_ignores_other_keys" {
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch("a", fn(e) { events.push(e) })
  db.set("b", @core.Int(1))
  assert_eq(events.length(), 0)
  db.set("a", @core.Int(1))
  assert_eq(events.length(), 1)
}

///|
test "watch_all_receives_everything" {
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch_all(fn(e) { events.push(e) })
  db.set("a", @core.Int(1))
  db.set("b", @core.Str("x"))
  let _ = db.delete("a")
  assert_eq(events.length(), 3)
}

///|
test "unwatch_stops_notifications" {
  let db = @core.DB::new()
  let count : Array[Int] = [0]
  let id = db.watch("k", fn(_e) { count[0] = count[0] + 1 })
  db.set("k", @core.Int(1))
  assert_eq(count[0], 1)
  assert_true(db.unwatch(id))
  assert_false(db.unwatch(id))
  db.set("k", @core.Int(2))
  assert_eq(count[0], 1)
  assert_eq(db.watcher_count(), 0)
}

///|
test "unwatch_in_callback_is_safe" {
  let db = @core.DB::new()
  let id_b_box : Array[Int] = []
  let b_called : Array[Int] = [0]
  let _ = db.watch("k", fn(_e) {
    if id_b_box.length() > 0 {
      let _ = db.unwatch(id_b_box[0])
    }
  })
  let id_b = db.watch("k", fn(_e) { b_called[0] = b_called[0] + 1 })
  id_b_box.push(id_b)
  db.set("k", @core.Int(1))
  assert_eq(db.watcher_count(), 1)
  assert_eq(b_called[0], 0)
}

///|
test "float_and_array_values" {
  let db = @core.DB::new()
  db.set("f", @core.Float(3.14))
  db.set("arr", @core.Arr([@core.Int(1), @core.Str("x")]))
  assert_eq(db.get("f"), Some(@core.Float(3.14)))
  assert_eq(db.get("arr"), Some(@core.Arr([@core.Int(1), @core.Str("x")])))
}

///|
test "ttl_expire_via_advance" {
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch_all(fn(e) { events.push(e) })
  db.set("k", @core.Int(1), ttl=5) // clock=0, expires_at=5
  db.set("forever", @core.Int(2)) // 无 ttl
  assert_eq(events.length(), 2)
  let n = db.advance(5) // clock=5, k 过期 (5<=5)
  assert_eq(n, 1)
  assert_true(events[2] is @core.Expire("k", @core.Int(1)))
  assert_eq(db.get("k"), None)
  assert_eq(db.get("forever"), Some(@core.Int(2)))
}

///|
test "ttl_not_yet_expired" {
  let db = @core.DB::new()
  db.set("k", @core.Int(1), ttl=5)
  let _ = db.advance(3) // clock=3, 未过期
  assert_eq(db.get("k"), Some(@core.Int(1)))
  assert_true(db.contains("k"))
}

///|
test "set_overwrites_expired_key_with_old_none" {
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch("k", fn(e) { events.push(e) })
  db.set("k", @core.Int(1), ttl=2)
  let _ = db.advance(2) // k 过期
  db.set("k", @core.Int(2)) // k 已被清理，old=None
  assert_true(events[2] is @core.Set("k", @core.Int(2), None))
}

///|
test "expire_now_manual" {
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch_all(fn(e) { events.push(e) })
  db.set("a", @core.Int(1), ttl=2)
  db.set("b", @core.Int(2), ttl=5)
  let _ = db.advance(3) // clock=3, a 过期, b 未过期
  assert_eq(events.length(), 3) // Set a, Set b, Expire a
  assert_true(events[2] is @core.Expire("a", @core.Int(1)))
  assert_eq(db.get("b"), Some(@core.Int(2)))
}

///|
test "mset_mget_mdelete" {
  let db = @core.DB::new()
  db.mset([("a", @core.Int(1)), ("b", @core.Str("x"))])
  assert_eq(db.mget(["a", "b", "c"]), [
    Some(@core.Int(1)),
    Some(@core.Str("x")),
    None,
  ])
  let deleted = db.mdelete(["a", "c"])
  assert_eq(deleted, [Some(@core.Int(1)), None])
  assert_eq(db.get("a"), None)
  assert_eq(db.get("b"), Some(@core.Str("x")))
}

///|
test "mset_with_ttl" {
  let db = @core.DB::new()
  db.mset([("a", @core.Int(1)), ("b", @core.Int(2))], ttl=3)
  let _ = db.advance(3)
  assert_eq(db.get("a"), None)
  assert_eq(db.get("b"), None)
}

///|
test "watch_prefix" {
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch_prefix("user:", fn(e) { events.push(e) })
  db.set("user:1", @core.Int(1)) // 匹配
  db.set("post:1", @core.Int(2)) // 不匹配
  db.set("user:2", @core.Int(3)) // 匹配
  assert_eq(events.length(), 2)
  assert_true(events[0] is @core.Set("user:1", @core.Int(1), None))
  assert_true(events[1] is @core.Set("user:2", @core.Int(3), None))
}

///|
test "unwatch_prefix_and_global" {
  let db = @core.DB::new()
  let count : Array[Int] = [0]
  let wp = db.watch_prefix("u:", fn(_e) { count[0] = count[0] + 1 })
  let wg = db.watch_all(fn(_e) { count[0] = count[0] + 1 })
  db.set("u:1", @core.Int(1))
  assert_eq(count[0], 2) // prefix + global
  assert_true(db.unwatch(wp))
  db.set("u:2", @core.Int(1))
  assert_eq(count[0], 3) // 只剩 global
  assert_true(db.unwatch(wg))
  db.set("u:3", @core.Int(1))
  assert_eq(count[0], 3) // 都取消了
}

///|
test "value_and_event_to_string" {
  assert_eq(@core.Str("hi").to_string(), "hi")
  assert_eq(@core.Int(42).to_string(), "42")
  assert_eq(@core.Bool(true).to_string(), "true")
  assert_eq(@core.Null.to_string(), "null")
  assert_eq(
    @core.Arr([@core.Int(1), @core.Str("x"), @core.Null]).to_string(),
    "[1, x, null]",
  )
  let db = @core.DB::new()
  let events : Array[String] = []
  let _ = db.watch("k", fn(e) { events.push(e.to_string()) })
  db.set("k", @core.Int(1))
  db.set("k", @core.Int(2))
  let _ = db.delete("k")
  assert_eq(events[0], "SET k = 1 (new)")
  assert_eq(events[1], "SET k = 2 (was 1)")
  assert_eq(events[2], "DELETE k (was 2)")
}

///|
test "expire_event_to_string" {
  let db = @core.DB::new()
  let events : Array[String] = []
  let _ = db.watch_all(fn(e) { events.push(e.to_string()) })
  db.set("k", @core.Int(1), ttl=2)
  let _ = db.advance(2)
  assert_eq(events[0], "SET k = 1 (new)")
  assert_eq(events[1], "EXPIRE k (was 1)")
}

///|
test "clock_tracks_time" {
  let db = @core.DB::new()
  assert_eq(db.clock(), 0)
  let _ = db.advance(5)
  assert_eq(db.clock(), 5)
  let _ = db.advance(3)
  assert_eq(db.clock(), 8)
}

///|
test "lazy_expire_on_get" {
  // 过期未清理的键，get 时自动触发 Expire 事件并返回 None。
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch_all(fn(e) { events.push(e) })
  db.set("k", @core.Int(1), ttl=2) // clock=0, expires_at=2
  let _ = db.advance(2) // clock=2, 触发 Expire
  assert_eq(events.length(), 2) // Set + Expire
  assert_true(events[1] is @core.Expire("k", @core.Int(1)))
  assert_eq(db.get("k"), None)
}

///|
test "lazy_expire_on_contains_and_delete" {
  // 过期后 delete 应该触发 Expire 而非 Delete。
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch_all(fn(e) { events.push(e) })
  db.set("k", @core.Int(1), ttl=2)
  let _ = db.advance(2)
  assert_false(db.contains("k")) // 触发 Expire 事件
  assert_eq(events.length(), 2) // Set + Expire
  // 键已被清理，delete 返回 None
  assert_eq(db.delete("k"), None)
  assert_eq(events.length(), 2) // 没有 Delete 事件
}

///|
test "values_and_entries" {
  let db = @core.DB::new()
  db.set("a", @core.Int(1))
  db.set("b", @core.Str("x"))
  assert_true(db.values().length() >= 2)
  assert_true(db.entries().length() >= 2)
}

///|
test "incr_decr" {
  let db = @core.DB::new()
  // 不存在的键初始化为 delta
  assert_true(db.incr("counter"))
  assert_eq(db.get("counter"), Some(@core.Int(1)))
  assert_true(db.incr("counter"))
  assert_eq(db.get("counter"), Some(@core.Int(2)))
  assert_true(db.incr("counter", delta=5))
  assert_eq(db.get("counter"), Some(@core.Int(7)))
  assert_true(db.decr("counter"))
  assert_eq(db.get("counter"), Some(@core.Int(6)))
  assert_true(db.decr("counter", delta=3))
  assert_eq(db.get("counter"), Some(@core.Int(3)))
}

///|
test "incr_decr_on_non_int_fails" {
  let db = @core.DB::new()
  db.set("s", @core.Str("hello"))
  assert_false(db.incr("s"))
  assert_false(db.decr("s"))
  assert_eq(db.get("s"), Some(@core.Str("hello"))) // 未被修改
}

///|
test "touch_resets_ttl" {
  let db = @core.DB::new()
  db.set("k", @core.Int(1), ttl=2) // clock=0, expires_at=2
  assert_true(db.touch("k", 10)) // expires_at=10
  let _ = db.advance(5) // clock=5, 未过期
  assert_eq(db.get("k"), Some(@core.Int(1)))
  // 不存在的键 touch 返回 false
  assert_false(db.touch("no_such_key", 1))
}

///|
test "persist_removes_ttl" {
  let db = @core.DB::new()
  db.set("k", @core.Int(1), ttl=2)
  assert_true(db.persist("k")) // 永不清理
  let _ = db.advance(100) // 远超过原 TTL
  assert_eq(db.get("k"), Some(@core.Int(1)))
}

///|
test "clear_deletes_all" {
  let db = @core.DB::new()
  let events : Array[@core.Event] = []
  let _ = db.watch_all(fn(e) { events.push(e) })
  db.set("a", @core.Int(1))
  db.set("b", @core.Int(2))
  db.clear()
  assert_eq(db.size(), 0)
  assert_false(db.contains("a"))
  assert_false(db.contains("b"))
  // 2 Set + 2 Delete = 4 事件
  assert_eq(events.length(), 4)
}

///|
test "size_and_keys_skip_expired" {
  // size/keys 在返回前会清理过期键，保证与 get/contains 一致。
  let db = @core.DB::new()
  db.set("a", @core.Int(1), ttl=2)
  db.set("b", @core.Int(2)) // 永不过期
  let _ = db.advance(2)
  // get/contains 触发了 a 的 Expire
  assert_false(db.contains("a"))
  // size 不应包括已过期的 a
  assert_eq(db.size(), 1)
  assert_eq(db.keys(), ["b"])
}

///|
test "setnx" {
  let db = @core.DB::new()
  // 不存在的键可以设置
  assert_true(db.setnx("k", @core.Int(1)))
  assert_eq(db.get("k"), Some(@core.Int(1)))
  // 存在的键不能覆盖
  assert_false(db.setnx("k", @core.Int(99)))
  assert_eq(db.get("k"), Some(@core.Int(1)))
  // setnx 也支持 ttl
  assert_true(db.setnx("ttl_key", @core.Int(1), ttl=2))
  let _ = db.advance(2)
  assert_false(db.contains("ttl_key"))
  // 过期后可以再次 setnx
  assert_true(db.setnx("ttl_key", @core.Int(2)))
  assert_eq(db.get("ttl_key"), Some(@core.Int(2)))
}

///|
test "value_map_basic" {
  let db = @core.DB::new()
  let m = Map([("name", @core.Str("alice")), ("age", @core.Int(30))])
  db.set("user", @core.Map(m))
  assert_eq(db.get("user"), Some(@core.Map(m)))
}

///|
test "value_map_to_string" {
  let m = Map([("a", @core.Int(1)), ("b", @core.Str("x"))])
  let s = @core.Map(m).to_string()
  // Map 迭代顺序不确定，检查包含所有元素
  assert_true(s.contains("a"))
  assert_true(s.contains("1"))
  assert_true(s.contains("b"))
  assert_true(s.contains("x"))
}

///|
test "value_map_nested_in_arr" {
  let inner = Map([("k", @core.Int(42))])
  let arr = [@core.Int(1), @core.Map(inner)]
  assert_eq(@core.Arr(arr).to_string(), "[1, {k=42}]")
}

///|
test "value_empty_map" {
  let m : Map[String, @core.Value] = Map([])
  assert_eq(@core.Map(m).to_string(), "{}")
}
