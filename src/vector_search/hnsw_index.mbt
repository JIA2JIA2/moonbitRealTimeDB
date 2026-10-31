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
  /// 伪随机数发生器状态（xorshift32，非零种子）
  mut rng_state : Int
}

///|
pub fn HNSWIndex::new(config : HNSWConfig) -> HNSWIndex {
  HNSWIndex::{
    config,
    nodes: Map([], capacity=0),
    layers: Array(capacity=config.max_layers),
    entry_point: "",
    entry_level: -1,
    rng_state: 0x2545F491,
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
/// xorshift32 伪随机数（返回 [0, 2^31) 内的非负整数）。
/// MoonBit 无内置随机源，用确定性 PRNG 保证可复现。
fn HNSWIndex::next_rand(self : HNSWIndex) -> Int {
  let mut x = self.rng_state
  x = x ^ (x << 13)
  x = x ^ (x >>> 17)
  x = x ^ (x << 5)
  let r = x & 0x7fffffff
  // 种子不能退化为 0（xorshift 的不动点）
  self.rng_state = if r == 0 { 1 } else { r }
  r
}

///|
/// 生成随机层级（几何分布，层级越高概率越小）。
///
/// 按 HNSW 论文的 mL = 1/ln(M) 采样：以 1/M 的概率逐层上升，
/// 等价于 floor(-ln(uniform) * mL) 的几何分布，且受 max_layers
/// 约束。修复前固定返回 4：所有节点都落在同一层，多层结构
/// 名存实亡，内存与插入成本放大 max_layers 倍。
fn HNSWIndex::random_level(self : HNSWIndex) -> Int {
  let m = self.config.m
  let max_level = self.config.max_layers - 1
  let p = 1.0 / m.to_double()
  let mut level = 0
  while level < max_level {
    let r = self.next_rand().to_double() / 2147483647.0
    if r < p {
      level = level + 1
    } else {
      break
    }
  }
  level
}

///|
/// 束搜索：在指定层从入口点出发，维护候选池与最近 ef 个结果，
/// 当候选池中最近的点都比结果集中第 ef 远的点更远时收敛。
/// 返回按距离升序的 (id, 距离) 列表，至多 ef 个。
///
/// 修复前为纯贪心：每轮只扩展当前最优点，best 的邻居全部更远时
/// 立即终止（错过其他分支，召回率显著下降），且无终止上限。
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
  let entry_dist = metric_distance(query, entry_node.vector, metric)
  // 待扩展候选池：(距离, id)
  let pool : Array[(Double, String)] = Array(capacity=0)
  pool.push((entry_dist, entry))
  // 最近 ef 个结果，保持按距离升序
  let top : Array[(Double, String)] = Array(capacity=ef)
  top.push((entry_dist, entry))
  let visited = Set([], capacity=0)
  visited.add(entry)
  while pool.length() > 0 {
    // 取出候选池中距离最小的节点
    let mut best_idx = 0
    let mut i = 1
    while i < pool.length() {
      if pool[i].0 < pool[best_idx].0 {
        best_idx = i
      }
      i = i + 1
    }
    let (dist, current) = pool.remove(best_idx)
    // 收敛：候选最近点已比结果集中第 ef 远更远
    if top.length() >= ef && dist > top[top.length() - 1].0 {
      break
    }
    let current_node = match self.nodes.get(current) {
      Some(n) => n
      None => continue
    }
    if layer >= current_node.neighbors.length() {
      continue
    }
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
      let nd = metric_distance(query, neighbor_node.vector, metric)
      pool.push((nd, neighbor_id))
      // 维护有序的最近 ef 结果集
      if top.length() < ef || nd < top[top.length() - 1].0 {
        top.push((nd, neighbor_id))
        top.sort_by(fn(a, b) { a.0.compare(b.0) })
        if top.length() > ef {
          top.truncate(ef)
        }
      }
    }
  }
  top.map(fn(p) { (p.1, p.0) })
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
  // 先把新节点写入节点表再建立双向连接：
  // connect_at_layer 剪枝时需要在 nodes 表中查询新节点的向量，
  // 否则邻居饱和（>m）时新节点的反向边会被静默剪掉——图越大
  // 越严重，此后插入的节点近乎不可达（系统性漏检）。
  // neighbors 为数组引用，后续逐层更新通过共享引用同步生效。
  self.nodes.set(id, node)
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
