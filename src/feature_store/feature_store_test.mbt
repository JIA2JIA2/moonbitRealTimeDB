// 特征存储模块测试
//
// 测试特征表、特征向量、特征计算

///|
test "test_feature_types" {
  // 测试特征类型
  assert_eq(@feature_store.Int, @feature_store.Int)
  assert_true(@feature_store.Float != @feature_store.Int)

  // 测试特征状态
  assert_eq(@feature_store.Active, @feature_store.Active)
  assert_true(@feature_store.Disabled != @feature_store.Active)

  // 测试特征来源
  assert_eq(@feature_store.Batch, @feature_store.Batch)
  assert_true(@feature_store.Streaming != @feature_store.Batch)

  // 测试特征视图类型
  assert_eq(@feature_store.BatchView, @feature_store.BatchView)
  assert_true(@feature_store.StreamingView != @feature_store.BatchView)
}

///|
test "test_feature_error" {
  let err = @feature_store.Table_Already_Exists
  assert_eq(err.code(), 6001)
  assert_true(err.message().length() > 0)

  let err2 = @feature_store.Feature_Not_Found
  assert_eq(err2.code(), 6004)

  let err3 = @feature_store.Internal_Error("test error")
  assert_eq(err3.code(), 6099)
  assert_true(err3.message().contains("test error"))
}

///|
test "test_create_feature_table" {
  let config = @feature_store.FeatureStoreConfig::default()
  let manager = @feature_store.FeatureStoreManager::new(config)

  // 创建特征
  let features = [
    @feature_store.Feature::{
      feature_id: "f1".to_string(),
      feature_name: "age".to_string(),
      feature_type: @feature_store.Int,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: Some("User age".to_string()),
      default_value: Some(@realtime_db.Int(0)),
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
    @feature_store.Feature::{
      feature_id: "f2".to_string(),
      feature_name: "name".to_string(),
      feature_type: @feature_store.String,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: Some("User name".to_string()),
      default_value: Some(@realtime_db.Str("")),
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
  ]

  // 创建表
  let table_id = manager.create_table("users", "user_id", features)
  assert_true(table_id is Ok(_))

  match table_id {
    Ok(id) => {
      assert_true(id.length() > 0)

      // 验证表存在
      let table = manager.get_table(id)
      assert_true(table is Some(_))

      match table {
        Some(t) => {
          assert_eq(t.table_name, "users")
          assert_eq(t.primary_key, "user_id")
          assert_eq(t.features.length(), 2)
        }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_duplicate_table_name" {
  let config = @feature_store.FeatureStoreConfig::default()
  let manager = @feature_store.FeatureStoreManager::new(config)

  let features = [
    @feature_store.Feature::{
      feature_id: "f1".to_string(),
      feature_name: "age".to_string(),
      feature_type: @feature_store.Int,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: None,
      default_value: None,
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
  ]

  // 创建第一个表
  let result1 = manager.create_table("users", "user_id", features)
  assert_true(result1 is Ok(_))

  // 创建重复表
  let features2 = [
    @feature_store.Feature::{
      feature_id: "f1".to_string(),
      feature_name: "age".to_string(),
      feature_type: @feature_store.Int,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: None,
      default_value: None,
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
  ]
  let result2 = manager.create_table("users", "user_id", features2)
  assert_true(result2 is Err(_))

  match result2 {
    Err(@feature_store.Table_Already_Exists) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "test_list_tables" {
  let config = @feature_store.FeatureStoreConfig::default()
  let manager = @feature_store.FeatureStoreManager::new(config)

  let make_features = fn() -> Array[@feature_store.Feature] {
    [
      @feature_store.Feature::{
        feature_id: "f1".to_string(),
        feature_name: "age".to_string(),
        feature_type: @feature_store.Int,
        status: @feature_store.Active,
        source: @feature_store.Batch,
        description: None,
        default_value: None,
        metadata: Map([]),
        created_at: 0,
        updated_at: 0,
      },
    ]
  }

  // 创建多个表
  let _ = manager.create_table("users", "user_id", make_features())
  let _ = manager.create_table("orders", "order_id", make_features())

  // 列出表
  let tables = manager.list_tables()
  assert_eq(tables.length(), 2)
}

///|
test "test_write_read_vector" {
  let config = @feature_store.FeatureStoreConfig::default()
  let manager = @feature_store.FeatureStoreManager::new(config)

  let features = [
    @feature_store.Feature::{
      feature_id: "f1".to_string(),
      feature_name: "age".to_string(),
      feature_type: @feature_store.Int,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: None,
      default_value: None,
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
  ]

  // 创建表
  let table_id = manager.create_table("users", "user_id", features)
  assert_true(table_id is Ok(_))

  match table_id {
    Ok(tid) => {
      // 写入特征向量
      let values = Map([("age", @realtime_db.Int(25))])
      let write_request = @feature_store.FeatureWriteRequest::{
        table_id: tid.to_string(),
        entity_id: "user1".to_string(),
        values,
        source: @feature_store.Realtime,
        overwrite: true,
      }

      let write_result = manager.write_vector(write_request)
      assert_true(write_result is Ok(_))

      // 读取特征向量
      let read_request = @feature_store.FeatureQueryRequest::{
        table_id: tid,
        entity_id: "user1".to_string(),
        feature_names: None,
        version: None,
        use_cache: false,
      }

      let read_result = manager.read_vector(read_request)
      assert_true(read_result is Ok(_))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_add_feature" {
  let config = @feature_store.FeatureStoreConfig::default()
  let manager = @feature_store.FeatureStoreManager::new(config)

  let features = [
    @feature_store.Feature::{
      feature_id: "f1".to_string(),
      feature_name: "age".to_string(),
      feature_type: @feature_store.Int,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: None,
      default_value: None,
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
  ]

  // 创建表
  let table_id = manager.create_table("users", "user_id", features)
  assert_true(table_id is Ok(_))

  match table_id {
    Ok(tid) => {
      // 添加新特征
      let new_feature = @feature_store.Feature::{
        feature_id: "f2".to_string(),
        feature_name: "name".to_string(),
        feature_type: @feature_store.String,
        status: @feature_store.Active,
        source: @feature_store.Batch,
        description: None,
        default_value: None,
        metadata: Map([]),
        created_at: 0,
        updated_at: 0,
      }

      let add_result = manager.add_feature(tid, new_feature)
      assert_true(add_result is Ok(_))

      // 验证特征已添加
      let table = manager.get_table(tid)
      assert_true(table is Some(_))

      match table {
        Some(t) => assert_eq(t.features.length(), 2)
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_create_feature_view" {
  let config = @feature_store.FeatureStoreConfig::default()
  let manager = @feature_store.FeatureStoreManager::new(config)

  let features = [
    @feature_store.Feature::{
      feature_id: "f1".to_string(),
      feature_name: "age".to_string(),
      feature_type: @feature_store.Int,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: None,
      default_value: None,
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
    @feature_store.Feature::{
      feature_id: "f2".to_string(),
      feature_name: "name".to_string(),
      feature_type: @feature_store.String,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: None,
      default_value: None,
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
  ]

  // 创建表
  let table_id = manager.create_table("users", "user_id", features)
  assert_true(table_id is Ok(_))

  match table_id {
    Ok(tid) => {
      // 创建视图
      let view_id = manager.create_view(
        "user_profile",
        @feature_store.BatchView,
        tid,
        ["age", "name"],
      )
      assert_true(view_id is Ok(_))

      match view_id {
        Ok(vid) => {
          // 验证视图存在
          let view = manager.get_view(vid)
          assert_true(view is Some(_))

          match view {
            Some(v) => {
              assert_eq(v.view_name, "user_profile")
              assert_eq(v.feature_names.length(), 2)
            }
            None => assert_true(false)
          }
        }
        Err(_) => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_cache_hit_rate" {
  let config = @feature_store.FeatureStoreConfig::default()
  let manager = @feature_store.FeatureStoreManager::new(config)

  // 初始命中率应该是 0
  let hit_rate = manager.cache_hit_rate()
  assert_eq(hit_rate, 0.0)
}

///|
test "test_count_aggregator" {
  let aggregator = @feature_store.CountAggregator::new()

  let data = [@realtime_db.Int(1), @realtime_db.Int(2), @realtime_db.Int(3)]

  let result = aggregator.aggregate(data)
  assert_true(result is Ok(_))

  match result {
    Ok(@realtime_db.Int(count)) => assert_eq(count, 3)
    _ => assert_true(false)
  }
}

///|
test "test_sum_aggregator" {
  let aggregator = @feature_store.SumAggregator::new()

  let data = [@realtime_db.Int(10), @realtime_db.Int(20), @realtime_db.Int(30)]

  let result = aggregator.aggregate(data)
  assert_true(result is Ok(_))

  match result {
    Ok(@realtime_db.Int(sum)) => assert_eq(sum, 60)
    _ => assert_true(false)
  }
}

///|
test "test_avg_aggregator" {
  let aggregator = @feature_store.AvgAggregator::new()

  let data = [@realtime_db.Int(10), @realtime_db.Int(20), @realtime_db.Int(30)]

  let result = aggregator.aggregate(data)
  assert_true(result is Ok(_))

  match result {
    Ok(@realtime_db.Float(avg)) => assert_true(avg > 19.9 && avg < 20.1)
    _ => assert_true(false)
  }
}

///|
test "test_max_aggregator" {
  let aggregator = @feature_store.MaxAggregator::new()

  let data = [@realtime_db.Int(10), @realtime_db.Int(30), @realtime_db.Int(20)]

  let result = aggregator.aggregate(data)
  assert_true(result is Ok(_))

  match result {
    Ok(@realtime_db.Int(max)) => assert_eq(max, 30)
    _ => assert_true(false)
  }
}

///|
test "test_min_aggregator" {
  let aggregator = @feature_store.MinAggregator::new()

  let data = [@realtime_db.Int(30), @realtime_db.Int(10), @realtime_db.Int(20)]

  let result = aggregator.aggregate(data)
  assert_true(result is Ok(_))

  match result {
    Ok(@realtime_db.Int(min)) => assert_eq(min, 10)
    _ => assert_true(false)
  }
}

///|
test "test_feature_cache" {
  let cache = @feature_store.FeatureCache::new(100, 300)

  // 创建特征向量
  let vector = @feature_store.FeatureVector::{
    vector_id: "vec1".to_string(),
    entity_id: "entity1".to_string(),
    table_id: "table1".to_string(),
    values: Map([("age", @realtime_db.Int(25))]),
    version: 1,
    timestamp: 0,
    is_valid: true,
  }

  // 写入缓存
  cache.put("key1", vector)

  // 读取缓存
  let cached = cache.get("key1")
  assert_true(cached is Some(_))

  // 删除缓存
  cache.remove("key1")

  let cached2 = cache.get("key1")
  assert_true(cached2 is None)
}

///|
test "test_delete_table" {
  let config = @feature_store.FeatureStoreConfig::default()
  let manager = @feature_store.FeatureStoreManager::new(config)

  let features = [
    @feature_store.Feature::{
      feature_id: "f1".to_string(),
      feature_name: "age".to_string(),
      feature_type: @feature_store.Int,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: None,
      default_value: None,
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
  ]

  // 创建表
  let table_id = manager.create_table("users", "user_id", features)
  assert_true(table_id is Ok(_))

  match table_id {
    Ok(tid) => {
      // 删除表
      let result = manager.delete_table(tid)
      assert_true(result is Ok(_))

      // 验证表已删除
      let table = manager.get_table(tid)
      assert_true(table is None)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "test_delete_view" {
  let config = @feature_store.FeatureStoreConfig::default()
  let manager = @feature_store.FeatureStoreManager::new(config)

  let features = [
    @feature_store.Feature::{
      feature_id: "f1".to_string(),
      feature_name: "age".to_string(),
      feature_type: @feature_store.Int,
      status: @feature_store.Active,
      source: @feature_store.Batch,
      description: None,
      default_value: None,
      metadata: Map([]),
      created_at: 0,
      updated_at: 0,
    },
  ]

  // 创建表
  let table_id = manager.create_table("users", "user_id", features)
  assert_true(table_id is Ok(_))

  match table_id {
    Ok(tid) => {
      // 创建视图
      let view_id = manager.create_view(
        "user_view",
        @feature_store.BatchView,
        tid,
        ["age"],
      )
      assert_true(view_id is Ok(_))

      match view_id {
        Ok(vid) => {
          // 删除视图
          let result = manager.delete_view(vid)
          assert_true(result is Ok(_))

          // 验证视图已删除
          let view = manager.get_view(vid)
          assert_true(view is None)
        }
        Err(_) => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}
