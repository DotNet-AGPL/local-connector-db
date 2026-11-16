<#
    PostgreSQL 对拍用例。数据源是 WSL/nerdctl 里的容器（tests/containers/postgres.ps1）。

    有意差异：
        - timestamp/timestamptz：node 转成 UTC ISO，我们原样输出
        - numeric：node 返回字符串，我们输出数字
        - bytea：node 输出 {"type":"Buffer",...}，我们输出 <BLOB n bytes>
        - bigint：超 2^53 我们输出字符串
        - JSON 列：node 重新序列化（缩进/键序可能不同），我们原样内联
        - DML：node 打印「返回 0 行数据」，我们打印「影响 N 行」
#>

$DbName = 'postgres'
$SkillRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ExpectedDir = Join-Path $PSScriptRoot 'expected'
$ExePath = Join-Path $SkillRoot "bin/$DbName-win-x64/db-$DbName.exe"
$NodeScriptDir = Join-Path $SkillRoot "scripts-$DbName"
$ContainerScript = Join-Path $SkillRoot 'tests/containers/postgres.ps1'

function Resolve-PostgresHost {
    $address = (& wsl -d debian-nerdctl -- hostname -I 2>$null | Out-String).Trim().Split(' ')[0]

    if (-not $address) {
        return '127.0.0.1'
    }

    return $address
}

$PgPort = 15432
$PgUser = 'postgres'
$PgPassword = 'lcdb_pw'
$PgDatabase = 'lcdb'

function New-PgArgs {
    param([string[]]$Tail = @())

    return @('{host}', $PgUser, $PgPassword, $PgDatabase, '-p', "$PgPort") + $Tail
}

$Script:CaseList = @(
    @{ Name = 'connect-existing';   Verb = 'connect'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs) }

    @{ Name = 'select-basic-json';  Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'SELECT id, name, qty FROM t_items ORDER BY id')) }
    @{ Name = 'select-basic-csv';   Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'SELECT id, name, qty FROM t_items ORDER BY id', '-o', 'csv')) }
    @{ Name = 'select-basic-table'; Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'SELECT id, name, qty FROM t_items ORDER BY id', '-o', 'table')) }
    @{ Name = 'select-empty';       Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'SELECT id, name FROM t_items WHERE 1 = 0')) }
    @{ Name = 'select-count';       Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-PgArgs @('-q', 'SELECT COUNT(*) AS cnt FROM t_items')) }
    @{ Name = 'select-null';        Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'SELECT id, amount FROM t_items WHERE amount IS NULL')) }
    @{ Name = 'select-cjk-json';    Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'SELECT id, name_cn FROM t_cn ORDER BY id')) }

    @{ Name = 'select-table-cjk';   Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-PgArgs @('-q', 'SELECT id, name_cn FROM t_cn ORDER BY id', '-o', 'table')) }
    @{ Name = 'select-types';       Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-PgArgs @('-q', 'SELECT id, b, nu, ts, tstz, da, tm FROM t_types ORDER BY id')) }
    @{ Name = 'select-json-col';    Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-PgArgs @('-q', 'SELECT id, js, jsb FROM t_types WHERE id = 1')) }
    @{ Name = 'select-bytea';       Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-PgArgs @('-q', 'SELECT id, bl FROM t_types WHERE id = 1')) }
    @{ Name = 'select-bigint';      Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-PgArgs @('-q', 'SELECT id, bi FROM t_types WHERE id = 1')) }
    @{ Name = 'select-array';       Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'SELECT id, ta, ia FROM t_types WHERE id = 1')) }

    @{ Name = 'dml-insert';         Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-PgArgs @('-q', "INSERT INTO t_items (name, qty, amount) VALUES ('delta', 7, 1.50)")) }
    @{ Name = 'dml-update';         Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-PgArgs @('-q', 'UPDATE t_items SET qty = qty + 1 WHERE id <= 2')) }
    @{ Name = 'dml-delete';         Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-PgArgs @('-q', 'DELETE FROM t_items WHERE id = 3')) }

    @{ Name = 'error-syntax';       Verb = 'query'; Mode = 'exit'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'SELEC 1')) }
    @{ Name = 'error-missing-db';   Verb = 'query'; Mode = 'exit'; ExpectDiff = $false; Args = @('{host}', $PgUser, $PgPassword, 'no_such_db', '-p', "$PgPort", '-q', 'SELECT 1') }
    @{ Name = 'error-auth';         Verb = 'query'; Mode = 'exit'; ExpectDiff = $false; Args = @('{host}', $PgUser, 'wrong_password', $PgDatabase, '-p', "$PgPort", '-q', 'SELECT 1') }
    @{ Name = 'error-format';       Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'SELECT 1 AS one', '-o', 'xml')) }
    @{ Name = 'error-no-sql';       Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-PgArgs) }
    @{ Name = 'fk-violation';       Verb = 'query'; Mode = 'exit'; ExpectDiff = $false; Args = (New-PgArgs @('-q', 'INSERT INTO t_child (parent_id) VALUES (999)')) }
)

function Initialize-TestData {
    param([string]$ExePath)

    & $ContainerScript -Action up
}

function New-CaseContext {
    param([hashtable]$Case)

    & $ContainerScript -Action seed

    $work = New-CaseWorkspace -CaseName $Case.Name
    $hostAddress = Resolve-PostgresHost
    $expanded = foreach ($item in $Case.Args) {
        if ($item -eq '{host}') { $hostAddress } else { $item }
    }

    return @{
        Work = $work
        Args = @($expanded)
    }
}

function Get-RunTarget {
    param(
        [ValidateSet('node', 'exe')][string]$Kind,
        [hashtable]$Case,
        [hashtable]$Context
    )

    $script = Join-Path $NodeScriptDir ($Case.Verb + '.js')

    if ($Kind -eq 'node') {
        return @{ File = 'node'; Args = @($script) + $Context.Args }
    }

    return @{ File = $ExePath; Args = @($Case.Verb) + $Context.Args }
}
