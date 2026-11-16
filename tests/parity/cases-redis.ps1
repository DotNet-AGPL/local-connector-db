<#
    Redis 对拍用例（Node 版用 ioredis）。

    写入只碰 lcdb_test:* 键，每个用例前后清理；该实例 db0 里还有业务键，绝不触碰。
#>

$DbName = 'redis'
$SkillRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ExpectedDir = Join-Path $PSScriptRoot 'expected'
$ExePath = Join-Path $SkillRoot "bin/$DbName-win-x64/db-$DbName.exe"
$NodeScriptDir = Join-Path $SkillRoot "scripts-$DbName"

$RedisHost = '172.16.10.222'
$RedisPort = 16379

$TestKeys = @(
    'lcdb_test:k', 'lcdb_test:list', 'lcdb_test:hash',
    'lcdb_test:n', 'lcdb_test:s', 'lcdb_test:q'
)

function New-RedisArgs {
    param([string[]]$Tail = @())

    return @($RedisHost, '-p', "$RedisPort") + $Tail
}

$Script:CaseList = @(
    @{ Name = 'connect-exit';   Verb = 'connect'; Mode = 'exit'; Args = (New-RedisArgs) }
    @{ Name = 'ping';           Verb = 'query'; Mode = 'full'; Args = (New-RedisArgs @('-c', 'PING')) }
    @{ Name = 'set-ok';         Verb = 'query'; Mode = 'full'; Args = (New-RedisArgs @('-c', 'SET lcdb_test:k hello EX 60')) }
    @{ Name = 'get-value';      Verb = 'query'; Mode = 'full'; Setup = 'set';  Args = (New-RedisArgs @('-c', 'GET lcdb_test:k')) }
    @{ Name = 'get-missing';    Verb = 'query'; Mode = 'full'; Args = (New-RedisArgs @('-c', 'GET lcdb_test:nope')) }
    @{ Name = 'lrange';         Verb = 'query'; Mode = 'full'; Setup = 'list'; Args = (New-RedisArgs @('-c', 'LRANGE lcdb_test:list 0 -1')) }
    @{ Name = 'hgetall';        Verb = 'query'; Mode = 'full'; Setup = 'hash'; ExpectDiff = $true; Args = (New-RedisArgs @('-c', 'HGETALL lcdb_test:hash')) }
    @{ Name = 'del-count';      Verb = 'query'; Mode = 'full'; Setup = 'set';  Args = (New-RedisArgs @('-c', 'DEL lcdb_test:k')) }
    @{ Name = 'incr';           Verb = 'query'; Mode = 'full'; Setup = 'num';  Args = (New-RedisArgs @('-c', 'INCR lcdb_test:n')) }
    @{ Name = 'dbsize';         Verb = 'query'; Mode = 'full'; Args = (New-RedisArgs @('-c', 'EXISTS lcdb_test:nope')) }
    @{ Name = 'quoted-value';   Verb = 'query'; Mode = 'full'; ExpectDiff = $true; Args = (New-RedisArgs @('-c', 'SET lcdb_test:q "hello world" EX 60')) }

    @{ Name = 'error-type';     Verb = 'query'; Mode = 'exit'; Setup = 'str'; Args = (New-RedisArgs @('-c', 'INCR lcdb_test:s')) }
    @{ Name = 'error-command';  Verb = 'query'; Mode = 'exit'; Args = (New-RedisArgs @('-c', 'NOTACOMMAND')) }
    @{ Name = 'error-no-command'; Verb = 'query'; Mode = 'full'; Args = (New-RedisArgs) }
)

function Clear-TestKeys {
    & $ExePath query @(New-RedisArgs @('-c', "DEL $($TestKeys -join ' ')")) *> $null
}

function Invoke-Setup {
    param([string]$Kind)

    $sql = switch ($Kind) {
        'set'  { 'SET lcdb_test:k hello EX 60' }
        'list' { 'RPUSH lcdb_test:list a b c' }
        'hash' { 'HSET lcdb_test:hash f1 v1 f2 2' }
        'num'  { 'SET lcdb_test:n 1 EX 60' }
        'str'  { 'SET lcdb_test:s abc EX 60' }
        default { $null }
    }

    if ($sql) {
        & $ExePath query @(New-RedisArgs @('-c', $sql)) *> $null
    }
}

function Initialize-TestData {
    Clear-TestKeys
}

function New-CaseContext {
    param([hashtable]$Case)

    Clear-TestKeys

    if ($Case.ContainsKey('Setup')) {
        Invoke-Setup -Kind $Case.Setup
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
