// RealTimeDB: 高可用实时数据库核心模块
//
// 这是一个内存键值存储引擎，支持以下特性：
//
// ## 核心特性
// - 基本 CRUD 操作：set/get/delete/contains/size/keys/values/entries
// - 订阅机制：watch(key)、watch_prefix(prefix)、watch_all 三种订阅模式
// - TTL 过期：基于逻辑时钟，支持 advance/expire_now 推进与清理
// - 批量操作：mset/mget/mdelete
// - 原子操作：incr/decr、touch/persist、setnx
// - O(1) 取消订阅：订阅者用 Map 索引，非数组 retain
// - 回调安全：回调内 unwatch 安全（notify 先收集订阅者 id 再调用）
//
// ## 设计原则
// - 非线程安全：单线程模型，如需并发访问需外部加锁
// - 逻辑时钟：TTL 基于逻辑时钟，用 advance 推进时间、expire_now 清理过期键
// - 事件驱动：所有数据变更都通过事件通知订阅者
//
// ## 使用示例
// ```moonbit
// let db = @realtime_db.DB::new()
// db.set("key", @realtime_db.Str("value"))
// let value = db.get("key") // Some(@realtime_db.Str("value"))
// ```

///|
/// 数据库支持的值类型。
/// 支持多种数据类型，包括基本类型和复合类型。
pub(all) enum Value {
  /// 字符串类型
  Str(String)
  /// 整数类型
  Int(Int)
  /// 浮点数类型
  Float(Double)
  /// 布尔类型
  Bool(Bool)
  /// 空值类型
  Null
  /// 数组类型，元素为 Value
  Arr(Array[Value])
  /// 映射类型，键为字符串，值为 Value
  Map(Map[String, Value])
}

///|
pub impl Eq for Value with fn equal(self, other) -> Bool {
  match (self, other) {
    (Str(a), Str(b)) => a == b
    (Int(a), Int(b)) => a == b
    (Float(a), Float(b)) => a == b
    (Bool(a), Bool(b)) => a == b
    (Null, Null) => true
    (Arr(a), Arr(b)) => a == b
    (Map(a), Map(b)) => a == b
    _ => false
  }
}

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub impl Debug for Value with fn to_repr(self) -> Repr {
  match self {
    Str(s) => Repr::ctor("Str", [(None, Repr(s))])
    Int(i) => Repr::ctor("Int", [(None, Repr(i))])
    Float(f) => Repr::ctor("Float", [(None, Repr(f))])
    Bool(b) => Repr::ctor("Bool", [(None, Repr(b))])
    Null => Repr::ctor("Null", [])
    Arr(items) => Repr::ctor("Arr", [(None, Repr(items))])
    Map(m) => {
      let entries : Array[(Repr, Repr)] = []
      for k, v in m {
        entries.push((Repr(k), Repr(v)))
      }
      Repr::ctor("Map", [(None, Repr::map(entries))])
    }
  }
}

///|
pub extend Value with Debug::{to_repr}

///|
/// 订阅事件。当数据变更时通知订阅者。
/// 事件包含变更类型、键名、新值和旧值（如果有）。
pub(all) enum Event {
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
///
/// ## 示例
/// ```moonbit nocheck
/// let db = @realtime_db.DB::new()
/// db.set("key", @realtime_db.Str("value"))
/// let value = db.get("key")
/// ```
pub struct DB {
  /// 键值存储：键 -> 条目（值 + 过期时间）
  data : Map[String, Entry]
  /// 所有订阅者：订阅者 ID -> 订阅者信息
  all_watchers : Map[Int, Watcher]
  /// 键订阅索引：键 -> 订阅者 ID 集合
  key_watchers : Map[String, Map[Int, Unit]]
  /// 前缀订阅索引：订阅者 ID -> 前缀
  prefix_watchers : Map[Int, String]
  /// 全局订阅者：订阅者 ID -> 单位
  global_watchers : Map[Int, Unit]
  /// 下一个订阅者 ID
  mut next_id : Int
  /// 逻辑时钟值
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
/// 设置键值。
/// ttl>0 时键在 ttl 个逻辑时钟单位后过期。
/// 如果键已存在，会覆盖旧值并触发 Set 事件（包含旧值）。
///
/// ## 参数
/// - key: 键名
/// - value: 值
/// - ttl: 可选的过期时间（逻辑时钟单位）
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("key", @realtime_db.Str("value"))
/// db.set("temp", @realtime_db.Int(42), ttl=10)
/// ```
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
/// 若键已过期（TTL <= clock），自动清理并返回 None，触发 Expire 事件。
///
/// ## 参数
/// - key: 键名
///
/// ## 返回
/// - Some(Value): 键存在且未过期
/// - None: 键不存在或已过期
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("key", @realtime_db.Str("value"))
/// let value = db.get("key") // Some(@realtime_db.Str("value"))
/// ```
pub fn DB::get(self : DB, key : String) -> Value? {
  guard self.data.get(key) is Some(entry) else { return None }
  if self.is_expired(entry) {
    self.do_expire(key, entry.value)
    return None
  }
  Some(entry.value)
}

///|
/// 删除键，触发 Delete 事件。
/// 返回被删除的值（键不存在或已过期时为 None）。
///
/// ## 参数
/// - key: 键名
///
/// ## 返回
/// - Some(Value): 被删除的值
/// - None: 键不存在或已过期
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("key", @realtime_db.Str("value"))
/// let old = db.delete("key") // Some(@realtime_db.Str("value"))
/// ```
pub fn DB::delete(self : DB, key : String) -> Value? {
  guard self.data.get(key) is Some(entry) else { return None }
  if self.is_expired(entry) {
    self.do_expire(key, entry.value)
    return None
  }
  self.data.remove(key)
  self.notify(key, Event::Delete(key, entry.value))
  Some(entry.value)
}

///|
/// 键是否存在。
/// 已过期的键返回 false，并在检查时自动清理。
///
/// ## 参数
/// - key: 键名
///
/// ## 返回
/// - true: 键存在且未过期
/// - false: 键不存在或已过期
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("key", @realtime_db.Str("value"))
/// assert_true(db.contains("key"))
/// ```
pub fn DB::contains(self : DB, key : String) -> Bool {
  guard self.data.get(key) is Some(entry) else { return false }
  if self.is_expired(entry) {
    self.do_expire(key, entry.value)
    return false
  }
  true
}

///|
/// 键值对数量。
/// 过期键在计数前被清理。
///
/// ## 返回
/// 当前数据库中未过期的键值对数量
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("a", @realtime_db.Int(1))
/// db.set("b", @realtime_db.Int(2))
/// assert_eq(db.size(), 2)
/// ```
pub fn DB::size(self : DB) -> Int {
  let _ = self.expire_now()
  self.data.length()
}

///|
/// 所有键。
/// 过期键在收集前被清理。
///
/// ## 返回
/// 当前数据库中所有未过期键的数组
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("a", @realtime_db.Int(1))
/// db.set("b", @realtime_db.Int(2))
/// let keys = db.keys() // ["a", "b"]
/// ```
pub fn DB::keys(self : DB) -> Array[String] {
  let _ = self.expire_now()
  let out : Array[String] = []
  for k, _ in self.data {
    out.push(k)
  }
  out
}

///|
/// 所有值。
/// 过期键在收集前被清理。
///
/// ## 返回
/// 当前数据库中所有未过期值的数组
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("a", @realtime_db.Int(1))
/// db.set("b", @realtime_db.Str("x"))
/// let values = db.values() // [Int(1), Str("x")]
/// ```
pub fn DB::values(self : DB) -> Array[Value] {
  let _ = self.expire_now()
  let out : Array[Value] = []
  for _, e in self.data {
    out.push(e.value)
  }
  out
}

///|
/// 所有键值对。
/// 过期键在收集前被清理。
///
/// ## 返回
/// 当前数据库中所有未过期键值对的数组
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("a", @realtime_db.Int(1))
/// db.set("b", @realtime_db.Str("x"))
/// let entries = db.entries() // [("a", Int(1)), ("b", Str("x"))]
/// ```
pub fn DB::entries(self : DB) -> Array[(String, Value)] {
  let _ = self.expire_now()
  let out : Array[(String, Value)] = []
  for k, e in self.data {
    out.push((k, e.value))
  }
  out
}

///|
/// 批量设置。
/// ttl 透传给每个 set。
///
/// ## 参数
/// - pairs: 键值对数组
/// - ttl: 可选的过期时间（逻辑时钟单位）
///
/// ## 示例
/// ```moonbit nocheck
/// db.mset([("a", @realtime_db.Int(1)), ("b", @realtime_db.Str("x"))])
/// db.mset([("c", @realtime_db.Int(3))], ttl=10)
/// ```
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
///
/// ## 参数
/// - keys: 键名数组
///
/// ## 返回
/// 每个键对应的值（不存在或已过期时为 None）
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("a", @realtime_db.Int(1))
/// db.set("b", @realtime_db.Str("x"))
/// let values = db.mget(["a", "b", "c"]) // [Some(Int(1)), Some(Str("x")), None]
/// ```
pub fn DB::mget(self : DB, keys : Array[String]) -> Array[Value?] {
  let out : Array[Value?] = []
  for k in keys {
    out.push(self.get(k))
  }
  out
}

///|
/// 批量删除。
/// 返回每个键被删除的值（不存在或已过期时为 None）。
///
/// ## 参数
/// - keys: 键名数组
///
/// ## 返回
/// 每个键被删除的值数组
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("a", @realtime_db.Int(1))
/// db.set("b", @realtime_db.Str("x"))
/// let deleted = db.mdelete(["a", "c"]) // [Some(Int(1)), None]
/// ```
pub fn DB::mdelete(self : DB, keys : Array[String]) -> Array[Value?] {
  let out : Array[Value?] = []
  for k in keys {
    out.push(self.delete(k))
  }
  out
}

///|
/// 原子增加计数器。
/// 键不存在或过期时初始化为 0 后再加。
/// 值不是 Int 时返回 false 且不修改。返回是否成功。
///
/// ## 参数
/// - key: 键名
/// - delta: 可选的增量（默认为 1）
///
/// ## 返回
/// - true: 成功增加
/// - false: 值不是 Int 类型
///
/// ## 示例
/// ```moonbit nocheck
/// assert_true(db.incr("counter")) // 从 0 增加到 1
/// assert_true(db.incr("counter", delta=5)) // 从 1 增加到 6
/// ```
pub fn DB::incr(self : DB, key : String, delta? : Int) -> Bool {
  let d = match delta {
    Some(x) => x
    None => 1
  }
  let cur = self.get(key)
  match cur {
    Some(Value::Int(n)) => {
      self.set(key, Value::Int(n + d))
      true
    }
    None => {
      self.set(key, Value::Int(d))
      true
    }
    _ => false
  }
}

///|
/// 原子减少计数器。
/// 等价于 incr(key, -delta)。
///
/// ## 参数
/// - key: 键名
/// - delta: 可选的减量（默认为 1）
///
/// ## 返回
/// - true: 成功减少
/// - false: 值不是 Int 类型
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("counter", @realtime_db.Int(10))
/// assert_true(db.decr("counter")) // 从 10 减少到 9
/// assert_true(db.decr("counter", delta=3)) // 从 9 减少到 6
/// ```
pub fn DB::decr(self : DB, key : String, delta? : Int) -> Bool {
  let d = match delta {
    Some(x) => -x
    None => -1
  }
  self.incr(key, delta=d)
}

///|
/// 重置键的过期时间为 ttl。
/// ttl<=0 表示永不过期。
/// 键不存在或已过期时返回 false。
///
/// ## 参数
/// - key: 键名
/// - ttl: 新的过期时间（逻辑时钟单位）
///
/// ## 返回
/// - true: 成功重置
/// - false: 键不存在或已过期
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("k", @realtime_db.Int(1), ttl=2)
/// assert_true(db.touch("k", 10)) // 重置为 10
/// let _ = db.advance(5) // 未过期
/// assert_eq(db.get("k"), Some(@realtime_db.Int(1)))
/// ```
pub fn DB::touch(self : DB, key : String, ttl : Int) -> Bool {
  guard self.data.get(key) is Some(entry) else { return false }
  if self.is_expired(entry) {
    self.do_expire(key, entry.value)
    return false
  }
  let new_expires = if ttl > 0 { Some(self.clock + ttl) } else { None }
  self.data.set(key, { value: entry.value, expires_at: new_expires, })
  true
}

///|
/// 移除键的 TTL，使其永不过期。
/// 键不存在或已过期时返回 false。
///
/// ## 参数
/// - key: 键名
///
/// ## 返回
/// - true: 成功移除 TTL
/// - false: 键不存在或已过期
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("k", @realtime_db.Int(1), ttl=2)
/// assert_true(db.persist("k"))
/// let _ = db.advance(100) // 远超过原 TTL
/// assert_eq(db.get("k"), Some(@realtime_db.Int(1))) // 仍然存在
/// ```
pub fn DB::persist(self : DB, key : String) -> Bool {
  self.touch(key, 0)
}

///|
/// 清空所有键和订阅者。
/// 对每个存在的键触发 Delete 事件（TTL 永不过期的也触发 Delete，不是 Expire）。
///
/// ## 示例
/// ```moonbit nocheck
/// db.set("a", @realtime_db.Int(1))
/// db.set("b", @realtime_db.Int(2))
/// db.clear()
/// assert_eq(db.size(), 0)
/// ```
pub fn DB::clear(self : DB) -> Unit {
  let ks = self.keys()
  for k in ks {
    let _ = self.delete(k)
  }
}

///|
/// 仅在键不存在（或已过期）时设置值。
/// 返回是否成功设置。
///
/// ## 参数
/// - key: 键名
/// - value: 值
/// - ttl: 可选的过期时间（逻辑时钟单位）
///
/// ## 返回
/// - true: 成功设置
/// - false: 键已存在且未过期
///
/// ## 示例
/// ```moonbit nocheck
/// assert_true(db.setnx("k", @realtime_db.Int(1)))
/// assert_eq(db.get("k"), Some(@realtime_db.Int(1)))
/// assert_false(db.setnx("k", @realtime_db.Int(99))) // 不能覆盖
/// assert_eq(db.get("k"), Some(@realtime_db.Int(1)))
/// ```
pub fn DB::setnx(self : DB, key : String, value : Value, ttl? : Int) -> Bool {
  match self.get(key) {
    Some(_) => false
    None => {
      match ttl {
        Some(t) => self.set(key, value, ttl=t)
        None => self.set(key, value)
      }
      true
    }
  }
}

///|
/// 订阅特定键的变更。
/// 返回订阅 id，可用于 unwatch。
///
/// ## 参数
/// - key: 键名
/// - callback: 事件回调函数
///
/// ## 返回
/// 订阅者 ID
///
/// ## 示例
/// ```moonbit nocheck
/// let events : Array[@realtime_db.Event] = []
/// let id = db.watch("key", fn(e) { events.push(e) })
/// db.set("key", @realtime_db.Str("new")) // 触发回调
/// db.unwatch(id)
/// ```
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
/// 订阅匹配前缀的所有键变更。
/// 返回订阅 id。
///
/// ## 参数
/// - prefix: 前缀
/// - callback: 事件回调函数
///
/// ## 返回
/// 订阅者 ID
///
/// ## 示例
/// ```moonbit nocheck
/// let events : Array[@realtime_db.Event] = []
/// let id = db.watch_prefix("user:", fn(e) { events.push(e) })
/// db.set("user:1", @realtime_db.Int(1)) // 匹配
/// db.set("post:1", @realtime_db.Int(2)) // 不匹配
/// db.unwatch(id)
/// ```
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
/// 订阅所有键的变更。
/// 返回订阅 id。
///
/// ## 参数
/// - callback: 事件回调函数
///
/// ## 返回
/// 订阅者 ID
///
/// ## 示例
/// ```moonbit nocheck
/// let events : Array[@realtime_db.Event] = []
/// let id = db.watch_all(fn(e) { events.push(e) })
/// db.set("key", @realtime_db.Int(1)) // 触发回调
/// db.unwatch(id)
/// ```
pub fn DB::watch_all(self : DB, callback : (Event) -> Unit) -> Int {
  let id = self.fresh_id()
  self.all_watchers.set(id, { kind: Global, callback, })
  self.global_watchers.set(id, ())
  id
}

///|
/// 取消订阅。
/// 返回是否成功取消（id 不存在时返回 false）。O(1)。
///
/// ## 参数
/// - id: 订阅者 ID
///
/// ## 返回
/// - true: 成功取消
/// - false: 订阅者 ID 不存在
///
/// ## 示例
/// ```moonbit nocheck
/// let id = db.watch("key", fn(e) { ... })
/// assert_true(db.unwatch(id))
/// assert_false(db.unwatch(id)) // 重复取消返回 false
/// ```
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
///
/// ## 返回
/// 当前活跃的订阅者数量
///
/// ## 示例
/// ```moonbit nocheck
/// let _ = db.watch("key", fn(e) { ... })
/// assert_eq(db.watcher_count(), 1)
/// ```
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
///
/// ## 示例
/// ```moonbit nocheck
/// assert_eq(@realtime_db.Str("hi").to_string(), "hi")
/// assert_eq(@realtime_db.Int(42).to_string(), "42")
/// assert_eq(@realtime_db.Bool(true).to_string(), "true")
/// ```
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
    Map(m) => {
      let mut s = "{"
      let mut first = true
      for k, v in m {
        if first {
          first = false
        } else {
          s = s + ", "
        }
        s = s + k + "=" + v.to_string()
      }
      s + "}"
    }
  }
}

///|
/// 将 Event 转为可读字符串。
///
/// ## 示例
/// ```moonbit nocheck
/// let db = @realtime_db.DB::new()
/// let events : Array[String] = []
/// let _ = db.watch("k", fn(e) { events.push(e.to_string()) })
/// db.set("k", @realtime_db.Int(1))
/// assert_eq(events[0], "SET k = 1 (new)")
/// ```
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
