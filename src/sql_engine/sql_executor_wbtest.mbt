// 白盒测试：SELECT 执行器的表达式求值辅助

///|
test "compare_ordered_strings" {
  assert_eq(
    compare_ordered(@realtime_db.Str("LA"), @realtime_db.Str("NY")),
    Ok(-1),
  )
  assert_eq(
    compare_ordered(@realtime_db.Str("NY"), @realtime_db.Str("LA")),
    Ok(1),
  )
  assert_eq(
    compare_ordered(@realtime_db.Str("NY"), @realtime_db.Str("NY")),
    Ok(0),
  )
}

///|
test "literal_string_and_number_values" {
  let statement = match parse_sql("SELECT * FROM t WHERE city = 'NY'") {
    Ok(s) => s
    Err(_) => {
      assert_true(false)
      return
    }
  }
  match statement {
    Select(select) =>
      match select.where_condition {
        Some(BinaryOp(op)) => {
          match op.operator {
            Equal => ()
            _ => assert_true(false)
          }
          match op.right {
            Literal(value) => assert_eq(value.value, @realtime_db.Str("NY"))
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }

  let number_statement = match parse_sql("SELECT * FROM t WHERE age > 18") {
    Ok(s) => s
    Err(_) => {
      assert_true(false)
      return
    }
  }
  match number_statement {
    Select(select) =>
      match select.where_condition {
        Some(BinaryOp(op)) =>
          match op.right {
            Literal(value) => assert_eq(value.value, @realtime_db.Int(18))
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "select_star_keeps_all_clauses" {
  let statement = match parse_sql("SELECT * FROM users WHERE age > 18") {
    Ok(s) => s
    Err(_) => {
      assert_true(false)
      return
    }
  }
  match statement {
    Select(select) => {
      assert_eq(select.select_items.length(), 1)
      match select.select_items[0].expression {
        Wildcard => ()
        _ => assert_true(false)
      }
      assert_eq(select.from, Some("users"))
      match select.where_condition {
        Some(BinaryOp(op)) =>
          match op.left {
            ColumnRef(name) => assert_eq(name, "age")
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}
