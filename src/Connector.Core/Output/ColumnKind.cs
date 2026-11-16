namespace Connector.Core.Output;

/// <summary>
/// 列的输出语义。RawJson 表示该列的文本是合法 JSON，输出时原样内联而不是加引号，
/// 用于 MySQL 的 JSON 类型列（node 版由 mysql2 直接解析成对象，两边语义一致）。
/// </summary>
public enum ColumnKind
{
    Scalar = 0,
    RawJson = 1,
}
