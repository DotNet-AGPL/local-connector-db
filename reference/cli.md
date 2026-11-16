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
| `-f, --file` | 从文件读取 SQL | SQL 数据库 |
