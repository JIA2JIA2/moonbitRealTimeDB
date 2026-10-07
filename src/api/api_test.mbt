///|
/// 统一门面包可用性测试
test "test_facade_db" {
  let db = @api.DB::new()
  db.set("name", @realtime_db.Str("test"))
  db.set("age", @realtime_db.Int(25))
  assert_eq(db.size(), 2)
  assert_eq(db.get("name"), Some(@realtime_db.Str("test")))
}

///|
test "test_facade_managers" {
  let tm = @api.TransactionManager::new(5000)
  let ig = @api.IndexManager::new()
  let pm = @api.PipelineManager::new()
  let tenant_mgr = @api.TenantManager::new()
  let fs_mgr = @feature_store.create_default_feature_store_manager()
  let ts_engine = @timeseries.create_default_timeseries_engine()
  let _ = tm
  let _ = ig
  let _ = pm
  let _ = tenant_mgr
  let _ = fs_mgr
  let _ = ts_engine
}
