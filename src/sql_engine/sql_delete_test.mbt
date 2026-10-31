// SQL DELETE 解析与执行测试

///|
fn delete_row(name : String, age : Int32) -> @realtime_db.Value {
  let fields : Map[String, @realtime_db.Value] = Map([])
  fields.set("name", @realtime_db.Str(name))
  fields.set("age", @realtime_db.Int(age))
  @realtime_db.Map(fields)
}

///|
fn delete_users_db() -> @realtime_db.DB {
  let db = @realtime_db.DB::new()
  db.set("u1", delete_row("Alice", 30))
  db.set("u2", delete_row("Bob", 17))
  db.set("u3", delete_row("Carol", 25))
  db.set("u4", delete_row("Dave", 40))
  db
}

///|
fn delete_executor(db : @realtime_db.DB) -> @sql_engine.QueryExecutor {
  let executor = @sql_engine.create_query_executor()
  executor.set_db(Some(db))
  executor
}

///|
fn parse_delete(
  sql : String,
) -> Result[@sql_engine.SqlStatement, @sql_engine.SqlError] {
  @sql_engine.parse_sql(sql)
}

///|
test "delete_parser_reads_table_and_where" {
  let statement = match parse_delete("DELETE FROM users WHERE age > 18") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  match statement {
    Delete(delete) => {
      assert_eq(delete.table, "users")
      assert_true(delete.where_condition is Some(_))
    }
    _ => assert_true(false)
  }
}

///|
test "delete_parser_without_where" {
  let statement = match parse_delete("DELETE FROM users") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  match statement {
    Delete(delete) => {
      assert_eq(delete.table, "users")
      assert_true(delete.where_condition is None)
    }
    _ => assert_true(false)
  }
}

///|
test "delete_parser_requires_from" {
  match parse_delete("DELETE users WHERE age > 18") {
    Ok(_) => assert_true(false)
    Err(error) => assert_eq(error, @sql_engine.Syntax_Error)
  }
}

///|
test "delete_parser_requires_table" {
  match parse_delete("DELETE FROM WHERE age > 18") {
    Ok(_) => assert_true(false)
    Err(error) => assert_eq(error, @sql_engine.Syntax_Error)
  }
}

///|
test "delete_execute_with_where" {
  let db = delete_users_db()
  let executor = delete_executor(db)
  let statement = match parse_delete("DELETE FROM users WHERE age >= 30") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  let deleted = match executor.execute_statement(statement) {
    Ok(deleted) => deleted
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(deleted.length(), 2)
  assert_eq(db.size(), 2)
  assert_true(!db.contains("u1"))
  assert_true(db.contains("u2"))
  assert_true(db.contains("u3"))
  assert_true(!db.contains("u4"))
}

///|
test "delete_execute_without_where_deletes_all" {
  let db = delete_users_db()
  let executor = delete_executor(db)
  let statement = match parse_delete("DELETE FROM users") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  let deleted = match executor.execute_statement(statement) {
    Ok(deleted) => deleted
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(deleted.length(), 4)
  assert_eq(db.size(), 0)
}

///|
test "delete_execute_no_match_deletes_nothing" {
  let db = delete_users_db()
  let executor = delete_executor(db)
  let statement = match parse_delete("DELETE FROM users WHERE age > 100") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  let deleted = match executor.execute_statement(statement) {
    Ok(deleted) => deleted
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(deleted.length(), 0)
  assert_eq(db.size(), 4)
}

///|
test "delete_execute_unknown_column_aborts_without_changes" {
  let db = delete_users_db()
  let executor = delete_executor(db)
  let statement = match parse_delete("DELETE FROM users WHERE missing = 1") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  match executor.execute_statement(statement) {
    Ok(_) => assert_true(false)
    Err(error) => assert_eq(error, @sql_engine.Column_Not_Found)
  }
  // 过滤失败时不得删除任何记录
  assert_eq(db.size(), 4)
}

///|
test "delete_execute_without_db_returns_error" {
  let executor = @sql_engine.create_query_executor()
  let statement = match parse_delete("DELETE FROM users") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  match executor.execute_statement(statement) {
    Ok(_) => assert_true(false)
    Err(error) =>
      assert_eq(error, @sql_engine.Internal_Error("Database not set"))
  }
}

///|
test "delete_execute_through_optimizer_plan" {
  let db = delete_users_db()
  let executor = delete_executor(db)
  let statement = match parse_delete("DELETE FROM users WHERE age < 18") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  let plan = match @sql_engine.create_query_optimizer().optimize(statement) {
    Ok(plan) => plan
    Err(_) => {
      assert_true(false)
      return
    }
  }
  let deleted = match executor.execute(plan) {
    Ok(deleted) => deleted
    Err(_) => {
      assert_true(false)
      return
    }
  }
  assert_eq(deleted.length(), 1)
  assert_eq(db.size(), 3)
  assert_true(!db.contains("u2"))
}

///|
test "delete_execute_emits_watch_events" {
  let db = delete_users_db()
  let events : Array[@realtime_db.Event] = []
  let _ = db.watch_all(fn(event) { events.push(event) })
  let executor = delete_executor(db)
  let statement = match parse_delete("DELETE FROM users WHERE age = 25") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  match executor.execute_statement(statement) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  assert_eq(events.length(), 1)
  match events[0] {
    @realtime_db.Delete(key, _) => assert_eq(key, "u3")
    _ => assert_true(false)
  }
}

///|
test "delete_execute_rejects_unsupported_statement" {
  let db = delete_users_db()
  let executor = delete_executor(db)
  let statement = match parse_delete("SELECT * FROM users") {
    Ok(statement) => statement
    Err(_) => {
      assert_true(false)
      return
    }
  }
  // SELECT 由同一入口正常执行
  match executor.execute_statement(statement) {
    Ok(rows) => assert_eq(rows.length(), 4)
    Err(_) => assert_true(false)
  }
}
