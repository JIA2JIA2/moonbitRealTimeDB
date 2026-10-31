// 元数据过滤表达式黑盒测试
//
// 覆盖 FilterExpr 全部操作符求值语义，以及精确/近似检索链路
// 的端到端过滤行为（含 over-fetch 与回退路径）。

///|
/// 构造测试元数据
fn test_meta(
  pairs : Array[(String, @realtime_db.Value)],
) -> Map[String, @realtime_db.Value] {
  let m : Map[String, @realtime_db.Value] = Map([])
  for (k, v) in pairs {
    m.set(k, v)
  }
  m
}

///|
/// 写入一条带元数据的向量记录
fn upsert_vec(
  mgr : @vector_search.CollectionManager,
  col : String,
  tenant : String,
  key : String,
  vector : Array[Double],
  metadata : Map[String, @realtime_db.Value],
) -> Bool {
  mgr.upsert_record(col, tenant, @vector_search.VectorRecord::{
    primary_key: key,
    vector,
    metadata,
    version: 1,
    updated_at: 0,
  })
}

///|
test "filter_expr_eq" {
  let meta = test_meta([
    ("cat", @realtime_db.Str("news")),
    ("rank", @realtime_db.Int(7)),
  ])
  assert_true(@vector_search.Eq("cat", @realtime_db.Str("news")).evaluate(meta))
  assert_false(
    @vector_search.Eq("cat", @realtime_db.Str("sports")).evaluate(meta),
  )
  // 类型不匹配一律不命中
  assert_false(@vector_search.Eq("rank", @realtime_db.Str("7")).evaluate(meta))
  assert_false(
    @vector_search.Eq("rank", @realtime_db.Float(7.0)).evaluate(meta),
  )
  // 字段缺失不命中
  assert_false(@vector_search.Eq("missing", @realtime_db.Int(0)).evaluate(meta))
}

///|
test "filter_expr_numeric_range" {
  let meta = test_meta([
    ("age", @realtime_db.Int(30)),
    ("score", @realtime_db.Float(0.85)),
    ("name", @realtime_db.Str("x")),
  ])
  assert_true(@vector_search.Gt("age", 29.5).evaluate(meta))
  assert_false(@vector_search.Gt("age", 30.0).evaluate(meta))
  assert_true(@vector_search.Gte("age", 30.0).evaluate(meta))
  assert_true(@vector_search.Lt("age", 30.5).evaluate(meta))
  assert_false(@vector_search.Lt("age", 30.0).evaluate(meta))
  assert_true(@vector_search.Lte("age", 30.0).evaluate(meta))
  // Float 字段同样参与数值比较
  assert_true(@vector_search.Gte("score", 0.85).evaluate(meta))
  assert_true(@vector_search.Lt("score", 0.9).evaluate(meta))
  // 非数值字段不匹配
  assert_false(@vector_search.Gt("name", 0.0).evaluate(meta))
  // 字段缺失不匹配
  assert_false(@vector_search.Lte("missing", 100.0).evaluate(meta))
}

///|
test "filter_expr_exists" {
  let meta = test_meta([("a", @realtime_db.Int(1)), ("n", @realtime_db.Null)])
  assert_true(@vector_search.Exists("a").evaluate(meta))
  // Null 值字段也算存在
  assert_true(@vector_search.Exists("n").evaluate(meta))
  assert_false(@vector_search.Exists("missing").evaluate(meta))
}

///|
test "filter_expr_logic_combinators" {
  let meta = test_meta([
    ("cat", @realtime_db.Str("news")),
    ("age", @realtime_db.Int(30)),
  ])
  // And：全部子表达式为真
  assert_true(
    @vector_search.And([
      @vector_search.Eq("cat", @realtime_db.Str("news")),
      @vector_search.Gt("age", 20.0),
    ]).evaluate(meta),
  )
  assert_false(
    @vector_search.And([
      @vector_search.Eq("cat", @realtime_db.Str("news")),
      @vector_search.Gt("age", 40.0),
    ]).evaluate(meta),
  )
  // 空 And 视为真
  assert_true(@vector_search.And([]).evaluate(meta))
  // Or：任一子表达式为真
  assert_true(
    @vector_search.Or([
      @vector_search.Eq("cat", @realtime_db.Str("sports")),
      @vector_search.Gt("age", 20.0),
    ]).evaluate(meta),
  )
  assert_false(
    @vector_search.Or([
      @vector_search.Eq("cat", @realtime_db.Str("sports")),
      @vector_search.Gt("age", 40.0),
    ]).evaluate(meta),
  )
  // 空 Or 视为假
  assert_false(@vector_search.Or([]).evaluate(meta))
  // Not：取反
  let not_sports = @vector_search.Not(
    @vector_search.Eq("cat", @realtime_db.Str("sports")),
  )
  assert_true(not_sports.evaluate(meta))
  let not_news = @vector_search.Not(
    @vector_search.Eq("cat", @realtime_db.Str("news")),
  )
  assert_false(not_news.evaluate(meta))
  // 嵌套组合：(cat = news OR age > 40) AND NOT(cat = sports)
  let combined = @vector_search.And([
    @vector_search.Or([
      @vector_search.Eq("cat", @realtime_db.Str("news")),
      @vector_search.Gt("age", 40.0),
    ]),
    @vector_search.Not(@vector_search.Eq("cat", @realtime_db.Str("sports"))),
  ])
  assert_true(combined.evaluate(meta))
}

///|
/// 精确检索端到端：filter 只保留匹配记录，复合过滤与空结果语义
test "search_exact_with_metadata_filter" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "col",
    2,
    @vector_search.Cosine,
    @vector_search.Exact,
    None,
    Array(capacity=0),
    "t1",
  )
  let _ = upsert_vec(
    mgr,
    "col",
    "t1",
    "a1",
    [1.0, 0.0],
    test_meta([("cat", @realtime_db.Str("a"))]),
  )
  let _ = upsert_vec(
    mgr,
    "col",
    "t1",
    "a2",
    [0.9, 0.1],
    test_meta([("cat", @realtime_db.Str("a")), ("score", @realtime_db.Int(90))]),
  )
  let _ = upsert_vec(
    mgr,
    "col",
    "t1",
    "b1",
    [0.0, 1.0],
    test_meta([("cat", @realtime_db.Str("b"))]),
  )
  let _ = upsert_vec(
    mgr,
    "col",
    "t1",
    "b2",
    [0.1, 0.9],
    test_meta([("cat", @realtime_db.Str("b")), ("score", @realtime_db.Int(50))]),
  )
  let engine = @vector_search.SearchEngine::new(mgr)
  // 只保留 cat=a：4 条记录过滤后剩 2 条
  let hits = engine.search_exact(
    "col",
    "t1",
    [1.0, 0.0],
    4,
    filter=@vector_search.Eq("cat", @realtime_db.Str("a")),
  )
  assert_eq(hits.length(), 2)
  for h in hits {
    assert_true(h.metadata.get("cat") is Some(@realtime_db.Str("a")))
  }
  // 复合过滤：cat=a 且 score >= 90，仅 a2 命中
  let hits2 = engine.search_exact(
    "col",
    "t1",
    [1.0, 0.0],
    4,
    filter=@vector_search.And([
      @vector_search.Eq("cat", @realtime_db.Str("a")),
      @vector_search.Gte("score", 90.0),
    ]),
  )
  assert_eq(hits2.length(), 1)
  assert_eq(hits2[0].primary_key, "a2")
  // 完全不命中返回空数组
  let hits3 = engine.search_exact(
    "col",
    "t1",
    [1.0, 0.0],
    4,
    filter=@vector_search.Eq("cat", @realtime_db.Str("zzz")),
  )
  assert_eq(hits3.length(), 0)
}

///|
/// 近似检索端到端：over-fetch 后过滤截断，命中不足时回退精确
test "search_approximate_with_metadata_filter" {
  let mgr = @vector_search.CollectionManager::new()
  mgr.create_collection(
    "col",
    2,
    @vector_search.Cosine,
    @vector_search.Approximate,
    None,
    Array(capacity=0),
    "t1",
  )
  // 12 条记录：6 条 cat=a 靠近查询向量，6 条 cat=b 远离
  let mut i = 0
  while i < 6 {
    let offset = i.to_double() * 0.01
    let _ = upsert_vec(
      mgr,
      "col",
      "t1",
      "a\{i}",
      [1.0 - offset, offset],
      test_meta([("cat", @realtime_db.Str("a"))]),
    )
    let _ = upsert_vec(
      mgr,
      "col",
      "t1",
      "b\{i}",
      [offset, 1.0 - offset],
      test_meta([("cat", @realtime_db.Str("b"))]),
    )
    i = i + 1
  }
  let engine = @vector_search.SearchEngine::new(mgr)
  // over-fetch 路径：top_k=2 → fetch_k=8（12 条记录足够），过滤后截断
  let hits = engine.search_approximate(
    "col",
    "t1",
    [1.0, 0.0],
    2,
    filter=@vector_search.Eq("cat", @realtime_db.Str("a")),
  )
  assert_eq(hits.length(), 2)
  for h in hits {
    assert_true(h.metadata.get("cat") is Some(@realtime_db.Str("a")))
  }
  // 回退路径：top_k=10 → fetch_k=40 超过记录总数 12，回退精确检索，
  // 返回全部 6 条 cat=a 命中
  let hits2 = engine.search_approximate(
    "col",
    "t1",
    [1.0, 0.0],
    10,
    filter=@vector_search.Eq("cat", @realtime_db.Str("a")),
  )
  assert_eq(hits2.length(), 6)
  for h in hits2 {
    assert_true(h.metadata.get("cat") is Some(@realtime_db.Str("a")))
  }
}
