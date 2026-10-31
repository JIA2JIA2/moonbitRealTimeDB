# JIA2JIA2/moonbitRealTimeDB

RealTimeDB 是一个高可用实时数据库，基于 MoonBit 语言实现的内存键值存储引擎。

## 特性

### 核心功能
- **基本 CRUD**：set/get/delete/contains/size/keys/values/entries
- **订阅机制**：watch(key)、watch_prefix(prefix)、watch_all 三种订阅
- **TTL 过期**：基于逻辑时钟，支持 advance/expire_now
- **批量操作**：mset/mget/mdelete
- **原子操作**：incr/decr、touch/persist、setnx
- **O(1) 取消订阅**：订阅者用 Map 索引
- **回调安全**：回调内 unwatch 安全

### 高可用功能
- **事务支持**：begin/commit/rollback、死锁检测、超时处理
- **持久化**：WAL 预写日志、快照保存、崩溃恢复
- **监控指标**：QPS、延迟、内存使用、Prometheus 集成
- **连接池**：连接复用、健康检查、空闲超时

### 高性能数据管道
- **零拷贝批量导入**：≥500,000 条/秒
- **流式处理**：P99 延迟 ≤100μs
- **内存池复用**：复用率 ≥80%
- **批量订阅聚合**：100ms 窗口
- **数据压缩**：gzip/zstd/lz4
- **转换管道**：Map/Filter/FlatMap/KeyBy/Reduce
- **优先级调度**：1~10 级优先级
- **并行导入**：1~16 并行度
- **自适应批处理**：动态调整批次大小
- **零拷贝读取**：内存映射、引用返回

### 二级索引
- **Hash 索引**：等值查询 O(1)
- **B+树索引**：范围查询 O(log n)
- **前缀树索引**：前缀匹配 O(m)
- **复合索引**：最左前缀原则
- **索引选择器**：智能选择最优索引
- **查询引擎**：等值/范围/前缀查询
- **统计收集**：基数、碎片率、命中率
- **碎片整理**：定期优化索引存储

### 实时数据流引擎
- **窗口聚合**：滚动/滑动/会话窗口
- **聚合函数**：Count/Sum/Avg/Max/Min
- **过滤订阅**：等值/范围/前缀/正则
- **状态存储**：内存优先、TTL 过期
- **检查点服务**：Exactly-Once 语义
- **水位线服务**：乱序容忍、迟到数据处理
- **背压控制**：流量整形、优先级调度

### 扩展模块
- **分布式集群**：节点管理、分片、路由
- **多租户**：租户隔离与配额
- **SQL 引擎**：语句解析、查询优化与执行；SELECT 支持过滤、投影、排序、
  LIMIT/OFFSET、DISTINCT、GROUP BY/HAVING、聚合函数与 CASE WHEN，DELETE
  支持按 WHERE 条件删除记录
- **数据湖集成**：湖仓同步
- **跨集群复制**：副本管理与同步
- **特征存储**：在线特征读写
- **GraphQL**：GraphQL 查询服务
- **版本控制**：快照、分支、合并、时间点查询
- **时间序列**：降采样、保留策略、连续查询
- **向量检索**：高维向量存储、IVF 倒排索引、元数据过滤、最近邻检索与向量删除

## 安装

核心引擎包位于 `src/core`，在 `moon.mod` 中添加依赖：

```
import {
  "JIA2JIA2/moonbitRealTimeDB/src/core@0.1.0",
}
```

也可以通过统一门面包一次性导入所有模块的公共类型：

```moonbit
import { "JIA2JIA2/moonbitRealTimeDB/src/api" }

let db = @api.DB::new()
let idx = @api.IndexManager::new()
```

## 快速开始

```moonbit
let db = @core.DB::new()

// 基本操作
db.set("key", @core.Str("value"))
let value = db.get("key") // Some(@core.Str("value"))

// 带 TTL 的设置
db.set("temp", @core.Int(42), ttl=10)

// 订阅
let _ = db.watch("key", fn(e) {
  println(e.to_string())
})
db.set("key", @core.Str("new")) // 触发回调

// 推进时间，清理过期键
let _ = db.advance(10)
```

### SQL 查询与删除

先导入 `JIA2JIA2/moonbitRealTimeDB/src/sql_engine`（下例假设 `db` 中已有 `users` 记录）：

```moonbit
let executor = @sql_engine.create_query_executor()
executor.set_db(Some(db))

// SELECT：返回结果行
let select = @sql_engine.parse_sql("SELECT name FROM users WHERE age > 18").unwrap()
let rows = executor.execute_statement(select)

// DELETE：返回被删除记录的键
let delete = @sql_engine.parse_sql("DELETE FROM users WHERE age < 18").unwrap()
let deleted = executor.execute_statement(delete)
```

## API 文档

### 值类型

`Value` 支持多种数据类型：
- `Str(String)` - 字符串
- `Int(Int)` - 整数
- `Float(Double)` - 浮点数
- `Bool(Bool)` - 布尔值
- `Null` - 空值
- `Arr(Array[Value])` - 数组
- `Map(Map[String, Value])` - 映射

### 核心方法

| 方法 | 说明 |
|------|------|
| `DB::new()` | 创建空数据库 |
| `DB::clock()` | 获取当前逻辑时钟值 |
| `DB::set(key, value, ttl?)` | 设置键值 |
| `DB::get(key)` | 获取键值 |
| `DB::delete(key)` | 删除键 |
| `DB::contains(key)` | 检查键是否存在 |
| `DB::size()` | 键值对数量 |
| `DB::keys()` | 所有键 |
| `DB::values()` | 所有值 |
| `DB::entries()` | 所有键值对 |
| `DB::advance(n)` | 推进逻辑时钟并清理过期键 |
| `DB::expire_now()` | 手动清理过期键 |

### 订阅方法

| 方法 | 说明 |
|------|------|
| `watch(key, callback)` | 订阅特定键 |
| `watch_prefix(prefix, callback)` | 订阅前缀匹配的所有键 |
| `watch_all(callback)` | 订阅所有键变更 |
| `unwatch(id)` | 取消订阅 |
| `watcher_count()` | 活跃订阅数 |

### 批量操作

| 方法 | 说明 |
|------|------|
| `mset(pairs, ttl?)` | 批量设置 |
| `mget(keys)` | 批量获取 |
| `mdelete(keys)` | 批量删除 |

### 原子操作

| 方法 | 说明 |
|------|------|
| `incr(key, delta?)` | 原子增加 |
| `decr(key, delta?)` | 原子减少 |
| `touch(key, ttl)` | 重置过期时间 |
| `persist(key)` | 移除 TTL |
| `setnx(key, value, ttl?)` | 仅当键不存在时设置 |
| `clear()` | 清空所有键 |

### 事务支持

| 方法 | 说明 |
|------|------|
| `TransactionManager::new(timeout)` | 创建事务管理器 |
| `TransactionManager::begin(isolation_level, clock)` | 开始新事务 |
| `TransactionManager::commit(tx_id)` | 提交事务 |
| `TransactionManager::rollback(tx_id)` | 回滚事务 |
| `TransactionManager::check_timeouts(clock)` | 检查超时事务 |

### 持久化

| 方法 | 说明 |
|------|------|
| `WAL::new(file_path, threshold)` | 创建 WAL 实例 |
| `WAL::append(operation)` | 追加写入日志 |
| `WAL::sync()` | 同步到磁盘 |
| `WAL::replay(callback)` | 重放日志 |
| `Snapshot::create(data, version)` | 创建快照 |
| `Snapshot::load(data, metadata)` | 加载快照 |

### 监控指标

| 方法 | 说明 |
|------|------|
| `Monitor::new(interval)` | 创建监控器 |
| `Monitor::register(metric)` | 注册指标 |
| `Monitor::update(name, value)` | 更新指标值 |
| `Monitor::expose()` | 暴露 Prometheus 格式 |

### 连接池

| 方法 | 说明 |
|------|------|
| `ConnectionPool::new(max_connections)` | 创建连接池 |
| `ConnectionPool::get(addr, time)` | 获取连接 |
| `ConnectionPool::return_connection(conn)` | 归还连接 |
| `ConnectionPool::reclaim(timeout, time)` | 回收超时连接 |

### 二级索引 API

| 方法 | 说明 |
|------|------|
| `IndexManager::new()` | 创建索引管理器 |
| `IndexManager::create_index(name, paths, type, unique)` | 创建索引 |
| `IndexManager::drop_index(name)` | 删除索引 |
| `IndexManager::rebuild_index(name, mode)` | 重建索引 |
| `QueryEngine::index_query(name, field, value)` | 等值查询 |
| `QueryEngine::index_range(name, field, start, end)` | 范围查询 |
| `QueryEngine::index_prefix(name, field, prefix)` | 前缀查询 |

### 流引擎 API

| 方法 | 说明 |
|------|------|
| `PipelineManager::new()` | 创建管道管理器 |
| `PipelineManager::create_pipeline(name, config)` | 创建管道 |
| `PipelineManager::start_pipeline(name)` | 启动管道 |
| `PipelineManager::stop_pipeline(name)` | 停止管道 |
| `PipelineManager::process_event(name, event)` | 处理事件 |

### SQL 引擎 API

| 方法 | 说明 |
|------|------|
| `parse_sql(sql)` | 解析 SQL 语句，返回 `SqlStatement` |
| `QueryOptimizer::optimize(statement)` | 生成查询计划 |
| `QueryExecutor::set_db(db)` | 绑定待查询的数据库 |
| `QueryExecutor::execute_statement(statement)` | 执行 SELECT / DELETE 语句 |
| `QueryExecutor::execute_select_statement(select)` | 执行 SELECT，返回结果行 |
| `QueryExecutor::execute_delete_statement(delete)` | 执行 DELETE，返回被删除记录的键 |
| `QueryExecutor::execute(plan)` | 按查询计划执行 |

SELECT 已支持 WHERE 过滤、字段投影、ORDER BY、LIMIT/OFFSET、DISTINCT、
GROUP BY/HAVING、聚合函数、LIKE/IN/BETWEEN/IS NULL 与 CASE WHEN；DELETE 支持
`DELETE FROM table [WHERE ...]`。INSERT/UPDATE 目前仅完成语法解析，执行会返回
`Not_Implemented`。

## 测试

```bash
moon test           # 运行全部测试（当前 399 个）
moon coverage analyze > uncovered.log   # 查看未覆盖代码
```

测试按包就近放置：核心引擎测试在 `src/core/realtime_db_test.mbt`（黑盒）与
`src/core/realtime_db_wbtest.mbt`（白盒）；各功能模块在自己的目录下以
`{module}_test.mbt` / `{module}_wbtest.mbt` 命名。

## 架构设计

### 模块结构

```
moonbitRealTimeDB/
├── moon.mod                  # 模块定义（名称/版本/依赖）
└── src/                      # 全部代码统一目录
    ├── core/                 # 核心数据库引擎（realtime_db.mbt + 测试）
    ├── api/                  # 统一 API 门面包
    ├── transaction/          # 事务支持
    ├── persistence/          # 持久化（WAL + 快照）
    ├── monitor/              # 监控指标
    ├── connection/           # 连接池
    ├── perf_pipeline/        # 高性能数据管道
    ├── index/                # 二级索引
    ├── stream_engine/        # 实时数据流引擎
    ├── cluster/              # 分布式集群
    ├── multi_tenant/         # 多租户管理
    ├── sql_engine/           # SQL 查询引擎
    ├── lake_integration/     # 数据湖集成
    ├── replication/          # 跨集群复制
    ├── feature_store/        # 特征存储
    ├── graphql/              # GraphQL 接口
    ├── versioning/           # 数据版本控制
    ├── timeseries/           # 时间序列引擎
    ├── vector_search/        # 向量检索引擎
    └── cmd/main/             # CLI 入口
```

### 统一 API 入口

`src/api/` 包通过 `pub using` 重导出所有模块的公共类型，提供单一导入入口：

```moonbit
import { "JIA2JIA2/moonbitRealTimeDB/src/api" }

let db = @api.DB::new()
let idx = @api.IndexManager::new()
```

> 门面包仅重导出核心类型与各模块的主 Manager 类型，避免跨模块同名类型
> （如 `Snapshot`、`Pipeline`）冲突。需要更多类型时按需直接导入对应模块。

### 设计原则

1. **非线程安全**：单线程模型，如需并发访问需外部加锁
2. **逻辑时钟**：TTL 基于逻辑时钟，用 advance 推进时间、expire_now 清理过期键
3. **事件驱动**：所有数据变更都通过事件通知订阅者
4. **WAL 优先**：所有写操作先写入 WAL，再更新内存

## 开发规范

### 包与文件组织

MoonBit 采用「每个目录一个包」。模块根目录只放工程配置与文档，全部代码
位于 `src/` 下：`src/core` 为核心引擎（无内部依赖），其余为功能模块，
`src/api` 为门面，`src/cmd/main` 为可执行 CLI。

| 文件名 | 用途 |
|--------|------|
| `moon.pkg` | 包定义与依赖声明（每个包必需） |
| `{module}_types.mbt` | 公共类型与错误定义 |
| `{module}_*.mbt` | 功能实现 |
| `{module}_test.mbt` | 黑盒单元测试 |
| `{module}_wbtest.mbt` | 白盒单元测试（可选） |
| `pkg.generated.mbti` | 自动生成的接口文件，勿手改 |

命名约定：目录/文件名用 snake_case 并与包名末段一致（如 `multi_tenant`）；
类型 PascalCase（`TenantManager`）；函数 snake_case（`create_tenant`）；
构造函数 `Type::new()`，工厂函数 `create_xxx()`。

### moon.pkg 依赖约定

模块内依赖一律写完整 `src` 路径。依赖核心包时显式指定别名 `@realtime_db`，
使各模块代码中的 `@realtime_db.Value` 等引用保持统一：

```moonbit
import {
  "JIA2JIA2/moonbitRealTimeDB/src/core" @realtime_db,
  "JIA2JIA2/moonbitRealTimeDB/src/persistence",
}
```

无依赖的包（如 `src/core`）保留空 `moon.pkg`。

### 代码风格

代码按 block 组织，每个 block 以 `///|` 分隔，block 之间顺序无关：

```moonbit
///|
/// 类型文档注释
pub(all) struct MyType {
  /// 字段文档
  field : String
}

///|
/// 函数文档注释
pub fn MyType::my_method(self : MyType, param : String) -> Result[String, MyError] {
  // 实现
}
```

### 常用命令

```bash
moon check          # 类型检查（CI 门禁，要求 0 error / 0 warning）
moon fmt            # 格式化代码（moon fmt --check 只检查不改动）
moon test           # 运行测试
moon info           # 重新生成 pkg.generated.mbti
moon build          # 构建
moon run src/cmd/main -- "help"   # 运行 CLI（每条命令作为一个带引号参数）
```

改动后收尾流程：`moon info && moon fmt`，检查 `.mbti` 差异是否符合预期，
再跑 `moon test`。影响快照输出时用 `moon test --update` 刷新快照。

## 性能指标

| 指标 | 目标值 |
|------|--------|
| 读写延迟 | ≤ 1ms（P99） |
| 事务提交延迟 | ≤ 5ms（P99） |
| 吞吐量 | ≥ 100,000 QPS |
| 批量导入 | ≥ 500,000 条/秒 |
| 流式处理延迟 | ≤ 100μs（P99） |
| 索引查询延迟 | ≤ 100μs（P99） |
| 可用性 | ≥ 99.99% |
| RPO | ≤ 1s |
| RTO | ≤ 30s |

## 许可证

Apache-2.0