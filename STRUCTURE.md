# RealTimeDB 代码结构规范

本文档定义 RealTimeDB 项目的目录结构、包组织、命名规范与开发流程。

## 项目结构

MoonBit 采用「每个目录一个包（package）」的模型。本项目采用「src 全量收纳」的分层布局：
模块根目录只保留工程配置与文档，全部代码（含核心引擎）都位于 `src/` 下：

```
moonbitRealTimeDB/
├── moon.mod                          # 模块定义（名称/版本/依赖）
├── README.md                         # 项目说明
├── AGENTS.md                         # Agent 开发指南
├── STRUCTURE.md                      # 本文件：结构规范
├── LICENSE                           # 许可证
│
└── src/                              # 全部代码统一目录
    ├── core/                         # 核心数据库引擎
    │   ├── moon.pkg                  # 核心包定义（无内部依赖）
    │   ├── realtime_db.mbt           # 核心实现
    │   ├── realtime_db_test.mbt      # 核心黑盒测试
    │   ├── realtime_db_wbtest.mbt    # 核心白盒测试
    │   └── pkg.generated.mbti        # 核心包接口（自动生成）
    │
    ├── api/                          # 【统一 API 门面包】
    │   ├── moon.pkg                  # 依赖所有模块
    │   ├── api.mbt                   # pub using 重导出
    │   └── api_test.mbt              # 门面包可用性测试
    │
    ├── transaction/                  # 事务支持
    ├── persistence/                  # 持久化（WAL + 快照）
    ├── monitor/                      # 监控指标
    ├── connection/                   # 连接池
    ├── perf_pipeline/                # 高性能数据管道
    ├── index/                        # 二级索引
    ├── stream_engine/                # 实时数据流引擎
    ├── cluster/                      # 分布式集群
    ├── multi_tenant/                 # 多租户管理
    ├── sql_engine/                   # SQL 查询引擎
    ├── lake_integration/             # 数据湖集成
    ├── replication/                  # 跨集群复制
    ├── feature_store/                # 特征存储
    ├── graphql/                      # GraphQL 接口
    ├── versioning/                   # 数据版本控制
    ├── timeseries/                   # 时间序列引擎
    ├── vector_search/                # 向量检索引擎
    └── cmd/main/                     # CLI 入口
```

## 包层次

```
moonbit/realtime_db/src/core           ← 核心数据库（无内部依赖）
├── moonbit/realtime_db/src/api        ← 统一门面包（依赖所有模块）
├── moonbit/realtime_db/src/transaction
├── moonbit/realtime_db/src/persistence
├── moonbit/realtime_db/src/monitor
├── moonbit/realtime_db/src/connection
├── moonbit/realtime_db/src/perf_pipeline
├── moonbit/realtime_db/src/index
├── moonbit/realtime_db/src/stream_engine
├── moonbit/realtime_db/src/cluster
├── moonbit/realtime_db/src/multi_tenant
├── moonbit/realtime_db/src/sql_engine
├── moonbit/realtime_db/src/lake_integration
├── moonbit/realtime_db/src/replication
├── moonbit/realtime_db/src/feature_store
├── moonbit/realtime_db/src/graphql
├── moonbit/realtime_db/src/versioning
├── moonbit/realtime_db/src/timeseries
└── moonbit/realtime_db/src/vector_search
```

> 说明：模块根目录不再放置代码包（无根 `moon.pkg`）。
> 核心包路径为 `moonbit/realtime_db/src/core`，包别名默认为 `@core`。

## 模块文件命名规范

每个功能模块目录内采用统一命名：

| 文件名 | 用途 | 必需 |
|--------|------|------|
| `moon.pkg` | 包定义与依赖声明 | 是 |
| `{module}_types.mbt` | 公共类型与错误定义 | 是 |
| `{module}_*.mbt` | 功能实现文件 | 是 |
| `{module}_test.mbt` | 黑盒单元测试 | 是 |
| `{module}_wbtest.mbt` | 白盒单元测试 | 否 |
| `pkg.generated.mbti` | 自动生成接口 | 自动 |

### 命名约定

- **文件名**：snake_case，如 `tenant_manager.mbt`
- **目录名**：snake_case，与包名最后一段一致，如 `multi_tenant`
- **类型名**：PascalCase，如 `TenantManager`
- **函数名**：snake_case，如 `create_tenant`
- **构造函数**：`Type::new()`、`Type::with_config()`
- **工厂函数**：`create_xxx()`
- **常量**：lower_snake_case，如 `default_order`

## 包定义规范（moon.pkg）

统一格式，包含模块说明注释。模块内所有依赖一律写完整 `src` 路径。
依赖核心包时显式指定别名为 `@realtime_db`，使各模块代码中的
`@realtime_db.Value` 等引用保持统一：

```moonbit
// {模块名} - {功能说明}
//
// {补充说明}

import {
  "moonbit/realtime_db/src/core" @realtime_db,
  "moonbit/realtime_db/src/persistence",
}
```

无依赖时（如 `src/core`），保留空 `moon.pkg` 文件与说明注释。
CLI 入口按自身需要取别名，例如 `src/cmd/main` 使用 `@db`。

## 统一门面包（src/api/）

`src/api/` 包通过 `pub using` 重导出所有模块的公共类型，提供单一导入入口：

```moonbit
// src/api/api.mbt
pub using @realtime_db {
  type DB,
  type Value,
  type Event,
}

pub using @index {
  type IndexManager,
  type QueryEngine,
}
```

使用方式：

```moonbit
// 方式一：统一入口
import { "moonbit/realtime_db/src/api" }

let db = @api.DB::new()
let idx = @api.IndexManager::new()

// 方式二：按需导入单个模块
import { "moonbit/realtime_db/src/index" }

let idx = @index.IndexManager::new()
```

> 注意：跨模块存在同名类型（如 `Snapshot`、`Pipeline`、`WindowConfig`），
> 门面包仅重导出核心类型与各模块的主 Manager 类型，避免命名冲突。

## 代码风格

采用 MoonBit block 风格，每个 block 用 `///|` 分隔：

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

## 文档规范

| 文档类型 | 位置 |
|----------|------|
| 需求规格 | `.codeartsdoer/specs/{module}/spec.md` |
| 实现方案 | `.codeartsdoer/specs/{module}/design.md` |
| 任务规划 | `.codeartsdoer/specs/{module}/tasks.md` |

## 开发流程

```
需求规格设计 → 实现方案设计 → 编码任务规划 → 编码实现 → 测试验证
   (spec.md)     (design.md)     (tasks.md)     (.mbt)    (moon test)
```

## 命令参考

```bash
moon fmt            # 格式化代码
moon test           # 运行测试
moon info           # 更新接口文件 .mbti
moon build          # 构建项目
moon check          # 类型检查
moon clean          # 清理构建产物
```
