// 元数据过滤表达式模块
//
// 对向量记录的 metadata 求值 FilterExpr，供检索链路做过滤。
// 范围比较（Gt/Lt/Gte/Lte）的阈值类型为 Double，字段值须为
// 数值类型（Int/Float），非数值字段不参与匹配。

///|
/// 将元数据值提取为 Double（数值字段 Int/Float），非数值返回 None
fn metadata_value_as_double(v : @realtime_db.Value) -> Double? {
  match v {
    @realtime_db.Int(i) => Some(i.to_double())
    @realtime_db.Float(f) => Some(f)
    _ => None
  }
}

///|
/// 数值有序比较：字段值须为数值类型，按给定比较函数与阈值比较。
/// 字段缺失或非数值时不匹配。
fn compare_metadata_field(
  metadata : Map[String, @realtime_db.Value],
  field : String,
  threshold : Double,
  cmp : (Double, Double) -> Bool,
) -> Bool {
  match metadata.get(field) {
    Some(v) =>
      match metadata_value_as_double(v) {
        Some(x) => cmp(x, threshold)
        None => false
      }
    None => false
  }
}

///|
/// 对一条记录的元数据求值过滤表达式，返回是否匹配。
///
/// 语义约定：
/// - `Eq(field, value)`：字段值与目标值相等（Value 的 Eq 语义，
///   跨类型一律不匹配）；字段缺失不匹配
/// - `Gt/Lt/Gte/Lte(field, threshold)`：字段为数值（Int/Float）时
///   与阈值比较；非数值字段或字段缺失不匹配
/// - `Exists(field)`：元数据中存在该字段（含 Null 值字段）
/// - `And(exprs)`：全部子表达式为真；空数组视为真
/// - `Or(exprs)`：任一子表达式为真；空数组视为假
/// - `Not(inner)`：子表达式取反
///
/// And/Or/Not 递归求值，表达式深度由构造方控制。
pub fn FilterExpr::evaluate(
  self : FilterExpr,
  metadata : Map[String, @realtime_db.Value],
) -> Bool {
  match self {
    Eq(field, target) =>
      match metadata.get(field) {
        Some(v) => v.equal(target)
        None => false
      }
    Gt(field, threshold) =>
      compare_metadata_field(metadata, field, threshold, fn(a, b) { a > b })
    Lt(field, threshold) =>
      compare_metadata_field(metadata, field, threshold, fn(a, b) { a < b })
    Gte(field, threshold) =>
      compare_metadata_field(metadata, field, threshold, fn(a, b) { a >= b })
    Lte(field, threshold) =>
      compare_metadata_field(metadata, field, threshold, fn(a, b) { a <= b })
    Exists(field) => metadata.contains(field)
    And(exprs) => {
      let mut all = true
      for e in exprs {
        if !e.evaluate(metadata) {
          all = false
          break
        }
      }
      all
    }
    Or(exprs) => {
      let mut any = false
      for e in exprs {
        if e.evaluate(metadata) {
          any = true
          break
        }
      }
      any
    }
    Not(inner) => !inner.evaluate(metadata)
  }
}
