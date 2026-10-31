// SQL CASE WHEN 表达式测试

///|
test "case_searched_with_else" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name, CASE WHEN age >= 30 THEN 'senior' ELSE 'junior' END AS level FROM users ORDER BY name",
  )
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 4)
  assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
  assert_eq(field(rows[0], "level"), Some(@realtime_db.Str("senior")))
  assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Bob")))
  assert_eq(field(rows[1], "level"), Some(@realtime_db.Str("junior")))
  assert_eq(field(rows[2], "name"), Some(@realtime_db.Str("Carol")))
  assert_eq(field(rows[2], "level"), Some(@realtime_db.Str("junior")))
  assert_eq(field(rows[3], "name"), Some(@realtime_db.Str("Dave")))
  assert_eq(field(rows[3], "level"), Some(@realtime_db.Str("senior")))
}

///|
test "case_multiple_when_branches" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name, CASE WHEN age < 20 THEN 'teen' WHEN age < 30 THEN 'young' ELSE 'adult' END AS stage FROM users ORDER BY name",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 4)
      assert_eq(field(rows[0], "stage"), Some(@realtime_db.Str("adult")))
      assert_eq(field(rows[1], "stage"), Some(@realtime_db.Str("teen")))
      assert_eq(field(rows[2], "stage"), Some(@realtime_db.Str("young")))
      assert_eq(field(rows[3], "stage"), Some(@realtime_db.Str("adult")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "case_simple_with_operand" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, CASE city WHEN 'NY' THEN 'east' WHEN 'SF' THEN 'west' ELSE 'other' END AS region FROM users ORDER BY city",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 4)
      assert_eq(field(rows[0], "region"), Some(@realtime_db.Str("other")))
      assert_eq(field(rows[1], "region"), Some(@realtime_db.Str("east")))
      assert_eq(field(rows[3], "region"), Some(@realtime_db.Str("west")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "case_without_else_returns_null" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name, CASE WHEN age > 100 THEN 'old' END AS label FROM users WHERE name = 'Alice'",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "label"), Some(@realtime_db.Null))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "case_in_where_clause" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users WHERE CASE WHEN city = 'NY' THEN 1 ELSE 0 END = 1 ORDER BY name",
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

///|
test "case_in_group_by" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT CASE WHEN age >= 25 THEN 'senior' ELSE 'junior' END AS grp, COUNT(*) AS cnt FROM users GROUP BY CASE WHEN age >= 25 THEN 'senior' ELSE 'junior' END ORDER BY grp",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "grp"), Some(@realtime_db.Str("junior")))
      assert_eq(field(rows[0], "cnt"), Some(@realtime_db.Int(1)))
      assert_eq(field(rows[1], "grp"), Some(@realtime_db.Str("senior")))
      assert_eq(field(rows[1], "cnt"), Some(@realtime_db.Int(3)))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "case_inside_aggregate_argument" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, SUM(CASE WHEN age >= 30 THEN 1 ELSE 0 END) AS seniors FROM users GROUP BY city ORDER BY city",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 3)
      assert_eq(field(rows[0], "city"), Some(@realtime_db.Str("LA")))
      assert_eq(field(rows[0], "seniors"), Some(@realtime_db.Int(0)))
      assert_eq(field(rows[1], "city"), Some(@realtime_db.Str("NY")))
      assert_eq(field(rows[1], "seniors"), Some(@realtime_db.Int(2)))
      assert_eq(field(rows[2], "city"), Some(@realtime_db.Str("SF")))
      assert_eq(field(rows[2], "seniors"), Some(@realtime_db.Int(0)))
    }
    Err(_) => assert_true(false)
  }
}
