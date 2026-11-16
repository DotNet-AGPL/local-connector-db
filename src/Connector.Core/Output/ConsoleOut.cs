using System.Text;

namespace Connector.Core.Output;

/// <summary>
/// 统一输出通道：
///   - 换行固定为 LF（不用 Console.WriteLine，它在 Windows 输出 CRLF）；
///   - UTF-8 无 BOM；
///   - stdout 有缓冲，进程结束前调用 Flush()。
/// </summary>
public static class ConsoleOut
{
    private static readonly StreamWriter Stdout = new(Console.OpenStandardOutput(), new UTF8Encoding(false))
    {
        AutoFlush = false,
    };

    private static readonly StreamWriter Stderr = new(Console.OpenStandardError(), new UTF8Encoding(false))
    {
        AutoFlush = true,
    };

    public static void Line(string text = "")
    {
        Stdout.Write(text);
        Stdout.Write('\n');
    }

    /// <summary>写入一段可能自带换行的多行文本，并补一个换行。</summary>
    public static void Block(string text)
    {
        Stdout.Write(text);
        Stdout.Write('\n');
    }

    public static void Error(string text)
    {
        Stderr.Write(text);
        Stderr.Write('\n');
    }

    public static void Flush() => Stdout.Flush();
}
