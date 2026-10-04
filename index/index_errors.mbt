// 索引错误类型定义
//
// 定义索引组件的所有错误场景

///|
/// 索引错误类型
pub(all) enum IndexError {
  /// 索引已存在
  Index_Already_Exists
  /// 索引不存在
  Index_Not_Found
  /// 无效字段路径
  Invalid_Field_Path
  /// 索引限制超限（单表索引数超过 16 个）
  Index_Limit_Exceeded
  /// 不支持的索引类型
  Unsupported_Type
  /// 索引未激活
  Index_Not_Active
  /// 索引正在重建
  Index_Rebuilding
  /// 索引已删除
  Index_Dropped
  /// 索引构建失败
  Build_Failed
  /// 索引重建失败
  Rebuild_Failed
  /// 查询超时
  Query_Timeout
  /// 查询值类型不匹配
  Type_Mismatch
  /// 覆盖索引不满足
  Cover_Index_Not_Satisfied
  /// 碎片整理失败
  Defragment_Failed
  /// 统计收集失败
  Stats_Collect_Failed
  /// 内部错误
  Internal_Error(String)
}

///|
pub impl Eq for IndexError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Index_Already_Exists, Index_Already_Exists) => true
    (Index_Not_Found, Index_Not_Found) => true
    (Invalid_Field_Path, Invalid_Field_Path) => true
    (Index_Limit_Exceeded, Index_Limit_Exceeded) => true
    (Unsupported_Type, Unsupported_Type) => true
    (Index_Not_Active, Index_Not_Active) => true
    (Index_Rebuilding, Index_Rebuilding) => true
    (Index_Dropped, Index_Dropped) => true
    (Build_Failed, Build_Failed) => true
    (Rebuild_Failed, Rebuild_Failed) => true
    (Query_Timeout, Query_Timeout) => true
    (Type_Mismatch, Type_Mismatch) => true
    (Cover_Index_Not_Satisfied, Cover_Index_Not_Satisfied) => true
    (Defragment_Failed, Defragment_Failed) => true
    (Stats_Collect_Failed, Stats_Collect_Failed) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend IndexError with Eq::{equal, not_equal}

///|
pub impl Debug for IndexError with fn to_repr(self) -> Repr {
  match self {
    Index_Already_Exists => Repr::ctor("Index_Already_Exists", [])
    Index_Not_Found => Repr::ctor("Index_Not_Found", [])
    Invalid_Field_Path => Repr::ctor("Invalid_Field_Path", [])
    Index_Limit_Exceeded => Repr::ctor("Index_Limit_Exceeded", [])
    Unsupported_Type => Repr::ctor("Unsupported_Type", [])
    Index_Not_Active => Repr::ctor("Index_Not_Active", [])
    Index_Rebuilding => Repr::ctor("Index_Rebuilding", [])
    Index_Dropped => Repr::ctor("Index_Dropped", [])
    Build_Failed => Repr::ctor("Build_Failed", [])
    Rebuild_Failed => Repr::ctor("Rebuild_Failed", [])
    Query_Timeout => Repr::ctor("Query_Timeout", [])
    Type_Mismatch => Repr::ctor("Type_Mismatch", [])
    Cover_Index_Not_Satisfied => Repr::ctor("Cover_Index_Not_Satisfied", [])
    Defragment_Failed => Repr::ctor("Defragment_Failed", [])
    Stats_Collect_Failed => Repr::ctor("Stats_Collect_Failed", [])
    Internal_Error(msg) => Repr::ctor("Internal_Error", [(None, Repr(msg))])
  }
}

///|
pub extend IndexError with Debug::{to_repr}

///|
/// 将错误转为可读字符串
pub fn IndexError::to_string(self : IndexError) -> String {
  match self {
    Index_Already_Exists => "Index already exists"
    Index_Not_Found => "Index not found"
    Invalid_Field_Path => "Invalid field path"
    Index_Limit_Exceeded => "Index limit exceeded (max 16 per table)"
    Unsupported_Type => "Unsupported index type"
    Index_Not_Active => "Index is not active"
    Index_Rebuilding => "Index is rebuilding"
    Index_Dropped => "Index has been dropped"
    Build_Failed => "Index build failed"
    Rebuild_Failed => "Index rebuild failed"
    Query_Timeout => "Query timeout"
    Type_Mismatch => "Value type mismatch"
    Cover_Index_Not_Satisfied => "Cover index not satisfied"
    Defragment_Failed => "Defragment failed"
    Stats_Collect_Failed => "Stats collection failed"
    Internal_Error(msg) => "Internal error: " + msg
  }
}

///|
/// 查询错误类型
pub(all) enum QueryError {
  /// 索引不存在
  Index_Not_Found
  /// 索引未激活
  Index_Not_Active
  /// 查询超时
  Query_Timeout
  /// 查询值类型不匹配
  Type_Mismatch
  /// 无效查询范围
  Invalid_Range
  /// 内部错误
  Internal_Error(String)
}

///|
pub impl Eq for QueryError with fn equal(self, other) -> Bool {
  match (self, other) {
    (Index_Not_Found, Index_Not_Found) => true
    (Index_Not_Active, Index_Not_Active) => true
    (Query_Timeout, Query_Timeout) => true
    (Type_Mismatch, Type_Mismatch) => true
    (Invalid_Range, Invalid_Range) => true
    (Internal_Error(a), Internal_Error(b)) => a == b
    _ => false
  }
}

///|
pub extend QueryError with Eq::{equal, not_equal}

///|
pub impl Debug for QueryError with fn to_repr(self) -> Repr {
  match self {
    Index_Not_Found => Repr::ctor("Index_Not_Found", [])
    Index_Not_Active => Repr::ctor("Index_Not_Active", [])
    Query_Timeout => Repr::ctor("Query_Timeout", [])
    Type_Mismatch => Repr::ctor("Type_Mismatch", [])
    Invalid_Range => Repr::ctor("Invalid_Range", [])
    Internal_Error(msg) => Repr::ctor("Internal_Error", [(None, Repr(msg))])
  }
}

///|
pub extend QueryError with Debug::{to_repr}

///|
/// 将查询错误转为可读字符串
pub fn QueryError::to_string(self : QueryError) -> String {
  match self {
    Index_Not_Found => "Index not found"
    Index_Not_Active => "Index is not active"
    Query_Timeout => "Query timeout"
    Type_Mismatch => "Value type mismatch"
    Invalid_Range => "Invalid query range"
    Internal_Error(msg) => "Internal error: " + msg
  }
}
