# local-skill-tools

本地工具集：数据库连接器 + 远程操作 + 文档办公，同时是 OpenCode / Claude 风格的 Agent Skill。13 个工具各自编译为 **.NET NativeAOT 单文件可执行程序**，运行时不需要 Node.js、驱动或 .NET 运行时。

## 数据库

| 数据库 | 入口（win / linux） |
|---|---|
| SQLite | `bin/sqlite-win-x64/db-sqlite.exe` / `bin/sqlite-linux-x64/db-sqlite` |
| MySQL | `bin/mysql-win-x64/db-mysql.exe` / `bin/mysql-linux-x64/db-mysql` |
| PostgreSQL | `bin/postgres-win-x64/db-postgres.exe` / `bin/postgres-linux-x64/db-postgres` |
| DuckDB | `bin/duckdb-win-x64/db-duckdb.exe` / `bin/duckdb-linux-x64/db-duckdb` |
| MongoDB | `bin/mongo-win-x64/db-mongo.exe` / `bin/mongo-linux-x64/db-mongo` |
| Redis | `bin/redis-win-x64/db-redis.exe` / `bin/redis-linux-x64/db-redis` |
| ClickHouse | `bin/clickhouse-win-x64/db-clickhouse.exe` / `bin/clickhouse-linux-x64/db-clickhouse` |
| Oracle | `bin/oracle-win-x64/db-oracle.exe` / `bin/oracle-linux-x64/db-oracle` |
| SQL Server | `bin/sqlserver-win-x64/db-sqlserver.exe` / `bin/sqlserver-linux-x64/db-sqlserver` |
| 达梦 | `bin/dm-win-x64/db-dm.exe` / `bin/dm-linux-x64/db-dm` |

## 远程操作

| 工具 | 用途 | 入口（win / linux） |
|---|---|---|
| `net-ssh` | 远程执行命令、端口转发 | `bin/ssh-win-x64/net-ssh.exe` / `bin/ssh-linux-x64/net-ssh` |
| `net-sftp` | 列目录、上传、下载、删除 | `bin/sftp-win-x64/net-sftp.exe` / `bin/sftp-linux-x64/net-sftp` |

`net-ssh` 与 `net-sftp` 共享认证与主机密钥校验逻辑（`src/Net.Core`），密码只从标准输入读取。

## 文档办公

| 工具 | 用途 | 入口（win / linux） |
|---|---|---|
| `file-office` | docx / xlsx / pptx / pdf / md 的读取、转换与模板填充 | `bin/office-win-x64/file-office.exe` / `bin/office-linux-x64/file-office` |

依赖内置的 Wisdom.Office（MIT），不装 Office / WPS / pandoc。能力矩阵与限制见 [reference/office.md](reference/office.md)。

用法、入口推断规则、参数与各库特性见 [SKILL.md](SKILL.md)。SKILL.md 是给 Agent 读的入口，细节在 `reference/` 下按需加载。

## 目录结构

```
SKILL.md                    # Agent 入口：选库、快速开始、输出约定
reference/cli.md            # 每个库的 query / connect 完整参数
reference/net.md            # SSH / SFTP 认证、主机密钥、递归传输
reference/office.md         # Word / Excel / PPT / PDF / Markdown 读写与转换
reference/dotnet.md         # 单文件 C#：工具覆盖不到时的 SDK 档扩展
reference/databases.md      # 各库连接参数、类型映射、专有行为
reference/build.md          # 重建流程、RID 与 ICU 策略
src/Connector.*/            # 每个数据库一个 .NET 项目
src/Net.*/                  # SSH / SFTP 项目与共享库
tests/                      # 各库联调与 parity 校验
build.ps1                   # 单工具构建
rebuild.bat / rebuild.sh    # 全量重建 + 校验
pack.ps1                    # 组装发布包（只含当前平台制品，可 -SmokeTest）
.github/workflows/          # tag 触发的三平台 release 流水线
bin/                        # 构建产物（不入库，见下）
```

## 从 Release 安装（不需要源码）

发布包按工具拆分，每个包都带完整的 `SKILL.md` / `reference/` / `LICENSE` / `SOURCE.md`，只含对应工具的 `bin/`。装几个解压几个，解压到同一目录即可叠加：

```bash
# Linux / macOS：单平台包
tar -xzf local-skill-tools-v1.0.0-mysql-linux-x64.tar.gz -C ~/.agents/skills/

# 三平台包（win + linux + osx，Win10+ 可用 tar -xzf）
tar -xzf local-skill-tools-v1.0.0-mysql-all.tar.gz -C ~/.agents/skills/

# Windows：单平台包是 zip
Expand-Archive local-skill-tools-v1.0.0-mysql-win-x64.zip -DestinationPath "$env:USERPROFILE\.agents\skills"
```

命名规则：`local-skill-tools-v<版本>-<工具>-<rid|all>.<zip|tar.gz>`，工具取值与 `SKILL.md` 表格一致（`sqlite`、`mysql`、`duckdb`、`ssh`、`sftp` 等）。

macOS 首次运行前还需 `xattr -dr com.apple.quarantine ~/.agents/skills/local-skill-tools/bin`（未签名二进制会被 Gatekeeper 拦）。校验完整性：`sha256sum -c SHA256SUMS.txt`。

## 安装为 Skill

运行时不需要任何安装步骤，把整个目录拷到 Agent 的 skills 目录即可：

```bash
git clone <repo> ~/.agents/skills/local-skill-tools
cd ~/.agents/skills/local-skill-tools && ./rebuild.sh   # 生成宿主平台 bin/（或从 release 解压产物）
```

Windows 用 `rebuild.bat`（或双击）。两者都不带参数时自动按宿主平台选 RID（Linux→linux-x64、macOS Apple Silicon→osx-arm64、Windows→win-x64）。产物必须保留 `BUILD-INFO.txt` 与同目录原生依赖（`e_sqlite3.dll`、`duckdb.dll`、`Microsoft.Data.SqlClient.SNI.dll`；`sqlserver-linux-x64/` 还需 `libicu*.so`）。

## 构建

需要 .NET SDK 11 + PowerShell 7（首次构建需联网）：

```bash
./rebuild.sh                 # 按宿主平台重建 + 校验
./rebuild.sh all             # 三平台：win-x64 + linux-x64 + osx-arm64
./rebuild.sh osx             # 只重建 osx-arm64（可在 Windows/Linux 上交叉构建）
./rebuild.sh verify          # 只校验，不构建
.\build.ps1 -Only mysql      # 单库，RID 按宿主推断
.\build.ps1 -Only mysql -Rid linux-x64 -Clean
.\build.ps1 -Skip sqlserver,dm
```

`bin/` 不纳入版本库：二进制每次重建都会产生新 blob，历史会迅速膨胀。发布时用 `pack.ps1` 组装成只含当前平台制品的包（`artifacts/local-skill-tools-v<版本>-<rid>.zip|tar.gz`），详见 [reference/build.md](reference/build.md)。

## 约定

- `bin/<tool>-<rid>/` 是自包含目录，整目录分发；不要只拷可执行文件。
- stdout 只有结果数据，进度 / 统计 / 报错都走 stderr，结果可直接管道给 jq 等工具。
- 切换 RID 构建必须带 `-Clean`（restore 按 RID 走）。
- 日期时间一律按库中原值输出，不做时区转换；超过 2^53 的整数输出字符串。
- `osx-arm64` 制品已在 Windows 上交叉构建通过（尚未在 macOS 真机验证）；跨机器拷贝后需 `xattr -dr com.apple.quarantine bin/<tool>-osx-arm64` 才能直接运行。
- SSH 密码只走标准输入或环境变量，不要写进命令行与脚本。

## 许可证

本项目以 **GNU Affero General Public License v3.0 or later**（AGPL-3.0-or-later）发布，全文见 [LICENSE](LICENSE)。

几点实际影响：

- 修改后分发（含以容器、制成品形式打包）必须同样以 AGPL 提供完整对应源码
- 把本项目作为网络服务对外提供时，需向使用者提供获取源码的途径（第 13 条）
- `bin/` 不入库，若把构建出的制品单独分发，需同时提供源码或书面获取途径
- 第三方 NuGet 依赖各自保留原有许可证，不受本项目授权影响
