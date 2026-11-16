<#
    SQLite 对拍用例。契约：
        $DbName / $ExePath / $NodeScriptDir / $CaseList
        Initialize-TestData      一次性准备（种子库模板）
        New-CaseContext          每个用例的上下文（工作目录 + 展开后的参数）
        Get-RunTarget            拼装 node 版与 exe 版的命令
#>

$DbName = 'sqlite'
$SkillRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$FixtureDir = Join-Path $PSScriptRoot 'fixtures'
$ExpectedDir = Join-Path $PSScriptRoot 'expected'
$CacheDir = Join-Path $PSScriptRoot '.cache'
$ExePath = Join-Path $SkillRoot "bin/$DbName-win-x64/db-$DbName.exe"
$NodeScriptDir = Join-Path $SkillRoot "scripts-$DbName"
$TemplatePath = Join-Path $CacheDir 'template.db'

$Script:CaseList = @(
    @{ Name = 'connect-new';        Verb = 'connect'; Db = 'missing';  Mode = 'full'; ExpectDiff = $false; Args = @('{db}') }
    @{ Name = 'connect-existing';   Verb = 'connect'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}') }

    @{ Name = 'select-json';        Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT id, name, qty, amount FROM t_items ORDER BY id') }
    @{ Name = 'select-csv';         Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT id, name, qty, amount FROM t_items ORDER BY id', '-o', 'csv') }
    @{ Name = 'select-table';       Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT id, name, qty, amount FROM t_items ORDER BY id', '-o', 'table') }
    @{ Name = 'select-empty';       Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT id, name FROM t_items WHERE 1 = 0') }
    @{ Name = 'select-aggregate';   Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT COUNT(*) AS cnt, SUM(qty) AS total FROM t_items') }
    @{ Name = 'select-null';        Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT id, amount FROM t_items WHERE amount IS NULL') }
    @{ Name = 'select-cjk-json';    Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT id, name_cn FROM t_cn ORDER BY id') }

    @{ Name = 'select-table-cjk';   Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $true;  Args = @('{db}', '-q', 'SELECT id, name_cn FROM t_cn ORDER BY id', '-o', 'table') }
    @{ Name = 'select-blob-json';   Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT id, payload FROM t_items WHERE id = 1') }
    @{ Name = 'select-bigint';      Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $true;  Args = @('{db}', '-q', 'SELECT id, big FROM t_big ORDER BY id') }

    @{ Name = 'dml-insert';         Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', "INSERT INTO t_items (name, qty, amount) VALUES ('delta', 7, 1.5)") }
    @{ Name = 'dml-update';         Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'UPDATE t_items SET qty = qty + 1 WHERE id <= 2') }
    @{ Name = 'dml-delete';         Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'DELETE FROM t_items WHERE id = 3') }
    @{ Name = 'script-multi';       Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-f', '{fixture:multi.sql}') }

    @{ Name = 'checkpoint';         Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '--checkpoint') }
    @{ Name = 'readonly-select';    Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT COUNT(*) AS cnt FROM t_items', '--readonly') }

    @{ Name = 'readonly-write';     Verb = 'query'; Db = 'template'; Mode = 'exit'; ExpectDiff = $false; Args = @('{db}', '-q', "INSERT INTO t_items (name) VALUES ('blocked')", '--readonly') }
    @{ Name = 'error-syntax';       Verb = 'query'; Db = 'template'; Mode = 'exit'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELEC 1') }
    @{ Name = 'error-missing-db';   Verb = 'query'; Db = 'missing';  Mode = 'exit'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT 1') }
    @{ Name = 'error-format';       Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}', '-q', 'SELECT 1 AS one', '-o', 'xml') }
    @{ Name = 'error-no-sql';       Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $false; Args = @('{db}') }
    @{ Name = 'error-unknown-opt';  Verb = 'query'; Db = 'template'; Mode = 'full'; ExpectDiff = $true;  Args = @('{db}', '-q', 'SELECT 1 AS one', '--bogus') }
    @{ Name = 'fk-violation';       Verb = 'query'; Db = 'template'; Mode = 'exit'; ExpectDiff = $false; Args = @('{db}', '-q', 'INSERT INTO t_child (parent_id) VALUES (999)') }
)

function Initialize-TestData {

    if (Test-Path $TemplatePath) {
        return
    }

    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

    & $ExePath connect $TemplatePath | Out-Null
    & $ExePath query $TemplatePath -f (Join-Path $FixtureDir 'create.sql') | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw '模板库初始化失败'
    }
}

function New-CaseContext {
    param([hashtable]$Case)

    $work = New-CaseWorkspace -CaseName $Case.Name
    $database = Join-Path $work ($Case.Name + '.db')

    if ($Case.Db -eq 'template') {
        Copy-Item -LiteralPath $TemplatePath -Destination $database -Force
    }

    $expanded = foreach ($item in $Case.Args) {
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
