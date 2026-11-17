# local-connector-db

多数据库命令行连接器，也是 OpenCode / Claude 风格的 Agent Skill。10 个数据库各自编译为 **.NET NativeAOT 单文件可执行程序**，运行时不需要 Node.js、驱动或 .NET 运行时。

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

用法、入口推断规则、参数与各库特性见 [SKILL.md](SKILL.md)。SKILL.md 是给 Agent 读的入口，细节在 `reference/` 下按需加载。

## 目录结构

```
SKILL.md                    # Agent 入口：选库、快速开始、输出约定
reference/cli.md            # 每个库的 query / connect 完整参数
reference/databases.md      # 各库连接参数、类型映射、专有行为
reference/build.md          # 重建流程、RID 与 ICU 策略
src/Connector.*/            # 每个数据库一个 .NET 项目
tests/                      # 各库联调与 parity 校验
build.ps1                   # 单库构建
rebuild.bat / rebuild.sh    # 全量重建 + 校验
bin/                        # 构建产物（不入库，见下）
```

## 安装为 Skill

运行时不需要任何安装步骤，把整个目录拷到 Agent 的 skills 目录即可：

```bash
git clone <repo> ~/.agents/skills/local-connector-db
cd ~/.agents/skills/local-connector-db && ./rebuild.sh   # 生成宿主平台 bin/（或从 release 解压产物）
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

`bin/` 不纳入版本库：353 MB 二进制每次重建都会产生新 blob，历史会迅速膨胀。发布时把 `bin/` 打包为 release 资产，或由使用者本地构建。详见 [reference/build.md](reference/build.md)。

## 约定

- `bin/<db>-<rid>/` 是自包含目录，整目录分发；不要只拷可执行文件。
- 切换 RID 构建必须带 `-Clean`（restore 按 RID 走）。
- 日期时间一律按库中原值输出，不做时区转换；超过 2^53 的整数输出字符串。
- `osx-arm64` 制品已在 Windows 上交叉构建通过（尚未在 macOS 真机验证）；跨机器拷贝后需 `xattr -dr com.apple.quarantine bin/<db>-osx-arm64` 才能直接运行。
