// 全文/前缀索引模块
//
// 基于 Trie（前缀树）实现
// 支持前缀查询、精确匹配
//
// 注意：TrieNode 按值存放在 Map 中，递归下降时必须把修改后的子节点
// 通过 `children.set(ch, child)` 写回。

///|
/// Trie 节点
pub(all) struct TrieNode {
  /// 子节点映射：字符 -> 节点
  mut children : Map[Char, TrieNode]
  /// 是否为词的结束节点
  mut is_end : Bool
  /// 该节点对应的键集合（支持相同文本值对应多个数据键）
  mut keys : Array[String]
}

///|
/// 前缀树索引结构体
pub(all) struct FulltextIndex {
  /// 索引名称
  name : String
  /// 根节点
  mut root : TrieNode
  /// 条目总数（按数据键计数）
  mut total_entries : Int32
  /// 内存占用估算
  mut memory_bytes : Int32
}

///|
fn create_trie_node() -> TrieNode {
  { children: Map([]), is_end: false, keys: [], }
}

///|
/// 创建前缀树索引
pub fn FulltextIndex::new(name : String) -> FulltextIndex {
  { name, root: create_trie_node(), total_entries: 0, memory_bytes: 0, }
}

///|
/// 将值规范化为可索引文本
fn value_to_text(value : @realtime_db.Value) -> String {
  match value {
    @realtime_db.Str(s) => s
    _ => value.to_string()
  }
}

///|
/// 插入索引条目，返回是否新增了（文本, key）对
pub fn FulltextIndex::insert(
  self : FulltextIndex,
  value : @realtime_db.Value,
  key : String,
) -> Bool {
  let text = value_to_text(value)
  let chars = text.to_array()
  let added = trie_insert(self.root, chars, 0, key)
  if added {
    self.total_entries = self.total_entries + 1
    self.memory_bytes = self.memory_bytes + text.length() + key.length() + 16
  }
  added
}

///|
/// 递归插入 Trie 节点，返回是否新增了 (文本, key)
fn trie_insert(
  node : TrieNode,
  chars : Array[Char],
  idx : Int32,
  key : String,
) -> Bool {
  if idx >= chars.length() {
    if array_contains(node.keys, key) {
      return false
    }
    node.keys.push(key)
    node.is_end = true
    return true
  }

  let ch = chars[idx]
  match node.children.get(ch) {
    Some(child) => {
      let added = trie_insert(child, chars, idx + 1, key)
      node.children.set(ch, child)
      added
    }
    None => {
      let child = create_trie_node()
      let added = trie_insert(child, chars, idx + 1, key)
      node.children.set(ch, child)
      added
    }
  }
}

///|
/// 删除索引条目，返回是否找到并删除
pub fn FulltextIndex::delete(
  self : FulltextIndex,
  value : @realtime_db.Value,
  key : String,
) -> Bool {
  let text = value_to_text(value)
  let chars = text.to_array()
  let removed = trie_delete(self.root, chars, 0, key)
  if removed {
    self.total_entries = self.total_entries - 1
    self.memory_bytes = self.memory_bytes - text.length() - key.length() - 16
  }
  removed
}

///|
/// 递归删除，并清理不再使用的节点
fn trie_delete(
  node : TrieNode,
  chars : Array[Char],
  idx : Int32,
  key : String,
) -> Bool {
  if idx >= chars.length() {
    if !array_contains(node.keys, key) {
      return false
    }
    let new_keys : Array[String] = []
    for k in node.keys {
      if k != key {
        new_keys.push(k)
      }
    }
    node.keys = new_keys
    if node.keys.length() == 0 {
      node.is_end = false
    }
    return true
  }

  let ch = chars[idx]
  match node.children.get(ch) {
    None => false
    Some(child) => {
      let removed = trie_delete(child, chars, idx + 1, key)
      if removed {
        if !child.is_end &&
          child.keys.length() == 0 &&
          child.children.length() == 0 {
          node.children.remove(ch)
        } else {
          node.children.set(ch, child)
        }
      }
      removed
    }
  }
}

///|
/// 精确查询
pub fn FulltextIndex::query(
  self : FulltextIndex,
  value : @realtime_db.Value,
) -> Array[String] {
  let text = value_to_text(value)
  let chars = text.to_array()
  let mut node = self.root
  for ch in chars {
    match node.children.get(ch) {
      Some(child) => node = child
      None => return []
    }
  }
  if node.is_end {
    node.keys.copy()
  } else {
    []
  }
}

///|
/// 范围查询（Trie 不支持，返回空数组）
pub fn FulltextIndex::range_query(
  self : FulltextIndex,
  _start : @realtime_db.Value?,
  _end : @realtime_db.Value?,
  _include_start : Bool?,
  _include_end : Bool?,
) -> Array[String] {
  let _ = self
  []
}

///|
/// 前缀查询：返回所有以 prefix 开头的值对应的键
pub fn FulltextIndex::prefix_query(
  self : FulltextIndex,
  prefix : String,
) -> Array[String] {
  let chars = prefix.to_array()
  let mut node = self.root
  for ch in chars {
    match node.children.get(ch) {
      Some(child) => node = child
      None => return []
    }
  }
  let result : Array[String] = []
  trie_collect(node, result)
  result
}

///|
/// 收集子树中所有键
fn trie_collect(node : TrieNode, result : Array[String]) -> Unit {
  for k in node.keys {
    result.push(k)
  }
  for _, child in node.children {
    trie_collect(child, result)
  }
}

///|
pub fn FulltextIndex::memory_usage(self : FulltextIndex) -> Int32 {
  self.memory_bytes
}

///|
pub fn FulltextIndex::size(self : FulltextIndex) -> Int32 {
  self.total_entries
}

///|
pub fn FulltextIndex::clear(self : FulltextIndex) -> Unit {
  self.root = create_trie_node()
  self.total_entries = 0
  self.memory_bytes = 0
}

///|
pub fn FulltextIndex::index_type(self : FulltextIndex) -> IndexType {
  let _ = self
  Fulltext
}

///|
/// 获取 Trie 节点数（用于测试与统计）
pub fn FulltextIndex::node_count(self : FulltextIndex) -> Int32 {
  trie_count_nodes(self.root)
}

///|
fn trie_count_nodes(node : TrieNode) -> Int32 {
  let mut count = 1
  for _, child in node.children {
    count = count + trie_count_nodes(child)
  }
  count
}

///|
/// 批量操作
pub fn FulltextIndex::batch_update(
  self : FulltextIndex,
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
