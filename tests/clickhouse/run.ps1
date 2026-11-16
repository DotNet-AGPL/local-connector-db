#Requires -Version 7.0
<#
.SYNOPSIS
    ClickHouse 黄金文件测试。

.DESCRIPTION
    为什么不做 Node 基线对拍：现有 scripts-clickhouse/query.js 拼 URL 时把 "http://host"
    当成已含端口（includes(':') 为真），端口永远不会追加，请求打到 80 端口返回 404，
    也就是说 Node 版从未真正可用，没有可信基线。

    测试直接连真实数仓（172.16.10.22），凭据从 Desktop\hadp\.env 读取，不落盘。
    写操作只碰 ods.lcdb_* 表，用例前后 DROP。

.EXAMPLE
    .\run.ps1
    .\run.ps1 -Regenerate
    .\run.ps1 -Filter select
#>
[CmdletBinding()]
param(
    [string]$Filter = '',

    [switch]$Regenerate,

    [switch]$ShowDiff
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'parity/common.ps1')

$SkillRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ExpectedDir = Join-Path $PSScriptRoot 'expected'
$ExePath = Join-Path $SkillRoot 'bin/clickhouse-win-x64/db-clickhouse.exe'
$EnvFile = 'C:\Users\Think\Desktop\hadp\.env'

if (-not (Test-Path $ExePath)) {
    throw ("未找到 {0}，请先运行: .\build.ps1 -Only clickhouse" -f $ExePath)
}

$envs = @{}
if (Test-Path $EnvFile) {
    Get-Content $EnvFile -Encoding UTF8 | ForEach-Object {
        if ($_ -match '^([A-Za-z0-9_]+)\s*=\s*(.*)$') { $envs[$matches[1]] = $matches[2].Trim() }
    }
}

$ChHost = $envs['DWH_CH_HOST']
$ChPort = $envs['DWH_CH_HTTP_PORT']
$ChUser = $envs['DWH_CH_ETL_USER']
$ChPassword = $envs['DWH_CH_ETL_PW']
$ChDb = 'ods'

if (-not $ChHost) {
    throw '未找到 ClickHouse 凭据（Desktop\hadp\.env 缺 DWH_CH_*）'
}

$TableName = 'lcdb_t'

New-Item -ItemType Directory -Force -Path $ExpectedDir | Out-Null

function New-ChArgs {
    param([string[]]$Tail = @())

    return @($ChHost, '-p', "$ChPort", '-u', $ChUser, '--password', $ChPassword, '-d', $ChDb) + $Tail
}

function Clear-TestTables {
    & $ExePath query @(New-ChArgs @('-q', "DROP TABLE IF EXISTS $TableName")) *> $null
}

function Invoke-TableSetup {
    foreach ($sql in @(
            "DROP TABLE IF EXISTS $TableName",
            "CREATE TABLE $TableName (id Int32, name String, amt Decimal(10,2)) ENGINE = MergeTree ORDER BY id",
            "INSERT INTO $TableName VALUES (1, '甲', 1.50), (2, '乙', 2.25)")) {
        & $ExePath query @(New-ChArgs @('-q', $sql)) *> $null
    }
}

$Cases = @(
    @{ Name = 'connect';            Verb = 'connect'; Mode = 'exit'; Args = @($ChHost, '-p', "$ChPort", '-u', $ChUser, '--password', $ChPassword, '-d', 'system') }

    @{ Name = 'select-scalars';     Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', "SELECT 42::Int32 AS i32, 'hello' AS s, '张三' AS cn, true AS b, toDate('2026-11-13') AS d")) }
    @{ Name = 'select-csv';         Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', "SELECT 42::Int32 AS i32, 'hello' AS s, '张三' AS cn", '-o', 'csv')) }
    @{ Name = 'select-table';       Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', "SELECT 42::Int32 AS i32, 'hello' AS s, '张三' AS cn", '-o', 'table')) }
    @{ Name = 'select-empty';       Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', 'SELECT 1 AS one WHERE 1 = 0')) }
    @{ Name = 'select-decimal';     Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', 'SELECT toDecimal64(1234.500, 3) AS dec')) }
    @{ Name = 'select-biguint';     Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', "SELECT toUInt64('18446744073709551615') AS u64")) }
    @{ Name = 'select-datetime';    Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', "SELECT toDateTime64('2026-11-13 10:00:00', 3, 'Asia/Shanghai') AS dt64")) }
    @{ Name = 'select-complex';     Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', "SELECT [1, 2, 3] AS arr, tuple(1, 'x') AS tup, map('a', 1) AS mp, CAST(NULL AS Nullable(String)) AS maybe")) }

    @{ Name = 'table-select';       Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-ChArgs @('-q', "SELECT id, name, amt FROM $TableName ORDER BY id")) }
    @{ Name = 'table-insert';       Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-ChArgs @('-q', "INSERT INTO $TableName VALUES (3, '丙', 3.25)")) }

    @{ Name = 'error-syntax';       Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', 'SELEC 1')) }
    @{ Name = 'error-auth';         Verb = 'query'; Mode = 'exit'; Args = @($ChHost, '-p', "$ChPort", '-u', $ChUser, '--password', 'wrong_password', '-d', $ChDb, '-q', 'SELECT 1') }
    @{ Name = 'error-unknown-db';   Verb = 'query'; Mode = 'exit'; Args = @($ChHost, '-p', "$ChPort", '-u', $ChUser, '--password', $ChPassword, '-d', 'no_such_db', '-q', 'SELECT 1') }
    @{ Name = 'error-format';       Verb = 'query'; Mode = 'full'; Args = (New-ChArgs @('-q', 'SELECT 1 AS one', '-o', 'xml')) }
    @{ Name = 'error-no-sql';       Verb = 'query'; Mode = 'full'; Args = (New-ChArgs) }
)

$passed = 0
$failed = @()

Clear-TestTables

foreach ($case in $Cases) {
    if ($Filter -and -not $case.Name.Contains($Filter)) {
        continue
    }

    Clear-TestTables

    if ($case.ContainsKey('Setup') -and $case.Setup) {
        Invoke-TableSetup
    }

    $work = New-CaseWorkspace -CaseName $case.Name
    $result = Invoke-Native -FilePath $ExePath -ArgumentList (@($case.Verb) + $case.Args) -WorkDir $work

    $actual = Normalize-Output -Code $result.Code -Stdout $result.Stdout -Stderr $result.Stderr -WorkDir $work
    $actual = $actual -replace 'ClickHouse 版本: .*', 'ClickHouse 版本: <ver>'
    $actual = $actual -replace '\[2026-\d\d-\d\dT[^\]]+\]', '[<ts>]'
    $actual = $actual -replace 'query_id[^,]*', 'query_id: <id>'
    $actual = $actual -replace '\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', '<uuid>'

    if ($case.Mode -eq 'exit') {
        $actual = ($actual -split "`n" | Select-Object -First 1) -join "`n"
    }

    $expectedFile = Join-Path $ExpectedDir ($case.Name + '.txt')

    if ($Regenerate) {
        Set-Content -LiteralPath $expectedFile -Value $actual -Encoding utf8 -NoNewline
        Write-Host ("[GEN  ] {0}" -f $case.Name) -ForegroundColor Cyan
        $passed++
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        continue
    }

    if (-not (Test-Path $expectedFile)) {
        $failed += $case.Name
        Write-Host ("[MISS ] {0}" -f $case.Name) -ForegroundColor Red
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        continue
    }

    $expected = (Get-Content -LiteralPath $expectedFile -Raw -Encoding utf8).TrimEnd("`n", "`r")

    if ($actual -eq $expected) {
        $passed++
        Write-Host ("[ OK   ] {0}" -f $case.Name) -ForegroundColor Green
    }
    else {
        $failed += $case.Name
        Write-Host ("[FAIL ] {0}" -f $case.Name) -ForegroundColor Red
        Show-TextDiff -Expected $expected -Actual $actual
    }

    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Clear-TestTables

Write-Host ''
Write-Host ("[clickhouse] 通过 {0} 个，失败 {1} 个" -f $passed, $failed.Count) -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    exit 1
}
