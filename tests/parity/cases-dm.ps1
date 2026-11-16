<#
    达梦（DM）用例。Node 版（dmdb）的基线生成时脚本本身是坏的，全部写成了
    `dm.connect is not a function`，因此 2026-11-13 按 exe 的实际输出重新固化，
    性质等同黄金文件测试（同 duckdb/mongo/oracle/sqlserver）。Node 脚本已移除，
    gen-baseline.ps1 对 dm 会直接退出，如需调整期望值请直接编辑 expected/dm/*.txt。

    测试只碰 LCDB_* 表，用例前后 DROP；SYSDBA 模式下的其它对象不动。
    凭据从环境变量读，不写进 expected 文件。
#>

$DbName = 'dm'
$SkillRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ExpectedDir = Join-Path $PSScriptRoot 'expected'
$ExePath = Join-Path $SkillRoot "bin/$DbName-win-x64/db-$DbName.exe"
$NodeScriptDir = Join-Path $SkillRoot "scripts-$DbName"

$DmHost = '172.16.10.53'
$DmPort = 5236
$DmUser = 'SYSDBA'
$DmSchema = 'SYSDBA'
$DmPassword = if ($env:LCDB_DM_PASSWORD) { $env:LCDB_DM_PASSWORD } else { 'Dameng123' }

function New-DmArgs {
    param([string[]]$Tail = @())

    return @($DmHost, $DmUser, $DmPassword, $DmSchema, '-p', "$DmPort") + $Tail
}

$Script:CaseList = @(
    @{ Name = 'connect-exit';    Verb = 'connect'; Mode = 'exit'; Args = (New-DmArgs) }

    @{ Name = 'select-scalars';  Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', "SELECT 42 AS i, 'hello' AS s, '张三' AS cn FROM DUAL")) }
    @{ Name = 'select-csv';      Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', "SELECT 42 AS i, 'hello' AS s, '张三' AS cn FROM DUAL", '-o', 'csv')) }
    @{ Name = 'select-table';    Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', "SELECT 42 AS i, 'hello' AS s, '张三' AS cn FROM DUAL", '-o', 'table')) }
    @{ Name = 'select-empty';    Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', 'SELECT 1 AS one FROM DUAL WHERE 1 = 0')) }
    @{ Name = 'select-types';    Verb = 'query'; Mode = 'full'; ExpectDiff = $true; Args = (New-DmArgs @('-q', "SELECT 1234.500 AS n, DATE '2026-11-13' AS d, TIMESTAMP '2026-11-13 10:00:00' AS ts FROM DUAL")) }

    @{ Name = 'table-select';    Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-DmArgs @('-q', 'SELECT ID, NAME, AMT FROM LCDB_T ORDER BY ID')) }
    @{ Name = 'table-insert';    Verb = 'query'; Mode = 'full'; Setup = $true; ExpectDiff = $true; Args = (New-DmArgs @('-q', "INSERT INTO LCDB_T VALUES (3, '丙', 3.25)")) }
    @{ Name = 'ddl-create';      Verb = 'query'; Mode = 'full'; ExpectDiff = $true; Args = (New-DmArgs @('-q', 'CREATE TABLE LCDB_T2 (ID INT)')) }

    @{ Name = 'error-syntax';    Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', 'SELEC 1')) }
    @{ Name = 'error-auth';      Verb = 'query'; Mode = 'exit'; Args = @($DmHost, $DmUser, 'wrong_password', $DmSchema, '-p', "$DmPort", '-q', 'SELECT 1 FROM DUAL') }
    @{ Name = 'error-format';    Verb = 'query'; Mode = 'full'; Args = (New-DmArgs @('-q', 'SELECT 1 AS one FROM DUAL', '-o', 'xml')) }
    @{ Name = 'error-no-sql';    Verb = 'query'; Mode = 'full'; Args = (New-DmArgs) }
)

function Clear-TestTables {
    foreach ($table in @('LCDB_T', 'LCDB_T2')) {
        & $ExePath query @(New-DmArgs @('-q', "DROP TABLE $table")) *> $null
    }
}

function Invoke-Setup {
    & $ExePath query @(New-DmArgs @('-q', 'CREATE TABLE LCDB_T (ID INT, NAME VARCHAR(20), AMT DECIMAL(10,2))')) *> $null
    & $ExePath query @(New-DmArgs @('-q', "INSERT INTO LCDB_T VALUES (1, '甲', 1.50)")) *> $null
    & $ExePath query @(New-DmArgs @('-q', "INSERT INTO LCDB_T VALUES (2, '乙', NULL)")) *> $null
}

function Initialize-TestData {
    Clear-TestTables
}

function New-CaseContext {
    param([hashtable]$Case)

    Clear-TestTables

    if ($Case.ContainsKey('Setup') -and $Case.Setup) {
        Invoke-Setup
    }

    $work = New-CaseWorkspace -CaseName $Case.Name

    return @{
        Work = $work
        Args = @($Case.Args)
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
