// 实时数据库核心：内存 KV + Watch 订阅 + TTL 过期 + 批量操作。
//
// 特性：
// - set/get/delete/contains/size/keys 基本 CRUD
// - watch(key) / watch_prefix(prefix) / watch_all 三种订阅
// - set 可选 ttl，基于逻辑时钟过期；advance/expire_now 推进与清理
// - mset/mget/mdelete 批量操作
// - unwatch O(1)（订阅者用 Map 索引，非数组 retain）
// - 回调内 unwatch 安全（notify 先收集订阅者 id 再调用）

///|
/// 数据库支持的值类型。
pub(all) enum Value {
  Str(String)
  Int(Int)
  Float(Double)
  Bool(Bool)
  Null
  Arr(Array[Value])
} derive(Eq, Debug)

///|
/// 订阅事件。当数据变更时通知订阅者。
pub enum Event {
  /// 设置键值：键、新值、旧值（键此前不存在或已过期时为 None）。
  Set(String, Value, Value?)
  /// 删除键：键、被删除的值。
  Delete(String, Value)
  /// 键因 TTL 过期：键、过期时的值。
  Expire(String, Value)
}

///|
/// 订阅种类。
priv enum WatchKind {
  Key(String)
  Prefix
  Global
}

///|
struct Watcher {
  kind : WatchKind
  callback : (Event) -> Unit
}

///|
/// 键值条目，含可选过期时间（逻辑时钟单位）。
struct Entry {
  value : Value
  expires_at : Int? // None = 永不过期
}

///|
/// 实时数据库。内存键值存储，支持 watch 订阅、TTL 过期、批量操作。
/// 非线程安全。TTL 基于逻辑时钟：用 advance 推进时间、expire_now 清理过期键。
pub struct DB {
  data : Map[String, Entry]
  all_watchers : Map[Int, Watcher]
  key_watchers : Map[String, Map[Int, Unit]]
  prefix_watchers : Map[Int, String] // id -> prefix
  global_watchers : Map[Int, Unit]
  mut next_id : Int
  mut clock : Int
}

///|
/// 创建空数据库。
pub fn DB::new() -> DB {
  {
    data: Map([]),
    all_watchers: Map([]),
    key_watchers: Map([]),
    prefix_watchers: Map([]),
    global_watchers: Map([]),
    next_id: 0,
    clock: 0,
  }
}

///|
/// 当前逻辑时钟值。
pub fn DB::clock(self : DB) -> Int {
  self.clock
}

///|
/// 推进逻辑时钟 n 个单位，并清理已过期键。返回清理的键数。
pub fn DB::advance(self : DB, n : Int) -> Int {
  self.clock = self.clock + n
  self.expire_now()
}

///|
/// 清理所有已过期键，对每个触发 Expire 事件。返回清理的键数。
pub fn DB::expire_now(self : DB) -> Int {
  let expired : Array[String] = []
  for k, e in self.data {
    if self.is_expired(e) {
      expired.push(k)
    }
  }
  for k in expired {
    guard self.data.get(k) is Some(e) else { continue }
    self.do_expire(k, e.value)
  }
  expired.length()
}

///|
/// 设置键值。ttl>0 时键在 ttl 个逻辑时钟单位后过期。
pub fn DB::set(self : DB, key : String, value : Value, ttl? : Int) -> Unit {
  let old = match self.data.get(key) {
    Some(e) => Some(e.value)
    None => None
  }
  let expires_at = match ttl {
    Some(t) => if t > 0 { Some(self.clock + t) } else { None }
    None => None
  }
  self.data.set(key, { value, expires_at, })
  self.notify(key, Event::Set(key, value, old))
}

///|
/// 获取键值。
pub fn DB::get(self : DB, key : String) -> Value? {
  guard self.data.get(key) is Some(entry) else { return None }
  Some(entry.value)
}

///|
/// 删除键，触发 Delete 事件。返回被删除的值（键不存在时为 None）。
pub fn DB::delete(self : DB, key : String) -> Value? {
  guard self.data.get(key) is Some(entry) else { return None }
  self.data.remove(key)
  self.notify(key, Event::Delete(key, entry.value))
  Some(entry.value)
}

///|
/// 键是否存在。
pub fn DB::contains(self : DB, key : String) -> Bool {
  self.data.contains(key)
}

///|
/// 键值对数量。
pub fn DB::size(self : DB) -> Int {
  self.data.length()
}

///|
/// 所有键。
pub fn DB::keys(self : DB) -> Array[String] {
  let out : Array[String] = []
  for k, _ in self.data {
    out.push(k)
  }
  out
}

///|
/// 批量设置。ttl 透传给每个 set。
pub fn DB::mset(self : DB, pairs : Array[(String, Value)], ttl? : Int) -> Unit {
  for (k, v) in pairs {
    match ttl {
      Some(t) => self.set(k, v, ttl=t)
      None => self.set(k, v)
    }
  }
}

///|
/// 批量获取。
pub fn DB::mget(self : DB, keys : Array[String]) -> Array[Value?] {
  let out : Array[Value?] = []
  for k in keys {
    out.push(self.get(k))
  }
  out
}

///|
/// 批量删除。返回每个键被删除的值（不存在或已过期时为 None）。
pub fn DB::mdelete(self : DB, keys : Array[String]) -> Array[Value?] {
  let out : Array[Value?] = []
  for k in keys {
    out.push(self.delete(k))
  }
  out
}

///|
/// 订阅特定键的变更。返回订阅 id，可用于 unwatch。
pub fn DB::watch(self : DB, key : String, callback : (Event) -> Unit) -> Int {
  let id = self.fresh_id()
  self.all_watchers.set(id, { kind: Key(key), callback, })
  match self.key_watchers.get(key) {
    Some(id_set) => id_set.set(id, ())
    None => self.key_watchers.set(key, Map([(id, ())]))
  }
  id
}

///|
/// 订阅匹配前缀的所有键变更。返回订阅 id。
pub fn DB::watch_prefix(
  self : DB,
  prefix : String,
  callback : (Event) -> Unit,
) -> Int {
  let id = self.fresh_id()
  self.all_watchers.set(id, { kind: Prefix, callback, })
  self.prefix_watchers.set(id, prefix)
  id
}

///|
/// 订阅所有键的变更。返回订阅 id。
pub fn DB::watch_all(self : DB, callback : (Event) -> Unit) -> Int {
  let id = self.fresh_id()
  self.all_watchers.set(id, { kind: Global, callback, })
  self.global_watchers.set(id, ())
  id
}

///|
/// 取消订阅。返回是否成功取消（id 不存在时返回 false）。O(1)。
pub fn DB::unwatch(self : DB, id : Int) -> Bool {
  guard self.all_watchers.get(id) is Some(w) else { return false }
  self.all_watchers.remove(id)
  match w.kind {
    Key(k) =>
      match self.key_watchers.get(k) {
        Some(id_set) => id_set.remove(id)
        None => ()
      }
    Prefix => self.prefix_watchers.remove(id)
    Global => self.global_watchers.remove(id)
  }
  true
}

///|
/// 当前活跃订阅数。
pub fn DB::watcher_count(self : DB) -> Int {
  self.all_watchers.length()
}

// ---- 内部实现 ----

///|
fn DB::fresh_id(self : DB) -> Int {
  let id = self.next_id
  self.next_id = id + 1
  id
}

///|
fn DB::is_expired(self : DB, entry : Entry) -> Bool {
  match entry.expires_at {
    Some(t) => t <= self.clock
    None => false
  }
}

///|
/// 删除已确认过期的键并触发 Expire 事件。
fn DB::do_expire(self : DB, key : String, value : Value) -> Unit {
  self.data.remove(key)
  self.notify(key, Event::Expire(key, value))
}

///|
/// 收集应被通知的订阅者 id（key 订阅者 + 前缀匹配 + 全局）。
/// 返回新数组，保证调用回调时迭代已结束，回调内 unwatch 安全。
fn DB::collect_watchers(self : DB, key : String) -> Array[Int] {
  let ids : Array[Int] = []
  match self.key_watchers.get(key) {
    Some(id_set) =>
      for id, _ in id_set {
        ids.push(id)
      }
    None => ()
  }
  for id, prefix in self.prefix_watchers {
    if str_starts_with(key, prefix) {
      ids.push(id)
    }
  }
  for id, _ in self.global_watchers {
    ids.push(id)
  }
  ids
}

///|
fn DB::notify(self : DB, key : String, event : Event) -> Unit {
  for id in self.collect_watchers(key) {
    guard self.all_watchers.get(id) is Some(w) else { continue }
    (w.callback)(event)
  }
}

///|
/// 字符串前缀匹配（String 无内建 starts_with）。
fn str_starts_with(s : String, prefix : String) -> Bool {
  let pl = prefix.length()
  pl <= s.length() && s[:pl].to_owned() == prefix
}

///|
/// 将 Value 转为可读字符串。
pub fn Value::to_string(self : Value) -> String {
  match self {
    Str(s) => s
    Int(i) => "\{i}"
    Float(f) => "\{f}"
    Bool(true) => "true"
    Bool(false) => "false"
    Null => "null"
    Arr(items) => {
      let mut s = "["
      let mut first = true
      for v in items {
        if first {
          first = false
        } else {
          s = s + ", "
        }
        s = s + v.to_string()
      }
      s + "]"
    }
  }
}

///|
/// 将 Event 转为可读字符串。
pub fn Event::to_string(self : Event) -> String {
  match self {
    Set(k, v, old) =>
      match old {
        Some(o) => "SET \{k} = \{v.to_string()} (was \{o.to_string()})"
        None => "SET \{k} = \{v.to_string()} (new)"
      }
    Delete(k, v) => "DELETE \{k} (was \{v.to_string()})"
    Expire(k, v) => "EXPIRE \{k} (was \{v.to_string()})"
  }
}
