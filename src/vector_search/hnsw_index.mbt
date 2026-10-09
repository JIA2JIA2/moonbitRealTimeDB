// HNSW 索引实现
//
// 实现多层图结构的近似最近邻检索：插入、检索、删除操作

///|
pub struct HNSWIndex {
  /// 配置
  config : HNSWConfig
  /// 节点表：主键 -> 节点
  mut nodes : Map[String, HNSWNode]
  /// 各层节点 ID 列表
  mut layers : Array[Array[String]]
  /// 顶层入口点
  mut entry_point : String
  /// 入口点层级
  mut entry_level : Int
}

///|
pub fn HNSWIndex::new(config : HNSWConfig) -> HNSWIndex {
  HNSWIndex::{
    config,
    nodes: Map([], capacity=0),
    layers: Array(capacity=config.max_layers),
    entry_point: "",
    entry_level: -1,
  }
}

///|
/// 获取索引中的记录数
pub fn HNSWIndex::size(self : HNSWIndex) -> Int {
  self.nodes.length()
}

///|
/// 统一的图遍历距离：所有度量都转换为「越小越近」，
/// 这样贪心搜索与排序逻辑无需区分相似度/距离。
fn metric_distance(
  a : Array[Double],
  b : Array[Double],
  metric : DistanceMetric,
) -> Double {
  match metric {
    Cosine => 1.0 - DistanceCalculator::cosine_similarity(a, b)
    InnerProduct => -DistanceCalculator::inner_product(a, b)
    Euclidean => DistanceCalculator::euclidean_distance(a, b)
    Manhattan => DistanceCalculator::manhattan_distance(a, b)
  }
}

///|
/// 生成 level+1 个相互独立的空邻居列表
fn empty_neighbors(level : Int) -> Array[Array[String]] {
  let neighbors : Array[Array[String]] = Array(capacity=level + 1)
  let mut i = 0
  while i <= level {
    neighbors.push(Array(capacity=0))
    i = i + 1
  }
  neighbors
}

///|
/// 保证邻居列表至少覆盖到 layer 层（不足时补空数组）
fn ensure_layer(neighbors : Array[Array[String]], layer : Int) -> Unit {
  while neighbors.length() <= layer {
    neighbors.push(Array(capacity=0))
  }
  ()
}

///|
/// 生成随机层级（指数分布，层级越高概率越小）
fn HNSWIndex::random_level(self : HNSWIndex) -> Int {
  // 简化实现：确定性返回固定层级，实际应用应使用指数分布随机数生成器。
  // 无论采用何种采样，层级都必须受 max_layers 约束。
  let level = 4
  let max_level = self.config.max_layers - 1
  if level > max_level {
    max_level
  } else {
    level
  }
}

///|
/// 贪心搜索：在指定层从入口点出发，收集访问过的候选并返回最近的 ef 个
fn HNSWIndex::search_layer(
  self : HNSWIndex,
  query : Array[Double],
  entry : String,
  ef : Int,
  layer : Int,
  metric : DistanceMetric,
) -> Array[(String, Double)] {
  if entry == "" {
    return Array(capacity=0)
  }
  // 入口点可能已被删除，悬空时直接放弃搜索
  let entry_node = match self.nodes.get(entry) {
    Some(n) => n
    None => return Array(capacity=0)
  }
  // 候选池（收集所有访问过的节点）
  let candidates : Array[(String, Double)] = Array(capacity=ef)
  let visited = Set([], capacity=0)
  let mut best = entry
  let mut best_dist = metric_distance(query, entry_node.vector, metric)
  candidates.push((entry, best_dist))
  visited.add(entry)
  // 贪心搜索：每轮走向当前最近节点的更近邻居
  let mut changed = true
  while changed {
    changed = false
    let current = best
    let current_node = match self.nodes.get(current) {
      Some(n) => n
      None => break
    }
    if layer < current_node.neighbors.length() {
      for neighbor_id in current_node.neighbors[layer] {
        if visited.contains(neighbor_id) {
          continue
        }
        visited.add(neighbor_id)
        // 删除后遗留的悬空邻居直接跳过
        let neighbor_node = match self.nodes.get(neighbor_id) {
          Some(n) => n
          None => continue
        }
        let dist = metric_distance(query, neighbor_node.vector, metric)
        candidates.push((neighbor_id, dist))
        if dist < best_dist {
          best = neighbor_id
          best_dist = dist
          changed = true
        }
      }
    }
  }
  // 距离升序，取前 ef 个
  candidates.sort_by(fn(a, b) { a.1.compare(b.1) })
  if candidates.length() > ef {
    candidates.truncate(ef)
  }
  candidates
}

///|
/// 剪枝：候选已按距离升序，保留最近的 m 个邻居
fn prune_neighbors(
  candidates : Array[(String, Double)],
  m : Int,
) -> Array[String] {
  let len = candidates.length()
  if len <= m {
    candidates.map(fn(c) { c.0 })
  } else {
    let result : Array[String] = Array(capacity=m)
    for i in 0..<m {
      result.push(candidates[i].0)
    }
    result
  }
}

///|
/// 将 neighbor_id 加入 target 的 layer 层邻居，超过 m 个时按 target
/// 自身向量重新排序剪枝。返回修改后的节点，由调用方写回节点表。
fn HNSWIndex::connect_at_layer(
  self : HNSWIndex,
  target_ : HNSWNode,
  neighbor_id : String,
  layer : Int,
  metric : DistanceMetric,
) -> HNSWNode {
  let target = target_
  ensure_layer(target.neighbors, layer)
  if !target.neighbors[layer].contains(neighbor_id) {
    target.neighbors[layer].push(neighbor_id)
  }
  let m = self.config.m
  if target.neighbors[layer].length() > m {
    // 以 target 自身为中心对候选邻居重新打分，丢弃悬空引用
    let ranked : Array[(String, Double)] = Array(capacity=0)
    for nid in target.neighbors[layer] {
      match self.nodes.get(nid) {
        Some(n) =>
          ranked.push((nid, metric_distance(target.vector, n.vector, metric)))
        None => ()
      }
    }
    ranked.sort_by(fn(a, b) { a.1.compare(b.1) })
    target.neighbors[layer] = prune_neighbors(ranked, m)
  }
  target
}

///|
/// 插入节点到 HNSW 索引
pub fn HNSWIndex::insert(
  self : HNSWIndex,
  id : String,
  vector : Array[Double],
  metric : DistanceMetric,
) -> Result[Unit, String] {
  match self.config.validate() {
    Ok(_) => ()
    Err(msg) => return Err(msg)
  }
  if self.nodes.contains(id) {
    return Err("Node already exists")
  }
  if vector.length() == 0 {
    return Err("Empty vector")
  }
  // 随机分配层级
  let level = self.random_level()
  let node = HNSWNode::{ id, vector, level, neighbors: empty_neighbors(level), }
  // 如果是第一个节点，直接作为入口点
  if self.entry_level == -1 {
    self.nodes.set(id, node)
    self.entry_point = id
    self.entry_level = level
    for l in 0..<=level {
      if l >= self.layers.length() {
        self.layers.push(Array(capacity=0))
      }
      self.layers[l].push(id)
    }
    return Ok(())
  }
  // 从顶层开始贪心下降到 level+1 层，逐层逼近入口点
  let mut entry = self.entry_point
  let mut l = self.entry_level
  while l >= level + 1 {
    let candidates = self.search_layer(vector, entry, 1, l, metric)
    if candidates.length() > 0 {
      entry = candidates[0].0
    }
    l = l - 1
  }
  // 在 min(level, entry_level) 及以下各层建立双向连接
  let max_l = if level < self.entry_level { level } else { self.entry_level }
  l = 0
  while l <= max_l {
    let candidates = self.search_layer(
      vector,
      entry,
      self.config.ef_construction,
      l,
      metric,
    )
    // 新节点的出边
    let neighbors = prune_neighbors(candidates, self.config.m)
    ensure_layer(node.neighbors, l)
    node.neighbors[l] = neighbors
    // 与每个邻居建立双向连接（节点存的是值类型，修改后必须写回 Map）
    for neighbor_id in neighbors {
      match self.nodes.get(neighbor_id) {
        Some(neighbor) => {
          let updated = self.connect_at_layer(neighbor, id, l, metric)
          self.nodes.set(neighbor_id, updated)
        }
        None => ()
      }
    }
    // 本层最近候选作为下一层的入口
    if candidates.length() > 0 {
      entry = candidates[0].0
    }
    l = l + 1
  }
  // 保存节点
  self.nodes.set(id, node)
  // 更新入口点
  if level > self.entry_level {
    self.entry_point = id
    self.entry_level = level
  }
  // 更新层列表
  for l in 0..<=level {
    if l >= self.layers.length() {
      self.layers.push(Array(capacity=0))
    }
    self.layers[l].push(id)
  }
  Ok(())
}

///|
/// 检索 Top-K 结果，返回 (主键, 距离)，距离越小越相似
pub fn HNSWIndex::search_top_k(
  self : HNSWIndex,
  query : Array[Double],
  k : Int,
  metric : DistanceMetric,
) -> Array[(String, Double)] {
  if self.entry_level == -1 || k <= 0 {
    return Array(capacity=0)
  }
  if self.config.validate() is Err(_) {
    return Array(capacity=0)
  }
  let ef = if self.config.ef_search > k { self.config.ef_search } else { k }
  // 从顶层贪心搜索入口点
  let mut entry = self.entry_point
  let mut l = self.entry_level
  while l >= 1 {
    let candidates = self.search_layer(query, entry, 1, l, metric)
    if candidates.length() > 0 {
      entry = candidates[0].0
    }
    l = l - 1
  }
  // 在第 0 层执行搜索
  let candidates = self.search_layer(query, entry, ef, 0, metric)
  // 取 Top-K
  if candidates.length() > k {
    let result : Array[(String, Double)] = Array(capacity=k)
    for i in 0..<k {
      result.push(candidates[i])
    }
    result
  } else {
    candidates
  }
}

///|
/// 删除节点
pub fn HNSWIndex::delete(
  self : HNSWIndex,
  id : String,
  _metric : DistanceMetric,
) -> Result[Unit, String] {
  let node = match self.nodes.get(id) {
    Some(n) => n
    None => return Err("Node not found")
  }
  // 从各层邻居的列表中反向移除自己（值类型，必须写回 Map）
  for l in 0..<node.neighbors.length() {
    for neighbor_id in node.neighbors[l] {
      match self.nodes.get(neighbor_id) {
        Some(neighbor) =>
          if l < neighbor.neighbors.length() {
            neighbor.neighbors[l] = neighbor.neighbors[l].filter(fn(nid) {
              nid != id
            })
            self.nodes.set(neighbor_id, neighbor)
          }
        None => ()
      }
    }
  }
  // 从节点表中移除
  self.nodes.remove(id)
  // 从层列表中移除
  for l in 0..<=node.level {
    if l < self.layers.length() {
      self.layers[l] = self.layers[l].filter(fn(nid) { nid != id })
    }
  }
  // 更新入口点（如需要）
  if id == self.entry_point {
    if self.nodes.length() > 0 {
      // 找一个新的入口点（最高层的节点）
      let mut new_entry = ""
      let mut max_level = -1
      for (nid, n) in self.nodes {
        if n.level > max_level {
          max_level = n.level
          new_entry = nid
        }
      }
      self.entry_point = new_entry
      self.entry_level = max_level
    } else {
      self.entry_point = ""
      self.entry_level = -1
    }
  }
  Ok(())
}

///|
/// 获取节点
pub fn HNSWIndex::get(self : HNSWIndex, id : String) -> HNSWNode? {
  self.nodes.get(id)
}

///|
/// 检查节点是否存在
pub fn HNSWIndex::contains(self : HNSWIndex, id : String) -> Bool {
  self.nodes.contains(id)
}

///|
/// 获取所有节点 ID
pub fn HNSWIndex::all_ids(self : HNSWIndex) -> Array[String] {
  let result : Array[String] = []
  for id in self.nodes.keys() {
    result.push(id)
  }
  result
}

///|
/// 清空索引
pub fn HNSWIndex::clear(self : HNSWIndex) -> Unit {
  self.nodes = Map([], capacity=0)
  self.layers = Array(capacity=self.config.max_layers)
  self.entry_point = ""
  self.entry_level = -1
}
