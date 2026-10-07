///|
/// 实时数据库 CLI。
/// - 无参数：运行内置演示。
/// - `moon run cmd/main -- "cmd1" "cmd2" ...`：逐条执行命令。
///
/// 命令：
///   set <k> <v> [ttl]   setnx <k> <v> [ttl]
///   get <k>   del <k>   incr <k> [delta]   decr <k> [delta]
///   keys   size   clock   entries   snapshot   clear
///   touch <k> <ttl>   persist <k>
///   watch <k>   watchp <prefix>   watchall   unwatch <id>
///   advance <n>   expire   help   quit
fn main {
  let args = @env.args()
  let cmds : Array[String] = []
  for i, a in args {
    if i > 0 {
      cmds.push(a)
    }
  }
  if cmds.length() == 0 {
    run_demo()
    return
  }
  let db = @db.DB::new()
  println("=== MoonBit 实时数据库 REPL ===")
  for cmd in cmds {
    println("> \{cmd}")
    let cont = run_command(db, cmd)
    if !cont {
      break
    }
  }
  println("=== 结束 ===")
}

///|
/// 执行单条命令。返回 false 表示 quit。
fn run_command(db : @db.DB, line : String) -> Bool {
  let tokens = tokenize(line)
  if tokens.length() == 0 {
    return true
  }
  match tokens[0] {
    "set" => {
      guard tokens.length() >= 3 else {
        println("  usage: set <key> <value> [ttl]")
        return true
      }
      let k = tokens[1]
      let v = parse_value(tokens[2])
      if tokens.length() >= 4 {
        db.set(k, v, ttl=parse_int_or(tokens[3], 0))
      } else {
        db.set(k, v)
      }
      println("  ok")
      true
    }
    "get" => {
      guard tokens.length() >= 2 else {
        println("  usage: get <key>")
        return true
      }
      match db.get(tokens[1]) {
        Some(v) => println("  \{v.to_string()}")
        None => println("  (nil)")
      }
      true
    }
    "del" => {
      guard tokens.length() >= 2 else {
        println("  usage: del <key>")
        return true
      }
      let _ = db.delete(tokens[1])
      println("  ok")
      true
    }
    "keys" => {
      for k in db.keys() {
        println("  \{k}")
      }
      true
    }
    "size" => {
      println("  \{db.size()}")
      true
    }
    "clock" => {
      println("  \{db.clock()}")
      true
    }
    "watch" => {
      guard tokens.length() >= 2 else {
        println("  usage: watch <key>")
        return true
      }
      let id = db.watch(tokens[1], fn(e) {
        println("  >> [watch] \{e.to_string()}")
      })
      println("  watcher#\{id} watching \{tokens[1]}")
      true
    }
    "watchp" => {
      guard tokens.length() >= 2 else {
        println("  usage: watchp <prefix>")
        return true
      }
      let id = db.watch_prefix(tokens[1], fn(e) {
        println("  >> [prefix] \{e.to_string()}")
      })
      println("  watcher#\{id} watching prefix \{tokens[1]}")
      true
    }
    "watchall" => {
      let id = db.watch_all(fn(e) { println("  >> [global] \{e.to_string()}") })
      println("  watcher#\{id} watching all")
      true
    }
    "unwatch" => {
      guard tokens.length() >= 2 else {
        println("  usage: unwatch <id>")
        return true
      }
      let id = parse_int_or(tokens[1], -1)
      println("  unwatch: \{db.unwatch(id)}")
      true
    }
    "advance" => {
      guard tokens.length() >= 2 else {
        println("  usage: advance <n>")
        return true
      }
      let expired = db.advance(parse_int_or(tokens[1], 0))
      println("  clock=\{db.clock()}, expired=\{expired}")
      true
    }
    "expire" => {
      println("  expired=\{db.expire_now()}")
      true
    }
    "snapshot" => {
      println(
        "  size=\{db.size()}, watchers=\{db.watcher_count()}, clock=\{db.clock()}",
      )
      for k in db.keys() {
        match db.get(k) {
          Some(v) => println("    \{k} = \{v.to_string()}")
          None => ()
        }
      }
      true
    }
    "entries" => {
      for (k, v) in db.entries() {
        println("    \{k} = \{v.to_string()}")
      }
      true
    }
    "setnx" => {
      guard tokens.length() >= 3 else {
        println("  usage: setnx <key> <value> [ttl]")
        return true
      }
      let k = tokens[1]
      let v = parse_value(tokens[2])
      let ok = if tokens.length() >= 4 {
        db.setnx(k, v, ttl=parse_int_or(tokens[3], 0))
      } else {
        db.setnx(k, v)
      }
      println("  setnx=\{ok}")
      true
    }
    "incr" => {
      guard tokens.length() >= 2 else {
        println("  usage: incr <key> [delta]")
        return true
      }
      let ok = if tokens.length() >= 3 {
        db.incr(tokens[1], delta=parse_int_or(tokens[2], 1))
      } else {
        db.incr(tokens[1])
      }
      println("  incr=\{ok}")
      true
    }
    "decr" => {
      guard tokens.length() >= 2 else {
        println("  usage: decr <key> [delta]")
        return true
      }
      let ok = if tokens.length() >= 3 {
        db.decr(tokens[1], delta=parse_int_or(tokens[2], 1))
      } else {
        db.decr(tokens[1])
      }
      println("  decr=\{ok}")
      true
    }
    "touch" => {
      guard tokens.length() >= 3 else {
        println("  usage: touch <key> <ttl>")
        return true
      }
      println("  touch=\{db.touch(tokens[1], parse_int_or(tokens[2], 0))}")
      true
    }
    "persist" => {
      guard tokens.length() >= 2 else {
        println("  usage: persist <key>")
        return true
      }
      println("  persist=\{db.persist(tokens[1])}")
      true
    }
    "clear" => {
      db.clear()
      println("  ok")
      true
    }
    "help" => {
      print_help()
      true
    }
    "quit" => {
      println("  bye")
      false
    }
    cmd => {
      println("  unknown command: \{cmd} (try help)")
      true
    }
  }
}

///|
/// 按空格切分命令行，去空 token。
fn tokenize(line : String) -> Array[String] {
  let parts : Array[String] = []
  for p in line.split(" ") {
    let t = p.trim().to_owned()
    if t.length() > 0 {
      parts.push(t)
    }
  }
  parts
}

///|
/// 解析字符串为 Value：Int > Float > Bool > Null > Str。
fn parse_value(s : String) -> @db.Value {
  let sv = s.to_string_view()
  try {
    let i = @string.parse_int(sv)
    return @db.Int(i)
  } catch {
    _ => ()
  }
  try {
    let f = @string.parse_double(sv)
    return @db.Float(f)
  } catch {
    _ => ()
  }
  if s == "true" {
    return @db.Bool(true)
  }
  if s == "false" {
    return @db.Bool(false)
  }
  if s == "null" {
    return @db.Null
  }
  @db.Str(s)
}

///|
/// 解析 Int，失败返回 default。
fn parse_int_or(s : String, default : Int) -> Int {
  @string.parse_int(s.to_string_view()) catch {
    _ => default
  }
}

///|
fn print_help() -> Unit {
  println("  commands:")
  println("    set <k> <v> [ttl]   setnx <k> <v> [ttl]")
  println("    get <k>   del <k>   incr <k> [delta]   decr <k> [delta]")
  println("    keys   size   clock   entries   snapshot   clear")
  println("    touch <k> <ttl>   persist <k>")
  println("    watch <k>   watchp <prefix>   watchall   unwatch <id>")
  println("    advance <n>   expire   quit   help")
  println(
    "  value: 42->Int  3.14->Float  true/false->Bool  null->Null  else->Str",
  )
}

///|
/// 内置演示：展示 watch/watch_all/watch_prefix/unwatch/TTL 的实时通知。
fn run_demo() -> Unit {
  let db = @db.DB::new()
  println("=== MoonBit 实时数据库演示 ===")
  println("")
  println("[1] watch(\"counter\")")
  let w_counter = db.watch("counter", fn(e) {
    println("      >> [counter] \{e.to_string()}")
  })
  let _ = w_counter
  println("[2] set counter = 1")
  db.set("counter", @db.Int(1))
  println("[3] set counter = 2")
  db.set("counter", @db.Int(2))
  println("[4] watch_prefix(\"user:\")")
  let _ = db.watch_prefix("user:", fn(e) {
    println("      >> [prefix]  \{e.to_string()}")
  })
  println("[5] set user:1 = 99")
  db.set("user:1", @db.Int(99))
  println("[6] watch_all()")
  let _ = db.watch_all(fn(e) { println("      >> [global]  \{e.to_string()}") })
  println("[7] set temp = 3.14 (Float)")
  db.set("temp", @db.Float(3.14))
  println("[8] set sess = x with ttl=3")
  db.set("sess", @db.Str("x"), ttl=3)
  println("[9] advance(3)  —— sess 过期")
  let expired = db.advance(3)
  println("      expired=\{expired}")
  println("[10] delete counter")
  let _ = db.delete("counter")
  println("[11] unwatch(w_counter)")
  let _ = db.unwatch(w_counter)
  println("[12] set counter = 3  —— 仅 prefix(不匹配)/global 收到")
  db.set("counter", @db.Int(3))
  println("[13] snapshot")
  println(
    "      size=\{db.size()}, watchers=\{db.watcher_count()}, clock=\{db.clock()}",
  )
  for k in db.keys() {
    match db.get(k) {
      Some(v) => println("      \{k} = \{v.to_string()}")
      None => ()
    }
  }
  println("")
  println("=== 演示结束 ===")
}
