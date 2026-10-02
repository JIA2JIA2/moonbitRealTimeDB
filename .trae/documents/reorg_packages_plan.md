# 代码路径整理：辅助模块拆分为子包 实施计划

## 现状调研（Repository Research）

主路径 `/home/developer/moonbitRealTimeDB` 当前平铺了 13 个 `.mbt` 文件，核心库与扩展模块混在一起：

- 核心包（根目录，包名 `moonbit/realtime_db`）：`realtime_db.mbt` 及其黑/白盒测试
- 辅助模块（目前都在根包内）：`wal`、`transaction`、`snapshot`、`monitor`、`connection_pool` 各含源码 + 黑盒测试
- 可执行入口：`cmd/main/`（已是独立子包）

依赖关系已确认：
- 只有 `wal.mbt` 引用核心包的 `Value` 类型（`Operation::Set(String, Value)`）
- 5 个辅助模块之间**互不依赖**
- `cmd/main` 只依赖核心包，不受影响
- MoonBit 约定：每个含 `moon.pkg` 的目录是一个独立包；子包路径形如 `moonbit/realtime_db/wal`，可 import 根包（无循环依赖）

## 目标结构

```
moonbit-realtime-db/                    ← 主路径只保留核心 DB + 工程文件
├── realtime_db.mbt                     核心：KV + Watch + TTL（不动）
├── realtime_db_test.mbt
├── realtime_db_wbtest.mbt
├── moon.pkg / moon.mod / pkg.generated.mbti
├── persistence/                        持久化域：WAL + 快照
│   ├── moon.pkg                        import "moonbit/realtime_db"（WAL 需要 Value）
│   ├── wal.mbt / wal_test.mbt
│   └── snapshot.mbt / snapshot_test.mbt
├── transaction/                        事务与锁
│   ├── moon.pkg
│   ├── transaction.mbt / transaction_test.mbt
├── monitor/                            监控指标
│   ├── moon.pkg
│   ├── monitor.mbt / monitor_test.mbt
├── connection/                         连接池
│   ├── moon.pkg
│   ├── connection_pool.mbt / connection_pool_test.mbt
└── cmd/main/                           CLI（不动）
```

说明：WAL 与 Snapshot 同属"持久化/崩溃恢复"域，合并为一个 `persistence` 包（减少目录碎片，与 moonbitlang/core 中 crypto/fs 等按域聚合的风格一致）；其余三个模块内聚性独立，各成一包。

## 实施步骤（依赖顺序）

1. 创建 4 个子目录及各自 `moon.pkg`：
   - `persistence/moon.pkg`：`import { "moonbit/realtime_db" }`
   - `transaction/`、`monitor/`、`connection/`：空 import（纯独立包）
2. 移动源文件与测试文件（`git mv` 语义，保留历史）：
   - `wal*.mbt`、`snapshot*.mbt` → `persistence/`
   - `transaction*.mbt` → `transaction/`
   - `monitor*.mbt` → `monitor/`
   - `connection_pool*.mbt` → `connection/`
3. 更新黑盒测试中的包限定符（MoonBit 黑盒测试按所属包引用）：
   - `@realtime_db.WAL/Lsn/WalEntry/Operation*` → `@persistence.*`
   - `@realtime_db.Snapshot*` → `@persistence.*`
   - `@realtime_db.Transaction*/Lock*/TX_*` → `@transaction.*`
   - `@realtime_db.Metric*/Monitor*/Counter/Gauge/Histogram` → `@monitor.*`
   - `@realtime_db.Connection*/Pool*` → `@connection.*`
   - 核心值类型限定符保持 `@realtime_db.Int(1)` 等不变（如 wal_test 中构造 `Value`）
4. 各包内跨包类型引用确认：`wal.mbt` 中 `Value` 改为 `@realtime_db.Value`（跨包后需限定）
5. `cmd/main` 与根包文件**不改动**
6. 运行 `moon clean && moon info && moon fmt && moon check && moon test` 全量验证

## 验证（Validation）

- `moon check`：0 error、0 warning
- `moon test`：全部 63 个测试通过（核心 36 + persistence 10 + transaction 7 + monitor 5 + connection 5，以实际为准）
- `moon info`：4 个子包各自生成 `pkg.generated.mbti`，根包 `.mbti` 不再出现 WAL/Monitor 等辅助类型
- `moon run cmd/main`：CLI 演示仍正常（仅依赖核心包）

## 风险与处理

- **风险 1：子包别名与预期不符**（如 `@persistence` 是否默认可用）。处理：移动 1 个包后先跑 `moon check` 验证别名规则，再批量处理其余包。
- **风险 2：黑盒测试里同时用两个包的类型**（wal_test 既用 Operation 又用核心 Value）。处理：`persistence/moon.pkg` 引入核心包后，测试中按 `@persistence.` / `@realtime_db.` 分别限定。
- **风险 3：`_build` 缓存旧包结构产生干扰**。处理：先 `moon clean` 再构建。
- 不改变任何函数签名与实现逻辑，纯结构调整；行为零变化。
