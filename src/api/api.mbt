///|
/// RealTimeDB 统一 API 门面
///
/// 提供所有模块的单一导入入口，使用方式：
/// ```moonbit nocheck
/// let db = @realtime_db_api.DB::new()
/// ```

///|
/// 核心数据库
pub using @realtime_db {type DB, type Value, type Event}

///|
/// 事务支持
pub using @transaction {type TransactionManager}

///|
/// 持久化
pub using @persistence {type WAL, type Snapshot}

///|
/// 监控指标
pub using @monitor {type Monitor}

///|
/// 连接池
pub using @connection {type ConnectionPool}

///|
/// 高性能数据管道
pub using @perf_pipeline {type Pipeline}

///|
/// 二级索引
pub using @index {type IndexManager, type QueryEngine}

///|
/// 实时数据流引擎
pub using @stream_engine {type PipelineManager}

///|
/// 分布式集群
pub using @cluster {
  type NodeManager,
  type ShardManager,
  type RoutingTableService,
}

///|
/// 多租户管理
pub using @multi_tenant {type TenantManager}

///|
/// SQL 查询引擎
pub using @sql_engine {type QueryExecutor, type QueryOptimizer}

///|
/// 数据湖集成
pub using @lake_integration {type LakeSyncer}

///|
/// 跨集群复制
pub using @replication {type ReplicationManager}

///|
/// 特征存储
pub using @feature_store {type FeatureStoreManager}

///|
/// GraphQL 接口
pub using @graphql {type GraphQLService, type GraphQLExecutor}

///|
/// 数据版本控制
pub using @versioning {type VersionManager}

///|
/// 时间序列引擎
pub using @timeseries {type TimeSeriesEngine}
