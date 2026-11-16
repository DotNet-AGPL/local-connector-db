using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Connector.Core.Output;

/// <summary>
/// 手写 JSON 输出（AOT 下不使用反射序列化）。
/// 版面与 Node 的 JSON.stringify(rows, null, 2) 对齐：2 空格缩进、键顺序 = 列顺序。
/// </summary>
public static class JsonText
{
    public static string Rows(
        IReadOnlyList<string> columns,
        IReadOnlyList<IReadOnlyDictionary<string, object?>> rows,
        IReadOnlyDictionary<string, ColumnKind>? kinds = null)
    {
        if (rows.Count == 0)
        {
            return "[]";
        }

        var builder = new StringBuilder();
        builder.Append('[').Append('\n');

        for (var r = 0; r < rows.Count; r++)
        {
            builder.Append("  {").Append('\n');

            for (var c = 0; c < columns.Count; c++)
            {
                var column = columns[c];
                builder.Append("    ");
                AppendString(builder, column);
                builder.Append(": ");
                var value = rows[r].TryGetValue(column, out var cell) ? cell : null;
                var kind = kinds is not null && kinds.TryGetValue(column, out var declared) ? declared : ColumnKind.Scalar;
                AppendValue(builder, value, kind, 4);
                builder.Append(c == columns.Count - 1 ? '\n' : ",\n");
            }

            builder.Append("  }");
            builder.Append(r == rows.Count - 1 ? '\n' : ",\n");
        }

        builder.Append(']');
        return builder.ToString();
    }

    private static void AppendValue(StringBuilder builder, object? value, ColumnKind kind, int indent)
    {
        if (kind == ColumnKind.RawJson)
        {
            AppendRawJson(builder, value);
            return;
        }

        switch (value)
        {
            case null or DBNull:
                builder.Append("null");
                break;
            case bool flag:
                builder.Append(flag ? "true" : "false");
                break;
            case string text:
                AppendString(builder, text);
                break;
            case byte[] bytes:
                AppendString(builder, $"<BLOB {bytes.Length} bytes>");
                break;
            case sbyte or byte or short or ushort or int or uint or long:
            {
                var integer = Convert.ToInt64(value, CultureInfo.InvariantCulture);
                var text = integer.ToString(CultureInfo.InvariantCulture);
                if (ValueFormat.IsLargeInteger(integer))
                {
                    AppendString(builder, text);
                }
                else
                {
                    builder.Append(text);
                }

                break;
            }
            case ulong unsigned:
            {
                var text = unsigned.ToString(CultureInfo.InvariantCulture);
                if (ValueFormat.IsLargeInteger(unsigned))
                {
                    AppendString(builder, text);
                }
                else
                {
                    builder.Append(text);
                }

                break;
            }
            case decimal number:
                builder.Append(number.ToString(CultureInfo.InvariantCulture));
                break;
            case double number:
                AppendDouble(builder, number);
                break;
            case float number:
                AppendDouble(builder, number);
                break;
            case DateTime or DateTimeOffset or DateOnly or TimeOnly or TimeSpan or Guid:
                AppendString(builder, ValueFormat.Plain(value));
                break;
            case System.Collections.IDictionary map:
                AppendObject(builder, map, indent);
                break;
            case System.Numerics.BigInteger big:
                AppendBigInteger(builder, big);
                break;
            case Stream stream:
                AppendString(builder, $"<BLOB {(stream.CanSeek ? stream.Length : 0)} bytes>");
                break;
            case System.Collections.IEnumerable sequence:
                AppendArray(builder, sequence, indent);
                break;
            case IFormattable formattable:
                builder.Append(formattable.ToString(null, CultureInfo.InvariantCulture));
                break;
            default:
                AppendString(builder, ValueFormat.Plain(value));
                break;
        }
    }

    /// <summary>
    /// JSON 列原样内联。历史脏数据可能不是合法 JSON，此时退回带引号的字符串，避免把输出打坏。
    /// </summary>
    private static void AppendRawJson(StringBuilder builder, object? value)
    {
        if (value is null or DBNull)
        {
            builder.Append("null");
            return;
        }

        var text = value as string ?? ValueFormat.Plain(value);

        if (IsValidJson(text))
        {
            builder.Append(text.Trim());
            return;
        }

        AppendString(builder, text);
    }

    private static bool IsValidJson(string text)
    {
        if (text.Length == 0)
        {
            return false;
        }

        var trimmed = text.TrimStart();
        if (trimmed.Length == 0 || (trimmed[0] != '{' && trimmed[0] != '['))
        {
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(text);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>把单个值（标量/数组/对象）序列化成 JSON，供 Redis 这类非表状结果使用。</summary>
    public static string Value(object? value)
    {
        var builder = new StringBuilder();
        AppendValue(builder, value, ColumnKind.Scalar, 0);
        return builder.ToString();
    }

    /// <summary>DuckDB 的 STRUCT / MAP 输出为 JSON 对象，缩进与 JSON.stringify 对齐。</summary>
    private static void AppendObject(StringBuilder builder, System.Collections.IDictionary map, int indent)
    {
        if (map.Count == 0)
        {
            builder.Append("{}");
            return;
        }

        builder.Append('{').Append('\n');

        var index = 0;

        foreach (System.Collections.DictionaryEntry entry in map)
        {
            builder.Append(' ', indent + 2);
            AppendString(builder, Convert.ToString(entry.Key, CultureInfo.InvariantCulture) ?? string.Empty);
            builder.Append(": ");
            AppendValue(builder, entry.Value, ColumnKind.Scalar, indent + 2);
            builder.Append(++index == map.Count ? '\n' : ",\n");
        }

        builder.Append(' ', indent).Append('}');
    }

    /// <summary>HUGEINT / UHUGEINT 转成 JSON 数字；超出 2^53 时按约定输出字符串。</summary>
    private static void AppendBigInteger(StringBuilder builder, System.Numerics.BigInteger value)
    {
        var text = value.ToString(CultureInfo.InvariantCulture);
        var limit = new System.Numerics.BigInteger(ValueFormat.MaxSafeInteger);

        if (value > limit || value < -limit)
        {
            AppendString(builder, text);
            return;
        }

        builder.Append(text);
    }

    /// <summary>PG 的数组类型（text[]、int[] 等）输出为 JSON 数组，缩进与 JSON.stringify 对齐。</summary>
    private static void AppendArray(StringBuilder builder, System.Collections.IEnumerable items, int indent)
    {
        var values = new List<object?>();

        foreach (var item in items)
        {
            values.Add(item);
        }

        if (values.Count == 0)
        {
            builder.Append("[]");
            return;
        }

        builder.Append('[').Append('\n');

        for (var index = 0; index < values.Count; index++)
        {
            builder.Append(' ', indent + 2);
            AppendValue(builder, values[index], ColumnKind.Scalar, indent + 2);
            builder.Append(index == values.Count - 1 ? '\n' : ",\n");
        }

        builder.Append(' ', indent).Append(']');
    }

    private static void AppendDouble(StringBuilder builder, double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value))
        {
            AppendString(builder, ValueFormat.FormatDouble(value));
            return;
        }

        builder.Append(value.ToString("R", CultureInfo.InvariantCulture));
    }

    /// <summary>与 JSON.stringify 一致的转义规则：\" \\ \b \f \n \r \t 与其余控制字符 \u00XX。</summary>
    public static void AppendString(StringBuilder builder, string text)
    {
        builder.Append('"');

        foreach (var character in text)
        {
            switch (character)
            {
                case '"':
                    builder.Append("\\\"");
                    break;
                case '\\':
                    builder.Append("\\\\");
                    break;
                case '\b':
                    builder.Append("\\b");
                    break;
                case '\f':
                    builder.Append("\\f");
                    break;
                case '\n':
                    builder.Append("\\n");
                    break;
                case '\r':
                    builder.Append("\\r");
                    break;
                case '\t':
                    builder.Append("\\t");
                    break;
                default:
                    if (character < ' ')
                    {
                        builder.Append("\\u").Append(((int)character).ToString("x4", CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        builder.Append(character);
                    }

                    break;
            }
        }

        builder.Append('"');
    }
}
