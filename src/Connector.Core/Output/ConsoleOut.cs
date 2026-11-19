using System.Text;

namespace Connector.Core.Output;

/// <summary>
/// 统一输出通道，按用途分两条流：
///   - stdout（Line / Block）：查询结果数据，只有数据，可直接管道给 jq / awk；
///   - stderr（Info / Error）：进度、耗时、行数统计等提示，不污染数据。
/// 两个流都固定 LF 换行（不用 Console.WriteLine，它在 Windows 输出 CRLF）、UTF-8 无 BOM。
/// stdout 有缓冲，进程结束前调用 Flush()；stderr 逐行自动刷新。
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

    /// <summary>
    /// 人读的进度 / 统计 / 提示，写 stderr。
    /// 与 Error 的区别只是语义：Info 不算错误，进度条、耗时、行数都走这里。
    /// 写之前先把 stdout 冲出去，保证终端上「数据在前、后续提示在后」的顺序。
    /// </summary>
    public static void Info(string text = "")
    {
        Stdout.Flush();
        Stderr.Write(text);
        Stderr.Write('\n');
    }

    /// <summary>写入一段可能自带换行的多行文本，并补一个换行。</summary>
    public static void Block(string text)
    {
        Stdout.Write(text);
        Stdout.Write('\n');
    }

    public static void Error(string text)
    {
        Stdout.Flush();
        Stderr.Write(text);
        Stderr.Write('\n');
    }

    public static void Flush() => Stdout.Flush();
}
