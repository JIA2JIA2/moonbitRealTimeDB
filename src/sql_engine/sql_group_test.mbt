// SQL GROUP BY / HAVING / 聚合函数测试

///|
test "group_by_count" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, COUNT(*) AS cnt FROM users GROUP BY city ORDER BY city",
  )
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 3)
  assert_eq(field(rows[0], "city"), Some(@realtime_db.Str("LA")))
  assert_eq(field(rows[0], "cnt"), Some(@realtime_db.Int(1)))
  assert_eq(field(rows[1], "city"), Some(@realtime_db.Str("NY")))
  assert_eq(field(rows[1], "cnt"), Some(@realtime_db.Int(2)))
  assert_eq(field(rows[2], "city"), Some(@realtime_db.Str("SF")))
  assert_eq(field(rows[2], "cnt"), Some(@realtime_db.Int(1)))
}

///|
test "group_by_having_filters_groups" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, COUNT(*) AS cnt FROM users GROUP BY city HAVING COUNT(*) > 1",
  )
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 1)
  assert_eq(field(rows[0], "city"), Some(@realtime_db.Str("NY")))
  assert_eq(field(rows[0], "cnt"), Some(@realtime_db.Int(2)))
}

///|
test "group_by_having_and_condition" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, COUNT(*) AS cnt FROM users GROUP BY city HAVING COUNT(*) > 1 AND city = 'NY'",
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
test "aggregate_without_group_by" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT SUM(age) AS total, AVG(age) AS average, MIN(age) AS low, MAX(age) AS high FROM users",
  )
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 1)
  assert_eq(field(rows[0], "total"), Some(@realtime_db.Int(112)))
  assert_eq(field(rows[0], "average"), Some(@realtime_db.Float(28.0)))
  assert_eq(field(rows[0], "low"), Some(@realtime_db.Int(17)))
  assert_eq(field(rows[0], "high"), Some(@realtime_db.Int(40)))
}

///|
test "count_distinct" {
  let db = users_db()
  let result = run_sql(db, "SELECT COUNT(DISTINCT age) AS cnt FROM users")
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "cnt"), Some(@realtime_db.Int(4)))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "count_distinct_per_group" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, COUNT(DISTINCT age) AS cnt FROM users GROUP BY city ORDER BY city",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 3)
      assert_eq(field(rows[1], "city"), Some(@realtime_db.Str("NY")))
      assert_eq(field(rows[1], "cnt"), Some(@realtime_db.Int(2)))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "aggregate_on_empty_input_returns_one_row" {
  let db = users_db()
  let result = run_sql(db, "SELECT COUNT(*) AS cnt FROM users WHERE age > 100")
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "cnt"), Some(@realtime_db.Int(0)))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "group_by_order_by_alias_and_limit" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, COUNT(*) AS cnt FROM users GROUP BY city ORDER BY cnt DESC, city ASC LIMIT 2",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "city"), Some(@realtime_db.Str("NY")))
      assert_eq(field(rows[1], "city"), Some(@realtime_db.Str("LA")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "aggregate_expression_in_projection" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, COUNT(*) * 2 AS double_cnt FROM users GROUP BY city ORDER BY city",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 3)
      assert_eq(field(rows[1], "city"), Some(@realtime_db.Str("NY")))
      assert_eq(field(rows[1], "double_cnt"), Some(@realtime_db.Int(4)))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "unsupported_function_returns_not_implemented" {
  let db = users_db()
  let result = run_sql(db, "SELECT UPPER(name) FROM users")
  match result {
    Ok(_) => assert_true(false)
    Err(error) =>
      match error {
        @sql_engine.Not_Implemented(_) => ()
        _ => assert_true(false)
      }
  }
}

///|
test "group_by_where_then_group" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, COUNT(*) AS cnt, SUM(age) AS total FROM users WHERE age >= 25 GROUP BY city ORDER BY city",
  )
  match result {
    Ok(rows) => {
      // Alice(30,NY), Carol(25,SF), Dave(40,NY)
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "city"), Some(@realtime_db.Str("NY")))
      assert_eq(field(rows[0], "cnt"), Some(@realtime_db.Int(2)))
      assert_eq(field(rows[0], "total"), Some(@realtime_db.Int(70)))
      assert_eq(field(rows[1], "city"), Some(@realtime_db.Str("SF")))
      assert_eq(field(rows[1], "cnt"), Some(@realtime_db.Int(1)))
    }
    Err(_) => assert_true(false)
  }
}
