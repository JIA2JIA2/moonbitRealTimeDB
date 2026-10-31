// SQL DISTINCT 与前缀 NOT 测试

///|
test "select_distinct_removes_duplicates" {
  let db = users_db()
  let plain = run_sql(db, "SELECT city FROM users ORDER BY city")
  match plain {
    Ok(rows) => assert_eq(rows.length(), 4)
    Err(_) => assert_true(false)
  }

  let result = run_sql(db, "SELECT DISTINCT city FROM users ORDER BY city")
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 3)
      assert_eq(field(rows[0], "city"), Some(@realtime_db.Str("LA")))
      assert_eq(field(rows[1], "city"), Some(@realtime_db.Str("NY")))
      assert_eq(field(rows[2], "city"), Some(@realtime_db.Str("SF")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "select_distinct_multi_column_keeps_unique_rows" {
  let db = users_db()
  let result = run_sql(db, "SELECT DISTINCT city, age FROM users ORDER BY city")
  match result {
    Ok(rows) => assert_eq(rows.length(), 4)
    Err(_) => assert_true(false)
  }
}

///|
test "select_distinct_with_limit" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT DISTINCT city FROM users ORDER BY city LIMIT 2",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "city"), Some(@realtime_db.Str("LA")))
      assert_eq(field(rows[1], "city"), Some(@realtime_db.Str("NY")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "select_distinct_with_group_by" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT DISTINCT city FROM users GROUP BY city ORDER BY city",
  )
  match result {
    Ok(rows) => assert_eq(rows.length(), 3)
    Err(_) => assert_true(false)
  }
}

///|
test "select_distinct_with_aggregate" {
  let db = users_db()
  let result = run_sql(db, "SELECT DISTINCT COUNT(*) AS cnt FROM users")
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "cnt"), Some(@realtime_db.Int(4)))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "where_prefix_not_with_parentheses" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users WHERE NOT (city = 'NY') ORDER BY name",
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
test "where_prefix_not_before_comparison" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users WHERE NOT age < 25 ORDER BY name",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 3)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
      assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Carol")))
      assert_eq(field(rows[2], "name"), Some(@realtime_db.Str("Dave")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "where_prefix_not_with_and_or" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users WHERE NOT (city = 'NY' OR age < 20)",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Carol")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "where_double_not_restores_condition" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users WHERE NOT NOT city = 'NY' ORDER BY name",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
      assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Dave")))
    }
    Err(_) => assert_true(false)
  }
}
