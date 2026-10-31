// SQL 表达式增强测试：LIKE / IN / BETWEEN / IS NULL / 标量函数

///|
test "where_like_prefix_and_underscore" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users WHERE name LIKE 'A%' ORDER BY name",
  )
  match result {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
    }
    Err(_) => assert_true(false)
  }

  let single = run_sql(db, "SELECT name FROM users WHERE name LIKE '_ob'")
  match single {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Bob")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "where_like_contains_and_not_like" {
  let db = users_db()
  let contains = run_sql(
    db, "SELECT name FROM users WHERE name LIKE '%a%' ORDER BY name",
  )
  match contains {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Carol")))
      assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Dave")))
    }
    Err(_) => assert_true(false)
  }

  let negated = run_sql(
    db, "SELECT name FROM users WHERE name NOT LIKE '%a%' ORDER BY name",
  )
  match negated {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
      assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Bob")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "where_in_and_not_in" {
  let db = users_db()
  let included = run_sql(
    db, "SELECT name FROM users WHERE city IN ('NY', 'SF') ORDER BY name",
  )
  match included {
    Ok(rows) => {
      assert_eq(rows.length(), 3)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
      assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Carol")))
      assert_eq(field(rows[2], "name"), Some(@realtime_db.Str("Dave")))
    }
    Err(_) => assert_true(false)
  }

  let excluded = run_sql(
    db, "SELECT name FROM users WHERE city NOT IN ('NY', 'SF')",
  )
  match excluded {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Bob")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "where_in_numeric_values" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users WHERE age IN (30, 40) ORDER BY name",
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
test "where_between_and_not_between" {
  let db = users_db()
  let between = run_sql(
    db, "SELECT name FROM users WHERE age BETWEEN 25 AND 35 ORDER BY name",
  )
  match between {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
      assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Carol")))
    }
    Err(_) => assert_true(false)
  }

  let negated = run_sql(
    db, "SELECT name FROM users WHERE age NOT BETWEEN 25 AND 35 ORDER BY name",
  )
  match negated {
    Ok(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Bob")))
      assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Dave")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "where_is_null_and_is_not_null" {
  let db = users_db()
  let not_null = run_sql(db, "SELECT name FROM users WHERE value IS NOT NULL")
  match not_null {
    Ok(rows) => assert_eq(rows.length(), 4)
    Err(_) => assert_true(false)
  }

  let is_null = run_sql(db, "SELECT name FROM users WHERE value IS NULL")
  match is_null {
    Ok(rows) => assert_eq(rows.length(), 0)
    Err(_) => assert_true(false)
  }
}

///|
test "scalar_functions_upper_lower_length" {
  let db = users_db()
  let upper = run_sql(
    db, "SELECT UPPER(name) AS name FROM users WHERE name = 'Alice'",
  )
  match upper {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("ALICE")))
    }
    Err(_) => assert_true(false)
  }

  let lower = run_sql(
    db, "SELECT LOWER(name) AS name FROM users WHERE name = 'Bob'",
  )
  match lower {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("bob")))
    }
    Err(_) => assert_true(false)
  }

  let length = run_sql(
    db, "SELECT LENGTH(name) AS len FROM users WHERE name = 'Carol'",
  )
  match length {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "len"), Some(@realtime_db.Int(5)))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "scalar_functions_abs_and_coalesce" {
  let db = users_db()
  let abs = run_sql(
    db, "SELECT ABS(age - 30) AS distance FROM users WHERE name = 'Bob'",
  )
  match abs {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "distance"), Some(@realtime_db.Int(13)))
    }
    Err(_) => assert_true(false)
  }

  let coalesce = run_sql(
    db, "SELECT COALESCE(NULL, name, city) AS chosen FROM users WHERE name = 'Alice'",
  )
  match coalesce {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      assert_eq(field(rows[0], "chosen"), Some(@realtime_db.Str("Alice")))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "scalar_function_in_group_having" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT city, COUNT(*) AS cnt FROM users GROUP BY city HAVING COUNT(*) > 1 AND LENGTH(city) = 2",
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
test "unknown_scalar_function_returns_not_implemented" {
  let db = users_db()
  let result = run_sql(db, "SELECT MEDIAN(age) FROM users")
  match result {
    Ok(_) => assert_true(false)
    Err(error) =>
      match error {
        @sql_engine.Not_Implemented(_) => ()
        _ => assert_true(false)
      }
  }
}
