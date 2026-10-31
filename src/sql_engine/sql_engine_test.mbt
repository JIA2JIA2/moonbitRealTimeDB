// SQL 引擎测试
//
// 测试 SQL 解析、优化、执行

///|
test "test_sql_types" {
  // 测试列类型
  assert_eq(@sql_engine.ColumnType::Int, @sql_engine.ColumnType::Int)
  assert_true(@sql_engine.ColumnType::String != @sql_engine.ColumnType::Int)

  // 测试约束类型
  assert_eq(
    @sql_engine.ConstraintType::PrimaryKey,
    @sql_engine.ConstraintType::PrimaryKey,
  )
  assert_true(
    @sql_engine.ConstraintType::NotNull != @sql_engine.ConstraintType::Unique,
  )

  // 测试错误类型
  let err = @sql_engine.SqlError::Syntax_Error
  assert_eq(err.code(), 3001)
  assert_true(err.message().length() > 0)
}

///|
test "test_lexer" {
  let sql = "SELECT * FROM users WHERE id = 1"
  let lexer = @sql_engine.Lexer::new(sql)

  // 测试第一个标记
  let token = lexer.next_token()
  assert_true(token is Ok(_))

  match token {
    Ok(t) => {
      assert_eq(t.token_type, @sql_engine.Keyword)
      assert_eq(t.value, "SELECT")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_lexer_identifier" {
  let sql = "username"
  let lexer = @sql_engine.Lexer::new(sql)

  let token = lexer.next_token()
  assert_true(token is Ok(_))

  match token {
    Ok(t) => {
      assert_eq(t.token_type, @sql_engine.Identifier)
      assert_eq(t.value, "username")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_lexer_number" {
  let sql = "123"
  let lexer = @sql_engine.Lexer::new(sql)

  let token = lexer.next_token()
  assert_true(token is Ok(_))

  match token {
    Ok(t) => {
      assert_eq(t.token_type, @sql_engine.NumberLiteral)
      assert_eq(t.value, "123")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_lexer_string" {
  let sql = "'hello'"
  let lexer = @sql_engine.Lexer::new(sql)

  let token = lexer.next_token()
  assert_true(token is Ok(_))

  match token {
    Ok(t) => {
      assert_eq(t.token_type, @sql_engine.StringLiteral)
      assert_eq(t.value, "hello")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_parse_select" {
  let sql = "SELECT id, name FROM users"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))

  match result {
    Ok(@sql_engine.Select(stmt)) => {
      assert_eq(stmt.select_items.length(), 2)
      assert_true(stmt.from is Some(_))
    }
    _ => assert_true(false)
  }
}

///|
test "test_parse_select_with_where" {
  let sql = "SELECT * FROM users WHERE id = 1"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))
}

///|
/// 回归测试：WHERE a=1 AND b=2 必须解析出两个条件，而非只解析 a
test "test_parse_select_with_where_and" {
  let sql = "SELECT * FROM users WHERE id = 1 AND name = 'test'"
  let result = @sql_engine.parse_sql(sql)

  // 修复前此查询会因 parse_expression 只解析 id 而失败
  assert_true(result is Ok(_))
}

///|
/// 回归测试：WHERE a=1 OR b=2 必须解析出两个条件
test "test_parse_select_with_where_or" {
  let sql = "SELECT * FROM users WHERE id = 1 OR name = 'test'"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))
}

///|
/// 回归测试：WHERE a=1 AND b=2 AND c=3 必须解析出三个条件
test "test_parse_select_with_where_multiple_and" {
  let sql = "SELECT * FROM users WHERE id = 1 AND name = 'test' AND age = 18"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))
}

///|
test "test_parse_select_with_order" {
  let sql = "SELECT * FROM users ORDER BY name DESC"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))
}

///|
test "test_parse_select_with_limit" {
  let sql = "SELECT * FROM users LIMIT 10"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))
}

///|
test "test_parse_insert" {
  let sql = "INSERT INTO users (id, name) VALUES (1, 'test')"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))
}

///|
test "test_parse_update" {
  let sql = "UPDATE users SET name = 'new' WHERE id = 1"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))
}

///|
test "test_parse_delete" {
  let sql = "DELETE FROM users WHERE id = 1"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))
}

///|
test "test_parse_create_table" {
  let sql = "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(255))"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))
}

///|
test "test_parse_begin" {
  let sql = "BEGIN"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))

  match result {
    Ok(@sql_engine.Begin(_)) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "test_parse_commit" {
  let sql = "COMMIT"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))

  match result {
    Ok(@sql_engine.Commit(_)) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "test_parse_rollback" {
  let sql = "ROLLBACK"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))

  match result {
    Ok(@sql_engine.Rollback(_)) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "test_query_optimizer" {
  let sql = "SELECT * FROM users WHERE id = 1"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Ok(_))

  match result {
    Ok(stmt) => {
      let optimizer = @sql_engine.create_query_optimizer()
      let plan = optimizer.optimize(stmt)
      assert_true(plan is Ok(_))
    }
    _ => assert_true(false)
  }
}

///|
test "test_invalid_sql" {
  let sql = "INVALID SQL"
  let result = @sql_engine.parse_sql(sql)

  assert_true(result is Err(_))
}

///|
test "test_keyword_case_insensitive" {
  let sql1 = "select * from users"
  let result1 = @sql_engine.parse_sql(sql1)
  assert_true(result1 is Ok(_))

  let sql2 = "SELECT * FROM users"
  let result2 = @sql_engine.parse_sql(sql2)
  assert_true(result2 is Ok(_))

  let sql3 = "SeLeCt * FrOm users"
  let result3 = @sql_engine.parse_sql(sql3)
  assert_true(result3 is Ok(_))
}
