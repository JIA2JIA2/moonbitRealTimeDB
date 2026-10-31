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
  let rows = build_rows(db)
  let filtered = match filter_rows(rows, select.where_condition) {
    Ok(rows) => rows
    Err(error) => return Err(error)
  }

  let has_group = select.group_by is Some(_)
  let having_aggregate = match select.having {
    Some(condition) => is_aggregate_expression(condition)
    None => false
  }
  let has_aggregate = select_items_have_aggregate(select.select_items) ||
    having_aggregate
  if has_group || has_aggregate {
    execute_grouped(select, filtered)
  } else {
    execute_simple(select, filtered)
  }
}

///|
/// WHERE 过滤。
fn filter_rows(
  rows : Array[@realtime_db.Value],
  condition : Expression?,
) -> Result[Array[@realtime_db.Value], SqlError] {
  let filtered : Array[@realtime_db.Value] = []
  match condition {
    Some(expr) =>
      for row in rows {
        let value = match eval_expression(expr, row) {
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
  Ok(filtered)
}

///|
/// 非聚合查询：排序、投影、LIMIT。
fn execute_simple(
  select : SelectStatement,
  filtered : Array[@realtime_db.Value],
) -> Result[Array[@realtime_db.Value], SqlError] {
  let sorted = match select.order_by {
    Some(items) =>
      match sort_rows(filtered, items) {
        Ok(rows) => rows
        Err(error) => return Err(error)
      }
    None => filtered
  }
  let projected : Array[@realtime_db.Value] = []
  for row in sorted {
    let value = match project_row(row, select.select_items) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    projected.push(value)
  }
  apply_limit(projected, select.limit)
  Ok(projected)
}

///|
fn apply_limit(rows : Array[@realtime_db.Value], limit : Int32?) -> Unit {
  match limit {
    Some(value) =>
      if value >= 0 && value < rows.length() {
        rows.truncate(value)
      }
    None => ()
  }
}

///|
/// 分组结果：代表行用于求值非聚合列，rows 保存组内全部行供聚合使用。
priv struct Group {
  representative : @realtime_db.Value
  rows : Array[@realtime_db.Value]
}

///|
/// 分组执行：GROUP BY → HAVING → 投影 → ORDER BY → LIMIT。
fn execute_grouped(
  select : SelectStatement,
  filtered : Array[@realtime_db.Value],
) -> Result[Array[@realtime_db.Value], SqlError] {
  let groups = match build_groups(filtered, select.group_by) {
    Ok(groups) => groups
    Err(error) => return Err(error)
  }

  let kept : Array[Group] = []
  match select.having {
    Some(condition) =>
      for group in groups {
        let value = match
          eval_group_expression(condition, group.representative, group.rows) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let matched = match value {
          @realtime_db.Bool(flag) => flag
          @realtime_db.Null => false
          _ => return Err(Type_Mismatch)
        }
        if matched {
          kept.push(group)
        }
      }
    None =>
      for group in groups {
        kept.push(group)
      }
  }

  let outputs : Array[(@realtime_db.Value, Group)] = []
  for group in kept {
    let value = match project_group(group, select.select_items) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    outputs.push((value, group))
  }

  let sorted = match select.order_by {
    Some(items) =>
      match sort_group_outputs(outputs, items) {
        Ok(pairs) => pairs
        Err(error) => return Err(error)
      }
    None => outputs
  }
  let projected : Array[@realtime_db.Value] = []
  for pair in sorted {
    projected.push(pair.0)
  }
  apply_limit(projected, select.limit)
  Ok(projected)
}

///|
/// 构建分组；无 GROUP BY 时所有行归入单一分组（空输入也返回一组，用于整表聚合）。
fn build_groups(
  rows : Array[@realtime_db.Value],
  group_by : Array[Expression]?,
) -> Result[Array[Group], SqlError] {
  match group_by {
    Some(expressions) => {
      let groups : Map[String, Group] = Map([])
      let order : Array[String] = []
      for row in rows {
        let key_values : Array[@realtime_db.Value] = []
        for expr in expressions {
          let value = match eval_expression(expr, row) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          key_values.push(value)
        }
        let key = group_key(key_values)
        match groups.get(key) {
          Some(group) => {
            group.rows.push(row)
            groups.set(key, group)
          }
          None => {
            let group_rows : Array[@realtime_db.Value] = []
            group_rows.push(row)
            groups.set(key, Group::{ representative: row, rows: group_rows, })
            order.push(key)
          }
        }
      }
      let result : Array[Group] = []
      for key in order {
        match groups.get(key) {
          Some(group) => result.push(group)
          None => ()
        }
      }
      Ok(result)
    }
    None => {
      let group_rows : Array[@realtime_db.Value] = []
      for row in rows {
        group_rows.push(row)
      }
      let representative = if group_rows.length() > 0 {
        group_rows[0]
      } else {
        @realtime_db.Map(Map([]))
      }
      Ok([Group::{ representative, rows: group_rows, }])
    }
  }
}

///|
fn group_key(values : Array[@realtime_db.Value]) -> String {
  let parts : Array[String] = []
  for value in values {
    parts.push(group_value_key(value))
  }
  parts.join("|")
}

///|
/// 分组键的类型化字符串表示，避免 Int(1) 与 Str("1") 冲突。
fn group_value_key(value : @realtime_db.Value) -> String {
  match value {
    @realtime_db.Str(text) => "s" + text.length().to_string() + ":" + text
    @realtime_db.Int(number) => "i:" + number.to_string()
    @realtime_db.Float(number) => "f:" + number.to_string()
    @realtime_db.Bool(flag) => if flag { "b:1" } else { "b:0" }
    @realtime_db.Null => "n"
    @realtime_db.Arr(_) => "a:" + value.to_string()
    @realtime_db.Map(_) => "m:" + value.to_string()
  }
}

///|
/// 分组上下文的表达式求值：聚合函数基于组内全部行计算。
fn eval_group_expression(
  expr : Expression,
  representative : @realtime_db.Value,
  rows : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, SqlError] {
  match expr {
    FunctionCall(call) => eval_aggregate(call, rows)
    BinaryOp(op) =>
      match op.operator {
        And | Or => {
          let left = match
            eval_group_expression(op.left, representative, rows) {
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
          let right = match
            eval_group_expression(op.right, representative, rows) {
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
          let left = match
            eval_group_expression(op.left, representative, rows) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          let right = match
            eval_group_expression(op.right, representative, rows) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          eval_binary_values(op.operator, left, right)
        }
      }
    UnaryOp(op) => {
      let operand = match
        eval_group_expression(op.operand, representative, rows) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      eval_unary_value(op.operator, operand)
    }
    _ => eval_expression(expr, representative)
  }
}

///|
/// 聚合函数求值。
fn eval_aggregate(
  call : FunctionCallExpr,
  rows : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, SqlError] {
  match call.function_name.to_upper() {
    "COUNT" => eval_count(call, rows)
    "SUM" => eval_sum(call, rows)
    "AVG" => eval_avg(call, rows)
    "MIN" => eval_min_max(call, rows, true)
    "MAX" => eval_min_max(call, rows, false)
    _ =>
      Err(
        Not_Implemented("function " + call.function_name + " is not supported"),
      )
  }
}

///|
fn eval_count(
  call : FunctionCallExpr,
  rows : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, SqlError] {
  if call.arguments.length() == 0 {
    return Err(Invalid_Value)
  }
  match call.arguments[0] {
    Wildcard => Ok(@realtime_db.Int(rows.length()))
    argument => {
      let mut count = 0
      let seen : Map[String, Bool] = Map([])
      for row in rows {
        let value = match eval_expression(argument, row) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        match value {
          @realtime_db.Null => ()
          _ =>
            if call.distinct {
              let key = group_value_key(value)
              if !seen.contains(key) {
                seen.set(key, true)
                count = count + 1
              }
            } else {
              count = count + 1
            }
        }
      }
      Ok(@realtime_db.Int(count))
    }
  }
}

///|
fn eval_sum(
  call : FunctionCallExpr,
  rows : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, SqlError] {
  if call.arguments.length() != 1 {
    return Err(Invalid_Value)
  }
  let argument = call.arguments[0]
  let mut int_sum = 0
  let mut float_sum = 0.0
  let mut has_value = false
  let mut use_float = false
  for row in rows {
    let value = match eval_expression(argument, row) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match value {
      @realtime_db.Int(number) => {
        has_value = true
        int_sum = int_sum + number
        float_sum = float_sum + number.to_double()
      }
      @realtime_db.Float(number) => {
        has_value = true
        use_float = true
        float_sum = float_sum + number
      }
      @realtime_db.Null => ()
      _ => return Err(Type_Mismatch)
    }
  }
  if !has_value {
    Ok(@realtime_db.Null)
  } else if use_float {
    Ok(@realtime_db.Float(float_sum))
  } else {
    Ok(@realtime_db.Int(int_sum))
  }
}

///|
fn eval_avg(
  call : FunctionCallExpr,
  rows : Array[@realtime_db.Value],
) -> Result[@realtime_db.Value, SqlError] {
  if call.arguments.length() != 1 {
    return Err(Invalid_Value)
  }
  let argument = call.arguments[0]
  let mut total = 0.0
  let mut count = 0
  for row in rows {
    let value = match eval_expression(argument, row) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match value {
      @realtime_db.Int(number) => {
        total = total + number.to_double()
        count = count + 1
      }
      @realtime_db.Float(number) => {
        total = total + number
        count = count + 1
      }
      @realtime_db.Null => ()
      _ => return Err(Type_Mismatch)
    }
  }
  if count == 0 {
    Ok(@realtime_db.Null)
  } else {
    Ok(@realtime_db.Float(total / count.to_double()))
  }
}

///|
fn eval_min_max(
  call : FunctionCallExpr,
  rows : Array[@realtime_db.Value],
  want_min : Bool,
) -> Result[@realtime_db.Value, SqlError] {
  if call.arguments.length() != 1 {
    return Err(Invalid_Value)
  }
  let argument = call.arguments[0]
  let mut best : @realtime_db.Value? = None
  for row in rows {
    let value = match eval_expression(argument, row) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match value {
      @realtime_db.Null => ()
      _ =>
        match best {
          None => best = Some(value)
          Some(current) => {
            let order = match compare_ordered(value, current) {
              Ok(order) => order
              Err(error) => return Err(error)
            }
            if (want_min && order < 0) || (!want_min && order > 0) {
              best = Some(value)
            }
          }
        }
    }
  }
  match best {
    Some(value) => Ok(value)
    None => Ok(@realtime_db.Null)
  }
}

///|
fn is_aggregate_name(name : String) -> Bool {
  match name.to_upper() {
    "COUNT" | "SUM" | "AVG" | "MIN" | "MAX" => true
    _ => false
  }
}

///|
fn is_aggregate_expression(expr : Expression) -> Bool {
  match expr {
    FunctionCall(call) => is_aggregate_name(call.function_name)
    BinaryOp(op) =>
      is_aggregate_expression(op.left) || is_aggregate_expression(op.right)
    UnaryOp(op) => is_aggregate_expression(op.operand)
    _ => false
  }
}

///|
fn select_items_have_aggregate(items : Array[SelectItem]) -> Bool {
  for item in items {
    if is_aggregate_expression(item.expression) {
      return true
    }
  }
  false
}

///|
fn project_group(
  group : Group,
  items : Array[SelectItem],
) -> Result[@realtime_db.Value, SqlError] {
  let fields : Map[String, @realtime_db.Value] = Map([])
  let mut index = 0
  for item in items {
    match item.expression {
      Wildcard =>
        match group.representative {
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
        let value = match
          eval_group_expression(
            item.expression,
            group.representative,
            group.rows,
          ) {
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
fn eval_order_expression(
  expr : Expression,
  output_row : @realtime_db.Value,
  group : Group,
) -> Result[@realtime_db.Value, SqlError] {
  if is_aggregate_expression(expr) {
    eval_group_expression(expr, group.representative, group.rows)
  } else {
    match eval_expression(expr, output_row) {
      Ok(value) => Ok(value)
      Err(Column_Not_Found) =>
        eval_group_expression(expr, group.representative, group.rows)
      Err(error) => Err(error)
    }
  }
}

///|
fn sort_group_outputs(
  outputs : Array[(@realtime_db.Value, Group)],
  items : Array[OrderByItem],
) -> Result[Array[(@realtime_db.Value, Group)], SqlError] {
  let keyed : Array[((@realtime_db.Value, Group), Array[@realtime_db.Value])] = []
  for pair in outputs {
    let keys : Array[@realtime_db.Value] = []
    for item in items {
      let value = match eval_order_expression(item.expression, pair.0, pair.1) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      keys.push(value)
    }
    keyed.push((pair, keys))
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
  let sorted : Array[(@realtime_db.Value, Group)] = []
  for pair in keyed {
    sorted.push(pair.0)
  }
  Ok(sorted)
}

///|
/// 一元运算的纯值求值，供行上下文与分组上下文复用。
fn eval_unary_value(
  operator : UnaryOperator,
  operand : @realtime_db.Value,
) -> Result[@realtime_db.Value, SqlError] {
  match operator {
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
  eval_unary_value(op.operator, operand)
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
