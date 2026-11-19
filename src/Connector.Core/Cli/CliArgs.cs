namespace Connector.Core.Cli;

/// <summary>参数使用错误（会以纯文本写到 stderr，退出码 1）。</summary>
public sealed class UsageException(string message) : Exception(message);

/// <summary>
/// 一个选项定义。Name 是规范名（Provider 内部取值用），Aliases 包含所有可接受的写法。
/// </summary>
public sealed record OptionDef(string Name, string[] Aliases, bool HasValue)
{
    public static OptionDef Value(string name, params string[] aliases) => new(name, [name, .. aliases], true);

    public static OptionDef Flag(string name, params string[] aliases) => new(name, [name, .. aliases], false);
}

/// <summary>
/// 极简 argv 解析：位置参数按出现顺序收集，选项按规范名归并。
/// 只支持「-x value」与「--flag」两种形态，与 Node 版脚本的用法一致。
/// </summary>
public sealed class CliArgs
{
    private readonly List<string> _positionals = [];
    private readonly Dictionary<string, string?> _values = new(StringComparer.Ordinal);
    private readonly Dictionary<string, List<string>> _multi = new(StringComparer.Ordinal);

    public IReadOnlyList<string> Positionals => _positionals;

    public static CliArgs Parse(string[] args, params OptionDef[] defs)
    {
        var result = new CliArgs();

        for (var i = 0; i < args.Length; i++)
        {
            var token = args[i];

            if (token.Length > 1 && token[0] == '-')
            {
                var def = Find(defs, token) ?? throw new UsageException($"未知参数: {token}");

                if (def.HasValue)
                {
                    if (i + 1 >= args.Length)
                    {
                        throw new UsageException($"参数 {token} 缺少取值");
                    }

                    var value = args[++i];
                    result._values[def.Name] = value;

                    if (!result._multi.TryGetValue(def.Name, out var list))
                    {
                        list = [];
                        result._multi[def.Name] = list;
                    }

                    list.Add(value);
                }
                else
                {
                    result._values[def.Name] = null;
                }

                continue;
            }

            result._positionals.Add(token);
        }

        return result;
    }

    private static OptionDef? Find(OptionDef[] defs, string token)
    {
        foreach (var def in defs)
        {
            foreach (var alias in def.Aliases)
            {
                if (string.Equals(alias, token, StringComparison.Ordinal))
                {
                    return def;
                }
            }
        }

        return null;
    }

    public bool Has(string name) => _values.ContainsKey(name);

    public string? Get(string name) => _values.TryGetValue(name, out var value) ? value : null;

    /// <summary>同名选项的全部取值（按出现顺序），用于 -L 这类可重复的参数。</summary>
    public IReadOnlyList<string> GetAll(string name) =>
        _multi.TryGetValue(name, out var values) ? values : [];
}
