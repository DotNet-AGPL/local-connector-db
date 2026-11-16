<#
    MySQL 对拍用例。数据源是 WSL/nerdctl 里的容器（tests/containers/mysql.ps1）。

    有意差异（都已在 SKILL.md 记录）：
        - DATETIME：node 转成 UTC ISO（偏移 8 小时），我们原样输出
        - DECIMAL：node 返回字符串，我们输出数字
        - TINYINT(1)：node 输出 0/1/2，我们按驱动映射成 true/false
        - BLOB：node 输出 {"type":"Buffer",...}，我们输出 <BLOB n bytes>
        - BIGINT：node 精度丢失，超 2^53 我们输出字符串
        - JSON 列：node 会重新序列化（缩进不同），我们原样内联
#>

$DbName = 'mysql'
$SkillRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ExpectedDir = Join-Path $PSScriptRoot 'expected'
$ExePath = Join-Path $SkillRoot "bin/$DbName-win-x64/db-$DbName.exe"
$NodeScriptDir = Join-Path $SkillRoot "scripts-$DbName"
$ContainerScript = Join-Path $SkillRoot 'tests/containers/mysql.ps1'

# 用 WSL 的 IP 而不是 localhost：容器重建后 WSL2 的 localhost 转发会失效（ECONNREFUSED），
# 但 WSL 网卡地址始终可达。地址每个用例现取，避免 WSL 重启后 IP 变化导致超时。
function Resolve-MySqlHost {
    $address = (& wsl -d debian-nerdctl -- hostname -I 2>$null | Out-String).Trim().Split(' ')[0]

    if (-not $address) {
        return '127.0.0.1'
    }

    return $address
}

$MySqlPort = 13306
$MySqlUser = 'root'
$MySqlPassword = 'lcdb_pw'
$MySqlDatabase = 'lcdb'

function New-MySqlArgs {
    param([string[]]$Tail = @())

    return @('{host}', $MySqlUser, $MySqlPassword, $MySqlDatabase, '-p', "$MySqlPort") + $Tail
}

$Script:CaseList = @(
    @{ Name = 'connect-existing';   Verb = 'connect'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs) }

    @{ Name = 'select-basic-json';  Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'SELECT id, name, qty FROM t_items ORDER BY id')) }
    @{ Name = 'select-basic-csv';   Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'SELECT id, name, qty FROM t_items ORDER BY id', '-o', 'csv')) }
    @{ Name = 'select-basic-table'; Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'SELECT id, name, qty FROM t_items ORDER BY id', '-o', 'table')) }
    @{ Name = 'select-empty';       Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'SELECT id, name FROM t_items WHERE 1 = 0')) }
    @{ Name = 'select-count';       Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'SELECT COUNT(*) AS cnt FROM t_items')) }
    @{ Name = 'select-null';        Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'SELECT id, amount FROM t_items WHERE amount IS NULL')) }
    @{ Name = 'select-cjk-json';    Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'SELECT id, name_cn FROM t_cn ORDER BY id')) }

    @{ Name = 'select-table-cjk';   Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-MySqlArgs @('-q', 'SELECT id, name_cn FROM t_cn ORDER BY id', '-o', 'table')) }
    @{ Name = 'select-types';       Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-MySqlArgs @('-q', 'SELECT id, ti1, de, dt, da, tm FROM t_types ORDER BY id')) }
    @{ Name = 'select-json-col';    Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-MySqlArgs @('-q', 'SELECT id, js FROM t_types WHERE id = 1')) }
    @{ Name = 'select-blob';        Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-MySqlArgs @('-q', 'SELECT id, bl FROM t_types WHERE id = 1')) }
    @{ Name = 'select-bigint';      Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-MySqlArgs @('-q', 'SELECT id, bi, ubi FROM t_types WHERE id = 1')) }
    @{ Name = 'select-bit';         Verb = 'query'; Mode = 'full'; ExpectDiff = $true;  Args = (New-MySqlArgs @('-q', 'SELECT id, bt1, bt8 FROM t_types WHERE id = 1')) }

    @{ Name = 'dml-insert';         Verb = 'query'; Mode = 'full'; Seed = $true; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', "INSERT INTO t_items (name, qty, amount) VALUES ('delta', 7, 1.50)")) }
    @{ Name = 'dml-update';         Verb = 'query'; Mode = 'full'; Seed = $true; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'UPDATE t_items SET qty = qty + 1 WHERE id <= 2')) }
    @{ Name = 'dml-delete';         Verb = 'query'; Mode = 'full'; Seed = $true; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'DELETE FROM t_items WHERE id = 3')) }

    @{ Name = 'error-syntax';       Verb = 'query'; Mode = 'exit'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'SELEC 1')) }
    @{ Name = 'error-missing-db';   Verb = 'query'; Mode = 'exit'; ExpectDiff = $false; Args = @('{host}', $MySqlUser, $MySqlPassword, 'no_such_db', '-p', "$MySqlPort", '-q', 'SELECT 1') }
    @{ Name = 'error-auth';         Verb = 'query'; Mode = 'exit'; ExpectDiff = $false; Args = @('{host}', $MySqlUser, 'wrong_password', $MySqlDatabase, '-p', "$MySqlPort", '-q', 'SELECT 1') }
    @{ Name = 'error-format';       Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'SELECT 1 AS one', '-o', 'xml')) }
    @{ Name = 'error-no-sql';       Verb = 'query'; Mode = 'full'; ExpectDiff = $false; Args = (New-MySqlArgs) }
    @{ Name = 'fk-violation';       Verb = 'query'; Mode = 'exit'; ExpectDiff = $false; Args = (New-MySqlArgs @('-q', 'INSERT INTO t_child (parent_id) VALUES (999)')) }
)

function Initialize-TestData {
    param([string]$ExePath)

    & $ContainerScript -Action up
}

function New-CaseContext {
    param([hashtable]$Case)

    # 每个用例前重置数据并自愈容器，保证与基线一致、且不受环境抖动影响
    & $ContainerScript -Action seed

    $work = New-CaseWorkspace -CaseName $Case.Name
    $hostAddress = Resolve-MySqlHost
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
