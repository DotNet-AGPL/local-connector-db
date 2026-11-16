#Requires -Version 7.0
<#
.SYNOPSIS
    MongoDB 黄金文件测试。

.DESCRIPTION
    为什么不做 Node 对拍：现有 scripts-mongodb/query.js 用 eval() 执行用户输入，
    find 返回的是游标对象（需要 .toArray() 才有数据），输出本身不可信；且 eval 是安全问题。

    测试用本地容器（tests/containers/mongo.ps1），库 lcdb_test，集合 lcdb_*，
    每个用例前 drop 数据库，跑完再 drop，确保无残留。

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
$ExePath = Join-Path $SkillRoot 'bin/mongo-win-x64/db-mongo.exe'
$ContainerScript = Join-Path $SkillRoot 'tests/containers/mongo.ps1'

if (-not (Test-Path $ExePath)) {
    throw ("未找到 {0}，请先运行: .\build.ps1 -Only mongo" -f $ExePath)
}

$MongoPort = 27018
$MongoUser = 'lcdb'
$MongoPassword = 'lcdb_pw'
$MongoDatabase = 'lcdb_test'

New-Item -ItemType Directory -Force -Path $ExpectedDir | Out-Null

function Resolve-MongoHost {
    $address = (& wsl -d debian-nerdctl -- hostname -I 2>$null | Out-String).Trim().Split(' ')[0]

    if (-not $address) {
        return '127.0.0.1'
    }

    return $address
}

function New-MongoArgs {
    param([string[]]$Tail = @())

    return @('{host}', $MongoDatabase, '-p', "$MongoPort", '-u', $MongoUser, '--password', $MongoPassword) + $Tail
}

function Clear-Database {
    $hostAddress = Resolve-MongoHost
    & $ExePath query @($hostAddress, $MongoDatabase, '-p', "$MongoPort", '-u', $MongoUser, '--password', $MongoPassword, '-c', 'db.dropDatabase()') *> $null
}

function Invoke-Seed {
    $hostAddress = Resolve-MongoHost
    $insert = 'lcdb_users.insertMany([{"id": 1, "name": "甲", "amt": 1.5}, {"id": 2, "name": "乙"}, {"id": 3, "name": "gamma", "amt": 2.25}])'
    & $ExePath query @($hostAddress, $MongoDatabase, '-p', "$MongoPort", '-u', $MongoUser, '--password', $MongoPassword, '-c', $insert) *> $null
}

$Cases = @(
    @{ Name = 'connect';            Verb = 'connect'; Mode = 'exit'; Args = (New-MongoArgs) }
    @{ Name = 'ping';               Verb = 'query'; Mode = 'full'; Args = (New-MongoArgs @('-c', 'db.runCommand({"ping": 1})')) }
    @{ Name = 'collection-names';   Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'db.getCollectionNames()')) }

    @{ Name = 'insert-one';         Verb = 'query'; Mode = 'full'; Args = (New-MongoArgs @('-c', 'lcdb_users.insertOne({"id": 1, "name": "甲"})')) }
    @{ Name = 'insert-many';        Verb = 'query'; Mode = 'full'; Args = (New-MongoArgs @('-c', 'lcdb_users.insertMany([{"id": 1}, {"id": 2}])')) }
    @{ Name = 'find-all';           Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.find({})')) }
    @{ Name = 'find-filter';        Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.find({"id": {"$gte": 2}})')) }
    @{ Name = 'find-one';           Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.findOne({"id": 1})')) }
    @{ Name = 'count';              Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.countDocuments({})')) }
    @{ Name = 'distinct';           Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.distinct("name")')) }
    @{ Name = 'aggregate';          Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.aggregate([{"$group": {"_id": null, "total": {"$sum": "$id"}, "n": {"$sum": 1}}}])')) }
    @{ Name = 'update-many';        Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.updateMany({"id": {"$gte": 2}}, {"$set": {"flag": true}})')) }
    @{ Name = 'delete-many';        Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.deleteMany({"id": {"$gte": 2}})')) }
    @{ Name = 'table';              Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.find({})', '-o', 'table')) }
    @{ Name = 'drop-collection';    Verb = 'query'; Mode = 'full'; Setup = $true; Args = (New-MongoArgs @('-c', 'lcdb_users.drop()')) }

    @{ Name = 'error-command';      Verb = 'query'; Mode = 'full'; Args = (New-MongoArgs @('-c', 'db.runCommand({"noSuchCommand": 1})')) }
    @{ Name = 'error-method';       Verb = 'query'; Mode = 'full'; Args = (New-MongoArgs @('-c', 'lcdb_users.noSuchMethod({})')) }
    @{ Name = 'error-format';       Verb = 'query'; Mode = 'full'; Args = (New-MongoArgs @('-c', 'db.runCommand({"ping": 1})', '-o', 'csv')) }
    @{ Name = 'error-no-command';   Verb = 'query'; Mode = 'full'; Args = (New-MongoArgs) }
)

& $ContainerScript -Action up | Out-Null

$passed = 0
$failed = @()

Clear-Database

foreach ($case in $Cases) {
    if ($Filter -and -not $case.Name.Contains($Filter)) {
        continue
    }

    Clear-Database

    if ($case.ContainsKey('Setup') -and $case.Setup) {
        Invoke-Seed
    }

    $hostAddress = Resolve-MongoHost
    $arguments = foreach ($item in $case.Args) {
        if ($item -eq '{host}') { $hostAddress } else { $item }
    }

    $work = New-CaseWorkspace -CaseName $case.Name
    $result = Invoke-Native -FilePath $ExePath -ArgumentList (@($case.Verb) + @($arguments)) -WorkDir $work

    $actual = Normalize-Output -Code $result.Code -Stdout $result.Stdout -Stderr $result.Stderr -WorkDir $work
    $actual = $actual -replace 'MongoDB 版本: .*', 'MongoDB 版本: <ver>'
    $actual = $actual -replace '\b[0-9a-f]{24}\b', '<oid>'

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

Clear-Database

Write-Host ''
Write-Host ("[mongo] 通过 {0} 个，失败 {1} 个" -f $passed, $failed.Count) -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    exit 1
}
