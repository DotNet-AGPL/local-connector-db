namespace Connector.Core.Output;

/// <summary>
/// CSV 与 TABLE 两种人读格式。
/// 列宽按显示宽度计算（CJK / 全角 / emoji 记 2 列），修掉 Node 版中文表头错位。
/// </summary>
public static class TextOut
{
    public static void Csv(
        IReadOnlyList<string> columns,
        IReadOnlyList<IReadOnlyDictionary<string, object?>> rows)
    {
        ConsoleOut.Line(string.Join(',', columns));

        foreach (var row in rows)
        {
            var cells = new string[columns.Count];

            for (var i = 0; i < columns.Count; i++)
            {
                cells[i] = CsvCell(row.TryGetValue(columns[i], out var value) ? value : null);
            }

            ConsoleOut.Line(string.Join(',', cells));
        }
    }

    private static string CsvCell(object? value)
    {
        var text = ValueFormat.Plain(value);
        return text.Contains(',') || text.Contains('"') || text.Contains('\n')
            ? "\"" + text.Replace("\"", "\"\"") + "\""
            : text;
    }

    public static void Table(
        IReadOnlyList<string> columns,
        IReadOnlyList<IReadOnlyDictionary<string, object?>> rows)
    {
        var widths = new int[columns.Count];

        for (var i = 0; i < columns.Count; i++)
        {
            var width = DisplayWidth(columns[i]);

            foreach (var row in rows)
            {
                width = Math.Max(width, DisplayWidth(Cell(row, columns[i])));
            }

            widths[i] = width + 2;
        }

        var separator = string.Join('+', widths.Select(width => new string('-', width)));

        ConsoleOut.Line(separator);
        ConsoleOut.Line(string.Join('|', columns.Select((column, i) => PadRight(column, widths[i]))));
        ConsoleOut.Line(separator);

        foreach (var row in rows)
        {
            ConsoleOut.Line(string.Join('|', columns.Select((column, i) => PadRight(Cell(row, column), widths[i]))));
        }

        ConsoleOut.Line(separator);
    }

    private static string Cell(IReadOnlyDictionary<string, object?> row, string column) =>
        ValueFormat.Plain(row.TryGetValue(column, out var value) ? value : null);

    private static string PadRight(string text, int width) =>
        text + new string(' ', Math.Max(0, width - DisplayWidth(text)));

    /// <summary>终端显示宽度：ASCII/半角记 1，CJK、全角、emoji 记 2。</summary>
    public static int DisplayWidth(string text)
    {
        var width = 0;

        foreach (var rune in text.EnumerateRunes())
        {
            width += RuneWidth(rune.Value);
        }

        return width;
    }

    private static int RuneWidth(int codePoint) => codePoint switch
    {
        0 => 0,
        < 0x20 => 0,
        >= 0x7F and < 0xA0 => 0,
        < 0x1100 => 1,
        <= 0x115F => 2,
        >= 0x2E80 and <= 0xA4CF when codePoint != 0x303F => 2,
        >= 0xAC00 and <= 0xD7A3 => 2,
        >= 0xF900 and <= 0xFAFF => 2,
        >= 0xFE10 and <= 0xFE19 => 2,
        >= 0xFE30 and <= 0xFE6F => 2,
        >= 0xFF00 and <= 0xFF60 => 2,
        >= 0xFFE0 and <= 0xFFE6 => 2,
        >= 0x1F300 and <= 0x1F64F => 2,
        >= 0x1F900 and <= 0x1F9FF => 2,
        >= 0x20000 and <= 0x3FFFD => 2,
        _ => 1,
    };
}
