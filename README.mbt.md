# moonbit/realtime_db
实时数据库（RealTimeDB）是一个内存键值存储库，支持 watch 订阅、TTL 过期和批量操作。

## 特性

- **基本 CRUD**：set/get/delete/contains/size/keys
- **订阅机制**：watch(key)、watch_prefix(prefix)、watch_all 三种订阅
- **TTL 过期**：基于逻辑时钟，支持 advance/expire_now
- **批量操作**：mset/mget/mdelete
- **原子操作**：incr/decr
- **其他功能**：touch、persist、clear、setnx
- **O(1) 取消订阅**：订阅者用 Map 索引
- **回调安全**：回调内 unwatch 安全

## 安装

在 `moon.mod` 中添加依赖：

```
import {
  "moonbit/realtime_db@0.1.0",
}
```

## 快速开始

```moonbit nocheck
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
| `set(key, value, ttl?)` | 设置键值 |
| `get(key)` | 获取键值 |
| `delete(key)` | 删除键 |
| `contains(key)` | 检查键是否存在 |
| `size()` | 键值对数量 |
| `keys()` | 所有键 |
| `advance(n)` | 推进逻辑时钟并清理过期键 |

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

## 测试

运行测试：

```bash
moon test
```

测试覆盖：
- 黑盒测试（`realtime_db_test.mbt`）：公共 API 测试
- 白盒测试（`realtime_db_wbtest.mbt`）：内部 helper 边界测试

## 许可证

Apache-2.0