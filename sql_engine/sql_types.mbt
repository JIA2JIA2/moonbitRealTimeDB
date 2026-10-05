// SQL 查询引擎 - 核心类型定义
//
// 定义 SQL 解析器、优化器、执行器所需的数据结构

///|
/// 列类型枚举
pub(all) enum ColumnType {
  /// 整数
  Int
  /// 大整数
  BigInt
  /// 双精度浮点数
  Double
  /// 字符串
  String
  /// 布尔值
  Boolean
  /// 时间戳
  Timestamp
  /// 十进制数
  Decimal
  /// 数组
  Array
  /// 映射
  Map
  /// 空值
  Null
}

///|
impl Eq for ColumnType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Int, Int) => true
    (BigInt, BigInt) => true
    (Double, Double) => true
    (String, String) => true
    (Boolean, Boolean) => true
    (Timestamp, Timestamp) => true
    (Decimal, Decimal) => true
    (Array, Array) => true
    (Map, Map) => true
    (Null, Null) => true
    _ => false
  }
}

///|
pub extend ColumnType with Eq::{equal, not_equal}

///|
impl Debug for ColumnType with fn to_repr(self) -> Repr {
  match self {
    Int => Repr::ctor("Int", [])
    BigInt => Repr::ctor("BigInt", [])
    Double => Repr::ctor("Double", [])
    String => Repr::ctor("String", [])
    Boolean => Repr::ctor("Boolean", [])
    Timestamp => Repr::ctor("Timestamp", [])
    Decimal => Repr::ctor("Decimal", [])
    Array => Repr::ctor("Array", [])
    Map => Repr::ctor("Map", [])
    Null => Repr::ctor("Null", [])
  }
}

///|
pub extend ColumnType with Debug::{to_repr}

///|
/// 列元数据
pub(all) struct ColumnMeta {
  /// 列名
  name : String
  /// 列类型
  column_type : ColumnType
  /// 是否可空
  nullable : Bool
  /// 精度
  precision : Int
  /// 标度
  scale : Int
}

///|
/// 表结构
pub(all) struct TableSchema {
  /// 列定义
  columns : Array[Column]
  /// 主键列
  primary_key : Array[String]
  /// 约束
  constraints : Array[Constraint]
}

///|
/// 列定义
pub(all) struct Column {
  /// 列名
  name : String
  /// 列类型
  column_type : ColumnType
  /// 是否可空
  nullable : Bool
  /// 默认值
  default_value : @realtime_db.Value?
  /// 长度
  length : Int?
  /// 别名
  alias : String?
}

///|
/// 约束
pub(all) struct Constraint {
  /// 约束名
  name : String
  /// 约束类型
  constraint_type : ConstraintType
  /// 列名
  columns : Array[String]
  /// 引用表（外键）
  referenced_table : String?
  /// 引用列（外键）
  referenced_columns : Array[String]?
}

///|
/// 约束类型枚举
pub(all) enum ConstraintType {
  /// 主键
  PrimaryKey
  /// 外键
  ForeignKey
  /// 唯一约束
  Unique
  /// 非空
  NotNull
  /// 检查约束
  Check
  /// 默认值
  Default
}

///|
impl Eq for ConstraintType with fn equal(self, other) -> Bool {
  match (self, other) {
    (PrimaryKey, PrimaryKey) => true
    (ForeignKey, ForeignKey) => true
    (Unique, Unique) => true
    (NotNull, NotNull) => true
    (Check, Check) => true
    (Default, Default) => true
    _ => false
  }
}

///|
pub extend ConstraintType with Eq::{equal, not_equal}

///|
/// SQL 值
pub(all) struct SqlValue {
  /// 值类型
  value_type : ColumnType
  /// 值
  value : @realtime_db.Value
  /// 是否为空
  is_null : Bool
}

///|
/// SQL 错误类型
pub(all) enum SqlError {
  /// 语法错误
  Syntax_Error
  /// 解析错误
  Parse_Error
  /// 列不存在
  Column_Not_Found
  /// 表不存在
  Table_Not_Found
  /// 数据库不存在
  Database_Not_Found
  /// 类型不匹配
  Type_Mismatch
  /// 无效操作符
  Invalid_Operator
  /// 无效值
  Invalid_Value
  /// 约束违反
  Constraint_Violation
  /// 除零错误
  Division_By_Zero
  /// 溢出
  Overflow
  /// 内部错误
  Internal_Error(String)
  /// 不支持
  Not_Implemented(String)
}

///|
impl Eq for SqlError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Syntax_Error, Syntax_Error) => true
    (Parse_Error, Parse_Error) => true
    (Column_Not_Found, Column_Not_Found) => true
    (Table_Not_Found, Table_Not_Found) => true
    (Database_Not_Found, Database_Not_Found) => true
    (Type_Mismatch, Type_Mismatch) => true
    (Invalid_Operator, Invalid_Operator) => true
    (Invalid_Value, Invalid_Value) => true
    (Constraint_Violation, Constraint_Violation) => true
    (Division_By_Zero, Division_By_Zero) => true
    (Overflow, Overflow) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    (Not_Implemented(a), Not_Implemented(b)) => a == b
    _ => false
  }
}

///|
pub extend SqlError with Eq::{equal, not_equal}

///|
impl Debug for SqlError with fn to_repr(self) -> Repr {
  match self {
    Syntax_Error => Repr::ctor("Syntax_Error", [])
    Parse_Error => Repr::ctor("Parse_Error", [])
    Column_Not_Found => Repr::ctor("Column_Not_Found", [])
    Table_Not_Found => Repr::ctor("Table_Not_Found", [])
    Database_Not_Found => Repr::ctor("Database_Not_Found", [])
    Type_Mismatch => Repr::ctor("Type_Mismatch", [])
    Invalid_Operator => Repr::ctor("Invalid_Operator", [])
    Invalid_Value => Repr::ctor("Invalid_Value", [])
    Constraint_Violation => Repr::ctor("Constraint_Violation", [])
    Division_By_Zero => Repr::ctor("Division_By_Zero", [])
    Overflow => Repr::ctor("Overflow", [])
    Internal_Error(msg) => Repr::ctor("Internal_Error", [(None, Repr(msg))])
    Not_Implemented(msg) => Repr::ctor("Not_Implemented", [(None, Repr(msg))])
  }
}

///|
pub extend SqlError with Debug::{to_repr}

///|
/// 获取错误码
pub fn SqlError::code(self : SqlError) -> Int {
  match self {
    Syntax_Error => 3001
    Parse_Error => 3002
    Column_Not_Found => 3003
    Table_Not_Found => 3004
    Database_Not_Found => 3005
    Type_Mismatch => 3006
    Invalid_Operator => 3007
    Invalid_Value => 3008
    Constraint_Violation => 3009
    Division_By_Zero => 3010
    Overflow => 3011
    Internal_Error(_) => 3099
    Not_Implemented(_) => 3098
  }
}

///|
/// 获取错误消息
pub fn SqlError::message(self : SqlError) -> String {
  match self {
    Syntax_Error => "SQL syntax error"
    Parse_Error => "SQL parse error"
    Column_Not_Found => "Column not found"
    Table_Not_Found => "Table not found"
    Database_Not_Found => "Database not found"
    Type_Mismatch => "Type mismatch"
    Invalid_Operator => "Invalid operator"
    Invalid_Value => "Invalid value"
    Constraint_Violation => "Constraint violation"
    Division_By_Zero => "Division by zero"
    Overflow => "Overflow"
    Internal_Error(msg) => "Internal error: " + msg
    Not_Implemented(msg) => "Not implemented: " + msg
  }
}

///|
/// 转为字符串
pub fn SqlError::to_string(self : SqlError) -> String {
  "[Error " + self.code().to_string() + "] " + self.message()
}

///|
/// SQL 语句类型
pub(all) enum SqlStatement {
  /// SELECT 语句
  Select(SelectStatement)
  /// INSERT 语句
  Insert(InsertStatement)
  /// UPDATE 语句
  Update(UpdateStatement)
  /// DELETE 语句
  Delete(DeleteStatement)
  /// CREATE TABLE 语句
  CreateTable(CreateTableStatement)
  /// DROP TABLE 语句
  DropTable(DropTableStatement)
  /// CREATE INDEX 语句
  CreateIndex(CreateIndexStatement)
  /// DROP INDEX 语句
  DropIndex(DropIndexStatement)
  /// BEGIN 语句
  Begin(BeginStatement)
  /// COMMIT 语句
  Commit(CommitStatement)
  /// ROLLBACK 语句
  Rollback(RollbackStatement)
  /// EXPLAIN 语句
  Explain(ExplainStatement)
}

///|
/// SELECT 语句
pub(all) struct SelectStatement {
  /// 选择列
  select_items : Array[SelectItem>
  /// 表名
  from : String?
  /// WHERE 条件
  where_condition : Expression?
  /// GROUP BY 子句
  group_by : Array[Expression]?
  /// HAVING 子句
  having : Expression?
  /// ORDER BY 子句
  order_by : Array[OrderByItem>?
  /// LIMIT 子句
  limit : Int?
  /// OFFSET 子句
  offset : Int?
}

///|
/// 选择项
pub(all) struct SelectItem {
  /// 表达式
  expression : Expression
  /// 别名
  alias : String?
}

///|
/// ORDER BY 项
pub(all) struct OrderByItem {
  /// 表达式
  expression : Expression
  /// 是否升序
  ascending : Bool
}

///|
/// INSERT 语句
pub(all) struct InsertStatement {
  /// 表名
  table : String
  /// 列名
  columns : Array[String]?
  /// 值
  values : Array[Array[Expression]>?
  /// SELECT 子句
  select : SelectStatement?
}

///|
/// UPDATE 语句
pub(all) struct UpdateStatement {
  /// 表名
  table : String
  /// SET 子句
  set : Array[(String, Expression)]
  /// WHERE 条件
  where_condition : Expression?
}

///|
/// DELETE 语句
pub(all) struct DeleteStatement {
  /// 表名
  table : String
  /// WHERE 条件
  where_condition : Expression?
}

///|
/// CREATE TABLE 语句
pub(all) struct CreateTableStatement {
  /// 表名
  table : String
  /// 列定义
  columns : Array[ColumnDef>
  /// 约束
  constraints : Array[TableConstraint>?
}

///|
/// 列定义
pub(all) struct ColumnDef {
  /// 列名
  name : String
  /// 列类型
  column_type : ColumnType
  /// 是否可空
  nullable : Bool
  /// 默认值
  default : Expression?
  /// 约束
  constraints : Array[ColumnConstraint>?
}

///|
/// 表约束
pub(all) struct TableConstraint {
  /// 约束类型
  constraint_type : ConstraintType
  /// 列名
  columns : Array[String]
}

///|
/// 列约束
pub(all) enum ColumnConstraint {
  /// 非空
  NotNull
  /// 唯一
  Unique
  /// 主键
  PrimaryKey
  /// 默认值
  Default(Expression)
  /// 检查
  Check(Expression)
}

///|
/// DROP TABLE 语句
pub(all) struct DropTableStatement {
  /// 表名
  table : String
  /// 是否如果存在
  if_exists : Bool
}

///|
/// CREATE INDEX 语句
pub(all) struct CreateIndexStatement {
  /// 索引名
  index_name : String
  /// 表名
  table : String
  /// 列名
  columns : Array[IndexColumn>?
  /// 是否唯一
  unique : Bool
}

///|
/// 索引列
pub(all) struct IndexColumn {
  /// 列名
  column : String
  /// 排序方向
  ascending : Bool
}

///|
/// DROP INDEX 语句
pub(all) struct DropIndexStatement {
  /// 索引名
  index_name : String
  /// 表名
  table : String
}

///|
/// BEGIN 语句
pub(all) struct BeginStatement {
  /// 隔离级别
  isolation_level : String?
}

///|
/// COMMIT 语句
pub(all) struct CommitStatement {}

///|
/// ROLLBACK 语句
pub(all) struct RollbackStatement {}

///|
/// EXPLAIN 语句
pub(all) struct ExplainStatement {
  /// 语句
  statement : SqlStatement
}

///|
/// 表达式
pub(all) enum Expression {
  /// 字面量
  Literal(SqlValue)
  /// 列引用
  ColumnRef(String)
  /// 二元操作
  BinaryOp(BinaryOpExpr)
  /// 一元操作
  UnaryOp(UnaryOpExpr)
  /// 函数调用
  FunctionCall(FunctionCallExpr)
  /// 子查询
  Subquery(SelectStatement)
  /// 列表
  List(Array[Expression])
  /// 条件表达式
  Case(CaseExpr)
  /// 通配符
  Wildcard
}

///|
/// 二元操作表达式
pub(all) struct BinaryOpExpr {
  /// 操作符
  operator : BinaryOperator
  /// 左操作数
  left : Expression
  /// 右操作数
  right : Expression
}

///|
/// 二元操作符
pub(all) enum BinaryOperator {
  /// 加
  Add
  /// 减
  Subtract
  /// 乘
  Multiply
  /// 除
  Divide
  /// 取模
  Modulo
  /// 等于
  Equal
  /// 不等于
  NotEqual
  /// 小于
  LessThan
  /// 小于等于
  LessThanOrEqual
  /// 大于
  GreaterThan
  /// 大于等于
  GreaterThanOrEqual
  /// AND
  And
  /// OR
  Or
  /// LIKE
  Like
  /// NOT LIKE
  NotLike
  /// IN
  In
  /// NOT IN
  NotIn
  /// BETWEEN
  Between
}

///|
/// 一元操作表达式
pub(all) struct UnaryOpExpr {
  /// 操作符
  operator : UnaryOperator
  /// 操作数
  operand : Expression
}

///|
/// 一元操作符
pub(all) enum UnaryOperator {
  /// 负号
  Negate
  /// NOT
  Not
  /// IS NULL
  IsNull
  /// IS NOT NULL
  IsNotNull
}

///|
/// 函数调用表达式
pub(all) struct FunctionCallExpr {
  /// 函数名
  function_name : String
  /// 参数
  arguments : Array[Expression]
  /// 是否 DISTINCT
  distinct : Bool
}

///|
/// CASE 表达式
pub(all) struct CaseExpr {
  /// 操作数
  operand : Expression?
  /// WHEN 子句
  when_clauses : Array[(Expression, Expression)]
  /// ELSE 子句
  else_clause : Expression?
}