// SQL 引擎测试
//
// 测试 SQL 解析、优化、执行

test "test_sql_types" {
  // 测试列类型
  assert_eq(ColumnType::Int, ColumnType::Int)
  assert_true(ColumnType::String != ColumnType::Int)

  // 测试约束类型
  assert_eq(ConstraintType::PrimaryKey, ConstraintType::PrimaryKey)
  assert_true(ConstraintType::NotNull != ConstraintType::Unique)

  // 测试错误类型
  let err = SqlError::Syntax_Error
  assert_eq(err.code(), 3001)
  assert_true(err.message().length() > 0)
}

test "test_lexer" {
  let sql = "SELECT * FROM users WHERE id = 1"
  let lexer = Lexer::new(sql)

  // 测试第一个标记
  let token = lexer.next_token()
  assert_true(token is Ok)

  match token {
    Ok(t) => {
      assert_eq(t.token_type, Keyword)
      assert_eq(t.value, "SELECT")
    }
    Err(_) => assert_true(false)
  }
}

test "test_lexer_identifier" {
  let sql = "username"
  let lexer = Lexer::new(sql)

  let token = lexer.next_token()
  assert_true(token is Ok)

  match token {
    Ok(t) => {
      assert_eq(t.token_type, Identifier)
      assert_eq(t.value, "username")
    }
    Err(_) => assert_true(false)
  }
}

test "test_lexer_number" {
  let sql = "123"
  let lexer = Lexer::new(sql)

  let token = lexer.next_token()
  assert_true(token is Ok)

  match token {
    Ok(t) => {
      assert_eq(t.token_type, NumberLiteral)
      assert_eq(t.value, "123")
    }
    Err(_) => assert_true(false)
  }
}

test "test_lexer_string" {
  let sql = "'hello'"
  let lexer = Lexer::new(sql)

  let token = lexer.next_token()
  assert_true(token is Ok)

  match token {
    Ok(t) => {
      assert_eq(t.token_type, StringLiteral)
      assert_eq(t.value, "hello")
    }
    Err(_) => assert_true(false)
  }
}

test "test_parse_select" {
  let sql = "SELECT id, name FROM users"
  let result = parse_sql(sql)

  assert_true(result is Ok)

  match result {
    Ok(Select(stmt)) => {
      assert_eq(stmt.select_items.length(), 2)
      assert_true(stmt.from is Some)
    }
    _ => assert_true(false)
  }
}

test "test_parse_select_with_where" {
  let sql = "SELECT * FROM users WHERE id = 1"
  let result = parse_sql(sql)

  assert_true(result is Ok)
}

test "test_parse_select_with_order" {
  let sql = "SELECT * FROM users ORDER BY name DESC"
  let result = parse_sql(sql)

  assert_true(result is Ok)
}

test "test_parse_select_with_limit" {
  let sql = "SELECT * FROM users LIMIT 10"
  let result = parse_sql(sql)

  assert_true(result is Ok)
}

test "test_parse_insert" {
  let sql = "INSERT INTO users (id, name) VALUES (1, 'test')"
  let result = parse_sql(sql)

  assert_true(result is Ok)
}

test "test_parse_update" {
  let sql = "UPDATE users SET name = 'new' WHERE id = 1"
  let result = parse_sql(sql)

  assert_true(result is Ok)
}

test "test_parse_delete" {
  let sql = "DELETE FROM users WHERE id = 1"
  let result = parse_sql(sql)

  assert_true(result is Ok)
}

test "test_parse_create_table" {
  let sql = "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(255))"
  let result = parse_sql(sql)

  assert_true(result is Ok)
}

test "test_parse_begin" {
  let sql = "BEGIN"
  let result = parse_sql(sql)

  assert_true(result is Ok)

  match result {
    Ok(Begin(_)) => assert_true(true)
    _ => assert_true(false)
  }
}

test "test_parse_commit" {
  let sql = "COMMIT"
  let result = parse_sql(sql)

  assert_true(result is Ok)

  match result {
    Ok(Commit(_)) => assert_true(true)
    _ => assert_true(false)
  }
}

test "test_parse_rollback" {
  let sql = "ROLLBACK"
  let result = parse_sql(sql)

  assert_true(result is Ok)

  match result {
    Ok(Rollback(_)) => assert_true(true)
    _ => assert_true(false)
  }
}

test "test_query_optimizer" {
  let sql = "SELECT * FROM users WHERE id = 1"
  let result = parse_sql(sql)

  assert_true(result is Ok)

  match result {
    Ok(stmt) => {
      let optimizer = create_query_optimizer()
      let plan = optimizer.optimize(stmt)
      assert_true(plan is Ok)
    }
    _ => assert_true(false)
  }
}

test "test_invalid_sql" {
  let sql = "INVALID SQL"
  let result = parse_sql(sql)

  assert_true(result is Err)
}

test "test_keyword_case_insensitive" {
  let sql1 = "select * from users"
  let result1 = parse_sql(sql1)
  assert_true(result1 is Ok)

  let sql2 = "SELECT * FROM users"
  let result2 = parse_sql(sql2)
  assert_true(result2 is Ok)

  let sql3 = "SeLeCt * FrOm users"
  let result3 = parse_sql(sql3)
  assert_true(result3 is Ok)
}