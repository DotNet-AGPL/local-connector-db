# 各库特性

## 目录

- SQLite
- MySQL
- PostgreSQL
- MongoDB
- Redis
- ClickHouse
- Oracle
- SQL Server
- 达梦 (DM)
- DuckDB

## SQLite

- 制品：`bin/sqlite-win-x64/` 下 `db-sqlite.exe` + `e_sqlite3.dll`
- **按文件路径打开，自动读取/恢复 `-wal`（WAL 感知）**
- 写操作成功后**默认执行 `PRAGMA wal_checkpoint(TRUNCATE)`**（可用 `--no-checkpoint` 关闭），使主库文件自身自洽
- 备份/离线拷贝前建议先跑 `--checkpoint`，或使用 SQLite 备份 API（`VACUUM INTO` / `.backup`）
- 数据库文件不存在时：`connect` 自动创建，`query` 直接报错
- 外键约束默认开启

## MySQL

- 制品：`bin/mysql-win-x64/db-mysql.exe` 单文件
- 连接参数：`SslMode=Preferred`（尝试 TLS，失败回退）、`utf8mb4`、关闭连接池
- `TINYINT(1)` 映射为布尔（非 0 即 true）；需要原始数值请改用 `TINYINT(2)` 及以上或 `CAST`；`BIT(1)` → `0/1`，`BIT(8)` → `0-255`
- `JSON` 列直接内联为对象/数组；`DECIMAL` 输出数字而非字符串
- 查询/更新结果判定基于结果集而非 SQL 文本：有列即为查询，否则输出 `影响 N 行` 与 `新插入记录 ID`
- 列名标识符：混合大小写、保留字或含特殊字符时统一用反引号（`` `procurement_orderNo` ``）；名字本身含反引号时写成 ```` `` ````
- MySQL 的列名本身大小写不敏感（`lower_case_table_names` 只影响库名/表名），遇到 `Unknown column` 先核对拼写与下划线，用 `SHOW COLUMNS FROM t LIKE '%procure%'` 或查 `information_schema.columns` 确认实际列名
- 中间层（TiDB / OceanBase / 代理 / 云厂商 DMS）可能有大小写或引号规则的额外差异，跨层排查时以 `SHOW COLUMNS` 结果为准
- 反引号在 bash 里是命令替换：`-q "SELECT `col` ..."` 会被 shell 破坏。含反引号的 SQL 用单引号包裹，或直接走 `-f script.sql` / `-f -`（推荐，见 [cli.md](cli.md)）

## PostgreSQL

- 制品：`bin/postgres-win-x64/db-postgres.exe` 单文件
- 连接参数：`SSL Mode=Prefer`（尝试 TLS，失败回退）、关闭连接池；全部走异步 API
- `numeric` / `int8` 输出数字，`timestamp` 不做时区转换，`bytea` 输出 `<BLOB n bytes>`，`json` / `jsonb` 原样内联
- 数组类型（`text[]`、`int[]`）输出为 JSON 数组

## MongoDB

- 制品：`bin/mongo-win-x64/db-mongo.exe` 单文件
- 命令格式 `collection.method(args)` 或 `db.method(args)`，参数是宽松 JSON（键可不加引号、可用单引号）
- 支持的方法：`find` / `findOne` / `countDocuments` / `estimatedDocumentCount` / `distinct` / `aggregate` / `insertOne` / `insertMany` / `updateOne` / `updateMany` / `replaceOne` / `deleteOne` / `deleteMany` / `createIndex` / `indexes` / `drop` / `dropIndexes`，以及 `db.stats()` / `db.getCollectionNames()` / `db.getCollectionInfos()` / `db.dropDatabase()` / `db.version()` / `db.runCommand({...})`
- 命令用白名单解析执行（不走 `eval`），**不支持 `ObjectId("…")` 这类 JS 包装**；改用扩展 JSON：`{"_id": {"$oid": "..."}}`、`{"$date": "..."}`、`{"$numberLong": "..."}`
- 输出形态：`ObjectId` 打印 24 位十六进制，日期打印 ISO 8601（带 Z），二进制打印 `<BLOB n bytes>`，嵌套文档/数组保持结构
- `-o table` 按文档顶层字段出表；嵌套值按 JSON 呈现

## Redis

- 制品：`bin/redis-win-x64/db-redis.exe` 单文件
- 命令透传，支持任意 Redis 命令（`GET` / `HGETALL` / `LRANGE` / `SCAN` / `MODULE LIST` 等）
- `INFO` / `CONFIG` 等管理命令可用（驱动已开 `AllowAdmin`）
- 结果形态：字符串原样、整数为数字、数组/集合为 JSON 数组、`HGETALL` 等 Map 为 JSON 对象、`nil` 输出 `(nil)`
- `--password` 是 AUTH 密码，`--user` 走 ACL（Redis 6+），`-d` 选择 db，`--secure` 走 TLS
- `connect` 用 `SCAN` 而不是 `KEYS` 取键样本，避免阻塞大库
- 批量操作建议使用 Lua 脚本（`EVAL`）

## ClickHouse

- 制品：`bin/clickhouse-win-x64/db-clickhouse.exe` 单文件
- 走官方 `ClickHouse.Driver` 的 HTTP(S) 模式：默认 `http`+8123，`--secure` 用 `https`+8443
- 结果集用 `FORMAT JSON` 取回后自行解析（不走驱动的 RowBinary 反序列化，那条路在 AOT 下对 `Tuple` / `Map` 会崩）
- 值形态：`Decimal` 输出数字、`UInt64` 超 2^53 输出字符串、`DateTime` / `DateTime64` 统一成带 `T` 的 ISO、`Array` / `Tuple` 输出 JSON 数组、`Map` 输出 JSON 对象、`Nullable` 为 `null`、`Enum` / `UUID` / `IPv4/6` 为字符串、`Bool` 为布尔
- 一次一条语句（多语句请拆分），`connect` 会列出当前库的表

## Oracle

- 制品：`bin/oracle-win-x64/db-oracle.exe` 单文件（ODP.NET 纯托管，无需 Instant Client）
- 第 4 个位置参数是**服务名**（如 `FREEPDB1` / `ORCL`），不是库名
- 连接用显式 TNS 描述符而不是 `//host:port/service`：后者在 AOT 下会报 ORA-50201
- 标识符默认大写；`DATE` 输出 `yyyy-MM-dd`，`TIMESTAMP` 输出 `yyyy-MM-ddTHH:mm:ss`
- `CLOB` 输出字符串，`BLOB` 输出 `<BLOB n bytes>`；DDL 影响行数统一显示 0

## SQL Server

- 制品：`bin/sqlserver-win-x64/` 下 `db-sqlserver.exe` + `Microsoft.Data.SqlClient.SNI.dll`（原生依赖，必须同目录）
- `--integrated` 走 Windows 集成认证（支持 `(localdb)\MSSQLLocalDB` 这类实例名，此时不加端口）
- `DATE` 输出 `yyyy-MM-dd`，`DATETIME2` 输出 `yyyy-MM-ddTHH:mm:ss`，`DATETIMEOFFSET` 带时区偏移
- DDL 的影响行数统一显示 0（SQL Server 返回 -1）

## 达梦 (DM)

- 制品：`bin/dm-win-x64/db-dm.exe` 单文件，驱动静态编入
- 第 4 个位置参数是**模式名 schema**（不是库名，达梦一个实例只有一个库）
- 兼容 Oracle 语法；标识符默认大写，`DATE` 输出 `yyyy-MM-dd`，`TIMESTAMP` 输出 `yyyy-MM-ddTHH:mm:ss`
- `CLOB` 输出字符串，`BLOB` 输出 `<BLOB n bytes>`；DDL 的影响行数统一显示 0（达梦返回 -1）
- 默认管理员用户为 `SYSDBA`

## DuckDB

- 制品：`bin/duckdb-win-x64/` 下 `db-duckdb.exe` + `duckdb.dll`
- 嵌入式列存分析库，单文件 `.duckdb`；`query` 要求文件已存在，`connect` 会创建
- `:memory:` 为临时库，只在单次进程内有效，不落盘
- 复杂类型：`LIST` / `ARRAY` 输出 JSON 数组，`STRUCT` / `MAP` 输出 JSON 对象，`HUGEINT` 超 2^53 输出字符串，`BLOB` 输出 `<BLOB n bytes>`
- `JSON` 列在 DuckDB 中类型名仍是 `VARCHAR`，因此按普通字符串输出（带引号）
- `--readonly` 用 `ACCESS_MODE=READ_ONLY` 打开，写操作会直接报错
