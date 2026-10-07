# moonbit/realtime_db

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

## 安装

在 `moon.mod` 中添加依赖：

```
import {
  "moonbit/realtime_db@0.1.0",
}
```

## 快速开始

```moonbit
let db = @realtime_db.DB::new()

// 基本操作
db.set("key", @realtime_db.Str("value"))
let value = db.get("key") // Some(@realtime_db.Str("value"))

// 带 TTL 的设置
db.set("temp", @realtime_db.Int(42), ttl=10)

// 订阅
let _ = db.watch("key", fn(e) {
  println(e.to_string())
})
db.set("key", @realtime_db.Str("new")) // 触发回调

// 推进时间，清理过期键
let _ = db.advance(10)
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

## 测试

运行测试：

```bash
moon test
```

测试覆盖：
- 黑盒测试（`realtime_db_test.mbt`）：公共 API 测试
- 白盒测试（`realtime_db_wbtest.mbt`）：内部 helper 边界测试
- 事务测试（`transaction_wbtest.mbt`）：事务模块测试
- WAL 测试（`wal_wbtest.mbt`）：WAL 模块测试
- 快照测试（`snapshot_wbtest.mbt`）：快照模块测试
- 监控测试（`monitor_wbtest.mbt`）：监控模块测试
- 连接池测试（`connection_pool_wbtest.mbt`）：连接池模块测试
- 数据管道测试（`perf_pipeline_test.mbt`）：性能管道测试
- 索引测试（`index_test.mbt`）：二级索引测试
- 流引擎测试（`stream_engine_test.mbt`）：流引擎测试

## 架构设计

### 模块结构

```
moonbitRealTimeDB/
├── realtime_db.mbt           # 核心数据库引擎（根包）
├── moon.mod / moon.pkg       # 模块与包定义
└── src/                      # 功能模块统一目录
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
    └── cmd/main/             # CLI 入口
```

### 统一 API 入口

`src/api/` 包重导出所有模块的公共类型，提供单一导入入口：

```moonbit
import { "moonbit/realtime_db/src/api" }

let db = @api.DB::new()
let idx = @api.IndexManager::new()
```

详见 [STRUCTURE.md](STRUCTURE.md) 代码结构规范。

### 设计原则

1. **非线程安全**：单线程模型，如需并发访问需外部加锁
2. **逻辑时钟**：TTL 基于逻辑时钟，用 advance 推进时间、expire_now 清理过期键
3. **事件驱动**：所有数据变更都通过事件通知订阅者
4. **WAL 优先**：所有写操作先写入 WAL，再更新内存

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