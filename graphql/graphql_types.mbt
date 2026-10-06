// GraphQL 接口模块 - 核心类型定义
//
// 定义 GraphQL Schema、查询、变更、订阅等核心数据结构

///|
/// GraphQL 值类型
pub(all) enum GraphQLValue {
  /// 整数值
  IntValue(Int)
  /// 浮点值
  FloatValue(Double)
  /// 字符串值
  StringValue(String)
  /// 布尔值
  BoolValue(Bool)
  /// 空值
  NullValue
  /// 列表值
  ListValue(Array[GraphQLValue])
  /// 对象值
  ObjectValue(Map[String, GraphQLValue])
}

///|
impl Eq for GraphQLValue with fn equal(self, other) -> Bool {
  match (self, other) {
    (IntValue(a), IntValue(b)) => a == b
    (FloatValue(a), FloatValue(b)) => a == b
    (StringValue(a), StringValue(b)) => a == b
    (BoolValue(a), BoolValue(b)) => a == b
    (NullValue, NullValue) => true
    (ListValue(a), ListValue(b)) => a == b
    (ObjectValue(a), ObjectValue(b)) => a == b
    _ => false
  }
}

///|
pub extend GraphQLValue with Eq::{equal, not_equal}

///|
impl Debug for GraphQLValue with fn to_repr(self) -> Repr {
  match self {
    IntValue(i) => Repr::ctor("IntValue", [(None, Repr(i))])
    FloatValue(f) => Repr::ctor("FloatValue", [(None, Repr(f))])
    StringValue(s) => Repr::ctor("StringValue", [(None, Repr(s))])
    BoolValue(b) => Repr::ctor("BoolValue", [(None, Repr(b))])
    NullValue => Repr::ctor("NullValue", [])
    ListValue(l) => Repr::ctor("ListValue", [(None, Repr(l))])
    ObjectValue(o) => Repr::ctor("ObjectValue", [(None, Repr(o))])
  }
}

///|
pub extend GraphQLValue with Debug::{to_repr}

///|
/// GraphQL 类型
pub(all) enum GraphQLType {
  /// 标量类型
  Scalar(String)
  /// 对象类型
  Object(String)
  /// 列表类型
  List(Box[GraphQLType])
  /// 非空类型
  NonNull(Box[GraphQLType])
}

///|
/// GraphQL 字段定义
pub(all) struct GraphQLField {
  /// 字段名
  name : String
  /// 字段类型
  field_type : GraphQLType
  /// 描述
  description : String?
  /// 参数
  args : Map[String, GraphQLArg>
  /// 解析函数
  resolve_fn : (GraphQLContext) -> GraphQLValue?
}

///|
/// GraphQL 参数
pub(all) struct GraphQLArg {
  /// 参数名
  name : String
  /// 参数类型
  arg_type : GraphQLType
  /// 默认值
  default_value : GraphQLValue?
  /// 描述
  description : String?
}

///|
/// GraphQL 对象类型
pub(all) struct GraphQLObjectType {
  /// 类型名
  name : String
  /// 描述
  description : String?
  /// 字段映射
  fields : Map[String, GraphQLField>
  /// 接口列表
  interfaces : Array[String]
}

///|
/// GraphQL Schema
pub(all) struct GraphQLSchema {
  /// 查询类型
  query_type : GraphQLObjectType
  /// 变更类型
  mutation_type : GraphQLObjectType?
  /// 订阅类型
  subscription_type : GraphQLObjectType?
  /// 类型映射
  types : Map[String, GraphQLObjectType]
  /// 指令映射
  directives : Map[String, GraphQLDirective>
}

///|
/// GraphQL 指令
pub(all) struct GraphQLDirective {
  /// 指令名
  name : String
  /// 描述
  description : String?
  /// 位置
  locations : Array[DirectiveLocation]
  /// 参数
  args : Map[String, GraphQLArg>
}

///|
/// 指令位置枚举
pub(all) enum DirectiveLocation {
  /// 查询
  Query
  /// 变更
  Mutation
  /// 订阅
  Subscription
  /// 字段
  Field
  /// 片段定义
  FragmentDefinition
  /// 片段传播
  FragmentSpread
}

///|
impl Eq for DirectiveLocation with fn equal(self, other) -> Bool {
  match (self, other) {
    (Query, Query) => true
    (Mutation, Mutation) => true
    (Subscription, Subscription) => true
    (Field, Field) => true
    (FragmentDefinition, FragmentDefinition) => true
    (FragmentSpread, FragmentSpread) => true
    _ => false
  }
}

///|
pub extend DirectiveLocation with Eq::{equal, not_equal}

///|
/// GraphQL 查询上下文
pub(all) struct GraphQLContext {
  /// 请求 ID
  request_id : String
  /// 操作名称
  operation_name : String?
  /// 变量
  variables : Map[String, GraphQLValue]
  /// 上下文数据
  context_data : Map[String, @realtime_db.Value]
  /// 数据库引用
  db : @realtime_db.DB?
  /// 租户 ID
  tenant_id : String?
}

///|
/// GraphQL 请求
pub(all) struct GraphQLRequest {
  /// 查询字符串
  query : String
  /// 操作名称
  operation_name : String?
  /// 变量
  variables : Map[String, GraphQLValue]
}

///|
/// GraphQL 响应
pub(all) struct GraphQLResponse {
  /// 数据
  data : GraphQLValue?
  /// 错误列表
  errors : Array[GraphQLError>
  /// 扩展
  extensions : Map[String, GraphQLValue]
}

///|
/// GraphQL 错误
pub(all) struct GraphQLError {
  /// 错误消息
  message : String
  /// 行号
  line : Int?
  /// 列号
  column : Int?
  /// 路径
  path : Array[String]?
  /// 扩展信息
  extensions : Map[String, GraphQLValue]
}

///|
/// GraphQL 错误类型
pub(all) enum GraphQLErrorType {
  /// 语法错误
  Syntax_Error
  /// 验证错误
  Validation_Error
  /// 解析错误
  Parse_Error
  /// 执行错误
  Execution_Error
  /// 内部错误
  Internal_Error
}

///|
impl Eq for GraphQLErrorType with fn equal(self, other) -> Bool {
  match (self, other) {
    (Syntax_Error, Syntax_Error) => true
    (Validation_Error, Validation_Error) => true
    (Parse_Error, Parse_Error) => true
    (Execution_Error, Execution_Error) => true
    (Internal_Error, Internal_Error) => true
    _ => false
  }
}

///|
pub extend GraphQLErrorType with Eq::{equal, not_equal}

///|
/// GraphQL 错误
pub(all) enum GraphQLErrorEnum {
  /// 语法错误
  SyntaxError(String)
  /// 字段不存在
  FieldNotFound(String)
  /// 类型不匹配
  TypeMismatch(String)
  /// 参数缺失
  MissingArgument(String)
  /// 内部错误
  InternalError(String)
}

///|
impl Eq for GraphQLErrorEnum with fn equal(self, other) -> Bool {
  match (self, other) {
    (SyntaxError(a), SyntaxError(b)) => a == b
    (FieldNotFound(a), FieldNotFound(b)) => a == b
    (TypeMismatch(a), TypeMismatch(b)) => a == b
    (MissingArgument(a), MissingArgument(b)) => a == b
    (InternalError(a), InternalError(b)) => a == b
    _ => false
  }
}

///|
pub extend GraphQLErrorEnum with Eq::{equal, not_equal}

///|
/// 获取错误消息
pub fn GraphQLErrorEnum::message(self : GraphQLErrorEnum) -> String {
  match self {
    SyntaxError(msg) => "Syntax error: " + msg
    FieldNotFound(field) => "Field not found: " + field
    TypeMismatch(msg) => "Type mismatch: " + msg
    MissingArgument(arg) => "Missing argument: " + arg
    InternalError(msg) => "Internal error: " + msg
  }
}

///|
/// GraphQL 错误码
pub fn GraphQLErrorEnum::code(self : GraphQLErrorEnum) -> Int {
  match self {
    SyntaxError(_) => 7001
    FieldNotFound(_) => 7002
    TypeMismatch(_) => 7003
    MissingArgument(_) => 7004
    InternalError(_) => 7099
  }
}

///|
/// GraphQL 解析结果
pub(all) struct GraphQLParseResult {
  /// 是否成功
  success : Bool
  /// 解析后的值
  value : GraphQLValue?
  /// 错误列表
  errors : Array[GraphQLErrorEnum]
}

///|
/// GraphQL 执行结果
pub(all) struct GraphQLExecutionResult {
  /// 是否成功
  success : Bool
  /// 数据
  data : GraphQLValue?
  /// 错误列表
  errors : Array[GraphQLErrorEnum]
}

///|
/// GraphQL 配置
pub(all) struct GraphQLConfig {
  /// 是否启用 DataLoader
  enable_dataloader : Bool
  /// 是否启用缓存
  enable_cache : Bool
  /// 缓存大小
  cache_size : Int
  /// 缓存 TTL（秒）
  cache_ttl : Int
  /// 最大查询深度
  max_query_depth : Int
  /// 最大字段数
  max_field_count : Int
  /// 是否启用订阅
  enable_subscription : Bool
}

///|
/// 默认 GraphQL 配置
pub fn GraphQLConfig::default() -> GraphQLConfig {
  {
    enable_dataloader: true,
    enable_cache: true,
    cache_size: 10000,
    cache_ttl: 300,
    max_query_depth: 10,
    max_field_count: 1000,
    enable_subscription: true,
  }
}

///|
/// GraphQL 统计
pub(all) struct GraphQLStats {
  /// 总查询数
  total_queries : Int
  /// 总变更数
  total_mutations : Int
  /// 总订阅数
  total_subscriptions : Int
  /// 平均延迟（毫秒）
  avg_latency_ms : Double
  /// P99 延迟（毫秒）
  p99_latency_ms : Int
  /// 错误数
  error_count : Int
  /// 缓存命中率
  cache_hit_rate : Double
}