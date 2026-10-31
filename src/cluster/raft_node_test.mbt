// Raft 节点黑盒测试
//
// 验证选举多数派按含自身的总节点数计算（peers 不含本节点）。

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
