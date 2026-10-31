// SQL SELECT 执行器
//
// 以 DB 的 key/value 记录作为行源：value 为 Map 时其字段展开为列，
// 同时提供 key / value 两个可引用列。支持 WHERE 过滤、表达式投影、
// ORDER BY 多键排序与 LIMIT。

///|
/// 执行 SELECT 语句，返回投影后的行（每行为 Value::Map）。
pub fn QueryExecutor::execute_select_statement(
  self : QueryExecutor,
  select : SelectStatement,
) -> Result[Array[@realtime_db.Value], SqlError] {
  let db = match self.db {
    Some(d) => d
    None => return Err(Internal_Error("Database not set"))
  }
  if select.group_by is Some(_) || select.having is Some(_) {
    return Err(Not_Implemented("GROUP BY / HAVING are not supported"))
  }

  let rows = build_rows(db)

  // WHERE 过滤
  let filtered : Array[@realtime_db.Value] = []
  match select.where_condition {
    Some(condition) =>
      for row in rows {
        let value = match eval_expression(condition, row) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let matched = match value {
          @realtime_db.Bool(flag) => flag
          @realtime_db.Null => false
          _ => return Err(Type_Mismatch)
        }
        if matched {
          filtered.push(row)
        }
      }
    None =>
      for row in rows {
        filtered.push(row)
      }
  }

  // ORDER BY 在投影前求值，允许按未投影的列排序
  let sorted = match select.order_by {
    Some(items) =>
      match sort_rows(filtered, items) {
        Ok(rows) => rows
        Err(error) => return Err(error)
      }
    None => filtered
  }

  // 投影
  let projected : Array[@realtime_db.Value] = []
  for row in sorted {
    match project_row(row, select.select_items) {
      Ok(value) => projected.push(value)
      Err(error) => return Err(error)
    }
  }

  // LIMIT
  match select.limit {
    Some(limit) =>
      if limit >= 0 && limit < projected.length() {
        projected.truncate(limit)
      }
    None => ()
  }

  Ok(projected)
}

///|
/// 将数据库记录构造成可执行的行：key、value 以及 Map 值的展开字段。
fn build_rows(db : @realtime_db.DB) -> Array[@realtime_db.Value] {
  let rows : Array[@realtime_db.Value] = []
  for (key, value) in db.entries() {
    let fields : Map[String, @realtime_db.Value] = Map([])
    fields.set("key", @realtime_db.Str(key))
    fields.set("value", value)
    match value {
      @realtime_db.Map(inner) =>
        for name, inner_value in inner.copy() {
          fields.set(name, inner_value)
        }
      _ => ()
    }
    rows.push(@realtime_db.Map(fields))
  }
  rows
}

///|
/// 求值表达式。
fn eval_expression(
  expr : Expression,
  row : @realtime_db.Value,
) -> Result[@realtime_db.Value, SqlError] {
  match expr {
    Literal(sql_value) => Ok(sql_value.value)
    ColumnRef(name) =>
      match row {
        @realtime_db.Map(fields) =>
          match fields.get(name) {
            Some(value) => Ok(value)
            None => Err(Column_Not_Found)
          }
        _ => Err(Column_Not_Found)
      }
    BinaryOp(op) => eval_binary(op, row)
    UnaryOp(op) => eval_unary(op, row)
    List(items) => {
      let values : Array[@realtime_db.Value] = []
      for item in items {
        let value = match eval_expression(item, row) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        values.push(value)
      }
      Ok(@realtime_db.Arr(values))
    }
    Wildcard => Err(Invalid_Operator)
    FunctionCall(_) => Err(Not_Implemented("function calls are not supported"))
    Subquery(_) => Err(Not_Implemented("subqueries are not supported"))
    Case(_) => Err(Not_Implemented("CASE expressions are not supported"))
  }
}

///|
/// 求值二元表达式，AND/OR 具备短路语义。
fn eval_binary(
  op : BinaryOpExpr,
  row : @realtime_db.Value,
) -> Result[@realtime_db.Value, SqlError] {
  match op.operator {
    And | Or => {
      let left = match eval_expression(op.left, row) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let left_flag = match left {
        @realtime_db.Bool(flag) => flag
        @realtime_db.Null => false
        _ => return Err(Type_Mismatch)
      }
      if op.operator is And && !left_flag {
        return Ok(@realtime_db.Bool(false))
      }
      if op.operator is Or && left_flag {
        return Ok(@realtime_db.Bool(true))
      }
      let right = match eval_expression(op.right, row) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let right_flag = match right {
        @realtime_db.Bool(flag) => flag
        @realtime_db.Null => false
        _ => return Err(Type_Mismatch)
      }
      Ok(@realtime_db.Bool(right_flag))
    }
    _ => {
      let left = match eval_expression(op.left, row) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let right = match eval_expression(op.right, row) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      eval_binary_values(op.operator, left, right)
    }
  }
}

///|
/// 按操作符对已求值的操作数计算。
fn eval_binary_values(
  operator : BinaryOperator,
  left : @realtime_db.Value,
  right : @realtime_db.Value,
) -> Result[@realtime_db.Value, SqlError] {
  match operator {
    Add | Subtract | Multiply | Divide | Modulo =>
      arithmetic(operator, left, right)
    Equal =>
      match compare_ordered(left, right) {
        Ok(order) => Ok(@realtime_db.Bool(order == 0))
        Err(_) => Ok(@realtime_db.Bool(false))
      }
    NotEqual =>
      match compare_ordered(left, right) {
        Ok(order) => Ok(@realtime_db.Bool(order != 0))
        Err(_) => Ok(@realtime_db.Bool(true))
      }
    LessThan | LessThanOrEqual | GreaterThan | GreaterThanOrEqual =>
      relational(operator, left, right)
    _ => Err(Not_Implemented("operator is not supported"))
  }
}

///|
/// 算术运算：两个整数保持整数结果，否则提升为浮点。
fn arithmetic(
  operator : BinaryOperator,
  left : @realtime_db.Value,
  right : @realtime_db.Value,
) -> Result[@realtime_db.Value, SqlError] {
  match (left, right) {
    (@realtime_db.Int(a), @realtime_db.Int(b)) =>
      match operator {
        Add => Ok(@realtime_db.Int(a + b))
        Subtract => Ok(@realtime_db.Int(a - b))
        Multiply => Ok(@realtime_db.Int(a * b))
        Divide =>
          if b == 0 {
            Err(Division_By_Zero)
          } else {
            Ok(@realtime_db.Int(a / b))
          }
        Modulo =>
          if b == 0 {
            Err(Division_By_Zero)
          } else {
            Ok(@realtime_db.Int(a % b))
          }
        _ => Err(Invalid_Operator)
      }
    _ => {
      let x = match to_double(left) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let y = match to_double(right) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match operator {
        Add => Ok(@realtime_db.Float(x + y))
        Subtract => Ok(@realtime_db.Float(x - y))
        Multiply => Ok(@realtime_db.Float(x * y))
        Divide =>
          if y == 0.0 {
            Err(Division_By_Zero)
          } else {
            Ok(@realtime_db.Float(x / y))
          }
        _ => Err(Invalid_Operator)
      }
    }
  }
}

///|
/// 关系比较。
fn relational(
  operator : BinaryOperator,
  left : @realtime_db.Value,
  right : @realtime_db.Value,
) -> Result[@realtime_db.Value, SqlError] {
  let order = match compare_ordered(left, right) {
    Ok(order) => order
    Err(error) => return Err(error)
  }
  match operator {
    LessThan => Ok(@realtime_db.Bool(order < 0))
    LessThanOrEqual => Ok(@realtime_db.Bool(order <= 0))
    GreaterThan => Ok(@realtime_db.Bool(order > 0))
    GreaterThanOrEqual => Ok(@realtime_db.Bool(order >= 0))
    _ => Err(Invalid_Operator)
  }
}

///|
/// 数值比较，返回 -1/0/1；数值与数值之间允许 int/float 混合比较。
fn compare_ordered(
  left : @realtime_db.Value,
  right : @realtime_db.Value,
) -> Result[Int32, SqlError] {
  match (left, right) {
    (@realtime_db.Int(a), @realtime_db.Int(b)) =>
      Ok(if a < b { -1 } else if a > b { 1 } else { 0 })
    (@realtime_db.Int(a), @realtime_db.Float(b)) =>
      Ok(compare_double(a.to_double(), b))
    (@realtime_db.Float(a), @realtime_db.Int(b)) =>
      Ok(compare_double(a, b.to_double()))
    (@realtime_db.Float(a), @realtime_db.Float(b)) => Ok(compare_double(a, b))
    (@realtime_db.Str(a), @realtime_db.Str(b)) => Ok(compare_string(a, b))
    (@realtime_db.Bool(a), @realtime_db.Bool(b)) =>
      Ok(if a == b { 0 } else if a { 1 } else { -1 })
    (@realtime_db.Null, @realtime_db.Null) => Ok(0)
    _ => Err(Type_Mismatch)
  }
}

///|
/// 按 UTF-8 码点做字典序比较，避免依赖 String 内建比较的未定义顺序。
fn compare_string(a : String, b : String) -> Int32 {
  let shorter = if a.length() < b.length() { a.length() } else { b.length() }
  let mut i = 0
  while i < shorter {
    let left = a.get_char(i).unwrap().to_int()
    let right = b.get_char(i).unwrap().to_int()
    if left < right {
      return -1
    }
    if left > right {
      return 1
    }
    i = i + 1
  }
  if a.length() < b.length() {
    -1
  } else if a.length() > b.length() {
    1
  } else {
    0
  }
}

///|
fn compare_double(a : Double, b : Double) -> Int32 {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
fn to_double(value : @realtime_db.Value) -> Result[Double, SqlError] {
  match value {
    @realtime_db.Int(i) => Ok(i.to_double())
    @realtime_db.Float(f) => Ok(f)
    _ => Err(Type_Mismatch)
  }
}

///|
/// 一元运算。
fn eval_unary(
  op : UnaryOpExpr,
  row : @realtime_db.Value,
) -> Result[@realtime_db.Value, SqlError] {
  let operand = match eval_expression(op.operand, row) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match op.operator {
    Negate =>
      match operand {
        @realtime_db.Int(i) => Ok(@realtime_db.Int(-i))
        @realtime_db.Float(f) => Ok(@realtime_db.Float(-f))
        _ => Err(Type_Mismatch)
      }
    Not =>
      match operand {
        @realtime_db.Bool(flag) => Ok(@realtime_db.Bool(!flag))
        @realtime_db.Null => Ok(@realtime_db.Bool(true))
        _ => Err(Type_Mismatch)
      }
    IsNull => Ok(@realtime_db.Bool(operand is @realtime_db.Null))
    IsNotNull => Ok(@realtime_db.Bool(!(operand is @realtime_db.Null)))
  }
}

///|
/// 对单行做投影：通配符展开源字段，其余表达式按别名或列名命名。
fn project_row(
  row : @realtime_db.Value,
  items : Array[SelectItem],
) -> Result[@realtime_db.Value, SqlError] {
  let fields : Map[String, @realtime_db.Value] = Map([])
  let mut index = 0
  for item in items {
    match item.expression {
      Wildcard =>
        match row {
          @realtime_db.Map(source) =>
            match source.get("value") {
              Some(@realtime_db.Map(inner)) =>
                for name, value in inner.copy() {
                  fields.set(name, value)
                }
              _ => {
                match source.get("key") {
                  Some(value) => fields.set("key", value)
                  None => ()
                }
                match source.get("value") {
                  Some(value) => fields.set("value", value)
                  None => ()
                }
              }
            }
          _ => ()
        }
      _ => {
        let value = match eval_expression(item.expression, row) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let name = match item.alias_name {
          Some(alias_name) => alias_name
          None =>
            match item.expression {
              ColumnRef(column) => column
              _ => "column_" + index.to_string()
            }
        }
        fields.set(name, value)
      }
    }
    index = index + 1
  }
  Ok(@realtime_db.Map(fields))
}

///|
/// 按 ORDER BY 多键排序（逐键比较，支持 ASC/DESC）。
fn sort_rows(
  rows : Array[@realtime_db.Value],
  items : Array[OrderByItem],
) -> Result[Array[@realtime_db.Value], SqlError] {
  let keyed : Array[(@realtime_db.Value, Array[@realtime_db.Value])] = []
  for row in rows {
    let keys : Array[@realtime_db.Value] = []
    for item in items {
      let value = match eval_expression(item.expression, row) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      keys.push(value)
    }
    keyed.push((row, keys))
  }
  keyed.sort_by(fn(a, b) {
    let mut result = 0
    let mut i = 0
    while i < items.length() && result == 0 {
      match compare_ordered(a.1[i], b.1[i]) {
        Ok(order) => {
          let directed = if items[i].ascending { order } else { -order }
          result = if directed < 0 { -1 } else if directed > 0 { 1 } else { 0 }
        }
        Err(_) => result = 0
      }
      i = i + 1
    }
    result
  })
  let sorted : Array[@realtime_db.Value] = []
  for pair in keyed {
    sorted.push(pair.0)
  }
  Ok(sorted)
}
