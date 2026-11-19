# CLI 参数参考

所有数据库的可执行文件共用两个子命令：`connect`、`query`。

## 目录

- 关系型数据库（MySQL / PostgreSQL / 达梦 / SQL Server）
- SQLite
- MongoDB
- Redis
- ClickHouse
- Oracle
- DuckDB
- 通用参数

## 关系型数据库

MySQL、PostgreSQL 与达梦：

```bash
# MySQL
db-mysql query <host> <user> <password> <database> -q "SQL" [-p port] [-o json|csv|table]
db-mysql connect <host> <user> <password> <database> [-p port]

# PostgreSQL
db-postgres query <host> <user> <password> <database> -q "SQL" [-p port] [-o json|csv|table]
db-postgres connect <host> <user> <password> <database> [-p port]

# 达梦（第 4 个位置参数是模式名 schema）
db-dm query <host> <user> <password> <schema> [-p port] -q "SQL" [-o json|csv|table]
db-dm connect <host> <user> <password> <schema> [-p port]
```

SQL Server：

```bash
# query 参数格式（--integrated 走 Windows 认证，此时 user/password 可随便填）
db-sqlserver query <host> <user> <password> <database> [-p port] -q "SQL" [-o json|csv|table] [--integrated]
db-sqlserver query <host> <user> <password> <database> [-p port] -f script.sql

# connect 参数格式
db-sqlserver connect <host> <user> <password> <database> [-p port] [--integrated]
```

## SQLite

```bash
# query 参数格式
db-sqlite query <filePath> -q "SQL" [-o json|csv|table] [--readonly] [--checkpoint] [--no-checkpoint]

# 批量脚本（支持 DDL/DML 多条；含多条 SELECT 时仅返回第一个结果集）
db-sqlite query <filePath> -f script.sql

# 仅做 WAL 合并（备份/离线拷贝前建议执行）
db-sqlite query <filePath> --checkpoint

# connect 参数格式
db-sqlite connect <filePath>
```

SQLite 专属选项：

| 选项 | 说明 |
|------|------|
| `--readonly` | 只读打开（纯查询场景，防误写） |
| `--checkpoint` | 仅执行 `PRAGMA wal_checkpoint(TRUNCATE)` 后退出 |
| `--no-checkpoint` | 关闭"写操作后自动 checkpoint"（默认开启） |

## MongoDB

```bash
# query 参数格式：命令形如 collection.method(args)，参数用宽松 JSON（键可省略引号）
db-mongo query <host> <database> -c "users.find({})" [-p port] [-u user] [--password pass] [-o json|table]

# connect 参数格式
db-mongo connect <host> <database> [-p port] [-u user] [--password pass]
```

## Redis

```bash
# query 参数格式（命令按空格切分，支持单/双引号包住带空格的值）
db-redis query <host> -c "COMMAND arg1 arg2" [-p port] [--password pass] [--user user] [-d db] [--secure]

# connect 参数格式
db-redis connect <host> [-p port] [--password pass] [--user user] [-d db] [--secure]
```

## ClickHouse

```bash
# query 参数格式（-p 默认 8123，加 --secure 走 https 且默认 8443）
db-clickhouse query <host> [-p port] [-u user] [-d database] [--password pass] [--secure] -q "SQL" [-o json|csv|table]
db-clickhouse query <host> [...] -f script.sql

# connect 参数格式
db-clickhouse connect <host> [-p port] [-u user] [-d database] [--password pass] [--secure]
```

## Oracle

```bash
# query 参数格式（第 4 个位置参数是服务名）
db-oracle query <host> <user> <password> <service> [-p port] -q "SQL" [-o json|csv|table]

# connect 参数格式
db-oracle connect <host> <user> <password> <service> [-p port]
```

## DuckDB

```bash
# query 参数格式（支持多语句脚本）
db-duckdb query <file.duckdb|:memory:> -q "SQL" [-o json|csv|table] [--readonly]
db-duckdb query <file.duckdb|:memory:> -f script.sql

# connect 参数格式（文件不存在会自动创建）
db-duckdb connect <file.duckdb>
```

## 通用参数

| 参数 | 说明 | 适用数据库 |
|------|------|----------|
| `-q, --query` | SQL 查询语句 | MySQL、PostgreSQL、SQLite、DuckDB、ClickHouse、Oracle、SQL Server、达梦 |
| `-c, --command` | 命令语句 | MongoDB、Redis |
| `-p, --port` | 端口号 | 所有网络数据库 |
| `-o, --output` | 输出格式（json/csv/table） | SQL 数据库；MongoDB 仅 json/table |
| `-f, --file` | 从文件读取 SQL；`-f -` 表示从标准输入读取 | SQL 数据库 |

### 输出通道

- **stdout**：只有结果数据（JSON / CSV / table）。可以直接管道：`... | jq`、`... | Import-Csv`。
- **stderr**：`正在执行查询...`、`查询执行完成 (Nms)`、`返回 N 行数据`、`影响 N 行`、`✓ 查询执行成功` 等进度与统计；报错同样在这里。
- `connect` 会打印连接概况，它本身就是该命令的输出，因此仍在 stdout。
- DML 的 stdout 为空：成功与否看退出码，影响行数在 stderr。

```bash
# 只要数据，丢弃提示
db-mysql query host user pass db -q "SELECT * FROM t LIMIT 10" 2>/dev/null | jq '.[].id'
```

### `-f` / `-f -`：复杂 SQL 的首选写法

`-q` 的 SQL 会先经过 shell 解析，反引号（命令替换）、`$`（变量）、`!`（历史展开）都可能被吃掉，跨平台行为还不一致。含反引号标识符、特殊字符或较长语句时，改用文件或标准输入：

```bash
# 文件
db-mysql query host user pass db -f query.sql

# 标准输入（heredoc，shell 侧零解析）
db-mysql query host user pass db -f - <<'SQL'
SELECT `procurement_orderNo` FROM orders LIMIT 10;
SQL

# 管道（Windows PowerShell 同样可用）
'SELECT 1 AS v' | db-sqlite.exe query app.db -f - -o json
```

语义：

- 整个输入作为一条命令提交，可包含多条语句
- 多语句时**只输出第一个结果集**，其余语句照常执行（会打印一行提示）
- 输入为空（0 字节）时保持原有报错「请提供 SQL 查询语句」
- `-f -` 在交互终端下无输入会阻塞，脚本里务必重定向

MongoDB 与 Redis 没有 `-f`，它们用 `-c` 传命令。
