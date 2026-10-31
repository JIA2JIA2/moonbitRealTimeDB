// 再平衡模块
//
// 实现再平衡计划、分片迁移、进度跟踪

///|
/// 再平衡计划
pub(all) struct RebalancePlan {
  /// 计划 ID
  plan_id : String
  /// 迁移任务列表
  mut tasks : Array[MigrationTask]
  /// 状态
  mut status : String
  /// 创建时间
  created_at : Int32
  /// 完成时间
  completed_at : Int32
}

///|
/// 迁移任务
pub(all) struct MigrationTask {
  /// 任务 ID
  task_id : String
  /// 分片 ID
  shard_id : String
  /// 源节点
  source_node : String
  /// 目标节点
  target_node : String
  /// 状态
  mut status : String
  /// 进度（0.0-1.0）
  mut progress : Double
  /// 已迁移数据量
  migrated_bytes : Int32
  /// 总数据量
  total_bytes : Int32
  /// 开始时间
  mut started_at : Int32
  /// 完成时间
  mut completed_at : Int32
}

///|
/// 再平衡计划器
pub(all) struct RebalancePlanner {
  /// 节点管理器
  node_manager : NodeManager
  /// 分片管理器
  shard_manager : ShardManager
  /// 再平衡阈值
  threshold : Double
  /// 再平衡计划
  mut current_plan : RebalancePlan?
}

///|
/// 创建再平衡计划器
pub fn RebalancePlanner::new(
  node_manager : NodeManager,
  shard_manager : ShardManager,
) -> RebalancePlanner {
  { node_manager, shard_manager, threshold: 0.2, current_plan: None, }
}

///|
/// 计划再平衡
pub fn RebalancePlanner::plan_rebalance(
  self : RebalancePlanner,
) -> RebalancePlan? {
  // 获取所有活跃节点
  let nodes = self.node_manager.get_active_nodes()
  if nodes.length() < 2 {
    return None
  }

  // 计算平均负载
  let mut total_load = 0.0
  for node in nodes {
    total_load = total_load + node.load_score
  }
  let avg_load = total_load / nodes.length().to_double()

  // 识别过载节点
  let overloaded : Array[NodeInfo] = []
  for node in nodes {
    if node.load_score > avg_load * (1.0 + self.threshold) {
      overloaded.push(node)
    }
  }

  if overloaded.length() == 0 {
    return None
  }

  // 创建迁移任务
  let tasks : Array[MigrationTask] = []
  for node in overloaded {
    // 获取该节点上的分片
    let shards = self.shard_manager.get_shards_by_node(node.id.to_string())
    for shard in shards {
      // 选择目标节点
      let target = self.select_target_node(nodes, node.id.to_string())
      match target {
        Some(target_id) =>
          tasks.push(MigrationTask::{
            task_id: "migration_" +
            shard.id.to_string() +
            "_" +
            target_id.to_string(),
            shard_id: shard.id,
            source_node: node.id,
            target_node: target_id,
            status: "pending".to_string(),
            progress: 0.0,
            migrated_bytes: 0,
            total_bytes: shard.size_bytes,
            started_at: 0,
            completed_at: 0,
          })
        None => ()
      }
    }
  }

  if tasks.length() == 0 {
    return None
  }

  let plan = RebalancePlan::{
    plan_id: "rebalance_0",
    tasks,
    status: "planned".to_string(),
    created_at: 0,
    completed_at: 0,
  }

  self.current_plan = Some({ ..plan, })
  Some(plan)
}

///|
/// 选择目标节点
fn RebalancePlanner::select_target_node(
  self : RebalancePlanner,
  nodes : Array[NodeInfo],
  exclude_node : String,
) -> String? {
  let _ = self
  let mut best_node : String? = None
  let mut min_load = 1.7976931348623157e308

  for node in nodes {
    if node.id.to_string() != exclude_node.to_string() &&
      node.load_score < min_load {
      min_load = node.load_score
      best_node = Some(node.id.to_string())
    }
  }

  best_node
}

///|
/// 分片迁移器
pub(all) struct MigrationExecutor {
  /// 迁移任务
  task : MigrationTask
  /// 分片管理器
  shard_manager : ShardManager
  /// 是否在迁移中
  mut is_migrating : Bool
}

///|
/// 创建分片迁移器
pub fn MigrationExecutor::new(
  task : MigrationTask,
  shard_manager : ShardManager,
) -> MigrationExecutor {
  { task, shard_manager, is_migrating: false, }
}

///|
/// 执行迁移
pub fn MigrationExecutor::execute(
  self : MigrationExecutor,
) -> Result[Unit, ClusterError] {
  if self.is_migrating {
    return Err(Migration_Failed)
  }

  self.is_migrating = true
  self.task.status = "running".to_string()
  self.task.started_at = 0

  // 执行分片迁移
  let result = self.shard_manager.migrate_shard(
    self.task.shard_id,
    self.task.source_node,
    self.task.target_node,
  )

  match result {
    Ok(_) => {
      self.task.status = "completed".to_string()
      self.task.progress = 1.0
      self.task.completed_at = 0
      self.is_migrating = false
      Ok(())
    }
    Err(e) => {
      self.task.status = "failed".to_string()
      self.is_migrating = false
      Err(e)
    }
  }
}

///|
/// 取消迁移
pub fn MigrationExecutor::cancel(self : MigrationExecutor) -> Unit {
  self.is_migrating = false
  self.task.status = "cancelled".to_string()
}

///|
/// 获取进度
pub fn MigrationExecutor::progress(self : MigrationExecutor) -> Double {
  self.task.progress
}

///|
/// 进度跟踪器
pub(all) struct ProgressTracker {
  /// 再平衡计划
  mut plan : RebalancePlan?
  /// 进度回调
  mut progress_callback : ((String, Double) -> Unit)?
}

///|
/// 创建进度跟踪器
pub fn ProgressTracker::new() -> ProgressTracker {
  { plan: None, progress_callback: None, }
}

///|
/// 设置计划
pub fn ProgressTracker::set_plan(
  self : ProgressTracker,
  plan : RebalancePlan,
) -> Unit {
  self.plan = Some(plan)
}

///|
/// 更新进度
pub fn ProgressTracker::update_progress(
  self : ProgressTracker,
  task_id : String,
  progress : Double,
) -> Unit {
  match self.plan {
    Some(plan) =>
      for task in plan.tasks {
        if task.task_id == task_id.to_string() {
          task.progress = progress
          break
        }
      }
    None => ()
  }

  // 调用回调
  match self.progress_callback {
    Some(cb) => cb(task_id, progress)
    None => ()
  }
}

///|
/// 获取整体进度
pub fn ProgressTracker::overall_progress(self : ProgressTracker) -> Double {
  let plan = match self.plan {
    Some(p) => p
    None => return 0.0
  }
  if plan.tasks.length() == 0 {
    return 0.0
  }

  let mut total_progress = 0.0
  for task in plan.tasks {
    total_progress = total_progress + task.progress
  }

  total_progress / plan.tasks.length().to_double()
}

///|
/// 设置进度回调
pub fn ProgressTracker::set_progress_callback(
  self : ProgressTracker,
  callback : (String, Double) -> Unit,
) -> Unit {
  self.progress_callback = Some(callback)
}

///|
/// 创建再平衡计划器
pub fn create_rebalance_planner(
  node_manager : NodeManager,
  shard_manager : ShardManager,
) -> RebalancePlanner {
  RebalancePlanner::new(node_manager, shard_manager)
}

///|
/// 创建分片迁移器
pub fn create_migration_executor(
  task : MigrationTask,
  shard_manager : ShardManager,
) -> MigrationExecutor {
  MigrationExecutor::new(task, shard_manager)
}

///|
/// 创建进度跟踪器
pub fn create_progress_tracker() -> ProgressTracker {
  ProgressTracker::new()
}
