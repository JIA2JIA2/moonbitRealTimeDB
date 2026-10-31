// B+树索引模块
//
// 提供范围查询 O(log n) 的索引实现
// 支持等值查询、范围查询
//
// 不变量：
// - 叶子节点保存全部条目 (value, keys)，叶子之间通过 next_leaf 串成有序链表
// - 内部节点 entries.length() + 1 == children.length()
// - entries[i] 是 children[i+1] 中最小键的副本（分隔键）
// - 插入采用递归分裂：子节点分裂时把 (分隔键, 新右节点) 冒泡给父节点

///|
/// B+树节点类型
pub(all) enum BTreeNodeType {
  Internal
  Leaf
}

///|
/// B+树节点
pub(all) struct BTreeNode {
  node_type : BTreeNodeType
  mut entries : Array[(@realtime_db.Value, Array[String])]
  mut children : Array[BTreeNode]
  mut next_leaf : BTreeNode?
}

///|
/// B+树索引结构体
pub(all) struct BTreeIndex {
  name : String
  mut root : BTreeNode?
  mut first_leaf : BTreeNode?
  /// 索引的数据键总数
  mut total_entries : Int32
  mut height : Int32
  order : Int32
  mut memory_bytes : Int32
}

///|
pub let default_order : Int32 = 32

///|
pub fn BTreeIndex::new(name : String) -> BTreeIndex {
  BTreeIndex::with_order(name, default_order)
}

///|
pub fn BTreeIndex::with_order(name : String, order : Int32) -> BTreeIndex {
  {
    name,
    root: None,
    first_leaf: None,
    total_entries: 0,
    height: 0,
    order,
    memory_bytes: 0,
  }
}

///|
fn create_leaf_node() -> BTreeNode {
  { node_type: Leaf, entries: [], children: [], next_leaf: None, }
}

///|
fn create_internal_node() -> BTreeNode {
  { node_type: Internal, entries: [], children: [], next_leaf: None, }
}

///|
/// 插入索引条目，返回是否新增了（value, key）对
pub fn BTreeIndex::insert(
  self : BTreeIndex,
  value : @realtime_db.Value,
  key : String,
) -> Bool {
  match self.root {
    None => {
      let leaf = create_leaf_node()
      leaf.entries.push((value, [key]))
      self.root = Some(leaf)
      self.first_leaf = self.root
      self.total_entries = 1
      self.height = 1
      self.memory_bytes = self.memory_bytes + 64
      return true
    }
    Some(root) => {
      let (added, split) = self.insert_rec(root, value, key)
      if !added {
        return false
      }
      match split {
        None => ()
        Some((split_key, right)) => {
          // 根节点分裂，产生新根
          let new_root = create_internal_node()
          new_root.entries.push((split_key, []))
          new_root.children.push(root)
          new_root.children.push(right)
          self.root = Some(new_root)
          self.height = self.height + 1
        }
      }
      self.total_entries = self.total_entries + 1
      self.memory_bytes = self.memory_bytes + 64
      true
    }
  }
}

///|
/// 递归插入。
/// 返回 (added, split)：
/// - added=false 表示 (value, key) 已存在，未做修改
/// - split=None 表示已插入但节点未分裂
/// - split=Some((分隔键, 新右节点)) 表示节点已分裂
fn BTreeIndex::insert_rec(
  self : BTreeIndex,
  node : BTreeNode,
  value : @realtime_db.Value,
  key : String,
) -> (Bool, (@realtime_db.Value, BTreeNode)?) {
  if node.node_type is Leaf {
    return self.insert_into_leaf(node, value, key)
  }

  // 内部节点：选择子树
  let mut pos = 0
  while pos < node.entries.length() {
    let (sep, _) = node.entries[pos]
    if compare_values(value, sep) < 0 {
      break
    }
    pos = pos + 1
  }
  let child = node.children[pos]
  let (added, split) = self.insert_rec(child, value, key)
  if !added {
    return (false, None)
  }
  match split {
    None => (true, None)
    Some((split_key, right)) => {
      // 分隔键插入到 pos 位置，右节点插入到 pos+1
      node.entries.insert(pos, (split_key, []))
      node.children.insert(pos + 1, right)
      if node.entries.length() > self.order {
        (true, Some(self.split_internal(node)))
      } else {
        (true, None)
      }
    }
  }
}

///|
/// 向叶子节点插入有序条目，必要时分裂。
fn BTreeIndex::insert_into_leaf(
  self : BTreeIndex,
  leaf : BTreeNode,
  value : @realtime_db.Value,
  key : String,
) -> (Bool, (@realtime_db.Value, BTreeNode)?) {
  // 定位插入位置
  let mut pos = 0
  while pos < leaf.entries.length() {
    let (v, _) = leaf.entries[pos]
    if compare_values(value, v) <= 0 {
      break
    }
    pos = pos + 1
  }

  if pos < leaf.entries.length() {
    let (v, keys) = leaf.entries[pos]
    if v == value {
      if array_contains(keys, key) {
        // 相同 (value, key) 已存在，幂等返回
        return (false, None)
      }
      keys.push(key)
      return (true, None)
    }
  }

  leaf.entries.insert(pos, (value, [key]))

  if leaf.entries.length() > self.order {
    (true, Some(self.split_leaf_node(leaf)))
  } else {
    (true, None)
  }
}

///|
/// 分裂叶子节点，返回 (新叶子首个键, 新叶子)
fn BTreeIndex::split_leaf_node(
  self : BTreeIndex,
  leaf : BTreeNode,
) -> (@realtime_db.Value, BTreeNode) {
  let _ = self
  let mid = leaf.entries.length() / 2
  let new_leaf = create_leaf_node()

  let old_entries : Array[(@realtime_db.Value, Array[String])] = []
  let mut i = 0
  for (v, keys) in leaf.entries {
    if i >= mid {
      new_leaf.entries.push((v, keys))
    } else {
      old_entries.push((v, keys))
    }
    i = i + 1
  }
  leaf.entries = old_entries

  // 维护叶子链表
  new_leaf.next_leaf = leaf.next_leaf
  leaf.next_leaf = Some(new_leaf)

  let (split_key, _) = new_leaf.entries[0]
  (split_key, new_leaf)
}

///|
/// 分裂内部节点，返回 (上提分隔键, 新右节点)
fn BTreeIndex::split_internal(
  self : BTreeIndex,
  node : BTreeNode,
) -> (@realtime_db.Value, BTreeNode) {
  let _ = self
  let mid = node.entries.length() / 2
  let (up_key, _) = node.entries[mid]

  let new_node = create_internal_node()
  let old_entries : Array[(@realtime_db.Value, Array[String])] = []
  let old_children : Array[BTreeNode] = []

  let mut i = 0
  while i < node.entries.length() {
    if i < mid {
      old_entries.push(node.entries[i])
    } else if i > mid {
      let (v, _) = node.entries[i]
      new_node.entries.push((v, []))
    }
    i = i + 1
  }
  i = 0
  while i < node.children.length() {
    if i <= mid {
      old_children.push(node.children[i])
    } else {
      new_node.children.push(node.children[i])
    }
    i = i + 1
  }

  node.entries = old_entries
  node.children = old_children
  (up_key, new_node)
}

///|
/// 删除索引条目（不做节点合并，删除后节点可能低于半满，不影响正确性）
pub fn BTreeIndex::delete(
  self : BTreeIndex,
  value : @realtime_db.Value,
  key : String,
) -> Bool {
  match self.root {
    None => false
    Some(_) => {
      let leaf = self.find_leaf(value)
      let mut found = false
      let new_entries : Array[(@realtime_db.Value, Array[String])] = []
      for (v, keys) in leaf.entries {
        if v == value {
          let new_keys : Array[String] = []
          for k in keys {
            if k == key {
              found = true
            } else {
              new_keys.push(k)
            }
          }
          if new_keys.length() > 0 {
            new_entries.push((v, new_keys))
          }
        } else {
          new_entries.push((v, keys))
        }
      }

      if found {
        leaf.entries = new_entries
        self.total_entries = self.total_entries - 1
        self.memory_bytes = self.memory_bytes - 64
      }
      found
    }
  }
}

///|
/// 等值查询
pub fn BTreeIndex::query(
  self : BTreeIndex,
  value : @realtime_db.Value,
) -> Array[String] {
  match self.root {
    None => []
    Some(_) => {
      let leaf = self.find_leaf(value)
      for (v, keys) in leaf.entries {
        if v == value {
          return keys.copy()
        }
      }
      []
    }
  }
}

///|
/// 沿分隔键下降到叶子节点
fn BTreeIndex::find_leaf(
  self : BTreeIndex,
  value : @realtime_db.Value,
) -> BTreeNode {
  let node = match self.root {
    Some(r) => r
    None => return create_leaf_node()
  }
  let mut node = node
  while node.node_type is Internal {
    let mut i = 0
    while i < node.entries.length() {
      let (key, _) = node.entries[i]
      if compare_values(value, key) < 0 {
        break
      }
      i = i + 1
    }
    node = node.children[i]
  }
  node
}

///|
/// 范围查询
pub fn BTreeIndex::range_query(
  self : BTreeIndex,
  start : @realtime_db.Value?,
  end : @realtime_db.Value?,
  include_start : Bool?,
  include_end : Bool?,
) -> Array[String] {
  let include_start = match include_start {
    Some(b) => b
    None => true
  }
  let include_end = match include_end {
    Some(b) => b
    None => true
  }
  let result : Array[String] = []

  let first = match start {
    Some(v) => self.find_leaf(v)
    None =>
      match self.first_leaf {
        Some(f) => f
        None => return result
      }
  }

  let mut current : BTreeNode? = Some(first)
  while true {
    match current {
      None => break
      Some(node) => {
        for (v, keys) in node.entries {
          let mut skip = false
          match start {
            Some(sv) => {
              let cmp = compare_values(v, sv)
              if cmp < 0 || (cmp == 0 && !include_start) {
                skip = true
              } else {
                ()
              }
            }
            None => ()
          }
          match end {
            Some(ev) => {
              let cmp = compare_values(v, ev)
              if cmp > 0 {
                return result
              }
              if cmp == 0 && !include_end {
                skip = true
              }
            }
            None => ()
          }
          if !skip {
            for k in keys {
              result.push(k)
            }
          }
        }
        current = node.next_leaf
      }
    }
  }

  result
}

///|
/// 前缀查询（B+树不支持，返回空数组）
pub fn BTreeIndex::prefix_query(
  self : BTreeIndex,
  _prefix : String,
) -> Array[String] {
  let _ = self
  []
}

///|
pub fn BTreeIndex::memory_usage(self : BTreeIndex) -> Int32 {
  self.memory_bytes
}

///|
pub fn BTreeIndex::size(self : BTreeIndex) -> Int32 {
  self.total_entries
}

///|
pub fn BTreeIndex::clear(self : BTreeIndex) -> Unit {
  self.root = None
  self.first_leaf = None
  self.total_entries = 0
  self.height = 0
  self.memory_bytes = 0
}

///|
pub fn BTreeIndex::index_type(self : BTreeIndex) -> IndexType {
  let _ = self
  BTree
}

///|
pub fn BTreeIndex::height(self : BTreeIndex) -> Int32 {
  self.height
}

///|
pub fn BTreeIndex::node_count(self : BTreeIndex) -> Int32 {
  match self.root {
    Some(root) => 1 + self.count_nodes(root)
    None => 0
  }
}

///|
fn BTreeIndex::count_nodes(self : BTreeIndex, node : BTreeNode) -> Int32 {
  let _ = self
  let mut count = 0
  for child in node.children {
    count = count + 1 + self.count_nodes(child)
  }
  count
}

///|
/// 批量操作
pub fn BTreeIndex::batch_update(
  self : BTreeIndex,
  inserts : Array[(@realtime_db.Value, String)],
  deletes : Array[(@realtime_db.Value, String)],
) -> BatchUpdateResult {
  let mut inserted = 0
  let mut deleted = 0
  let mut failed = 0

  for (value, key) in deletes {
    if self.delete(value, key) {
      deleted = deleted + 1
    } else {
      failed = failed + 1
    }
  }
  for (value, key) in inserts {
    if self.insert(value, key) {
      inserted = inserted + 1
    } else {
      failed = failed + 1
    }
  }

  { inserted, deleted, failed, }
}
