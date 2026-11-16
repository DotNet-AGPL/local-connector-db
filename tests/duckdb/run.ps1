#Requires -Version 7.0
<#
.SYNOPSIS
    DuckDB 黄金文件测试。没有 Node 版可对拍，期望输出由本工具一次性生成后人工确认。

.DESCRIPTION
    每个用例前重建种子库，输出经归一化（毫秒耗时、临时路径、版本号）后与 expected 比对。

.EXAMPLE
    .\run.ps1
    .\run.ps1 -Filter select-types
    .\run.ps1 -Regenerate      # 重新生成期望文件（改动用例或格式后使用）
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
$FixtureDir = Join-Path $PSScriptRoot 'fixtures'
$ExpectedDir = Join-Path $PSScriptRoot 'expected'
$ExePath = Join-Path $SkillRoot 'bin/duckdb-win-x64/db-duckdb.exe'

if (-not (Test-Path $ExePath)) {
    throw ("未找到 {0}，请先运行: .\build.ps1 -Only duckdb" -f $ExePath)
}

New-Item -ItemType Directory -Force -Path $ExpectedDir | Out-Null

$Cases = @(
    @{ Name = 'connect-new';      Verb = 'connect'; Db = 'missing';  Mode = 'full'; Args = @('{db}') }
    @{ Name = 'connect-existing'; Verb = 'connect'; Db = 'seed';     Mode = 'full'; Args = @('{db}') }

    @{ Name = 'select-basic-json';  Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT id, name, qty FROM t_items ORDER BY id') }
    @{ Name = 'select-basic-csv';   Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT id, name, qty FROM t_items ORDER BY id', '-o', 'csv') }
    @{ Name = 'select-basic-table'; Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT id, name, qty FROM t_items ORDER BY id', '-o', 'table') }
    @{ Name = 'select-empty';       Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT id, name FROM t_items WHERE 1 = 0') }
    @{ Name = 'select-count';       Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT COUNT(*) AS cnt FROM t_items') }
    @{ Name = 'select-null';        Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT id, amt FROM t_items WHERE amt IS NULL') }
    @{ Name = 'select-cjk';         Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT id, name_cn FROM t_cn ORDER BY id') }
    @{ Name = 'select-table-cjk';   Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT id, name_cn FROM t_cn ORDER BY id', '-o', 'table') }
    @{ Name = 'select-types';       Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT id, flag, big, huge, amt, ts, d, tm FROM t_types ORDER BY id') }
    @{ Name = 'select-nested';      Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT id, lst, st, mp, blb, js FROM t_types WHERE id = 1') }
    @{ Name = 'select-aggregate';   Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT name, SUM(qty) AS total FROM t_items GROUP BY name ORDER BY name') }

    @{ Name = 'dml-insert';         Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', "INSERT INTO t_items VALUES (4, 'delta', 7, 1.50)") }
    @{ Name = 'dml-update';         Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'UPDATE t_items SET qty = qty + 1 WHERE id <= 2') }
    @{ Name = 'dml-delete';         Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'DELETE FROM t_items WHERE id = 3') }
    @{ Name = 'script-multi';       Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-f', '{fixture:multi.sql}') }

    @{ Name = 'memory-query';       Verb = 'query'; Db = 'none'; Mode = 'full'; Args = @(':memory:', '-q', 'SELECT 42 AS answer, [1, 2, 3] AS lst') }
    @{ Name = 'readonly-select';    Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT COUNT(*) AS cnt FROM t_items', '--readonly') }
    @{ Name = 'readonly-write';     Verb = 'query'; Db = 'seed'; Mode = 'exit'; Args = @('{db}', '-q', "INSERT INTO t_items VALUES (9, 'blocked', 0, NULL)", '--readonly') }

    @{ Name = 'error-missing-db';   Verb = 'query'; Db = 'missing'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT 1') }
    @{ Name = 'error-syntax';       Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELEC 1') }
    @{ Name = 'error-format';       Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}', '-q', 'SELECT 1 AS one', '-o', 'xml') }
    @{ Name = 'error-no-sql';       Verb = 'query'; Db = 'seed'; Mode = 'full'; Args = @('{db}') }
)

function New-SeededDatabase {
    param([string]$Path)

    Remove-Item ($Path + '*') -Force -ErrorAction SilentlyContinue
    & $ExePath connect $Path *> $null
    & $ExePath query $Path -f (Join-Path $FixtureDir 'create.sql') *> $null

    if ($LASTEXITCODE -ne 0) {
        throw '种子库初始化失败'
    }
}

$passed = 0
$failed = @()

foreach ($case in $Cases) {
    if ($Filter -and -not $case.Name.Contains($Filter)) {
        continue
    }

    $work = New-CaseWorkspace -CaseName $case.Name
    $database = Join-Path $work 'case.duckdb'

    if ($case.Db -eq 'seed') {
        New-SeededDatabase -Path $database
    }

    $args = foreach ($item in $case.Args) {
        if ($item -eq '{db}') {
            $database
        }
        elseif ($item.StartsWith('{fixture:')) {
            Join-Path $FixtureDir $item.Substring(9).TrimEnd('}')
        }
        else {
            $item
        }
    }

    $result = Invoke-Native -FilePath $ExePath -ArgumentList (@($case.Verb) + @($args)) -WorkDir $work
    $actual = Normalize-Output -Code $result.Code -Stdout $result.Stdout -Stderr $result.Stderr -WorkDir $work
    $actual = $actual -replace 'DuckDB 版本: .*', 'DuckDB 版本: <ver>'
    $actual = $actual -replace '数据库文件大小: [\d.]+ KB', '数据库文件大小: <size> KB'

    if ($case.Mode -eq 'exit') {
        $actual = ($actual -split "`n" | Select-Object -First 1) -join "`n"
    }

    $expectedFile = Join-Path $ExpectedDir ($case.Name + '.txt')

    if ($Regenerate) {
        # exit 模式只固化退出码，其余固化完整输出
        Set-Content -LiteralPath $expectedFile -Value $actual -Encoding utf8 -NoNewline
        Write-Host ("[GEN  ] {0}" -f $case.Name) -ForegroundColor Cyan
        $passed++
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        continue
    }

    if (-not (Test-Path $expectedFile)) {
        $failed += $case.Name
        Write-Host ("[MISS ] {0}  (缺少期望文件，先运行 -Regenerate)" -f $case.Name) -ForegroundColor Red
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        continue
    }

    $expected = (Get-Content -LiteralPath $expectedFile -Raw -Encoding utf8)
    $expected = $expected.TrimEnd("`n", "`r")

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

Write-Host ''
Write-Host ("[duckdb] 通过 {0} 个，失败 {1} 个" -f $passed, $failed.Count) -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    exit 1
}
