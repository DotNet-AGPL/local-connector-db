#Requires -Version 7.0
<#
.SYNOPSIS
    达梦（DM）黄金文件测试。

.DESCRIPTION
    为什么不做 Node 对拍：现有 scripts-dm/query.js 调用的 dm.connect 在当前 dmdb 包里不存在
    （报 dm.connect is not a function），Node 版从未真正可用，没有可信基线。

    测试连 172.16.10.53:5236（SYSDBA）。写操作只碰 LCDB_* 表，用例前后 DROP。
    密码从环境变量 LCDB_DM_PASSWORD 或同目录 .env.local 读，不写进期望文件。

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
$ExePath = Join-Path $SkillRoot 'bin/dm-win-x64/db-dm.exe'
$LocalEnv = Join-Path $PSScriptRoot '.env.local'

if (-not (Test-Path $ExePath)) {
    throw ("未找到 {0}，请先运行: .\build.ps1 -Only dm" -f $ExePath)
}

$DmHost = '172.16.10.53'
$DmPort = 5236
$DmUser = 'SYSDBA'
$DmSchema = 'SYSDBA'
$DmPassword = $env:LCDB_DM_PASSWORD

if (-not $DmPassword -and (Test-Path $LocalEnv)) {
    Get-Content $LocalEnv -Encoding UTF8 | ForEach-Object {
        if ($_ -match '^\s*LCDB_DM_PASSWORD\s*=\s*(.*)$') { $DmPassword = $matches[1].Trim() }
    }
}

if (-not $DmPassword) {
    throw '缺少 DM 密码：请设置环境变量 LCDB_DM_PASSWORD，或在 tests/dm/.env.local 写入 LCDB_DM_PASSWORD=...'
}

New-Item -ItemType Directory -Force -Path $ExpectedDir | Out-Null

function New-DmArgs {
    param([string[]]$Tail = @())

    return @($DmHost, $DmUser, $DmPassword, $DmSchema, '-p', "$DmPort") + $Tail
}

function Clear-TestTables {
    foreach ($table in @('LCDB_T', 'LCDB_T2')) {
        & $ExePath query @(New-DmArgs @('-q', "DROP TABLE $table")) *> $null
    }
}

function Invoke-TableSetup {
    & $ExePath query @(New-DmArgs @('-q', 'CREATE TABLE LCDB_T (ID INT, NAME VARCHAR(20), AMT DECIMAL(10,2), D DATE, TS TIMESTAMP, TXT CLOB, BIN BLOB)')) *> $null
    & $ExePath query @(New-DmArgs @('-q', "INSERT INTO LCDB_T VALUES (1, '甲', 1.50, DATE '2026-11-13', TIMESTAMP '2026-11-13 10:00:00', 'clob text', 0x0102030405)")) *> $null
    & $ExePath query @(New-DmArgs @('-q', "INSERT INTO LCDB_T VALUES (2, '乙', NULL, NULL, NULL, NULL, NULL)")) *> $null
}

$Cases = @(
    @{ Name = 'connect';        Verb = 'connect'; Mode = 'exit'; Args = (New-DmArgs) }

    @{ Name = 'select-scalars'; Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', "SELECT 42 AS i, 'hello' AS s, '张三' AS cn FROM DUAL")) }
    @{ Name = 'select-csv';     Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', "SELECT 42 AS i, 'hello' AS s, '张三' AS cn FROM DUAL", '-o', 'csv')) }
    @{ Name = 'select-table';   Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', "SELECT 42 AS i, 'hello' AS s, '张三' AS cn FROM DUAL", '-o', 'table')) }
    @{ Name = 'select-empty';   Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', 'SELECT 1 AS one FROM DUAL WHERE 1 = 0')) }
    @{ Name = 'select-types';   Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', "SELECT 1234.500 AS n, DATE '2026-11-13' AS d, TIMESTAMP '2026-11-13 10:00:00' AS ts FROM DUAL")) }

    @{ Name = 'table-select';   Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-DmArgs @('-q', 'SELECT ID, NAME, AMT FROM LCDB_T ORDER BY ID')) }
    @{ Name = 'table-blob';     Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-DmArgs @('-q', 'SELECT ID, NAME, AMT, D, TS, TXT, BIN FROM LCDB_T ORDER BY ID')) }
    @{ Name = 'table-insert';   Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-DmArgs @('-q', "INSERT INTO LCDB_T VALUES (3, '丙', 3.25)")) }
    @{ Name = 'ddl-create';     Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', 'CREATE TABLE LCDB_T2 (ID INT)')) }

    @{ Name = 'error-syntax';   Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', 'SELEC 1')) }
    @{ Name = 'error-auth';     Verb = 'query'; Mode = 'exit'; Args = @($DmHost, $DmUser, 'wrong_password', $DmSchema, '-p', "$DmPort", '-q', 'SELECT 1 FROM DUAL') }
    @{ Name = 'error-format';   Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', 'SELECT 1 AS one FROM DUAL', '-o', 'xml')) }
    @{ Name = 'error-no-sql';   Verb = 'query'; Mode = 'full'; Args = (New-DmArgs) }
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

        # 补一列大对象数据，覆盖 CLOB / BLOB
        & $ExePath query @(New-DmArgs @(
                '-q',
                "INSERT INTO LCDB_T VALUES (9, '大对象', 1.00, DATE '2026-11-13', TIMESTAMP '2026-11-13 10:00:00', 'clob text', 0x0102030405)"
            )) *> $null
    }

    $work = New-CaseWorkspace -CaseName $case.Name
    $result = Invoke-Native -FilePath $ExePath -ArgumentList (@($case.Verb) + $case.Args) -WorkDir $work

    $actual = Normalize-Output -Code $result.Code -Stdout $result.Stdout -Stderr $result.Stderr -WorkDir $work

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
Write-Host ("[dm] 通过 {0} 个，失败 {1} 个" -f $passed, $failed.Count) -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    exit 1
}
