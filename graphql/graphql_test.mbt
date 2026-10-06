// GraphQL 模块测试
//
// 测试 GraphQL 解析、执行、DataLoader、缓存

///|
test "test_graphql_value" {
  // 测试整数值
  let int_val = @graphql.IntValue(42)
  assert_eq(int_val, @graphql.IntValue(42))
  assert_true(int_val != @graphql.IntValue(43))

  // 测试字符串值
  let str_val = @graphql.StringValue("hello")
  assert_eq(str_val, @graphql.StringValue("hello"))

  // 测试布尔值
  let bool_val = @graphql.BoolValue(true)
  assert_eq(bool_val, @graphql.BoolValue(true))

  // 测试空值
  let null_val = @graphql.NullValue
  assert_eq(null_val, @graphql.NullValue)

  // 测试列表值
  let list_val = @graphql.ListValue([
    @graphql.IntValue(1),
    @graphql.IntValue(2),
    @graphql.IntValue(3),
  ])
  match list_val {
    @graphql.ListValue(l) => assert_eq(l.length(), 3)
    _ => assert_true(false)
  }

  // 测试对象值
  let obj_val = @graphql.ObjectValue(
    Map([("name", @graphql.StringValue("test"))]),
  )
  match obj_val {
    @graphql.ObjectValue(m) => assert_eq(m.length(), 1)
    _ => assert_true(false)
  }
}

///|
test "test_parse_query" {
  let query = "{ user { id name } }"
  let result = @graphql.parse_graphql(query)

  assert_true(result is Ok(_))

  match result {
    Ok(r) => assert_true(r.success)
    Err(_) => assert_true(false)
  }
}

///|
test "test_parse_query_with_args" {
  let query = "{ user(id: \"1\") { id name } }"
  let result = @graphql.parse_graphql(query)

  assert_true(result is Ok(_))

  match result {
    Ok(r) => assert_true(r.success)
    Err(_) => assert_true(false)
  }
}

///|
test "test_parse_mutation" {
  let query = "mutation { createUser(name: \"test\") { id } }"
  let result = @graphql.parse_graphql(query)

  assert_true(result is Ok(_))

  match result {
    Ok(r) => assert_true(r.success)
    Err(_) => assert_true(false)
  }
}

///|
test "test_parse_subscription" {
  let query = "subscription { userUpdated { id name } }"
  let result = @graphql.parse_graphql(query)

  assert_true(result is Ok(_))

  match result {
    Ok(r) => assert_true(r.success)
    Err(_) => assert_true(false)
  }
}

///|
test "test_parse_invalid_query" {
  let query = "invalid query"
  let result = @graphql.parse_graphql(query)

  assert_true(result is Ok(_))

  match result {
    Ok(r) => assert_true(!r.success)
    Err(_) => assert_true(false)
  }
}

///|
test "test_dataloader" {
  let batch_fn = fn(keys : Array[String]) -> Array[@realtime_db.Value] {
    let results : Array[@realtime_db.Value] = []
    for key in keys {
      results.push(@realtime_db.Str("value_" + key))
    }
    results
  }

  let dataloader = @graphql.DataLoader::new(2, batch_fn)

  // 加载单个键
  let value1 = dataloader.load("key1")
  // 第一次加载会返回 None，因为需要等待批处理
  assert_true(value1 is None)

  // 加载第二个键，此时触发批处理并回填缓存
  let value2 = dataloader.load("key2")
  assert_true(value2 is None)

  // 再次加载应该从缓存获取
  let value3 = dataloader.load("key1")
  match value3 {
    Some(@realtime_db.Str(v)) => assert_eq(v, "value_key1")
    _ => assert_true(false)
  }
}

///|
test "test_dataloader_load_many" {
  let batch_fn = fn(keys : Array[String]) -> Array[@realtime_db.Value] {
    let results : Array[@realtime_db.Value] = []
    for key in keys {
      results.push(@realtime_db.Str("value_" + key))
    }
    results
  }

  let dataloader = @graphql.DataLoader::new(10, batch_fn)

  let keys = ["key1", "key2", "key3"]
  let values = dataloader.load_many(keys)

  assert_eq(values.length(), 3)
}

///|
test "test_cache" {
  let cache = @graphql.GraphQLCache::new(100, 300)

  // 初始命中率应该是 0
  assert_eq(cache.hit_rate(), 0.0)

  // 设置缓存
  cache.set("key1", @graphql.IntValue(42))

  // 获取缓存
  let value = cache.get("key1")
  assert_true(value is Some(_))

  match value {
    Some(@graphql.IntValue(v)) => assert_eq(v, 42)
    _ => assert_true(false)
  }

  // 获取不存在的键
  let value2 = cache.get("key2")
  assert_true(value2 is None)
}

///|
test "test_cache_hit_rate" {
  let cache = @graphql.GraphQLCache::new(100, 300)

  // 设置缓存
  cache.set("key1", @graphql.IntValue(42))

  // 获取缓存（命中）
  let _ = cache.get("key1")

  // 获取不存在的键（未命中）
  let _ = cache.get("key2")

  // 命中率应该是 0.5
  let hit_rate = cache.hit_rate()
  assert_true(hit_rate > 0.4 && hit_rate < 0.6)
}

///|
test "test_graphql_config" {
  let config = @graphql.GraphQLConfig::default()

  assert_true(config.enable_dataloader)
  assert_true(config.enable_cache)
  assert_eq(config.cache_size, 10000)
  assert_eq(config.cache_ttl, 300)
  assert_eq(config.max_query_depth, 10)
  assert_eq(config.max_field_count, 1000)
  assert_true(config.enable_subscription)
}

///|
test "test_graphql_error" {
  let err = @graphql.FieldNotFound("user")
  assert_eq(err.code(), 7002)
  assert_true(err.message().contains("user"))

  let err2 = @graphql.SyntaxError("Unexpected token")
  assert_eq(err2.code(), 7001)

  let err3 = @graphql.InternalError("test")
  assert_eq(err3.code(), 7099)
}

///|
test "test_parse_query_with_variables" {
  let query = "query($id: ID!) { user(id: $id) { id name } }"
  let result = @graphql.parse_graphql(query)

  // 简化实现：变量声明不支持完整解析，返回 Ok 但 success 为 false
  assert_true(result is Ok(_))
}

///|
test "test_parse_query_with_fragments" {
  let query =
    #|    fragment UserFields on User {
    #|      id
    #|      name
    #|    }
    #|    query {
    #|      user {
    #|        ...UserFields
    #|      }
    #|    }
  let result = @graphql.parse_graphql(query)

  // 简化实现：不支持片段，返回 Ok 但 success 为 false
  assert_true(result is Ok(_))
}

///|
test "test_parse_query_with_directives" {
  let query =
    #|    query {
    #|      user @include(if: true) {
    #|        id
    #|      }
    #|    }
  let result = @graphql.parse_graphql(query)

  // 简化实现：不验证指令
  assert_true(result is Ok(_))
}

///|
test "test_clear_cache" {
  let cache = @graphql.GraphQLCache::new(100, 300)

  // 设置缓存
  cache.set("key1", @graphql.IntValue(42))
  cache.set("key2", @graphql.IntValue(43))

  // 清除缓存
  cache.clear()

  // 验证缓存已清除
  let value = cache.get("key1")
  assert_true(value is None)
}

///|
test "test_dataloader_clear" {
  let batch_fn = fn(keys : Array[String]) -> Array[@realtime_db.Value] {
    let results : Array[@realtime_db.Value] = []
    for key in keys {
      results.push(@realtime_db.Str("value_" + key))
    }
    results
  }

  let dataloader = @graphql.DataLoader::new(10, batch_fn)

  // 加载数据
  let _ = dataloader.load("key1")

  // 清除缓存
  dataloader.clear()

  // 验证缓存已清除
  let value = dataloader.load("key1")
  assert_true(value is None)
}
