// SQL 解析器模块
//
// 实现 SQL 语句的词法分析和语法分析

///|
/// 词法标记类型
pub(all) enum TokenType {
  /// 关键字
  Keyword
  /// 标识符
  Identifier
  /// 字符串字面量
  StringLiteral
  /// 数字字面量
  NumberLiteral
  /// 操作符
  Operator
  /// 逗号
  Comma
  /// 左括号
  LeftParen
  /// 右括号
  RightParen
  /// 分号
  Semicolon
  /// 点
  Dot
  /// 文件结束
  EndOfFile
}

///|
/// 词法标记
pub(all) struct Token {
  /// 标记类型
  token_type : TokenType
  /// 标记值
  value : String
  /// 行号
  line : Int
  /// 列号
  column : Int
}

///|
/// 词法分析器
pub(all) struct Lexer {
  /// SQL 文本
  text : String
  /// 当前位置
  mut position : Int
  /// 当前行
  mut line : Int
  /// 当前列
  mut column : Int
  /// 当前标记
  mut current_token : Token?
}

///|
/// 关键字列表
pub let keywords : Array[String] = [
  "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN",
  "BETWEEN", "LIKE", "IS", "NULL", "TRUE", "FALSE",
  "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
  "CREATE", "TABLE", "DROP", "INDEX", "PRIMARY", "KEY",
  "UNIQUE", "CONSTRAINT", "FOREIGN", "REFERENCES",
  "DEFAULT", "CHECK", "CASCADE", "RESTRICT",
  "GROUP", "BY", "HAVING", "ORDER", "ASC", "DESC",
  "LIMIT", "OFFSET", "JOIN", "LEFT", "RIGHT", "INNER",
  "ON", "AS", "ALL", "DISTINCT", "CASE", "WHEN", "THEN",
  "ELSE", "END", "BEGIN", "COMMIT", "ROLLBACK", "EXPLAIN",
  "IF", "EXISTS", "NULLS", "FIRST", "LAST",
]

///|
/// 创建词法分析器
pub fn Lexer::new(text : String) -> Lexer {
  {
    text,
    position: 0,
    line: 1,
    column: 1,
    current_token: None,
  }
}

///|
/// 获取下一个标记
pub fn Lexer::next_token(self : Lexer) -> Result[Token, SqlError] {
  // 跳过空白字符
  self.skip_whitespace()

  // 检查是否结束
  if self.position >= self.text.length() {
    return Ok(Token {
      token_type: EndOfFile,
      value: "",
      line: self.line,
      column: self.column,
    })
  }

  let ch = self.text[self.position]

  // 检查标识符或关键字
  if ch.is_alpha() or ch == '_' {
    return self.read_identifier()
  }

  // 检查数字
  if ch.is_digit() {
    return self.read_number()
  }

  // 检查字符串
  if ch == '\'' or ch == '"' {
    return self.read_string()
  }

  // 检查操作符
  match ch {
    '+' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: Operator, value: "+", line: self.line, column: self.column - 1 })
    }
    '-' => {
      // 检查注释
      if self.position + 1 < self.text.length() and self.text[self.position + 1] == '-' {
        self.skip_comment()
        return self.next_token()
      }
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: Operator, value: "-", line: self.line, column: self.column - 1 })
    }
    '*' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: Operator, value: "*", line: self.line, column: self.column - 1 })
    }
    '/' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: Operator, value: "/", line: self.line, column: self.column - 1 })
    }
    '=' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: Operator, value: "=", line: self.line, column: self.column - 1 })
    }
    '<' => {
      self.position = self.position + 1
      if self.position < self.text.length() and self.text[self.position] == '=' {
        self.position = self.position + 1
        self.column = self.column + 2
        Ok(Token { token_type: Operator, value: "<=", line: self.line, column: self.column - 2 })
      } else if self.position < self.text.length() and self.text[self.position] == '>' {
        self.position = self.position + 1
        self.column = self.column + 2
        Ok(Token { token_type: Operator, value: "<>", line: self.line, column: self.column - 2 })
      } else {
        self.column = self.column + 1
        Ok(Token { token_type: Operator, value: "<", line: self.line, column: self.column - 1 })
      }
    }
    '>' => {
      self.position = self.position + 1
      if self.position < self.text.length() and self.text[self.position] == '=' {
        self.position = self.position + 1
        self.column = self.column + 2
        Ok(Token { token_type: Operator, value: ">=", line: self.line, column: self.column - 2 })
      } else {
        self.column = self.column + 1
        Ok(Token { token_type: Operator, value: ">", line: self.line, column: self.column - 1 })
      }
    }
    '!' => {
      self.position = self.position + 1
      if self.position < self.text.length() and self.text[self.position] == '=' {
        self.position = self.position + 1
        self.column = self.column + 2
        Ok(Token { token_type: Operator, value: "!=", line: self.line, column: self.column - 2 })
      } else {
        self.column = self.column + 1
        Ok(Token { token_type: Operator, value: "!", line: self.line, column: self.column - 1 })
      }
    }
    ',' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: Comma, value: ",", line: self.line, column: self.column - 1 })
    }
    '(' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: LeftParen, value: "(", line: self.line, column: self.column - 1 })
    }
    ')' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: RightParen, value: ")", line: self.line, column: self.column - 1 })
    }
    ';' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: Semicolon, value: ";", line: self.line, column: self.column - 1 })
    }
    '.' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token { token_type: Dot, value: ".", line: self.line, column: self.column - 1 })
    }
    _ => Err(SqlError::Syntax_Error)
  }
}

///|
/// 读取标识符
fn Lexer::read_identifier(self : Lexer) -> Result[Token, SqlError> {
  let start = self.position
  while self.position < self.text.length() {
    let ch = self.text[self.position]
    if not (ch.is_alpha() or ch.is_digit() or ch == '_') {
      break
    }
    self.position = self.position + 1
  }

  let value = self.text.slice(start, self.position)
  self.column = self.column + (self.position - start)

  // 检查是否是关键字
  let token_type = if keywords.contains(value.to_uppercase()) {
    Keyword
  } else {
    Identifier
  }

  Ok(Token {
    token_type,
    value,
    line: self.line,
    column: start + 1,
  })
}

///|
/// 读取数字
fn Lexer::read_number(self : Lexer) -> Result[Token, SqlError> {
  let start = self.position
  var has_dot = false

  while self.position < self.text.length() {
    let ch = self.text[self.position]
    if ch == '.' {
      if has_dot {
        break
      }
      has_dot = true
      self.position = self.position + 1
    } else if ch.is_digit() {
      self.position = self.position + 1
    } else {
      break
    }
  }

  let value = self.text.slice(start, self.position)
  self.column = self.column + (self.position - start)

  Ok(Token {
    token_type: NumberLiteral,
    value,
    line: self.line,
    column: start + 1,
  })
}

///|
/// 读取字符串
fn Lexer::read_string(self : Lexer) -> Result[Token, SqlError> {
  let quote = self.text[self.position]
  self.position = self.position + 1
  let start = self.position

  while self.position < self.text.length() and self.text[self.position] != quote {
    self.position = self.position + 1
  }

  if self.position >= self.text.length() {
    return Err(SqlError::Syntax_Error)
  }

  let value = self.text.slice(start, self.position)
  self.position = self.position + 1 // 跳过结束引号
  self.column = self.column + (self.position - start) + 2

  Ok(Token {
    token_type: StringLiteral,
    value,
    line: self.line,
    column: start,
  })
}

///|
/// 跳过空白字符
fn Lexer::skip_whitespace(self : Lexer) -> Unit {
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
      _ => break
    }
  }
}

///|
/// 跳过注释
fn Lexer::skip_comment(self : Lexer) -> Unit {
  // 跳过 '--'
  self.position = self.position + 2

  // 跳过直到行尾
  while self.position < self.text.length() and self.text[self.position] != '\n' {
    self.position = self.position + 1
  }
}

///|
/// 查看下一个标记
pub fn Lexer::peek(self : Lexer) -> Result[Token, SqlError> {
  let saved_position = self.position
  let saved_line = self.line
  let saved_column = self.column

  let token = self.next_token()

  self.position = saved_position
  self.line = saved_line
  self.column = saved_column

  token
}

///|
/// 匹配标记
pub fn Lexer::match_token(self : Lexer, expected_type : TokenType, expected_value : String?) -> Result[Token, SqlError> {
  let token = self.next_token()

  if token is Err {
    return Err(SqlError::Syntax_Error)
  }

  let t = token?
  if t.token_type != expected_type or (expected_value is Some and t.value != expected_value) {
    return Err(SqlError::Syntax_Error)
  }

  Ok(t)
}

///|
/// SQL 解析器
pub(all) struct Parser {
  /// 词法分析器
  lexer : Lexer
  /// 当前标记
  mut current_token : Token?
}

///|
/// 创建解析器
pub fn Parser::new(lexer : Lexer) -> Parser {
  {
    lexer,
    current_token: None,
  }
}

///|
/// 解析 SQL
pub fn Parser::parse(self : Parser) -> Result[SqlStatement, SqlError> {
  // 获取第一个标记
  self.current_token = self.lexer.next_token()

  // 解析语句
  let token = self.current_token?

  match token.value.to_uppercase() {
    "SELECT" => self.parse_select()
    "INSERT" => self.parse_insert()
    "UPDATE" => self.parse_update()
    "DELETE" => self.parse_delete()
    "CREATE" => self.parse_create()
    "DROP" => self.parse_drop()
    "BEGIN" => self.parse_begin()
    "COMMIT" => self.parse_commit()
    "ROLLBACK" => self.parse_rollback()
    "EXPLAIN" => self.parse_explain()
    _ => Err(SqlError::Syntax_Error)
  }
}

///|
/// 解析 SELECT 语句
fn Parser::parse_select(self : Parser) -> Result[SqlStatement, SqlError> {
  // 跳过 SELECT
  self.current_token = self.lexer.next_token()

  // 解析选择列
  let select_items = self.parse_select_items()

  // 解析 FROM 子句
  var from : String? = None
  if self.current_token is Some and self.current_token?.value.to_uppercase() == "FROM" {
    self.current_token = self.lexer.next_token()
    from = self.parse_identifier()
  }

  // 解析 WHERE 子句
  var where_condition : Expression? = None
  if self.current_token is Some and self.current_token?.value.to_uppercase() == "WHERE" {
    self.current_token = self.lexer.next_token()
    where_condition = self.parse_expression()
  }

  // 解析 ORDER BY 子句
  var order_by : Array[OrderByItem]? = None
  if self.current_token is Some and self.current_token?.value.to_uppercase() == "ORDER" {
    self.current_token = self.lexer.next_token()
    if self.current_token is Some and self.current_token?.value.to_uppercase() == "BY" {
      self.current_token = self.lexer.next_token()
      order_by = self.parse_order_by()
    }
  }

  // 解析 LIMIT 子句
  var limit : Int? = None
  if self.current_token is Some and self.current_token?.value.to_uppercase() == "LIMIT" {
    self.current_token = self.lexer.next_token()
    limit = self.parse_number()
  }

  Ok(Select(SelectStatement {
    select_items,
    from,
    where_condition,
    group_by: None,
    having: None,
    order_by,
    limit,
    offset: None,
  }))
}

///|
/// 解析选择项
fn Parser::parse_select_items(self : Parser) -> Array[SelectItem> {
  let items : Array[SelectItem] = []

  loop {
    let expr = self.parse_expression()
    var alias : String? = None

    // 检查别名
    if self.current_token is Some and self.current_token?.value.to_uppercase() == "AS" {
      self.current_token = self.lexer.next_token()
      alias = self.parse_identifier()
    }

    items.push(SelectItem { expression: expr, alias })

    // 检查逗号
    if self.current_token is Some and self.current_token?.value == "," {
      self.current_token = self.lexer.next_token()
    } else {
      break
    }
  }

  items
}

///|
/// 解析表达式
fn Parser::parse_expression(self : Parser) -> Expression {
  // 简化实现：解析列引用或字面量
  let token = self.current_token?

  if token.token_type == Identifier {
    self.current_token = self.lexer.next_token()
    ColumnRef(token.value)
  } else if token.token_type == StringLiteral or token.token_type == NumberLiteral {
    self.current_token = self.lexer.next_token()
    Literal(SqlValue {
      value_type: String,
      value: @realtime_db.Str(token.value),
      is_null: false,
    })
  } else {
    Wildcard
  }
}

///|
/// 解析标识符
fn Parser::parse_identifier(self : Parser) -> String {
  let token = self.current_token?
  if token.token_type == Identifier {
    self.current_token = self.lexer.next_token()
    token.value
  } else {
    ""
  }
}

///|
/// 解析数字
fn Parser::parse_number(self : Parser) -> Int {
  let token = self.current_token?
  if token.token_type == NumberLiteral {
    self.current_token = self.lexer.next_token()
    token.value.parse_int()?
  } else {
    0
  }
}

///|
/// 解析 ORDER BY 子句
fn Parser::parse_order_by(self : Parser) -> Array[OrderByItem> {
  let items : Array[OrderByItem] = []

  loop {
    let expr = self.parse_expression()
    var ascending = true

    // 检查排序方向
    if self.current_token is Some {
      let direction = self.current_token?.value.to_uppercase()
      if direction == "ASC" {
        ascending = true
        self.current_token = self.lexer.next_token()
      } else if direction == "DESC" {
        ascending = false
        self.current_token = self.lexer.next_token()
      }
    }

    items.push(OrderByItem { expression: expr, ascending })

    // 检查逗号
    if self.current_token is Some and self.current_token?.value == "," {
      self.current_token = self.lexer.next_token()
    } else {
      break
    }
  }

  items
}

///|
/// 解析 INSERT 语句
fn Parser::parse_insert(self : Parser) -> Result[SqlStatement, SqlError> {
  // 简化实现
  Ok(Insert(InsertStatement {
    table: "".to_string(),
    columns: None,
    values: None,
    select: None,
  }))
}

///|
/// 解析 UPDATE 语句
fn Parser::parse_update(self : Parser) -> Result[SqlStatement, SqlError> {
  // 简化实现
  Ok(Update(UpdateStatement {
    table: "".to_string(),
    set: [],
    where_condition: None,
  }))
}

///|
/// 解析 DELETE 语句
fn Parser::parse_delete(self : Parser) -> Result[SqlStatement, SqlError> {
  // 简化实现
  Ok(Delete(DeleteStatement {
    table: "".to_string(),
    where_condition: None,
  }))
}

///|
/// 解析 CREATE 语句
fn Parser::parse_create(self : Parser) -> Result[SqlStatement, SqlError> {
  // 简化实现
  Ok(CreateTable(CreateTableStatement {
    table: "".to_string(),
    columns: [],
    constraints: None,
  }))
}

///|
/// 解析 DROP 语句
fn Parser::parse_drop(self : Parser) -> Result[SqlStatement, SqlError> {
  // 简化实现
  Ok(DropTable(DropTableStatement {
    table: "".to_string(),
    if_exists: false,
  }))
}

///|
/// 解析 BEGIN 语句
fn Parser::parse_begin(self : Parser) -> Result[SqlStatement, SqlError> {
  Ok(Begin(BeginStatement { isolation_level: None }))
}

///|
/// 解析 COMMIT 语句
fn Parser::parse_commit(self : Parser) -> Result[SqlStatement, SqlError> {
  Ok(Commit(CommitStatement {}))
}

///|
/// 解析 ROLLBACK 语句
fn Parser::parse_rollback(self : Parser) -> Result[SqlStatement, SqlError> {
  Ok(Rollback(RollbackStatement {}))
}

///|
/// 解析 EXPLAIN 语句
fn Parser::parse_explain(self : Parser) -> Result[SqlStatement, SqlError> {
  // 简化实现
  Ok(Explain(ExplainStatement {
    statement: Select(SelectStatement {
      select_items: [],
      from: None,
      where_condition: None,
      group_by: None,
      having: None,
      order_by: None,
      limit: None,
      offset: None,
    }),
  }))
}

///|
/// 创建解析器
pub fn create_parser(lexer : Lexer) -> Parser {
  Parser::new(lexer)
}

///|
/// 解析 SQL 语句
pub fn parse_sql(sql : String) -> Result[SqlStatement, SqlError> {
  let lexer = Lexer::new(sql)
  let parser = Parser::new(lexer)
  parser.parse()
}