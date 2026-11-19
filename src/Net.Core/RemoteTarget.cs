namespace Net.Core;

/// <summary>远程目标：<c>user@host</c>，端口另用 -p 指定。</summary>
public sealed record RemoteTarget(string User, string Host)
{
    public static RemoteTarget Parse(string value)
    {
        var at = value.LastIndexOf('@');

        if (at <= 0 || at == value.Length - 1)
        {
            throw new FormatException($"目标格式应为 user@host，实际: {value}");
        }

        return new RemoteTarget(value[..at], value[(at + 1)..]);
    }

    /// <summary>known_hosts 里的主机字段（非 22 端口写成 [host]:port）。</summary>
    public string KnownHostsName(int port) => port == 22 ? Host : $"[{Host}]:{port}";

    public override string ToString() => $"{User}@{Host}";
}
