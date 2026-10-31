// 白盒测试：索引内部值比较辅助函数

///|
test "compare_values_cross_type_is_ordered" {
  let int_val = @realtime_db.Int(1)
  let str_val = @realtime_db.Str("1")
  let float_val = @realtime_db.Float(1.0)
  let bool_val = @realtime_db.Bool(true)
  let null_val = @realtime_db.Null

  // 跨类型不能返回"相等"，否则破坏 B+ 树全序
  assert_true(compare_values(str_val, int_val) < 0)
  assert_true(compare_values(int_val, str_val) > 0)
  assert_true(compare_values(int_val, float_val) < 0)
  assert_true(compare_values(float_val, int_val) > 0)
  assert_true(compare_values(float_val, bool_val) < 0)
  assert_true(compare_values(bool_val, null_val) < 0)
  assert_true(compare_values(null_val, bool_val) > 0)

  // 任意两种不同类型都不可比出 0
  let values : Array[@realtime_db.Value] = [
    int_val, str_val, float_val, bool_val, null_val,
  ]
  for i in 0..<values.length() {
    for j in 0..<values.length() {
      if i != j {
        assert_true(compare_values(values[i], values[j]) != 0)
      }
    }
  }
}

///|
test "compare_values_same_type_still_ordered" {
  assert_eq(compare_values(@realtime_db.Int(1), @realtime_db.Int(1)), 0)
  assert_true(compare_values(@realtime_db.Int(1), @realtime_db.Int(2)) < 0)
  assert_true(compare_values(@realtime_db.Int(2), @realtime_db.Int(1)) > 0)
  assert_true(
    compare_values(@realtime_db.Float(1.5), @realtime_db.Float(2.5)) < 0,
  )
  assert_true(compare_values(@realtime_db.Str("a"), @realtime_db.Str("b")) < 0)
  assert_true(
    compare_values(@realtime_db.Bool(false), @realtime_db.Bool(true)) < 0,
  )
}
