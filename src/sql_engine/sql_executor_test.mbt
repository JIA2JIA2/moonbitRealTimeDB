// SQL SELECT 执行器测试

///|
fn sql_row(name : String, age : Int32, city : String) -> @realtime_db.Value {
  let fields : Map[String, @realtime_db.Value] = Map([])
  fields.set("name", @realtime_db.Str(name))
  fields.set("age", @realtime_db.Int(age))
  fields.set("city", @realtime_db.Str(city))
  @realtime_db.Map(fields)
}

///|
fn field(row : @realtime_db.Value, name : String) -> @realtime_db.Value? {
  match row {
    @realtime_db.Map(fields) => fields.get(name)
    _ => None
  }
}

///|
fn run_sql(
  db : @realtime_db.DB,
  sql : String,
) -> Result[Array[@realtime_db.Value], @sql_engine.SqlError] {
  let statement = match @sql_engine.parse_sql(sql) {
    Ok(statement) => statement
    Err(error) => return Err(error)
  }
  let plan = match @sql_engine.create_query_optimizer().optimize(statement) {
    Ok(plan) => plan
    Err(error) => return Err(error)
  }
  let executor = @sql_engine.create_query_executor()
  executor.set_db(Some(db))
  executor.execute(plan)
}

///|
fn users_db() -> @realtime_db.DB {
  let db = @realtime_db.DB::new()
  db.set("u1", sql_row("Alice", 30, "NY"))
  db.set("u2", sql_row("Bob", 17, "LA"))
  db.set("u3", sql_row("Carol", 25, "SF"))
  db.set("u4", sql_row("Dave", 40, "NY"))
  db
}

///|
test "select_where_projection_order_limit" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name, age FROM users WHERE age > 18 ORDER BY age DESC LIMIT 2",
  )
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 2)
  assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Dave")))
  assert_eq(field(rows[0], "age"), Some(@realtime_db.Int(40)))
  assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Alice")))
  // 未投影列不应出现在结果中
  assert_eq(field(rows[0], "city"), None)
}

///|
test "select_star_expands_map_fields" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT * FROM users WHERE city = 'NY' ORDER BY name",
  )
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 2)
  assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
  assert_eq(field(rows[0], "age"), Some(@realtime_db.Int(30)))
  assert_eq(field(rows[0], "city"), Some(@realtime_db.Str("NY")))
  // 通配符展开 Map 字段，不暴露内部行键
  assert_eq(field(rows[0], "key"), None)
}

///|
test "select_and_or_and_comparison" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT name FROM users WHERE (city = 'NY' OR city = 'SF') AND age >= 25 ORDER BY name",
  )
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 3)
  assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Alice")))
  assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Carol")))
  assert_eq(field(rows[2], "name"), Some(@realtime_db.Str("Dave")))
}

///|
test "select_arithmetic_with_alias" {
  let db = users_db()
  let result = run_sql(
    db, "SELECT age + 10 AS age_plus FROM users WHERE name = 'Alice'",
  )
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 1)
  assert_eq(field(rows[0], "age_plus"), Some(@realtime_db.Int(40)))
}

///|
test "select_order_asc_limit" {
  let db = users_db()
  let result = run_sql(db, "SELECT name FROM users ORDER BY age ASC LIMIT 3")
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 3)
  assert_eq(field(rows[0], "name"), Some(@realtime_db.Str("Bob")))
  assert_eq(field(rows[1], "name"), Some(@realtime_db.Str("Carol")))
  assert_eq(field(rows[2], "name"), Some(@realtime_db.Str("Alice")))
}

///|
test "select_unknown_column_returns_error" {
  let db = users_db()
  let result = run_sql(db, "SELECT missing FROM users")
  match result {
    Ok(_) => assert_true(false)
    Err(error) => assert_eq(error, @sql_engine.Column_Not_Found)
  }
}

///|
test "select_non_map_value_exposes_key_and_value" {
  let db = @realtime_db.DB::new()
  db.set("counter", @realtime_db.Int(42))
  let result = run_sql(db, "SELECT * FROM kv WHERE key = 'counter'")
  let rows = match result {
    Ok(rows) => rows
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(rows.length(), 1)
  assert_eq(field(rows[0], "key"), Some(@realtime_db.Str("counter")))
  assert_eq(field(rows[0], "value"), Some(@realtime_db.Int(42)))
}

///|
test "select_division_by_zero_returns_error" {
  let db = users_db()
  let result = run_sql(db, "SELECT age / 0 FROM users")
  match result {
    Ok(_) => assert_true(false)
    Err(error) => assert_eq(error, @sql_engine.Division_By_Zero)
  }
}

///|
test "select_limit_zero_and_empty_table" {
  let empty = @realtime_db.DB::new()
  let result = run_sql(empty, "SELECT * FROM users")
  match result {
    Ok(rows) => assert_eq(rows.length(), 0)
    Err(_) => assert_true(false)
  }

  let db = users_db()
  let limited = run_sql(db, "SELECT name FROM users LIMIT 0")
  match limited {
    Ok(rows) => assert_eq(rows.length(), 0)
    Err(_) => assert_true(false)
  }
}

///|
test "plan_carries_select_statement" {
  let statement = match @sql_engine.parse_sql("SELECT * FROM users") {
    Ok(s) => s
    Err(_) => {
      assert_true(false)
      return
    }
  }
  let plan = match @sql_engine.create_query_optimizer().optimize(statement) {
    Ok(p) => p
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_true(plan.select is Some(_))
}

///|
test "debug_parser_carries_clauses" {
  let statement = match
    @sql_engine.parse_sql(
      "SELECT name, age FROM users WHERE age > 18 ORDER BY age DESC LIMIT 2",
    ) {
    Ok(s) => s
    Err(_) => {
      assert_true(false)
      return
    }
  }
  match statement {
    Select(select) => {
      assert_eq(select.select_items.length(), 2)
      assert_true(select.where_condition is Some(_))
      assert_true(select.order_by is Some(_))
      assert_true(select.limit is Some(_))
    }
    _ => assert_true(false)
  }
}
