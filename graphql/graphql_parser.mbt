// GraphQL 解析器模块
//
// 实现 GraphQL 查询解析、验证、执行

///|
/// GraphQL 解析器
pub(all) struct GraphQLParser {
  /// 查询文本
  text : String
  /// 当前位置
  mut position : Int
  /// 当前行
  mut line : Int
  /// 当前列
  mut column : Int
}

///|
/// 创建解析器
pub fn GraphQLParser::new(text : String) -> GraphQLParser {
  {
    text,
    position: 0,
    line: 1,
    column: 1,
  }
}

///|
/// 解析查询
pub fn GraphQLParser::parse(self : GraphQLParser) -> Result[GraphQLParseResult, GraphQLErrorEnum> {
  // 跳过空白字符
  self.skip_whitespace()

  // 检查是否结束
  if self.position >= self.text.length() {
    return Ok(GraphQLParseResult {
      success: false,
      value: None,
      errors: [SyntaxError("Empty query")],
    })
  }

  // 解析操作定义
  let operation = self.parse_operation()

  match operation {
    Ok(value) => Ok(GraphQLParseResult {
      success: true,
      value: Some(value),
      errors: [],
    })
    Err(e) => Ok(GraphQLParseResult {
      success: false,
      value: None,
      errors: [e],
    })
  }
}

///|
/// 解析操作
fn GraphQLParser::parse_operation(self : GraphQLParser) -> Result[GraphQLValue, GraphQLErrorEnum> {
  // 跳过空白字符
  self.skip_whitespace()

  // 检查关键字
  let keyword = self.read_keyword()

  match keyword {
    "query" => self.parse_query()
    "mutation" => self.parse_mutation()
    "subscription" => self.parse_subscription()
    "{" => {
      // 匿名查询
      self.position = self.position - 1
      self.parse_selection_set()
    }
    _ => Err(SyntaxError("Expected 'query', 'mutation', 'subscription' or '{'"))
  }
}

///|
/// 解析查询
fn GraphQLParser::parse_query(self : GraphQLParser) -> Result[GraphQLValue, GraphQLErrorEnum> {
  // 跳过空白字符
  self.skip_whitespace()

  // 读取操作名
  let name = self.read_identifier()

  // 解析选择集
  self.parse_selection_set()
}

///|
/// 解析变更
fn GraphQLParser::parse_mutation(self : GraphQLParser) -> Result[GraphQLValue, GraphQLErrorEnum> {
  // 跳过空白字符
  self.skip_whitespace()

  // 读取操作名
  let name = self.read_identifier()

  // 解析选择集
  self.parse_selection_set()
}

///|
/// 解析订阅
fn GraphQLParser::parse_subscription(self : GraphQLParser) -> Result[GraphQLValue, GraphQLErrorEnum> {
  // 跳过空白字符
  self.skip_whitespace()

  // 读取操作名
  let name = self.read_identifier()

  // 解析选择集
  self.parse_selection_set()
}

///|
/// 解析选择集
fn GraphQLParser::parse_selection_set(self : GraphQLParser) -> Result[GraphQLValue, GraphQLErrorEnum> {
  // 跳过空白字符
  self.skip_whitespace()

  // 检查左花括号
  if self.peek() != "{" {
    return Err(SyntaxError("Expected '{'"))
  }

  self.position = self.position + 1
  self.column = self.column + 1

  // 解析字段
  let fields : Array[GraphQLValue] = []

  loop {
    self.skip_whitespace()

    // 检查右花括号
    if self.peek() == "}" {
      self.position = self.position + 1
      self.column = self.column + 1
      break
    }

    // 解析字段
    let field = self.parse_field()
    match field {
      Ok(f) => fields.push(f)
      Err(e) => return Err(e)
    }
  }

  Ok(ObjectValue(Map([("fields", ListValue(fields))])))
}

///|
/// 解析字段
fn GraphQLParser::parse_field(self : GraphQLParser) -> Result[GraphQLValue, GraphQLErrorEnum> {
  // 读取字段名
  let name = self.read_identifier()

  // 跳过空白字符
  self.skip_whitespace()

  // 检查参数
  var args : Map[String, GraphQLValue] = Map([])
  if self.peek() == "(" {
    self.position = self.position + 1
    self.column = self.column + 1

    let parsed_args = self.parse_arguments()
    match parsed_args {
      Ok(a) => args = a,
      Err(e) => return Err(e)
    }

    self.skip_whitespace()
    if self.peek() != ")" {
      return Err(SyntaxError("Expected ')'"))
    }
    self.position = self.position + 1
    self.column = self.column + 1
  }

  // 检查选择集
  var selection_set : GraphQLValue? = None
  self.skip_whitespace()
  if self.peek() == "{" {
    let ss = self.parse_selection_set()
    match ss {
      Ok(s) => selection_set = Some(s)
      Err(e) => return Err(e)
    }
  }

  // 构建字段对象
  let mut field_obj : Map[String, GraphQLValue] = Map([])
  field_obj.set("name", StringValue(name))
  field_obj.set("args", ObjectValue(args))

  if selection_set is Some(ss) {
    field_obj.set("selection_set", ss)
  }

  Ok(ObjectValue(field_obj))
}

///|
/// 解析参数
fn GraphQLParser::parse_arguments(self : GraphQLParser) -> Result[Map[String, GraphQLValue], GraphQLErrorEnum> {
  let args : Map[String, GraphQLValue] = Map([])

  loop {
    self.skip_whitespace()

    // 检查右括号
    if self.peek() == ")" {
      break
    }

    // 读取参数名
    let name = self.read_identifier()

    self.skip_whitespace()

    // 检查冒号
    if self.peek() != ":" {
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
    if self.peek() == "," {
      self.position = self.position + 1
      self.column = self.column + 1
    } else {
      break
    }
  }

  Ok(args)
}

///|
/// 解析值
fn GraphQLParser::parse_value(self : GraphQLParser) -> Result[GraphQLValue, GraphQLErrorEnum> {
  self.skip_whitespace()

  let ch = self.peek()

  match ch {
    '"' => {
      let str_val = self.read_string()
      Ok(StringValue(str_val))
    }
    '[' => {
      self.position = self.position + 1
      self.column = self.column + 1

      let values : Array[GraphQLValue] = []

      loop {
        self.skip_whitespace()

        if self.peek() == "]" {
          self.position = self.position + 1
          self.column = self.column + 1
          break
        }

        let val = self.parse_value()
        match val {
          Ok(v) => values.push(v)
          Err(e) => return Err(e)
        }

        self.skip_whitespace()

        if self.peek() == "," {
          self.position = self.position + 1
          self.column = self.column + 1
        }
      }

      Ok(ListValue(values))
    }
    '{' => {
      self.position = self.position + 1
      self.column = self.column + 1

      let fields : Map[String, GraphQLValue] = Map([])

      loop {
        self.skip_whitespace()

        if self.peek() == "}" {
          self.position = self.position + 1
          self.column = self.column + 1
          break
        }

        let name = self.read_identifier()

        self.skip_whitespace()

        if self.peek() != ":" {
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

        if self.peek() == "," {
          self.position = self.position + 1
          self.column = self.column + 1
        }
      }

      Ok(ObjectValue(fields))
    }
    '0'..'9' => {
      let num = self.read_number()
      Ok(IntValue(num))
    }
    't' | 'f' => {
      let bool_val = self.read_boolean()
      Ok(BoolValue(bool_val))
    }
    'n' => {
      self.read_null()
      Ok(NullValue)
    }
    _ => {
      // 可能是变量或枚举值
      let ident = self.read_identifier()
      if ident.starts_with("$") {
        // 变量
        Ok(StringValue(ident))
      } else {
        // 枚举值
        Ok(StringValue(ident))
      }
    }
  }
}

///|
/// 读取关键字
fn GraphQLParser::read_keyword(self : GraphQLParser) -> String {
  self.skip_whitespace()

  let start = self.position
  while self.position < self.text.length() {
    let ch = self.text[self.position]
    if not ch.is_alpha() {
      break
    }
    self.position = self.position + 1
  }

  let keyword = self.text.slice(start, self.position)
  self.column = self.column + (self.position - start)

  keyword
}

///|
/// 读取标识符
fn GraphQLParser::read_identifier(self : GraphQLParser) -> String {
  self.skip_whitespace()

  let start = self.position
  while self.position < self.text.length() {
    let ch = self.text[self.position]
    if not (ch.is_alpha() or ch.is_digit() or ch == '_') {
      break
    }
    self.position = self.position + 1
  }

  let ident = self.text.slice(start, self.position)
  self.column = self.column + (self.position - start)

  ident
}

///|
/// 读取字符串
fn GraphQLParser::read_string(self : GraphQLParser) -> String {
  let quote = self.text[self.position]
  self.position = self.position + 1
  self.column = self.column + 1

  let start = self.position

  while self.position < self.text.length() and self.text[self.position] != quote {
    self.position = self.position + 1
  }

  let str_val = self.text.slice(start, self.position)
  self.position = self.position + 1
  self.column = self.column + (self.position - start) + 1

  str_val
}

///|
/// 读取数字
fn GraphQLParser::read_number(self : GraphQLParser) -> Int {
  self.skip_whitespace()

  let start = self.position

  while self.position < self.text.length() {
    let ch = self.text[self.position]
    if not ch.is_digit() {
      break
    }
    self.position = self.position + 1
  }

  let num_str = self.text.slice(start, self.position)
  self.column = self.column + (self.position - start)

  num_str.parse_int()?
}

///|
/// 读取布尔值
fn GraphQLParser::read_boolean(self : GraphQLParser) -> Bool {
  self.skip_whitespace()

  let start = self.position
  while self.position < self.text.length() and self.text[self.position].is_alpha() {
    self.position = self.position + 1
  }

  let bool_str = self.text.slice(start, self.position)
  self.column = self.column + (self.position - start)

  bool_str == "true"
}

///|
/// 读取 null
fn GraphQLParser::read_null(self : GraphQLParser) -> Unit {
  self.skip_whitespace()

  let start = self.position
  while self.position < self.text.length() and self.text[self.position].is_alpha() {
    self.position = self.position + 1
  }

  self.column = self.column + (self.position - start)
}

///|
/// 查看下一个字符
fn GraphQLParser::peek(self : GraphQLParser) -> String {
  if self.position >= self.text.length() {
    return ""
  }

  self.text[self.position].to_string()
}

///|
/// 跳过空白字符
fn GraphQLParser::skip_whitespace(self : GraphQLParser) -> Unit {
  while self.position < self.text.length() {
    let ch = self.text[self.position]
    match ch {
      ' ' | '\t' | '\r' => {
        self.position = self.position + 1
        self.column = self.column + 1
      }
      '\n' => {
        self.position = self.position + 1
        self.line = self.line + 1
        self.column = 1
      }
      '#' => {
        // 跳过注释
        self.skip_comment()
      }
      _ => break
    }
  }
}

///|
/// 跳过注释
fn GraphQLParser::skip_comment(self : GraphQLParser) -> Unit {
  // 跳过 '#'
  self.position = self.position + 1

  // 跳过直到行尾
  while self.position < self.text.length() and self.text[self.position] != '\n' {
    self.position = self.position + 1
  }
}

///|
/// 创建解析器
pub fn create_parser(text : String) -> GraphQLParser {
  GraphQLParser::new(text)
}

///|
/// 解析 GraphQL 查询
pub fn parse_graphql(query : String) -> Result[GraphQLParseResult, GraphQLErrorEnum> {
  let parser = GraphQLParser::new(query)
  parser.parse()
}