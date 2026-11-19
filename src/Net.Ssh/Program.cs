using System.Text;
using Connector.Core.Cli;
using Connector.Core.Output;
using Net.Core;

namespace Net.Ssh;

internal static class Program
{
    private const string Usage =
        "用法: net-ssh exec <user@host> [选项] -- <命令>\n" +
        "      net-ssh exec <user@host> [选项] -f script.sh\n" +
        "\n" +
        "选项:\n" +
        "  -p, --port <n>        端口，默认 22\n" +
        "  -i, --identity <file> 私钥文件（默认探测 ~/.ssh/id_ed25519|id_ecdsa|id_rsa）\n" +
        "      --password-stdin  从标准输入读一行密码\n" +
        "      --strict          主机不在 known_hosts 中时直接失败\n" +
        "      --insecure        跳过主机密钥校验（等价 ssh StrictHostKeyChecking=no）\n" +
        "      --timeout <sec>   连接超时，默认 30\n" +
        "  -f, --file <file>     从本地文件读取要执行的命令";

    private static readonly OptionDef[] Options =
    [
        OptionDef.Value("-p", "--port"),
        OptionDef.Value("-i", "--identity"),
        OptionDef.Flag("--password-stdin"),
        OptionDef.Flag("--strict"),
        OptionDef.Flag("--insecure"),
        OptionDef.Value("--timeout"),
        OptionDef.Value("-f", "--file"),
    ];

    private static int Main(string[] args)
    {
        try
        {
            return Run(args);
        }
        finally
        {
            ConsoleOut.Flush();
        }
    }

    private static int Run(string[] args)
    {
        if (args.Length == 0 || args[0] is "-h" or "--help" or "help")
        {
            ConsoleOut.Line(Usage);
            return args.Length == 0 ? 1 : 0;
        }

        if (args[0] != "exec")
        {
            ConsoleOut.Error($"未知子命令: {args[0]}");
            ConsoleOut.Error(Usage);
            return 1;
        }

        var rest = args[1..];

        // "--" 之后的内容原样作为远端命令，避免把 "ls -l" 里的 -l 当成自己的选项
        var separator = Array.IndexOf(rest, "--");
        var remoteArgs = separator >= 0 ? rest[(separator + 1)..] : [];
        var optionArgs = separator >= 0 ? rest[..separator] : rest;

        CliArgs parsed;

        try
        {
            parsed = CliArgs.Parse(optionArgs, Options);
        }
        catch (UsageException error)
        {
            ConsoleOut.Error(error.Message);
            ConsoleOut.Error(Usage);
            return 1;
        }

        if (parsed.Positionals.Count < 1)
        {
            ConsoleOut.Error(Usage);
            return 1;
        }

        RemoteTarget target;

        try
        {
            target = RemoteTarget.Parse(parsed.Positionals[0]);
        }
        catch (FormatException error)
        {
            ConsoleOut.Error(error.Message);
            return 1;
        }

        string command;

        if (parsed.Get("-f") is { } scriptPath)
        {
            if (!File.Exists(scriptPath))
            {
                ConsoleOut.Error($"错误: 脚本文件不存在: {scriptPath}");
                return 1;
            }

            command = File.ReadAllText(scriptPath);
        }
        else
        {
            if (remoteArgs.Length == 0)
            {
                ConsoleOut.Error("错误: 缺少要执行的命令（用 -- 分隔，例如: net-ssh exec root@host -- ls -l）");
                return 1;
            }

            command = string.Join(' ', remoteArgs);
        }

        if (command.Trim().Length == 0)
        {
            ConsoleOut.Error("错误: 命令为空");
            return 1;
        }

        var options = new SshOptions
        {
            Target = target,
            Port = ParseInt(parsed.Get("-p"), 22, "端口"),
            IdentityPath = parsed.Get("-i"),
            Password = parsed.Has("--password-stdin") ? Console.In.ReadLine() : null,
            Strict = parsed.Has("--strict"),
            Insecure = parsed.Has("--insecure"),
            Timeout = TimeSpan.FromSeconds(ParseInt(parsed.Get("--timeout"), 30, "超时")),
        };

        try
        {
            using var client = SshSession.Open(options);
            using var cmd = client.CreateCommand(command);
            cmd.CommandTimeout = options.Timeout + TimeSpan.FromMinutes(10);

            var stdout = cmd.Execute();
            var stderr = cmd.Error;

            WriteRaw(Console.OpenStandardOutput(), stdout);

            if (!string.IsNullOrEmpty(stderr))
            {
                WriteRaw(Console.OpenStandardError(), stderr);
            }

            return cmd.ExitStatus ?? 0;
        }
        catch (Exception error)
        {
            ConsoleOut.Error($"✗ {error.GetType().Name}: {error.Message}");
            return 1;
        }
    }

    private static void WriteRaw(Stream stream, string text)
    {
        using var writer = new StreamWriter(stream, new UTF8Encoding(false), leaveOpen: true);
        writer.Write(text);
        writer.Flush();
    }

    private static int ParseInt(string? value, int fallback, string name)
    {
        if (value is null)
        {
            return fallback;
        }

        if (!int.TryParse(value, out var parsed) || parsed <= 0)
        {
            throw new UsageException($"{name} 需要正整数，实际: {value}");
        }

        return parsed;
    }
}
