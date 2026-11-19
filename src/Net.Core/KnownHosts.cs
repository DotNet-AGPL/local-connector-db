using System.Security.Cryptography;
using System.Text;
using Connector.Core.Output;

namespace Net.Core;

/// <summary>
/// known_hosts 校验：只解析明文条目（host keytype base64），
/// 哈希条目（|1|...）与 @revoked 等标记会跳过并提示。
/// </summary>
public static class KnownHosts
{
    public static string FilePath { get; } =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".ssh",
            "known_hosts");

    public enum CheckResult
    {
        Match,
        Mismatch,
        Unknown,
        Skipped,
    }

    public static CheckResult Verify(string hostName, string keyType, byte[] hostKey, out string detail)
    {
        detail = string.Empty;

        if (!File.Exists(FilePath))
        {
            return CheckResult.Unknown;
        }

        var hashed = false;

        foreach (var raw in File.ReadLines(FilePath))
        {
            var line = raw.Trim();

            if (line.Length == 0 || line[0] == '#')
            {
                continue;
            }

            if (line.StartsWith('@'))
            {
                continue;
            }

            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);

            if (parts.Length < 3)
            {
                continue;
            }

            if (parts[0].StartsWith("|1|", StringComparison.Ordinal))
            {
                hashed = true;
                continue;
            }

            var hosts = parts[0].Split(',');

            if (!Array.Exists(hosts, h => string.Equals(h, hostName, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            if (!string.Equals(parts[1], keyType, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (!TryDecode(parts[2], out var expected))
            {
                continue;
            }

            if (CryptographicOperations.FixedTimeEquals(expected, hostKey))
            {
                return CheckResult.Match;
            }

            detail = $"主机密钥与 known_hosts 不一致（{hostName} / {keyType}）";
            return CheckResult.Mismatch;
        }

        if (hashed)
        {
            detail = $"known_hosts 含哈希条目，无法校验 {hostName}（如需严格校验请改用非哈希格式）";
            return CheckResult.Skipped;
        }

        return CheckResult.Unknown;
    }

    /// <summary>把 HostKey 字节算成 SHA256 指纹，与 ssh-keygen -lf 的显示一致（去掉 = 填充）。</summary>
    public static string Fingerprint(byte[] hostKey)
    {
        var hash = SHA256.HashData(hostKey);
        return "SHA256:" + Convert.ToBase64String(hash).TrimEnd('=');
    }

    private static bool TryDecode(string value, out byte[] bytes)
    {
        try
        {
            bytes = Convert.FromBase64String(value);
            return true;
        }
        catch (FormatException)
        {
            bytes = [];
            return false;
        }
    }
}
