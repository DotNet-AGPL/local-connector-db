using System.Globalization;

namespace Connector.Core.Output;

/// <summary>
/// 驱动值到文本的统一映射。JSON / CSV / TABLE 三个出口共用同一套规则，
/// 避免同一条数据在 json 与 table 下出现不同含义。
/// </summary>
public static class ValueFormat
{
    public const long MaxSafeInteger = 9007199254740991L;

    public static bool IsBlank(object? value) => value is null or DBNull;

    public static bool IsLargeInteger(long value) => value > MaxSafeInteger || value < -MaxSafeInteger;

    public static bool IsLargeInteger(ulong value) => value > (ulong)MaxSafeInteger;

    /// <summary>纯文本形态（csv / table / 兜底 JSON 字符串）。</summary>
    public static string Plain(object? value) => value switch
    {
        null or DBNull => string.Empty,
        byte[] bytes => $"<BLOB {bytes.Length} bytes>",
        Stream stream => $"<BLOB {(stream.CanSeek ? stream.Length : 0)} bytes>",
        bool flag => flag ? "true" : "false",
        string text => text,
        System.Numerics.BigInteger big => big.ToString(CultureInfo.InvariantCulture),
        System.Collections.IDictionary map => FormatMap(map),
        System.Collections.IEnumerable sequence => FormatSequence(sequence),
        double number => FormatDouble(number),
        float number => FormatDouble(number),
        decimal number => number.ToString(CultureInfo.InvariantCulture),
        DateTime time => FormatDateTime(time),
        DateTimeOffset time => time.ToString("yyyy-MM-ddTHH:mm:ss.fffffffzzz", CultureInfo.InvariantCulture),
        DateOnly date => date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        TimeOnly time => FormatTimeOnly(time),
        TimeSpan span => FormatTimeSpan(span),
        Guid id => id.ToString("D"),
        IFormattable formattable => formattable.ToString(null, CultureInfo.InvariantCulture),
        _ => value.ToString() ?? string.Empty,
    };

    private static string FormatMap(System.Collections.IDictionary map)
    {
        var parts = new List<string>();

        foreach (System.Collections.DictionaryEntry entry in map)
        {
            parts.Add($"{entry.Key}={Plain(entry.Value)}");
        }

        return "{" + string.Join(", ", parts) + "}";
    }

    private static string FormatSequence(System.Collections.IEnumerable sequence)
    {
        var parts = new List<string>();

        foreach (var item in sequence)
        {
            parts.Add(Plain(item));
        }

        return string.Join(",", parts);
    }

    public static string FormatDouble(double value)
    {
        if (double.IsNaN(value))
        {
            return "NaN";
        }

        if (double.IsPositiveInfinity(value))
        {
            return "Infinity";
        }

        if (double.IsNegativeInfinity(value))
        {
            return "-Infinity";
        }

        return value.ToString("R", CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// DATETIME 原样输出，不做任何时区转换：整秒用 yyyy-MM-ddTHH:mm:ss，
    /// 有小数秒时补三位。
    /// </summary>
    public static string FormatDateTime(DateTime value)
    {
        var text = value.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture);
        return value.Ticks % TimeSpan.TicksPerSecond == 0
            ? text
            : text + "." + value.Millisecond.ToString("000", CultureInfo.InvariantCulture);
    }

    private static string FormatTimeOnly(TimeOnly value) => value.Ticks % TimeSpan.TicksPerSecond == 0
        ? value.ToString("HH:mm:ss", CultureInfo.InvariantCulture)
        : value.ToString("HH:mm:ss.fffffff", CultureInfo.InvariantCulture);

    private static string FormatTimeSpan(TimeSpan value)
    {
        var negative = value < TimeSpan.Zero;
        var span = value.Duration();
        var hours = (long)span.TotalHours;
        var text = $"{hours:00}:{span.Minutes:00}:{span.Seconds:00}";

        if (span.Ticks % TimeSpan.TicksPerSecond != 0)
        {
            text += "." + span.Milliseconds.ToString("000", CultureInfo.InvariantCulture);
        }

        return negative ? "-" + text : text;
    }
}
