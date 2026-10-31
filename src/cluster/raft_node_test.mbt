// Raft 节点黑盒测试
//
// 验证选举多数派按含自身的总节点数计算（peers 不含本节点），
// 以及日志快照压缩方向（移除已快照区间、保留其后新日志）。

///|
/// 4 节点集群多数派为 3：自身 + 1 票不足，自身 + 2 票才当选。
/// 修复前按 peers/2+1 计算多数派为 2，少数票即当选造成脑裂。
test "raft_majority_four_node_cluster" {
  let config = @cluster.ClusterConfig::default()
  let node = @cluster.RaftNode::new("n1", ["n2", "n3", "n4"], config)
  node.start_election()
  assert_true(node.state.is_candidate())
  let granted : @cluster.VoteResponse = {
    term: 0,
    vote_granted: true,
    error: None,
  }
  // 第 1 张选票：共 2 票 < 多数 3 票，不能当选
  assert_false(node.receive_vote_response(granted))
  assert_false(node.state.is_leader())
  // 第 2 张选票：共 3 票达到多数，当选
  assert_true(node.receive_vote_response(granted))
  assert_true(node.state.is_leader())
}

///|
/// 3 节点集群多数派为 2：自身 + 1 票即当选
test "raft_majority_three_node_cluster" {
  let config = @cluster.ClusterConfig::default()
  let node = @cluster.RaftNode::new("n1", ["n2", "n3"], config)
  node.start_election()
  let granted : @cluster.VoteResponse = {
    term: 0,
    vote_granted: true,
    error: None,
  }
  assert_true(node.receive_vote_response(granted))
  assert_true(node.state.is_leader())
}

///|
/// 2 节点集群多数派为 2：被拒绝的选票不能当选，凑满 2 票才当选
test "raft_majority_two_node_cluster" {
  let config = @cluster.ClusterConfig::default()
  let node = @cluster.RaftNode::new("n1", ["n2"], config)
  node.start_election()
  let denied : @cluster.VoteResponse = {
    term: 0,
    vote_granted: false,
    error: None,
  }
  assert_false(node.receive_vote_response(denied))
  assert_false(node.state.is_leader())
  let granted : @cluster.VoteResponse = {
    term: 0,
    vote_granted: true,
    error: None,
  }
  assert_true(node.receive_vote_response(granted))
  assert_true(node.state.is_leader())
}

///|
/// 在 index=2 处快照应移除 e1/e2、保留 e3/e4，last_index 不回退，
/// 快照后追加的日志接在原 last_index 之后。
/// 修复前 truncate(index+1) 删除的是 e3/e4（最新日志），方向相反。
test "raft_snapshot_preserves_entries_after_index" {
  let log = @cluster.RaftLog::new()
  for i in 1..<5 {
    let _ = log.append(@cluster.LogEntry::{
      index: 0,
      term: 1,
      command: "cmd_\{i}",
      data: None,
    })
  }
  log.create_snapshot(2, @realtime_db.Null)
  assert_eq(log.snapshot_index(), 2)
  assert_eq(log.size(), 2)
  assert_eq(log.last_index(), 4)
  assert_true(log.get_entry(3) is Some(_))
  assert_true(log.get_entry(4) is Some(_))
  assert_true(log.get_entry(1) is None)
  assert_true(log.get_entry(2) is None)
  let idx = log.append(@cluster.LogEntry::{
    index: 0,
    term: 1,
    command: "cmd_5",
    data: None,
  })
  assert_eq(idx, 5)
  assert_true(log.get_entry(5) is Some(_))
}

///|
/// 快照点等于最后索引时日志清空，追加仍从正确索引继续
test "raft_snapshot_at_last_index_empties_log" {
  let log = @cluster.RaftLog::new()
  let _ = log.append(@cluster.LogEntry::{
    index: 0,
    term: 1,
    command: "a",
    data: None,
  })
  let _ = log.append(@cluster.LogEntry::{
    index: 0,
    term: 1,
    command: "b",
    data: None,
  })
  log.create_snapshot(2, @realtime_db.Null)
  assert_eq(log.size(), 0)
  assert_eq(log.last_index(), 2)
  let idx = log.append(@cluster.LogEntry::{
    index: 0,
    term: 1,
    command: "c",
    data: None,
  })
  assert_eq(idx, 3)
  assert_true(log.get_entry(3) is Some(_))
}
