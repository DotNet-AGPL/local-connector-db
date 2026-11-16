#Requires -Version 7.0
<#
.SYNOPSIS
    Oracle 黄金文件测试（本地 nerdctl 容器 gvenzl/oracle-free）。

.DESCRIPTION
    测试连 127.0.0.1:1521/FREEPDB1（system/Lcdb_Test123）。
    写操作只碰 LCDB_* 表，用例前后 DROP ... PURGE，跑完确认 USER_TABLES 无残留。
    不做 Node 对拍：旧 scripts-oracle 需要 oracledb 包且未安装，输出形态与本工具差异大。

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
$ExePath = Join-Path $SkillRoot 'bin/oracle-win-x64/db-oracle.exe'
$ContainerScript = Join-Path $SkillRoot 'tests/containers/oracle.ps1'

if (-not (Test-Path $ExePath)) {
    throw ("未找到 {0}，请先运行: .\build.ps1 -Only oracle" -f $ExePath)
}

$OraPort = 1521
$OraUser = 'system'
$OraPassword = 'Lcdb_Test123'
$OraService = 'FREEPDB1'

New-Item -ItemType Directory -Force -Path $ExpectedDir | Out-Null

function Resolve-OraHost {
    $address = (& wsl -d debian-nerdctl -- hostname -I 2>$null | Out-String).Trim().Split(' ')[0]

    if (-not $address) {
        return '127.0.0.1'
    }

    return $address
}

function New-OraArgs {
    param([string[]]$Tail = @())

    return @('{host}', $OraUser, $OraPassword, $OraService, '-p', "$OraPort") + $Tail
}

function Clear-TestTables {
    $hostAddress = Resolve-OraHost
    foreach ($table in @('LCDB_T', 'LCDB_T2')) {
        & $ExePath query @($hostAddress, $OraUser, $OraPassword, $OraService, '-p', "$OraPort", '-q', "DROP TABLE $table PURGE") *> $null
    }
}

function Invoke-TableSetup {
    $hostAddress = Resolve-OraHost
    $base = @($hostAddress, $OraUser, $OraPassword, $OraService, '-p', "$OraPort", '-q')

    & $ExePath query @($base + 'CREATE TABLE LCDB_T (ID NUMBER(10), NAME VARCHAR2(32), AMT NUMBER(10,2), D DATE, TS TIMESTAMP, TXT CLOB, BIN BLOB)') *> $null
    & $ExePath query @($base + "INSERT INTO LCDB_T VALUES (1, '甲', 1.50, DATE '2026-11-13', TIMESTAMP '2026-11-13 10:00:00', 'clob text', HEXTORAW('0102030405'))") *> $null
    & $ExePath query @($base + "INSERT INTO LCDB_T VALUES (2, '乙', NULL, NULL, NULL, NULL, NULL)") *> $null
    & $ExePath query @($base + 'COMMIT') *> $null
}

$Cases = @(
    @{ Name = 'connect';        Verb = 'connect'; Mode = 'exit'; Args = (New-OraArgs) }

    @{ Name = 'select-scalars'; Verb = 'query'; Mode = 'full'; Args = (New-OraArgs @('-q', "SELECT 42 AS I, 'hello' AS S, '张三' AS CN FROM DUAL")) }
    @{ Name = 'select-csv';     Verb = 'query'; Mode = 'full'; Args = (New-OraArgs @('-q', "SELECT 42 AS I, 'hello' AS S, '张三' AS CN FROM DUAL", '-o', 'csv')) }
    @{ Name = 'select-table';   Verb = 'query'; Mode = 'full'; Args = (New-OraArgs @('-q', "SELECT 42 AS I, 'hello' AS S, '张三' AS CN FROM DUAL", '-o', 'table')) }
    @{ Name = 'select-empty';   Verb = 'query'; Mode = 'full'; Args = (New-OraArgs @('-q', 'SELECT 1 AS ONE FROM DUAL WHERE 1 = 0')) }
    @{ Name = 'select-types';   Verb = 'query'; Mode = 'full'; Args = (New-OraArgs @('-q', "SELECT 1234.500 AS N, DATE '2026-11-13' AS D, TIMESTAMP '2026-11-13 10:00:00' AS TS FROM DUAL")) }

    @{ Name = 'table-select';   Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-OraArgs @('-q', 'SELECT ID, NAME, AMT, D, TS, TXT, BIN FROM LCDB_T ORDER BY ID')) }
    @{ Name = 'table-insert';   Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-OraArgs @('-q', "INSERT INTO LCDB_T (ID, NAME) VALUES (3, '丙')")) }
    @{ Name = 'ddl-create';     Verb = 'query'; Mode = 'full'; Args = (New-OraArgs @('-q', 'CREATE TABLE LCDB_T2 (ID NUMBER(10))')) }

    @{ Name = 'error-syntax';   Verb = 'query'; Mode = 'full'; Args = (New-OraArgs @('-q', 'SELEC 1 FROM DUAL')) }
    @{ Name = 'error-format';   Verb = 'query'; Mode = 'full'; Args = (New-OraArgs @('-q', 'SELECT 1 AS ONE FROM DUAL', '-o', 'xml')) }
    @{ Name = 'error-no-sql';   Verb = 'query'; Mode = 'full'; Args = (New-OraArgs) }
)

& $ContainerScript -Action up | Out-Null

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

    $hostAddress = Resolve-OraHost
    $arguments = foreach ($item in $case.Args) {
        if ($item -eq '{host}') { $hostAddress } else { $item }
    }

    $work = New-CaseWorkspace -CaseName $case.Name
    $result = Invoke-Native -FilePath $ExePath -ArgumentList (@($case.Verb) + @($arguments)) -WorkDir $work

    $actual = Normalize-Output -Code $result.Code -Stdout $result.Stdout -Stderr $result.Stderr -WorkDir $work
    $actual = $actual -replace '服务端版本: .*', '服务端版本: <ver>'
    # ODP.NET 的客户端错误消息跟随系统语言（zh 环境是中文），只比较错误码
    $actual = $actual -replace '(ORA-\d{5}):[^\r\n]*', '$1: <msg>'

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
Write-Host ("[oracle] 通过 {0} 个，失败 {1} 个" -f $passed, $failed.Count) -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    exit 1
}
