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
} derive(Eq, Debug)

///|
pub extend TokenType with Eq::{equal, not_equal}

///|
pub extend TokenType with Debug::{to_repr}

///|
/// 词法标记
pub(all) struct Token {
  /// 标记类型
  token_type : TokenType
  /// 标记值
  value : String
  /// 行号
  line : Int32
  /// 列号
  column : Int32
}

///|
/// 词法分析器
pub(all) struct Lexer {
  /// SQL 文本
  text : String
  /// 当前位置
  mut position : Int32
  /// 当前行
  mut line : Int32
  /// 当前列
  mut column : Int32
  /// 当前标记
  mut current_token : Token?
}

///|
/// 关键字列表
pub let keywords : Array[String] = [
  "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "BETWEEN", "LIKE", "IS", "NULL",
  "TRUE", "FALSE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE",
  "TABLE", "DROP", "INDEX", "PRIMARY", "KEY", "UNIQUE", "CONSTRAINT", "FOREIGN",
  "REFERENCES", "DEFAULT", "CHECK", "CASCADE", "RESTRICT", "GROUP", "BY", "HAVING",
  "ORDER", "ASC", "DESC", "LIMIT", "OFFSET", "JOIN", "LEFT", "RIGHT", "INNER", "ON",
  "AS", "ALL", "DISTINCT", "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN", "COMMIT",
  "ROLLBACK", "EXPLAIN", "IF", "EXISTS", "NULLS", "FIRST", "LAST",
]

///|
/// 创建词法分析器
pub fn Lexer::new(text : String) -> Lexer {
  { text, position: 0, line: 1, column: 1, current_token: None, }
}

///|
/// 获取下一个标记
pub fn Lexer::next_token(self : Lexer) -> Result[Token, SqlError] {
  // 跳过空白字符
  self.skip_whitespace()

  // 检查是否结束
  if self.position >= self.text.length() {
    return Ok(Token::{
      token_type: EndOfFile,
      value: "",
      line: self.line,
      column: self.column,
    })
  }

  let ch = self.text.get_char(self.position).unwrap()

  // 检查标识符或关键字
  if ch.is_ascii_alphabetic() || ch == '_' {
    return self.read_identifier()
  }

  // 检查数字
  if ch.is_ascii_digit() {
    return self.read_number()
  }

  // 检查字符串
  if ch == '\'' || ch == '"' {
    return self.read_string()
  }

  // 检查操作符
  match ch {
    '+' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: Operator,
        value: "+",
        line: self.line,
        column: self.column - 1,
      })
    }
    '-' => {
      // 检查注释
      if self.position + 1 < self.text.length() &&
        self.text.get_char(self.position + 1).unwrap() == '-' {
        self.skip_comment()
        return self.next_token()
      }
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: Operator,
        value: "-",
        line: self.line,
        column: self.column - 1,
      })
    }
    '*' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: Operator,
        value: "*",
        line: self.line,
        column: self.column - 1,
      })
    }
    '/' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: Operator,
        value: "/",
        line: self.line,
        column: self.column - 1,
      })
    }
    '=' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: Operator,
        value: "=",
        line: self.line,
        column: self.column - 1,
      })
    }
    '<' => {
      self.position = self.position + 1
      if self.position < self.text.length() &&
        self.text.get_char(self.position).unwrap() == '=' {
        self.position = self.position + 1
        self.column = self.column + 2
        Ok(Token::{
          token_type: Operator,
          value: "<=",
          line: self.line,
          column: self.column - 2,
        })
      } else if self.position < self.text.length() &&
        self.text.get_char(self.position).unwrap() == '>' {
        self.position = self.position + 1
        self.column = self.column + 2
        Ok(Token::{
          token_type: Operator,
          value: "<>",
          line: self.line,
          column: self.column - 2,
        })
      } else {
        self.column = self.column + 1
        Ok(Token::{
          token_type: Operator,
          value: "<",
          line: self.line,
          column: self.column - 1,
        })
      }
    }
    '>' => {
      self.position = self.position + 1
      if self.position < self.text.length() &&
        self.text.get_char(self.position).unwrap() == '=' {
        self.position = self.position + 1
        self.column = self.column + 2
        Ok(Token::{
          token_type: Operator,
          value: ">=",
          line: self.line,
          column: self.column - 2,
        })
      } else {
        self.column = self.column + 1
        Ok(Token::{
          token_type: Operator,
          value: ">",
          line: self.line,
          column: self.column - 1,
        })
      }
    }
    '!' => {
      self.position = self.position + 1
      if self.position < self.text.length() &&
        self.text.get_char(self.position).unwrap() == '=' {
        self.position = self.position + 1
        self.column = self.column + 2
        Ok(Token::{
          token_type: Operator,
          value: "!=",
          line: self.line,
          column: self.column - 2,
        })
      } else {
        self.column = self.column + 1
        Ok(Token::{
          token_type: Operator,
          value: "!",
          line: self.line,
          column: self.column - 1,
        })
      }
    }
    ',' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: Comma,
        value: ",",
        line: self.line,
        column: self.column - 1,
      })
    }
    '(' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: LeftParen,
        value: "(",
        line: self.line,
        column: self.column - 1,
      })
    }
    ')' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: RightParen,
        value: ")",
        line: self.line,
        column: self.column - 1,
      })
    }
    ';' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: Semicolon,
        value: ";",
        line: self.line,
        column: self.column - 1,
      })
    }
    '.' => {
      self.position = self.position + 1
      self.column = self.column + 1
      Ok(Token::{
        token_type: Dot,
        value: ".",
        line: self.line,
        column: self.column - 1,
      })
    }
    _ => Err(Syntax_Error)
  }
}

///|
/// 读取标识符
fn Lexer::read_identifier(self : Lexer) -> Result[Token, SqlError] {
  let start = self.position
  while self.position < self.text.length() {
    let ch = self.text.get_char(self.position).unwrap()
    if !(ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_') {
      break
    }
    self.position = self.position + 1
  }

  let value = self.text[start:self.position].to_owned()
  self.column = self.column + (self.position - start)

  // 检查是否是关键字
  let token_type = if keywords.contains(value.to_upper()) {
    Keyword
  } else {
    Identifier
  }

  Ok(Token::{ token_type, value, line: self.line, column: start + 1, })
}

///|
/// 读取数字
fn Lexer::read_number(self : Lexer) -> Result[Token, SqlError] {
  let start = self.position
  let mut has_dot = false

  while self.position < self.text.length() {
    let ch = self.text.get_char(self.position).unwrap()
    if ch == '.' {
      if has_dot {
        break
      }
      has_dot = true
      self.position = self.position + 1
    } else if ch.is_ascii_digit() {
      self.position = self.position + 1
    } else {
      break
    }
  }

  let value = self.text[start:self.position].to_owned()
  self.column = self.column + (self.position - start)

  Ok(Token::{
    token_type: NumberLiteral,
    value,
    line: self.line,
    column: start + 1,
  })
}

///|
/// 读取字符串
fn Lexer::read_string(self : Lexer) -> Result[Token, SqlError] {
  let quote = self.text.get_char(self.position).unwrap()
  self.position = self.position + 1
  let start = self.position

  while self.position < self.text.length() &&
        self.text.get_char(self.position).unwrap() != quote {
    self.position = self.position + 1
  }

  if self.position >= self.text.length() {
    return Err(Syntax_Error)
  }

  let value = self.text[start:self.position].to_owned()
  self.position = self.position + 1 // 跳过结束引号
  self.column = self.column + (self.position - start) + 2

  Ok(Token::{
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
    let ch = self.text.get_char(self.position).unwrap()
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
  while self.position < self.text.length() &&
        self.text.get_char(self.position).unwrap() != '\n' {
    self.position = self.position + 1
  }
}

///|
/// 查看下一个标记
pub fn Lexer::peek(self : Lexer) -> Result[Token, SqlError] {
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
pub fn Lexer::match_token(
  self : Lexer,
  expected_type : TokenType,
  expected_value : String?,
) -> Result[Token, SqlError] {
  let t = match self.next_token() {
    Ok(t) => t
    Err(_) => return Err(Syntax_Error)
  }

  let value_matches = match expected_value {
    Some(value) => t.value == value
    None => true
  }

  if t.token_type != expected_type || !value_matches {
    return Err(Syntax_Error)
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
  { lexer, current_token: None, }
}

///|
/// 前进到下一个标记
fn Parser::advance(self : Parser) -> Result[Unit, SqlError] {
  match self.lexer.next_token() {
    Ok(token) => {
      self.current_token = Some(token)
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// 当前标记是否为指定关键字（大小写不敏感）
fn Parser::is_keyword(self : Parser, keyword : String) -> Bool {
  match self.current_token {
    Some(token) => token.value.to_upper() == keyword
    None => false
  }
}

///|
/// 当前标记是否为指定值
fn Parser::is_value(self : Parser, value : String) -> Bool {
  match self.current_token {
    Some(token) => token.value == value
    None => false
  }
}

///|
/// 解析 SQL
pub fn Parser::parse(self : Parser) -> Result[SqlStatement, SqlError] {
  // 获取第一个标记
  match self.advance() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }

  let token = match self.current_token {
    Some(t) => t
    None => return Err(Syntax_Error)
  }

  match token.value.to_upper() {
    "SELECT" => self.parse_select()
    "INSERT" => Ok(self.parse_insert())
    "UPDATE" => Ok(self.parse_update())
    "DELETE" => Ok(self.parse_delete())
    "CREATE" => Ok(self.parse_create())
    "DROP" => Ok(self.parse_drop())
    "BEGIN" => Ok(self.parse_begin())
    "COMMIT" => Ok(self.parse_commit())
    "ROLLBACK" => Ok(self.parse_rollback())
    "EXPLAIN" => Ok(self.parse_explain())
    _ => Err(Syntax_Error)
  }
}

///|
/// 解析 SELECT 语句
fn Parser::parse_select(self : Parser) -> Result[SqlStatement, SqlError] {
  // 跳过 SELECT
  match self.advance() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }

  // 解析选择列
  let select_items = match self.parse_select_items() {
    Ok(items) => items
    Err(e) => return Err(e)
  }

  // 解析 FROM 子句
  let mut from : String? = None
  if self.is_keyword("FROM") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    from = Some(
      match self.parse_identifier() {
        Ok(name) => name
        Err(e) => return Err(e)
      },
    )
  }

  // 解析 WHERE 子句
  let mut where_condition : Expression? = None
  if self.is_keyword("WHERE") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    where_condition = Some(
      match self.parse_expression() {
        Ok(expr) => expr
        Err(e) => return Err(e)
      },
    )
  }

  // 解析 GROUP BY 子句
  let mut group_by : Array[Expression]? = None
  if self.is_keyword("GROUP") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    if self.is_keyword("BY") {
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      group_by = Some(
        match self.parse_group_by() {
          Ok(items) => items
          Err(e) => return Err(e)
        },
      )
    }
  }

  // 解析 HAVING 子句
  let mut having : Expression? = None
  if self.is_keyword("HAVING") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    having = Some(
      match self.parse_expression() {
        Ok(expr) => expr
        Err(e) => return Err(e)
      },
    )
  }

  // 解析 ORDER BY 子句
  let mut order_by : Array[OrderByItem]? = None
  if self.is_keyword("ORDER") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    if self.is_keyword("BY") {
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      order_by = Some(
        match self.parse_order_by() {
          Ok(items) => items
          Err(e) => return Err(e)
        },
      )
    }
  }

  // 解析 LIMIT 子句
  let mut limit : Int32? = None
  if self.is_keyword("LIMIT") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    limit = Some(
      match self.parse_number() {
        Ok(n) => n
        Err(e) => return Err(e)
      },
    )
  }

  Ok(
    Select(SelectStatement::{
      select_items,
      from,
      where_condition,
      group_by,
      having,
      order_by,
      limit,
      offset: None,
    }),
  )
}

///|
/// 解析选择项
fn Parser::parse_select_items(
  self : Parser,
) -> Result[Array[SelectItem], SqlError] {
  let items : Array[SelectItem] = []
  let mut has_more = true

  while has_more {
    let expr = match self.parse_expression() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    let mut alias_name : String? = None

    // 检查别名
    if self.is_keyword("AS") {
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      alias_name = Some(
        match self.parse_identifier() {
          Ok(name) => name
          Err(e) => return Err(e)
        },
      )
    }

    items.push(SelectItem::{ expression: expr, alias_name, })

    // 检查逗号
    if self.is_value(",") {
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    } else {
      has_more = false
    }
  }

  Ok(items)
}

///|
/// 解析表达式（入口）
fn Parser::parse_expression(self : Parser) -> Result[Expression, SqlError] {
  self.parse_or_expr()
}

///|
/// 解析 OR 表达式
fn Parser::parse_or_expr(self : Parser) -> Result[Expression, SqlError] {
  let mut left = match self.parse_and_expr() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  while self.is_keyword("OR") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let right = match self.parse_and_expr() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    left = BinaryOp(BinaryOpExpr::{ operator: Or, left, right, })
  }
  Ok(left)
}

///|
/// 解析 AND 表达式
fn Parser::parse_and_expr(self : Parser) -> Result[Expression, SqlError] {
  let mut left = match self.parse_comparison_expr() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  while self.is_keyword("AND") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let right = match self.parse_comparison_expr() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    left = BinaryOp(BinaryOpExpr::{ operator: And, left, right, })
  }
  Ok(left)
}

///|
/// 解析加减表达式
fn Parser::parse_additive_expr(self : Parser) -> Result[Expression, SqlError] {
  let mut left = match self.parse_multiplicative_expr() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  let mut has_more = true
  while has_more {
    let operator : BinaryOperator? = if self.is_value("+") {
      Some(Add)
    } else if self.is_value("-") {
      Some(Subtract)
    } else {
      None
    }
    match operator {
      Some(op) => {
        match self.advance() {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
        let right = match self.parse_multiplicative_expr() {
          Ok(e) => e
          Err(e) => return Err(e)
        }
        left = BinaryOp(BinaryOpExpr::{ operator: op, left, right, })
      }
      None => has_more = false
    }
  }
  Ok(left)
}

///|
/// 解析乘除模表达式
fn Parser::parse_multiplicative_expr(
  self : Parser,
) -> Result[Expression, SqlError] {
  let mut left = match self.parse_primary_expr() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  let mut has_more = true
  while has_more {
    let operator : BinaryOperator? = if self.is_value("*") {
      Some(Multiply)
    } else if self.is_value("/") {
      Some(Divide)
    } else if self.is_value("%") {
      Some(Modulo)
    } else {
      None
    }
    match operator {
      Some(op) => {
        match self.advance() {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
        let right = match self.parse_primary_expr() {
          Ok(e) => e
          Err(e) => return Err(e)
        }
        left = BinaryOp(BinaryOpExpr::{ operator: op, left, right, })
      }
      None => has_more = false
    }
  }
  Ok(left)
}

///|
/// 解析比较表达式
fn Parser::parse_comparison_expr(self : Parser) -> Result[Expression, SqlError] {
  let left = match self.parse_additive_expr() {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  if self.current_token is Some(_) {
    let token = self.current_token.unwrap()
    if token.token_type == Operator {
      let op_val = token.value.to_upper()
      let op = if op_val == "=" {
        Equal
      } else if op_val == "!=" || op_val == "<>" {
        NotEqual
      } else if op_val == "<" {
        LessThan
      } else if op_val == ">" {
        GreaterThan
      } else if op_val == "<=" {
        LessThanOrEqual
      } else if op_val == ">=" {
        GreaterThanOrEqual
      } else {
        return Ok(left)
      }
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      let right = match self.parse_additive_expr() {
        Ok(e) => e
        Err(e) => return Err(e)
      }
      return Ok(BinaryOp(BinaryOpExpr::{ operator: op, left, right, }))
    }
  }
  // IS [NOT] NULL
  if self.is_keyword("IS") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let mut negated = false
    if self.is_keyword("NOT") {
      negated = true
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    }
    if !self.is_keyword("NULL") {
      return Err(Syntax_Error)
    }
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    if negated {
      return Ok(UnaryOp(UnaryOpExpr::{ operator: IsNotNull, operand: left, }))
    }
    return Ok(UnaryOp(UnaryOpExpr::{ operator: IsNull, operand: left, }))
  }

  // [NOT] LIKE / IN / BETWEEN
  let mut negated = false
  if self.is_keyword("NOT") {
    negated = true
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  if self.is_keyword("LIKE") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let right = match self.parse_additive_expr() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    let operator = if negated { NotLike } else { Like }
    return Ok(BinaryOp(BinaryOpExpr::{ operator, left, right, }))
  }
  if self.is_keyword("IN") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    if !self.is_value("(") {
      return Err(Syntax_Error)
    }
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let items = match self.parse_expression_list() {
      Ok(items) => items
      Err(e) => return Err(e)
    }
    if !self.is_value(")") {
      return Err(Syntax_Error)
    }
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let operator = if negated { NotIn } else { In }
    return Ok(BinaryOp(BinaryOpExpr::{ operator, left, right: List(items), }))
  }
  if self.is_keyword("BETWEEN") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let low = match self.parse_additive_expr() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    if !self.is_keyword("AND") {
      return Err(Syntax_Error)
    }
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let high = match self.parse_additive_expr() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    let bounds : Array[Expression] = [low, high]
    let between = BinaryOp(BinaryOpExpr::{
      operator: Between,
      left,
      right: List(bounds),
    })
    if negated {
      return Ok(UnaryOp(UnaryOpExpr::{ operator: Not, operand: between, }))
    }
    return Ok(between)
  }
  if negated {
    return Err(Syntax_Error)
  }
  Ok(left)
}

///|
/// 解析逗号分隔的表达式列表（用于 IN 的值列表）
fn Parser::parse_expression_list(
  self : Parser,
) -> Result[Array[Expression], SqlError] {
  let items : Array[Expression] = []
  if self.is_value(")") {
    return Ok(items)
  }
  let mut has_more = true
  while has_more {
    let expr = match self.parse_expression() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    items.push(expr)
    if self.is_value(",") {
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    } else {
      has_more = false
    }
  }
  Ok(items)
}

///|
/// 解析基本表达式（列引用、字面量、括号表达式）
fn Parser::parse_primary_expr(self : Parser) -> Result[Expression, SqlError] {
  let token = match self.current_token {
    Some(t) => t
    None => return Err(Syntax_Error)
  }

  // 括号表达式
  if token.token_type == LeftParen {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let expr = match self.parse_or_expr() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    match self.current_token {
      Some(t) if t.token_type == RightParen =>
        match self.advance() {
          Ok(_) => Ok(expr)
          Err(e) => return Err(e)
        }
      _ => Err(Syntax_Error)
    }
  } else if token.token_type == Identifier {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let name = token.value.to_string()
    // 标识符后紧跟左括号时按函数调用解析，如 COUNT(*)
    if self.is_value("(") {
      self.parse_function_call(name)
    } else {
      Ok(ColumnRef(name))
    }
  } else if token.token_type == StringLiteral {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    Ok(
      Literal(SqlValue::{
        value_type: String,
        value: @realtime_db.Str(token.value.to_string()),
        is_null: false,
      }),
    )
  } else if token.token_type == NumberLiteral {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let text = token.value.to_string()
    // 整数字面量保持 Int，含小数点/指数的按 Double 解析
    let is_float = text.contains(".") ||
      text.contains("e") ||
      text.contains("E")
    if is_float {
      let value = @string.parse_double(text) catch { _ => 0.0 }
      Ok(
        Literal(SqlValue::{
          value_type: Double,
          value: @realtime_db.Float(value),
          is_null: false,
        }),
      )
    } else {
      let value = @string.parse_int(text) catch { _ => 0 }
      Ok(
        Literal(SqlValue::{
          value_type: Int,
          value: @realtime_db.Int(value),
          is_null: false,
        }),
      )
    }
  } else if token.token_type == Keyword {
    // NULL / TRUE / FALSE 字面量
    let upper = token.value.to_upper()
    if upper == "NULL" {
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      Ok(
        Literal(SqlValue::{
          value_type: Null,
          value: @realtime_db.Null,
          is_null: true,
        }),
      )
    } else if upper == "TRUE" || upper == "FALSE" {
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      Ok(
        Literal(SqlValue::{
          value_type: Boolean,
          value: @realtime_db.Bool(upper == "TRUE"),
          is_null: false,
        }),
      )
    } else {
      // 非字面量关键字（如 key）作为列引用，避免 WHERE key = ... 被误判
      match self.advance() {
        Ok(_) => Ok(ColumnRef(token.value.to_string()))
        Err(e) => Err(e)
      }
    }
  } else {
    // 通配符等无法归类的 token 仍需消费，避免词法位置停滞
    match self.advance() {
      Ok(_) => Ok(Wildcard)
      Err(e) => Err(e)
    }
  }
}

///|
/// 解析标识符
fn Parser::parse_identifier(self : Parser) -> Result[String, SqlError] {
  match self.current_token {
    Some(token) =>
      if token.token_type == Identifier {
        match self.advance() {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
        Ok(token.value.to_string())
      } else {
        Ok("")
      }
    None => Ok("")
  }
}

///|
/// 解析数字
fn Parser::parse_number(self : Parser) -> Result[Int32, SqlError] {
  match self.current_token {
    Some(token) =>
      if token.token_type == NumberLiteral {
        match self.advance() {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
        // 数字无法解析时返回 0
        Ok(@string.parse_int(token.value) catch { _ => 0 })
      } else {
        Ok(0)
      }
    None => Ok(0)
  }
}

///|
/// 解析 GROUP BY 表达式列表
fn Parser::parse_group_by(self : Parser) -> Result[Array[Expression], SqlError] {
  let items : Array[Expression] = []
  let mut has_more = true
  while has_more {
    let expr = match self.parse_expression() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    items.push(expr)
    if self.is_value(",") {
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    } else {
      has_more = false
    }
  }
  Ok(items)
}

///|
/// 解析函数调用，调用时左括号尚未消费
fn Parser::parse_function_call(
  self : Parser,
  name : String,
) -> Result[Expression, SqlError] {
  match self.advance() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let mut distinct = false
  if self.is_keyword("DISTINCT") {
    distinct = true
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  let arguments : Array[Expression] = []
  if !self.is_value(")") {
    let mut has_more = true
    while has_more {
      if self.is_value(")") {
        has_more = false
      } else {
        let expr = match self.parse_expression() {
          Ok(e) => e
          Err(e) => return Err(e)
        }
        arguments.push(expr)
        if self.is_value(",") {
          match self.advance() {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        } else {
          has_more = false
        }
      }
    }
  }
  if self.is_value(")") {
    match self.advance() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  } else {
    return Err(Syntax_Error)
  }
  Ok(
    FunctionCall(FunctionCallExpr::{ function_name: name, arguments, distinct, }),
  )
}

///|
/// 解析 ORDER BY 子句
fn Parser::parse_order_by(
  self : Parser,
) -> Result[Array[OrderByItem], SqlError] {
  let items : Array[OrderByItem] = []
  let mut has_more = true

  while has_more {
    let expr = match self.parse_expression() {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    let mut ascending = true

    // 检查排序方向
    if self.is_keyword("ASC") {
      ascending = true
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    } else if self.is_keyword("DESC") {
      ascending = false
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    }

    items.push(OrderByItem::{ expression: expr, ascending, })

    // 检查逗号
    if self.is_value(",") {
      match self.advance() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    } else {
      has_more = false
    }
  }

  Ok(items)
}

///|
/// 解析 INSERT 语句
fn Parser::parse_insert(self : Parser) -> SqlStatement {
  let _ = self
  // 简化实现
  Insert(InsertStatement::{
    table: "".to_string(),
    columns: None,
    values: None,
    select: None,
  })
}

///|
/// 解析 UPDATE 语句
fn Parser::parse_update(self : Parser) -> SqlStatement {
  let _ = self
  // 简化实现
  Update(UpdateStatement::{
    table: "".to_string(),
    set: [],
    where_condition: None,
  })
}

///|
/// 解析 DELETE 语句
fn Parser::parse_delete(self : Parser) -> SqlStatement {
  let _ = self
  // 简化实现
  Delete(DeleteStatement::{ table: "".to_string(), where_condition: None, })
}

///|
/// 解析 CREATE 语句
fn Parser::parse_create(self : Parser) -> SqlStatement {
  let _ = self
  // 简化实现
  CreateTable(CreateTableStatement::{
    table: "".to_string(),
    columns: [],
    constraints: None,
  })
}

///|
/// 解析 DROP 语句
fn Parser::parse_drop(self : Parser) -> SqlStatement {
  let _ = self
  // 简化实现
  DropTable(DropTableStatement::{ table: "".to_string(), if_exists: false, })
}

///|
/// 解析 BEGIN 语句
fn Parser::parse_begin(self : Parser) -> SqlStatement {
  let _ = self
  Begin(BeginStatement::{ isolation_level: None, })
}

///|
/// 解析 COMMIT 语句
fn Parser::parse_commit(self : Parser) -> SqlStatement {
  let _ = self
  Commit(CommitStatement::{ })
}

///|
/// 解析 ROLLBACK 语句
fn Parser::parse_rollback(self : Parser) -> SqlStatement {
  let _ = self
  Rollback(RollbackStatement::{ })
}

///|
/// 解析 EXPLAIN 语句
fn Parser::parse_explain(self : Parser) -> SqlStatement {
  let _ = self
  // 简化实现
  Explain(ExplainStatement::{
    statement: Select(SelectStatement::{
      select_items: [],
      from: None,
      where_condition: None,
      group_by: None,
      having: None,
      order_by: None,
      limit: None,
      offset: None,
    }),
  })
}

///|
/// 创建解析器
pub fn create_parser(lexer : Lexer) -> Parser {
  Parser::new(lexer)
}

///|
/// 解析 SQL 语句
pub fn parse_sql(sql : String) -> Result[SqlStatement, SqlError] {
  let lexer = Lexer::new(sql)
  let parser = Parser::new(lexer)
  parser.parse()
}
