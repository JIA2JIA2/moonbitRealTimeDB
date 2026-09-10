// 黑盒测试：针对 @realtime_db 公共 API。

///|
test "set_get_contains_size_keys" {
  let db = @realtime_db.DB::new()
  assert_eq(db.size(), 0)
  db.set("a", @realtime_db.Str("1"))
  db.set("b", @realtime_db.Int(2))
  db.set("c", @realtime_db.Bool(true))
  assert_eq(db.get("a"), Some(@realtime_db.Str("1")))
  assert_eq(db.get("b"), Some(@realtime_db.Int(2)))
  assert_eq(db.get("missing"), None)
  assert_true(db.contains("a"))
  assert_false(db.contains("missing"))
  assert_eq(db.size(), 3)
  assert_eq(db.keys().length(), 3)
}

///|
test "delete" {
  let db = @realtime_db.DB::new()
  db.set("a", @realtime_db.Int(1))
  assert_eq(db.delete("a"), Some(@realtime_db.Int(1)))
  assert_eq(db.get("a"), None)
  assert_eq(db.size(), 0)
  assert_eq(db.delete("nope"), None)
}

///|
test "overwrite_preserves_old_in_event" {
  let db = @realtime_db.DB::new()
  let events : Array[@realtime_db.Event] = []
  let _ = db.watch("counter", fn(e) { events.push(e) })
  db.set("counter", @realtime_db.Int(1))
  db.set("counter", @realtime_db.Int(2))
  assert_eq(events.length(), 2)
  assert_true(
    events[0] is @realtime_db.Set("counter", @realtime_db.Int(1), None),
  )
  assert_true(
    events[1]
    is @realtime_db.Set(
      "counter",
      @realtime_db.Int(2),
      Some(@realtime_db.Int(1))
    ),
  )
}

///|
test "watch_key_receives_delete" {
  let db = @realtime_db.DB::new()
  let events : Array[@realtime_db.Event] = []
  let _ = db.watch("k", fn(e) { events.push(e) })
  db.set("k", @realtime_db.Str("v"))
  let _ = db.delete("k")
  assert_eq(events.length(), 2)
  assert_true(events[1] is @realtime_db.Delete("k", @realtime_db.Str("v")))
}

///|
test "watch_key_ignores_other_keys" {
  let db = @realtime_db.DB::new()
  let events : Array[@realtime_db.Event] = []
  let _ = db.watch("a", fn(e) { events.push(e) })
  db.set("b", @realtime_db.Int(1))
  assert_eq(events.length(), 0)
  db.set("a", @realtime_db.Int(1))
  assert_eq(events.length(), 1)
}

///|
test "watch_all_receives_everything" {
  let db = @realtime_db.DB::new()
  let events : Array[@realtime_db.Event] = []
  let _ = db.watch_all(fn(e) { events.push(e) })
  db.set("a", @realtime_db.Int(1))
  db.set("b", @realtime_db.Str("x"))
  let _ = db.delete("a")
  assert_eq(events.length(), 3)
}

///|
test "unwatch_stops_notifications" {
  let db = @realtime_db.DB::new()
  let count : Array[Int] = [0]
  let id = db.watch("k", fn(_e) { count[0] = count[0] + 1 })
  db.set("k", @realtime_db.Int(1))
  assert_eq(count[0], 1)
  assert_true(db.unwatch(id))
  assert_false(db.unwatch(id))
  db.set("k", @realtime_db.Int(2))
  assert_eq(count[0], 1)
  assert_eq(db.watcher_count(), 0)
}

///|
test "unwatch_in_callback_is_safe" {
  let db = @realtime_db.DB::new()
  let id_b_box : Array[Int] = []
  let b_called : Array[Int] = [0]
  let _ = db.watch("k", fn(_e) {
    if id_b_box.length() > 0 {
      let _ = db.unwatch(id_b_box[0])
    }
  })
  let id_b = db.watch("k", fn(_e) { b_called[0] = b_called[0] + 1 })
  id_b_box.push(id_b)
  db.set("k", @realtime_db.Int(1))
  assert_eq(db.watcher_count(), 1)
  assert_eq(b_called[0], 0)
}

///|
test "float_and_array_values" {
  let db = @realtime_db.DB::new()
  db.set("f", @realtime_db.Float(3.14))
  db.set("arr", @realtime_db.Arr([@realtime_db.Int(1), @realtime_db.Str("x")]))
  assert_eq(db.get("f"), Some(@realtime_db.Float(3.14)))
  assert_eq(
    db.get("arr"),
    Some(@realtime_db.Arr([@realtime_db.Int(1), @realtime_db.Str("x")])),
  )
}

///|
test "ttl_expire_via_advance" {
  let db = @realtime_db.DB::new()
  let events : Array[@realtime_db.Event] = []
  let _ = db.watch_all(fn(e) { events.push(e) })
  db.set("k", @realtime_db.Int(1), ttl=5) // clock=0, expires_at=5
  db.set("forever", @realtime_db.Int(2)) // 无 ttl
  assert_eq(events.length(), 2)
  let n = db.advance(5) // clock=5, k 过期 (5<=5)
  assert_eq(n, 1)
  assert_true(events[2] is @realtime_db.Expire("k", @realtime_db.Int(1)))
  assert_eq(db.get("k"), None)
  assert_eq(db.get("forever"), Some(@realtime_db.Int(2)))
}

///|
test "ttl_not_yet_expired" {
  let db = @realtime_db.DB::new()
  db.set("k", @realtime_db.Int(1), ttl=5)
  let _ = db.advance(3) // clock=3, 未过期
  assert_eq(db.get("k"), Some(@realtime_db.Int(1)))
  assert_true(db.contains("k"))
}

///|
test "set_overwrites_expired_key_with_old_none" {
  let db = @realtime_db.DB::new()
  let events : Array[@realtime_db.Event] = []
  let _ = db.watch("k", fn(e) { events.push(e) })
  db.set("k", @realtime_db.Int(1), ttl=2)
  let _ = db.advance(2) // k 过期
  db.set("k", @realtime_db.Int(2)) // k 已被清理，old=None
  assert_true(events[2] is @realtime_db.Set("k", @realtime_db.Int(2), None))
}

///|
test "expire_now_manual" {
  let db = @realtime_db.DB::new()
  let events : Array[@realtime_db.Event] = []
  let _ = db.watch_all(fn(e) { events.push(e) })
  db.set("a", @realtime_db.Int(1), ttl=2)
  db.set("b", @realtime_db.Int(2), ttl=5)
  let _ = db.advance(3) // clock=3, a 过期, b 未过期
  assert_eq(events.length(), 3) // Set a, Set b, Expire a
  assert_true(events[2] is @realtime_db.Expire("a", @realtime_db.Int(1)))
  assert_eq(db.get("b"), Some(@realtime_db.Int(2)))
}

///|
test "mset_mget_mdelete" {
  let db = @realtime_db.DB::new()
  db.mset([("a", @realtime_db.Int(1)), ("b", @realtime_db.Str("x"))])
  assert_eq(db.mget(["a", "b", "c"]), [
    Some(@realtime_db.Int(1)),
    Some(@realtime_db.Str("x")),
    None,
  ])
  let deleted = db.mdelete(["a", "c"])
  assert_eq(deleted, [Some(@realtime_db.Int(1)), None])
  assert_eq(db.get("a"), None)
  assert_eq(db.get("b"), Some(@realtime_db.Str("x")))
}

///|
test "mset_with_ttl" {
  let db = @realtime_db.DB::new()
  db.mset([("a", @realtime_db.Int(1)), ("b", @realtime_db.Int(2))], ttl=3)
  let _ = db.advance(3)
  assert_eq(db.get("a"), None)
  assert_eq(db.get("b"), None)
}

///|
test "watch_prefix" {
  let db = @realtime_db.DB::new()
  let events : Array[@realtime_db.Event] = []
  let _ = db.watch_prefix("user:", fn(e) { events.push(e) })
  db.set("user:1", @realtime_db.Int(1)) // 匹配
  db.set("post:1", @realtime_db.Int(2)) // 不匹配
  db.set("user:2", @realtime_db.Int(3)) // 匹配
  assert_eq(events.length(), 2)
  assert_true(
    events[0] is @realtime_db.Set("user:1", @realtime_db.Int(1), None),
  )
  assert_true(
    events[1] is @realtime_db.Set("user:2", @realtime_db.Int(3), None),
  )
}

///|
test "unwatch_prefix_and_global" {
  let db = @realtime_db.DB::new()
  let count : Array[Int] = [0]
  let wp = db.watch_prefix("u:", fn(_e) { count[0] = count[0] + 1 })
  let wg = db.watch_all(fn(_e) { count[0] = count[0] + 1 })
  db.set("u:1", @realtime_db.Int(1))
  assert_eq(count[0], 2) // prefix + global
  assert_true(db.unwatch(wp))
  db.set("u:2", @realtime_db.Int(1))
  assert_eq(count[0], 3) // 只剩 global
  assert_true(db.unwatch(wg))
  db.set("u:3", @realtime_db.Int(1))
  assert_eq(count[0], 3) // 都取消了
}

///|
test "value_and_event_to_string" {
  assert_eq(@realtime_db.Str("hi").to_string(), "hi")
  assert_eq(@realtime_db.Int(42).to_string(), "42")
  assert_eq(@realtime_db.Bool(true).to_string(), "true")
  assert_eq(@realtime_db.Null.to_string(), "null")
  assert_eq(
    @realtime_db.Arr([
      @realtime_db.Int(1),
      @realtime_db.Str("x"),
      @realtime_db.Null,
    ]).to_string(),
    "[1, x, null]",
  )
  let db = @realtime_db.DB::new()
  let events : Array[String] = []
  let _ = db.watch("k", fn(e) { events.push(e.to_string()) })
  db.set("k", @realtime_db.Int(1))
  db.set("k", @realtime_db.Int(2))
  let _ = db.delete("k")
  assert_eq(events[0], "SET k = 1 (new)")
  assert_eq(events[1], "SET k = 2 (was 1)")
  assert_eq(events[2], "DELETE k (was 2)")
}

///|
test "expire_event_to_string" {
  let db = @realtime_db.DB::new()
  let events : Array[String] = []
  let _ = db.watch_all(fn(e) { events.push(e.to_string()) })
  db.set("k", @realtime_db.Int(1), ttl=2)
  let _ = db.advance(2)
  assert_eq(events[0], "SET k = 1 (new)")
  assert_eq(events[1], "EXPIRE k (was 1)")
}

///|
test "clock_tracks_time" {
  let db = @realtime_db.DB::new()
  assert_eq(db.clock(), 0)
  let _ = db.advance(5)
  assert_eq(db.clock(), 5)
  let _ = db.advance(3)
  assert_eq(db.clock(), 8)
}
