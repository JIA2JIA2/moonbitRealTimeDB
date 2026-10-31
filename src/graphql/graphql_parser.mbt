// GraphQL 解析器模块
//
// 实现 GraphQL 查询解析、验证、执行

///|
/// GraphQL 解析器
pub(all) struct GraphQLParser {
  /// 查询文本
  text : String
  /// 当前位置
  mut position : Int32
  /// 当前行
  mut line : Int32
  /// 当前列
  mut column : Int32
}

///|
/// 创建解析器
pub fn GraphQLParser::new(text : String) -> GraphQLParser {
  { text, position: 0, line: 1, column: 1, }
}

///|
/// 解析查询
pub fn GraphQLParser::parse(
  self : GraphQLParser,
) -> Result[GraphQLParseResult, GraphQLErrorEnum] {
  // 跳过空白字符
  self.skip_whitespace()

  // 检查是否结束
  if self.position >= self.text.length() {
    return Ok(GraphQLParseResult::{
      success: false,
      value: None,
      errors: [SyntaxError("Empty query")],
    })
  }

  // 解析操作定义
  let operation = self.parse_operation()

  match operation {
    Ok(value) =>
      Ok(GraphQLParseResult::{ success: true, value: Some(value), errors: [], })
    Err(e) =>
      Ok(GraphQLParseResult::{ success: false, value: None, errors: [e], })
  }
}

///|
/// 解析操作
fn GraphQLParser::parse_operation(
  self : GraphQLParser,
) -> Result[GraphQLValue, GraphQLErrorEnum] {
  // 跳过空白字符
  self.skip_whitespace()

  // 匿名查询：以 { 开头
  match self.peek() {
    Some('{') => self.parse_selection_set()
    _ => {
      // 检查关键字
      let keyword = self.read_keyword()

      match keyword {
        "query" => self.parse_query()
        "mutation" => self.parse_mutation()
        "subscription" => self.parse_subscription()
        _ =>
          Err(
            SyntaxError("Expected 'query', 'mutation', 'subscription' or '{'"),
          )
      }
    }
  }
}

///|
/// 解析查询
fn GraphQLParser::parse_query(
  self : GraphQLParser,
) -> Result[GraphQLValue, GraphQLErrorEnum] {
  // 跳过空白字符
  self.skip_whitespace()

  // 读取操作名（可选）
  let _ = self.read_identifier()

  // 解析选择集
  self.parse_selection_set()
}

///|
/// 解析变更
fn GraphQLParser::parse_mutation(
  self : GraphQLParser,
) -> Result[GraphQLValue, GraphQLErrorEnum] {
  // 跳过空白字符
  self.skip_whitespace()

  // 读取操作名（可选）
  let _ = self.read_identifier()

  // 解析选择集
  self.parse_selection_set()
}

///|
/// 解析订阅
fn GraphQLParser::parse_subscription(
  self : GraphQLParser,
) -> Result[GraphQLValue, GraphQLErrorEnum] {
  // 跳过空白字符
  self.skip_whitespace()

  // 读取操作名（可选）
  let _ = self.read_identifier()

  // 解析选择集
  self.parse_selection_set()
}

///|
/// 解析选择集
fn GraphQLParser::parse_selection_set(
  self : GraphQLParser,
) -> Result[GraphQLValue, GraphQLErrorEnum] {
  // 跳过空白字符
  self.skip_whitespace()

  // 检查左花括号
  if self.peek() != Some('{') {
    return Err(SyntaxError("Expected '{'"))
  }

  self.position = self.position + 1
  self.column = self.column + 1

  // 解析字段
  let fields : Array[GraphQLValue] = []

  let mut done = false
  while !done {
    self.skip_whitespace()

    // 检查右花括号
    if self.peek() == Some('}') {
      self.position = self.position + 1
      self.column = self.column + 1
      done = true
    } else {
      // 解析字段
      let field = self.parse_field()
      match field {
        Ok(f) => fields.push(f)
        Err(e) => return Err(e)
      }
    }
  }

  Ok(ObjectValue(Map([("fields", ListValue(fields))])))
}

///|
/// 解析字段
fn GraphQLParser::parse_field(
  self : GraphQLParser,
) -> Result[GraphQLValue, GraphQLErrorEnum] {
  // 读取字段名
  let name = self.read_identifier()
  if name.is_empty() {
    return Err(SyntaxError("Expected field name"))
  }

  // 跳过空白字符
  self.skip_whitespace()

  // 检查参数
  let mut args : Map[String, GraphQLValue] = Map([])
  if self.peek() == Some('(') {
    self.position = self.position + 1
    self.column = self.column + 1

    let parsed_args = self.parse_arguments()
    match parsed_args {
      Ok(a) => args = a
      Err(e) => return Err(e)
    }

    self.skip_whitespace()
    if self.peek() != Some(')') {
      return Err(SyntaxError("Expected ')'"))
    }
    self.position = self.position + 1
    self.column = self.column + 1
  }

  // 检查选择集
  let mut selection_set : GraphQLValue? = None
  self.skip_whitespace()
  if self.peek() == Some('{') {
    let ss = self.parse_selection_set()
    match ss {
      Ok(s) => selection_set = Some(s)
      Err(e) => return Err(e)
    }
  }

  // 构建字段对象
  let field_obj : Map[String, GraphQLValue] = Map([])
  field_obj.set("name", StringValue(name))
  field_obj.set("args", ObjectValue(args))

  match selection_set {
    Some(ss) => field_obj.set("selection_set", ss)
    None => ()
  }

  Ok(ObjectValue(field_obj))
}

///|
/// 解析参数
fn GraphQLParser::parse_arguments(
  self : GraphQLParser,
) -> Result[Map[String, GraphQLValue], GraphQLErrorEnum] {
  let args : Map[String, GraphQLValue] = Map([])

  let mut done = false
  while !done {
    self.skip_whitespace()

    // 检查右括号
    if self.peek() == Some(')') {
      done = true
    } else {
      // 读取参数名
      let name = self.read_identifier()

      self.skip_whitespace()

      // 检查冒号
      if self.peek() != Some(':') {
        return Err(SyntaxError("Expected ':'"))
      }
      self.position = self.position + 1
      self.column = self.column + 1

      self.skip_whitespace()

      // 解析值
      let value = self.parse_value()
      match value {
        Ok(v) => args.set(name, v)
        Err(e) => return Err(e)
      }

      self.skip_whitespace()

      // 检查逗号
      if self.peek() == Some(',') {
        self.position = self.position + 1
        self.column = self.column + 1
      } else {
        done = true
      }
    }
  }

  Ok(args)
}

///|
/// 解析值
fn GraphQLParser::parse_value(
  self : GraphQLParser,
) -> Result[GraphQLValue, GraphQLErrorEnum] {
  self.skip_whitespace()

  let ch = self.peek()

  match ch {
    Some('"') => {
      let str_val = self.read_string()
      Ok(StringValue(str_val))
    }
    Some('[') => {
      self.position = self.position + 1
      self.column = self.column + 1

      let values : Array[GraphQLValue] = []

      let mut done = false
      while !done {
        self.skip_whitespace()

        if self.peek() == Some(']') {
          self.position = self.position + 1
          self.column = self.column + 1
          done = true
        } else {
          let val = self.parse_value()
          match val {
            Ok(v) => values.push(v)
            Err(e) => return Err(e)
          }

          self.skip_whitespace()

          if self.peek() == Some(',') {
            self.position = self.position + 1
            self.column = self.column + 1
          }
        }
      }

      Ok(ListValue(values))
    }
    Some('{') => {
      self.position = self.position + 1
      self.column = self.column + 1

      let fields : Map[String, GraphQLValue] = Map([])

      let mut done = false
      while !done {
        self.skip_whitespace()

        if self.peek() == Some('}') {
          self.position = self.position + 1
          self.column = self.column + 1
          done = true
        } else {
          let name = self.read_identifier()

          self.skip_whitespace()

          if self.peek() != Some(':') {
            return Err(SyntaxError("Expected ':'"))
          }
          self.position = self.position + 1
          self.column = self.column + 1

          self.skip_whitespace()

          let value = self.parse_value()
          match value {
            Ok(v) => fields.set(name, v)
            Err(e) => return Err(e)
          }

          self.skip_whitespace()

          if self.peek() == Some(',') {
            self.position = self.position + 1
            self.column = self.column + 1
          }
        }
      }

      Ok(ObjectValue(fields))
    }
    Some('t') | Some('f') => {
      let bool_val = self.read_boolean()
      Ok(BoolValue(bool_val))
    }
    Some('n') => {
      self.read_null()
      Ok(NullValue)
    }
    Some(c) =>
      if c.is_ascii_digit() {
        let num = self.read_number()
        Ok(IntValue(num))
      } else {
        // 可能是变量或枚举值
        let ident = self.read_identifier()
        if ident.has_prefix("$") {
          // 变量
          Ok(StringValue(ident))
        } else {
          // 枚举值
          Ok(StringValue(ident))
        }
      }
    None => Err(SyntaxError("Unexpected end of query"))
  }
}

///|
/// 判断字符是否为标识符字符
fn is_ident_char(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_'
}

///|
/// 读取关键字
fn GraphQLParser::read_keyword(self : GraphQLParser) -> String {
  self.skip_whitespace()

  let start = self.position
  let mut continue_reading = true
  while continue_reading && self.position < self.text.length() {
    match self.text.get_char(self.position) {
      Some(ch) =>
        if ch.is_ascii_alphabetic() {
          self.position = self.position + 1
        } else {
          continue_reading = false
        }
      None => continue_reading = false
    }
  }

  let keyword = self.text[start:self.position].to_owned()
  self.column = self.column + (self.position - start)

  keyword
}

///|
/// 读取标识符
fn GraphQLParser::read_identifier(self : GraphQLParser) -> String {
  self.skip_whitespace()

  let start = self.position
  let mut continue_reading = true
  while continue_reading && self.position < self.text.length() {
    match self.text.get_char(self.position) {
      Some(ch) =>
        if is_ident_char(ch) {
          self.position = self.position + 1
        } else {
          continue_reading = false
        }
      None => continue_reading = false
    }
  }

  let ident = self.text[start:self.position].to_owned()
  self.column = self.column + (self.position - start)

  ident
}

///|
/// 读取字符串
fn GraphQLParser::read_string(self : GraphQLParser) -> String {
  let quote = match self.text.get_char(self.position) {
    Some(ch) => ch
    None => '"'
  }
  self.position = self.position + 1
  self.column = self.column + 1

  let start = self.position

  let mut continue_reading = true
  while continue_reading && self.position < self.text.length() {
    match self.text.get_char(self.position) {
      Some(ch) =>
        if ch == quote {
          continue_reading = false
        } else {
          self.position = self.position + 1
        }
      None => continue_reading = false
    }
  }

  let str_val = self.text[start:self.position].to_owned()
  self.position = self.position + 1
  self.column = self.column + (self.position - start) + 1

  str_val
}

///|
/// 读取数字
fn GraphQLParser::read_number(self : GraphQLParser) -> Int32 {
  self.skip_whitespace()

  let mut num = 0
  let mut continue_reading = true
  while continue_reading && self.position < self.text.length() {
    match self.text.get_char(self.position) {
      Some(ch) =>
        if ch.is_ascii_digit() {
          num = num * 10 + (ch.to_int() - '0'.to_int())
          self.position = self.position + 1
        } else {
          continue_reading = false
        }
      None => continue_reading = false
    }
  }

  num
}

///|
/// 读取布尔值
fn GraphQLParser::read_boolean(self : GraphQLParser) -> Bool {
  self.skip_whitespace()

  let start = self.position
  let mut continue_reading = true
  while continue_reading && self.position < self.text.length() {
    match self.text.get_char(self.position) {
      Some(ch) =>
        if ch.is_ascii_alphabetic() {
          self.position = self.position + 1
        } else {
          continue_reading = false
        }
      None => continue_reading = false
    }
  }

  let bool_str = self.text[start:self.position].to_owned()
  self.column = self.column + (self.position - start)

  bool_str == "true"
}

///|
/// 读取 null
fn GraphQLParser::read_null(self : GraphQLParser) -> Unit {
  self.skip_whitespace()

  let start = self.position
  let mut continue_reading = true
  while continue_reading && self.position < self.text.length() {
    match self.text.get_char(self.position) {
      Some(ch) =>
        if ch.is_ascii_alphabetic() {
          self.position = self.position + 1
        } else {
          continue_reading = false
        }
      None => continue_reading = false
    }
  }

  self.column = self.column + (self.position - start)
}

///|
/// 查看下一个字符
fn GraphQLParser::peek(self : GraphQLParser) -> Char? {
  self.text.get_char(self.position)
}

///|
/// 跳过空白字符
fn GraphQLParser::skip_whitespace(self : GraphQLParser) -> Unit {
  let mut continue_reading = true
  while continue_reading && self.position < self.text.length() {
    match self.text.get_char(self.position) {
      Some(' ') | Some('\t') | Some('\r') => {
        self.position = self.position + 1
        self.column = self.column + 1
      }
      Some('\n') => {
        self.position = self.position + 1
        self.line = self.line + 1
        self.column = 1
      }
      Some('#') =>
        // 跳过注释
        self.skip_comment()
      _ => continue_reading = false
    }
  }
}

///|
/// 跳过注释
fn GraphQLParser::skip_comment(self : GraphQLParser) -> Unit {
  // 跳过 '#'
  self.position = self.position + 1

  // 跳过直到行尾
  let mut continue_reading = true
  while continue_reading && self.position < self.text.length() {
    match self.text.get_char(self.position) {
      Some('\n') | None => continue_reading = false
      Some(_) => self.position = self.position + 1
    }
  }
}

///|
/// 创建解析器
pub fn create_parser(text : String) -> GraphQLParser {
  GraphQLParser::new(text)
}

///|
/// 解析 GraphQL 查询
pub fn parse_graphql(
  query : String,
) -> Result[GraphQLParseResult, GraphQLErrorEnum] {
  let parser = GraphQLParser::new(query)
  parser.parse()
}
