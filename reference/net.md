# 远程操作（SSH / SFTP）

两个 NativeAOT 单文件工具，入口与数据库工具同构：

| 工具 | 用途 | Windows 入口 |
|------|------|--------------|
| `net-ssh` | 远程执行命令 | `bin/ssh-win-x64/net-ssh.exe` |
| `net-sftp` | 列目录、上传、下载、删除 | `bin/sftp-win-x64/net-sftp.exe` |

Linux / macOS 把 `.exe` 换成无扩展名的同名文件，路径前缀对应 `-linux-x64` / `-osx-arm64`。

## 认证

按以下顺序自动选择：

1. `-i, --identity <私钥>` 显式指定私钥
2. 未指定时探测 `~/.ssh/id_ed25519`、`~/.ssh/id_ecdsa`、`~/.ssh/id_rsa`
3. `--password-stdin` 从标准输入读一行密码（与私钥可同时提供，任一成功即可）

密码只从标准输入读，不接受 `--password xxx`：避免出现在进程列表、shell 历史和日志里。

```bash
# 密钥
net-ssh exec deploy@10.0.2.74 -- 'systemctl status nginx'

# 密码（printf 不带换行时可加 echo）
echo "$REMOTE_PASSWORD" | net-ssh exec deploy@10.0.2.74 --password-stdin -- 'df -h'
```

## 主机密钥校验

| 场景 | 行为 |
|------|------|
| 命中 `~/.ssh/known_hosts` | 正常连接 |
| 命中但密钥不一致 | **直接失败**（可能是中间人，或服务器换过密钥） |
| 未命中（首次连接） | 打印算法与 SHA256 指纹后继续 |
| 未命中 + `--strict` | 直接失败 |
| `--insecure` | 完全跳过校验（每次打印警告） |

已知限制：`known_hosts` 里的哈希条目（`|1|...`）无法校验，此类主机按「未命中」处理。

## net-ssh

```bash
net-ssh exec <user@host> [选项] -- <命令>
net-ssh exec <user@host> [选项] -f script.sh
```

- `--` 之后的参数原样拼成远端命令，所以 `ls -l` 里的 `-l` 不会被本工具解析
- stdout / stderr 原样透传，进程退出码等于远端退出码
- `-f script.sh` 把本地脚本内容整段作为命令发送，适合多行、含引号或反引号的脚本
- 选项：`-p/--port`、`-i/--identity`、`--password-stdin`、`--strict`、`--insecure`、`--timeout <秒>`（默认 30）

```bash
# 多行脚本：本地文件最稳，不受 shell 转义影响
cat > deploy.sh <<'SH'
set -e
cd /opt/app && git pull && systemctl restart app
SH
net-ssh exec root@10.0.2.74 -i ~/.ssh/id_ed25519 -f deploy.sh
```

输出是整段缓冲后写出的：命令会产生大量输出时，建议在远端自己重定向到文件（`... > /tmp/out.log 2>&1`）。

## net-sftp

```bash
net-sftp ls   <user@host> [远端路径] [-l]
net-sftp get  <user@host> <远端> <本地> [-r]
net-sftp put  <user@host> <本地> <远端> [-r]
net-sftp mkdir <user@host> <远端路径>
net-sftp rm   <user@host> <远端路径> [-r]
```

- `ls`：默认只列名字；`-l` 显示权限、大小、修改时间
- `get` / `put`：目录必须带 `-r`，递归时不保留权限位与软链接目标
- 目标是已存在的目录（或远端路径以 `/` 结尾）时，文件会被放进该目录
- 同名文件默认覆盖
- 每条操作打印一行 `✓ ...`，失败时 stderr 输出 `✗ 类型: 消息` 并返回 1

```bash
# 下载发布包
net-sftp get deploy@10.0.2.74 /opt/release/app.tar.gz ./app.tar.gz -i ~/.ssh/id_ed25519

# 递归上传目录（远端不存在会自动创建）
net-sftp put deploy@10.0.2.74 ./dist /opt/app/dist -r --password-stdin < /run/secrets/pw

# 递归删除
net-sftp rm deploy@10.0.2.74 /opt/app/old -r
```

## 常见错误

| 报错 | 处理 |
|------|------|
| `SshAuthenticationException` | 私钥路径/权限不对，或服务器只允许其他认证方式；用 `-i` 明确指定 |
| `Permission denied (publickey)` | 公钥没在远端 `~/.ssh/authorized_keys` 中 |
| `主机密钥与 known_hosts 不一致` | 确认服务器是否重装/换证书；确认后从 `known_hosts` 删除对应行 |
| `SftpPathNotFoundException` | 远端路径不存在（父目录需先用 `mkdir` 建） |
| 下载中文文件名乱码 | 旧版服务器可能用非 UTF-8 文件名，先在远端改名 |
| `Permission denied` (上传) | 目标目录对登录用户不可写；改用有写权限的目录或先 `chmod` |

## 安全约定

- 密码只走 stdin 或环境变量，不要写进命令行、脚本或仓库
- 生产环境建议 `--strict`，首次连接后用 `ssh-keyscan <host> >> ~/.ssh/known_hosts` 固化
- 工具不会修改服务器配置；删除、覆盖类操作（`rm`、`put` 覆盖）请先确认路径
