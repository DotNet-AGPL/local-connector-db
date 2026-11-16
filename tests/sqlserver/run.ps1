#Requires -Version 7.0
<#
.SYNOPSIS
    SQL Server 黄金文件测试（Windows LocalDB）。

.DESCRIPTION
    用本机 LocalDB 实例 MSSQLLocalDB（Windows 集成认证），测试库 lcdb_test，表 dbo.LCDB_*。
    容器方案（mcr 镜像）实测被限速到 175 KiB/s，故改用 LocalDB。

    为什么不做 Node 对拍：旧 scripts-sqlserver 需要 mssql 包且未安装，且现有实现的输出形态
    （Date 对象、Buffer）与本工具差异较大，直接用黄金文件更可靠。

.EXAMPLE
    .\run.ps1
    .\run.ps1 -Regenerate
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
$ExePath = Join-Path $SkillRoot 'bin/sqlserver-win-x64/db-sqlserver.exe'

if (-not (Test-Path $ExePath)) {
    throw ("未找到 {0}，请先运行: .\build.ps1 -Only sqlserver" -f $ExePath)
}

$SqlHostName = '(localdb)\MSSQLLocalDB'
$SqlDatabase = 'lcdb_test'
$SqlUser = 'x'
$SqlPassword = 'x'

New-Item -ItemType Directory -Force -Path $ExpectedDir | Out-Null

function New-SqlArgs {
    param([string[]]$Tail = @())

    return @($SqlHostName, $SqlUser, $SqlPassword, $SqlDatabase, '--integrated') + $Tail
}

function Invoke-Sql {
    param([string]$Sql)

    & $ExePath query @(New-SqlArgs @('-q', $Sql)) *> $null
}

function Clear-TestTables {
    Invoke-Sql 'IF OBJECT_ID(''dbo.LCDB_T'', ''U'') IS NOT NULL DROP TABLE dbo.LCDB_T'
    Invoke-Sql 'IF OBJECT_ID(''dbo.LCDB_T2'', ''U'') IS NOT NULL DROP TABLE dbo.LCDB_T2'
}

function Invoke-TableSetup {
    Invoke-Sql 'CREATE TABLE dbo.LCDB_T (ID INT, NAME NVARCHAR(32), AMT DECIMAL(10,2), D DATE, TS DATETIME2(3), BIN VARBINARY(16))'
    Invoke-Sql "INSERT INTO dbo.LCDB_T VALUES (1, N'甲', 1.50, '2026-11-13', '2026-11-13T10:00:00', 0x0102030405)"
    Invoke-Sql "INSERT INTO dbo.LCDB_T VALUES (2, N'乙', NULL, NULL, NULL, NULL)"
}

function Initialize-TestData {
    # 确保测试库存在（LocalDB 集成认证有 sysadmin 权限）
    $create = "IF DB_ID('$SqlDatabase') IS NULL CREATE DATABASE [$SqlDatabase]"
    & $ExePath query @($SqlHostName, $SqlUser, $SqlPassword, 'master', '--integrated', '-q', $create) *> $null
}

$Cases = @(
    @{ Name = 'connect';        Verb = 'connect'; Mode = 'exit'; Args = (New-SqlArgs) }

    @{ Name = 'select-scalars'; Verb = 'query'; Mode = 'full'; Args = (New-SqlArgs @('-q', "SELECT CAST(42 AS INT) AS i, N'hello' AS s, N'张三' AS cn, CAST(1 AS BIT) AS flag")) }
    @{ Name = 'select-csv';     Verb = 'query'; Mode = 'full'; Args = (New-SqlArgs @('-q', "SELECT CAST(42 AS INT) AS i, N'hello' AS s, N'张三' AS cn", '-o', 'csv')) }
    @{ Name = 'select-table';   Verb = 'query'; Mode = 'full'; Args = (New-SqlArgs @('-q', "SELECT CAST(42 AS INT) AS i, N'hello' AS s, N'张三' AS cn", '-o', 'table')) }
    @{ Name = 'select-empty';   Verb = 'query'; Mode = 'full'; Args = (New-SqlArgs @('-q', 'SELECT 1 AS one WHERE 1 = 0')) }
    @{ Name = 'select-types';   Verb = 'query'; Mode = 'full'; Args = (New-SqlArgs @('-q', "SELECT CAST(1234.500 AS DECIMAL(12,3)) AS dec, CAST('2026-11-13' AS DATE) AS d, CAST('2026-11-13T10:00:00' AS DATETIME2(3)) AS dt2, CAST('11111111-2222-3333-4444-555555555555' AS UNIQUEIDENTIFIER) AS uid")) }

    @{ Name = 'table-select';   Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-SqlArgs @('-q', 'SELECT ID, NAME, AMT, D, TS, BIN FROM dbo.LCDB_T ORDER BY ID')) }
    @{ Name = 'table-insert';   Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-SqlArgs @('-q', "INSERT INTO dbo.LCDB_T (ID, NAME, AMT) VALUES (3, N'丙', 3.25)")) }
    @{ Name = 'ddl-create';     Verb = 'query'; Mode = 'full'; Args = (New-SqlArgs @('-q', 'CREATE TABLE dbo.LCDB_T2 (ID INT)')) }

    @{ Name = 'error-syntax';   Verb = 'query'; Mode = 'full'; Args = (New-SqlArgs @('-q', 'SELEC 1')) }
    @{ Name = 'error-format';   Verb = 'query'; Mode = 'full'; Args = (New-SqlArgs @('-q', 'SELECT 1 AS one', '-o', 'xml')) }
    @{ Name = 'error-no-sql';   Verb = 'query'; Mode = 'full'; Args = (New-SqlArgs) }
)

Initialize-TestData

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
    $actual = $actual -replace '服务端版本: .*', '服务端版本: <ver>'

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
Write-Host ("[sqlserver] 通过 {0} 个，失败 {1} 个" -f $passed, $failed.Count) -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    exit 1
}
