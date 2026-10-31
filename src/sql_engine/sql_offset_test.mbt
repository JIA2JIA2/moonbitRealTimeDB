// SQL OFFSET 分页测试

///|
test "offset_with_limit" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users ORDER BY age ASC LIMIT 2 OFFSET 1",
  )
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  // 按年龄升序为 Bob(17), Carol(25), Alice(30), Dave(40)
  assert_eq(rows.length(), 2)
  assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Carol")))
  assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Alice")))
}

///|
test "offset_without_limit" {
  let db = users_db()
  let result = run_sql(db, "SELECT name FROM users ORDER BY age ASC OFFSET 2")
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
      assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Dave")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "offset_beyond_row_count_returns_empty" {
  let db = users_db()
  let result = run_sql(db, "SELECT name FROM users ORDER BY age ASC OFFSET 10")
  match result {
    Ok(rows) => assert_eq(rows.length(), 0)
    Err(_) => assert_true(false)
  }
}

///|
test "offset_zero_keeps_all_rows" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users ORDER BY age ASC LIMIT 2 OFFSET 0",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Bob")))
      assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Carol")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "offset_applies_after_distinct" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT DISTINCT city FROM users ORDER BY city LIMIT 1 OFFSET 1",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "city"), Some(@realtime_db.Str("NY")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "offset_with_order_by_desc" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users ORDER BY age DESC LIMIT 1 OFFSET 1",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
    }
    Err(_) => assert_true(false)
  }
}
