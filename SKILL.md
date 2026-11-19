---
name: local-skill-tools
description: 用本地 NativeAOT 单文件工具操作数据库与远程服务器。数据库支持 MySQL、PostgreSQL、SQLite、DuckDB、MongoDB、Redis、ClickHouse、Oracle、SQL Server、达梦的查询与库管理；远程支持 SSH 执行命令与 SFTP 上传下载。当用户提供数据库连接串（mysql://、postgres://、mongodb://、redis://、clickhouse://、jdbc:、Server=...;Database=...）、host:port、.db/.sqlite/.duckdb 文件路径，或提供 user@host、私钥、SSH 连接信息并要求连库、执行 SQL、查看表结构、远程执行命令、上传下载文件时使用。
---

# 本地工具集（local-skill-tools）

用 `bin/<tool>-<rid>/` 下的单文件可执行程序直接干活：不需要安装运行时、驱动或包管理器。

## 前置依赖

全部工具为 .NET NativeAOT 单文件制品，随 skill 分发，直接执行 `bin/` 下对应可执行文件即可：**无需安装依赖，也不需要 .NET 运行时**。

每个 `bin/<tool>-<rid>/` 都是自包含目录，整目录拷贝即可运行。下表中的「额外文件」必须与可执行文件放在同一目录，不要单独删除。

### 数据库

| 数据库 | Windows 入口 | Linux 入口 | macOS 入口 | Windows 额外文件 |
|-------|-------------|-----------|-----------|-----------------|
| SQLite | `bin/sqlite-win-x64/db-sqlite.exe` | `bin/sqlite-linux-x64/db-sqlite` | `bin/sqlite-osx-arm64/db-sqlite` | `e_sqlite3.dll` |
| MySQL | `bin/mysql-win-x64/db-mysql.exe` | `bin/mysql-linux-x64/db-mysql` | `bin/mysql-osx-arm64/db-mysql` | - |
| PostgreSQL | `bin/postgres-win-x64/db-postgres.exe` | `bin/postgres-linux-x64/db-postgres` | `bin/postgres-osx-arm64/db-postgres` | - |
| DuckDB | `bin/duckdb-win-x64/db-duckdb.exe` | `bin/duckdb-linux-x64/db-duckdb` | `bin/duckdb-osx-arm64/db-duckdb` | `duckdb.dll` |
| MongoDB | `bin/mongo-win-x64/db-mongo.exe` | `bin/mongo-linux-x64/db-mongo` | `bin/mongo-osx-arm64/db-mongo` | - |
| Redis | `bin/redis-win-x64/db-redis.exe` | `bin/redis-linux-x64/db-redis` | `bin/redis-osx-arm64/db-redis` | - |
| ClickHouse | `bin/clickhouse-win-x64/db-clickhouse.exe` | `bin/clickhouse-linux-x64/db-clickhouse` | `bin/clickhouse-osx-arm64/db-clickhouse` | - |
| Oracle | `bin/oracle-win-x64/db-oracle.exe` | `bin/oracle-linux-x64/db-oracle` | `bin/oracle-osx-arm64/db-oracle` | - |
| SQL Server | `bin/sqlserver-win-x64/db-sqlserver.exe` | `bin/sqlserver-linux-x64/db-sqlserver` | `bin/sqlserver-osx-arm64/db-sqlserver` | `Microsoft.Data.SqlClient.SNI.dll` |
| 达梦 | `bin/dm-win-x64/db-dm.exe` | `bin/dm-linux-x64/db-dm` | `bin/dm-osx-arm64/db-dm` | - |

### 远程操作

| 工具 | 用途 | Windows 入口 | Linux 入口 | macOS 入口 |
|------|------|-------------|-----------|-----------|
| `net-ssh` | 远程执行命令 | `bin/ssh-win-x64/net-ssh.exe` | `bin/ssh-linux-x64/net-ssh` | `bin/ssh-osx-arm64/net-ssh` |
| `net-sftp` | 列目录 / 上传 / 下载 / 删除 | `bin/sftp-win-x64/net-sftp.exe` | `bin/sftp-linux-x64/net-sftp` | `bin/sftp-osx-arm64/net-sftp` |

macOS 列对应 Apple Silicon（`osx-arm64`）。发布包只带构建机对应平台的 `bin/`；如果当前目录缺少你所在平台的制品，从 Releases 下载对应包，或在源码仓库跑 `bash rebuild.sh`（按宿主自动选 RID）生成。`sqlserver` 与 `dm` 在非 Windows 平台都走纯托管驱动，不需要额外原生库。

## 安装

发布包按**工具**拆分，每个包都是完整 skill，解压到同一个目录即可叠加安装：

```bash
# 只装当前平台
tar -xzf local-skill-tools-v1.0.0-sqlite-linux-x64.tar.gz -C ~/.agents/skills/

# 或装三平台包（含 win/linux/osx；Windows 用 tar -xzf 解压）
tar -xzf local-skill-tools-v1.0.0-sqlite-all.tar.gz -C ~/.agents/skills/

# Windows 单平台包是 zip
Expand-Archive local-skill-tools-v1.0.0-sqlite-win-x64.zip -DestinationPath "$env:USERPROFILE\.agents\skills"
```

安装多个工具就是重复解压对应包（同名 `SKILL.md` 内容一致，覆盖无副作用）。

**若 `bin/<tool>-<rid>/` 不存在，说明该工具没有安装**：直接告知用户需要下载对应工具的包，不要改用其他数据库工具或猜测替代方案。

macOS 下载的二进制带 quarantine 标记，首次运行前执行 `xattr -dr com.apple.quarantine ~/.agents/skills/local-skill-tools/bin`。

Linux 侧只有 `sqlserver-linux-x64/` 需要 `libicu*.so`（运行依赖，必须随目录一起分发）。

## 选择入口

按下列顺序判断，命中即停。**推断不出来就先问用户，不要猜**——猜错会连错库或连到别的服务上。

**1. 连接串 / URL 协议前缀**

| 输入形态 | 数据库类型 |
|---------|-----------|
| `mongodb://`、`mongodb+srv://` | MongoDB |
| `redis://`、`rediss://` | Redis |
| `postgres://`、`postgresql://` | PostgreSQL |
| `mysql://` | MySQL |
| `clickhouse://` 或 `http(s)://<host>:8123/8443` | ClickHouse |
| `Server=...;Database=...`、`Data Source=...;Initial Catalog=...` | SQL Server |
| `User Id=...;Data Source=(DESCRIPTION=...` | Oracle |
| `jdbc:<db>://...` | 去掉 `jdbc:` 前缀后按本表重判 |

**2. 主机与端口**

`<host>:<port>`（含 IPv4、域名、`localhost`）按端口号查下表；`(localdb)\...`（无端口）走 SQL Server 集成认证。

| 端口 | 数据库类型 | 端口 | 数据库类型 |
|------|-----------|------|-----------|
| `3306` | MySQL | `1433` | SQL Server |
| `5432` | PostgreSQL | `1521` | Oracle |
| `27017` | MongoDB | `5236` | 达梦 (DM) |
| `6379` | Redis | `8123` / `8443` | ClickHouse |

**3. 文件路径**

| 输入形态 | 数据库类型 |
|---------|-----------|
| 扩展名 `.sqlite` / `.db` / `.sqlite3` | SQLite |
| 扩展名 `.duckdb` | DuckDB |

**4. 兜底**

| 输入形态 | 处理方式 |
|---------|---------|
| 用户指定 `--type <db>` | 覆盖以上所有推断 |
| 以上都不匹配（如只有主机名、没有端口） | 先问用户，不要猜 |

## 快速开始

下列命令中的 `db-*` 指上表对应的可执行文件（Windows 为 `.exe`，PowerShell 调用需加 `&` 前缀）。命令行只接受纯主机名/IP：URL 或连接串里的协议、端口、用户名、密码要拆到 `-p` / `-u` / `--password` 等参数。

```bash
# SQLite / DuckDB：文件路径
db-sqlite query ./data/app.db -q "SELECT * FROM users"
db-duckdb query ./data/analytics.duckdb -q "SELECT * FROM events LIMIT 10"
db-duckdb query :memory: -q "SELECT 42 AS answer"   # 临时库，进程结束即丢

# MySQL / PostgreSQL / 达梦：host user password db/schema
db-mysql query localhost root password mydb -p 3306 -q "SELECT 1"
db-postgres query localhost postgres password mydb -p 5432 -q "SELECT * FROM users"
db-dm query localhost SYSDBA password SYSDBA -p 5236 -q "SELECT * FROM USERS"

# Oracle：第 4 个位置参数是服务名
db-oracle query localhost system password FREEPDB1 -p 1521 -q "SELECT * FROM USERS"

# SQL Server：--integrated 走 Windows 认证，此时 user/password 可随便填
db-sqlserver query localhost sa password mydb -p 1433 -q "SELECT * FROM users"
db-sqlserver query "(localdb)\MSSQLLocalDB" x x mydb --integrated -q "SELECT 1"

# ClickHouse：-p 默认 8123，--secure 走 https 且默认 8443
db-clickhouse query localhost -p 8123 -q "SELECT * FROM system.tables"

# MongoDB / Redis：用 -c 传命令
db-mongo query localhost mydb -p 27017 -c "users.find({})"
db-redis query localhost -p 6379 -c "GET mykey"
```

子命令只有两个：`connect` 验证连通并给出库/表概况，`query` 执行并输出结果。两者参数一致，把 `query` 换成 `connect` 即可。

### 远程操作（SSH / SFTP）

```bash
# 执行命令：-- 之后的参数原样送到远端，退出码与远端一致
net-ssh exec root@10.0.2.74 -- 'systemctl status nginx'
net-ssh exec root@10.0.2.74 -i ~/.ssh/id_ed25519 -f deploy.sh

# 密码只从标准输入读，不要写在命令行里
echo "$REMOTE_PASSWORD" | net-ssh exec root@10.0.2.74 --password-stdin -- 'df -h'

# 上传 / 下载（目录加 -r）
net-sftp put deploy@10.0.2.74 ./dist /opt/app/dist -r
net-sftp get deploy@10.0.2.74 /var/log/app.log ./app.log
net-sftp ls deploy@10.0.2.74 /opt/app -l
net-sftp mkdir deploy@10.0.2.74 /opt/app/releases
net-sftp rm deploy@10.0.2.74 /opt/app/old -r
```

主机密钥默认按 `~/.ssh/known_hosts` 校验；首次连接打印指纹后继续，`--strict` 要求必须已存在，`--insecure` 才完全跳过。

## 输出格式

SQL 类数据库支持 `-o json|csv|table`（默认 JSON）；MongoDB 只有 `json` / `table`。

**stdout 只有结果数据**：`正在执行查询...`、耗时、行数统计、`✓ 查询执行成功` 等提示一律写 stderr。因此结果可以直接管道给下游，不需要先剔除提示行：

```bash
db-mysql query db.example.com app pass mydb -q "SELECT id, name FROM t LIMIT 5" | jq -r '.[].name'
db-sqlite query ./app.db -q "SELECT * FROM t" -o csv | Import-Csv
```

`connect` 的诊断报告是命令本身的输出，仍走 stdout。

- **JSON**：标准 JSON 数组（`[]` 也可被 jq 直接解析）
- **CSV**：逗号分隔值，`NULL` 为空串
- **TABLE**：终端表格，列宽按显示宽度计算（中日韩字符按 2 列对齐）

跨库统一的值形态：

| 类型 | 输出 |
|------|------|
| `NULL` | `null` |
| 整数 | JSON 数字；绝对值超过 2^53-1 时输出**字符串**（避免下游精度丢失） |
| 定点/浮点 | JSON 数字，保留原始精度（`DECIMAL` / `numeric` 不再是字符串） |
| `TEXT` / `VARCHAR` | 原始文本 |
| `BLOB` / `bytea` | 字符串 `<BLOB n bytes>` |
| 日期时间 | 按库中的值原样输出，**不做时区转换** |
| `JSON` / `jsonb` 列 | 原样内联为对象/数组 |
| 数组（PG `text[]`、`int[]`） | JSON 数组 |

各库专有类型（`TINYINT(1)`、`BIT`、`Decimal`、`HUGEINT`、`Map` 等）的映射见 [reference/databases.md](reference/databases.md)。

## 多语句脚本

MySQL / PostgreSQL / SQL Server / Oracle / ClickHouse / 达梦的 `query` **一次只执行一条语句**，多语句需拆分逐条调用。

SQLite / DuckDB 的 `-f` 支持多条 DDL/DML，执行方式由**首关键字**决定：

- `SELECT` / `WITH` / `PRAGMA` / `EXPLAIN` / `VALUES` / `SHOW` / `DESCRIBE` 开头 → 按查询处理，只输出第一个结果集，后续语句仍会执行
- 其他（`CREATE` / `INSERT` / `UPDATE` / `DELETE` / `DROP` 等）→ 全部执行并输出影响行数
- `PRAGMA` 建议放在脚本末尾，避免整段被当成查询

**执行顺序**：DDL → DML、有外键依赖的表创建必须顺序执行；多条独立 INSERT/UPDATE/DELETE 与多条独立 SELECT 可并行。

## 注意事项

- 密码含特殊字符时用引号包裹；敏感信息不要硬编码在脚本里
- 含反引号、`$`、`!` 或较长的 SQL 用 `-f script.sql` 或 `-f -`（stdin）传入，避免 shell 破坏语句；`-q` 只适合单行简单查询
- 查询执行后自动关闭连接
- 大量数据查询加 `LIMIT`
- 只要结果、不要提示：`2>/dev/null` 即可；DML 的「影响 N 行」也在 stderr，判断成功与否看退出码
- SQLite 与 DuckDB 无需网络，直接操作本地文件；SQLite 写操作默认自动 checkpoint，备份前建议先跑 `--checkpoint`

## 参考

- **完整参数格式**（每个库的 `query` / `connect` 签名、SQLite 专属选项、通用参数）：[reference/cli.md](reference/cli.md)
- **SSH / SFTP**（认证、主机密钥校验、递归传输、常见错误）：[reference/net.md](reference/net.md)
- **各库特性**（连接参数、类型映射、专有行为、已知限制）：[reference/databases.md](reference/databases.md)
- **重新构建制品**（`bin/` 被误删时、三平台入口、SDK 与 ICU 策略）：[reference/build.md](reference/build.md)

## 许可证

AGPL-3.0-or-later，全文见仓库根目录 [LICENSE](LICENSE)。修改后分发或以网络服务形式提供时，需同样以 AGPL 提供对应源码。
