// 白盒测试：覆盖内部 helper 的边界情况。

///|
test "str_starts_with_edges" {
  assert_true(str_starts_with("abc", "a"))
  assert_true(str_starts_with("abc", "abc"))
  assert_true(str_starts_with("abc", ""))
  assert_true(str_starts_with("", ""))
  assert_false(str_starts_with("abc", "abcd"))
  assert_false(str_starts_with("abc", "b"))
  assert_false(str_starts_with("", "a"))
  assert_true(str_starts_with("user:1", "user:"))
  assert_false(str_starts_with("post:1", "user:"))
}

///|
test "is_expired_logic" {
  let db = DB::new()
  // 永不过期
  assert_false(db.is_expired({ value: Int(1), expires_at: None, }))
  // 未到期
  assert_false(db.is_expired({ value: Int(1), expires_at: Some(5), }))
  let _ = db.advance(5)
  // 刚好到期 (t <= clock)
  assert_true(db.is_expired({ value: Int(1), expires_at: Some(5), }))
  assert_true(db.is_expired({ value: Int(1), expires_at: Some(3), }))
  // 仍未到期
  assert_false(db.is_expired({ value: Int(1), expires_at: Some(6), }))
}
