#Requires -Version 7.0
<#
.SYNOPSIS
    构建 local-connector-db 的 .NET NativeAOT 制品。

.DESCRIPTION
    每个已迁移的数据库一个 exe，产物按 <db>-<rid> 目录封装：
        bin/sqlite-win-x64/   db-sqlite.exe + e_sqlite3.dll + BUILD-INFO.txt
        bin/mysql-win-x64/    db-mysql.exe + BUILD-INFO.txt
        bin/postgres-win-x64/ db-postgres.exe + BUILD-INFO.txt

    -m:1 -nodeReuse:false 是必须的：PublishAotCross 的内联任务在并发/节点复用时
    会撞上 MSB4175（程序集文件被其他进程占用）。

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Only sqlite
    .\build.ps1 -Only sqlite -Rid linux-x64
    .\build.ps1 -Clean
#>
[CmdletBinding()]
param(
    [ValidateSet('sqlite', 'mysql', 'postgres', 'duckdb', 'clickhouse', 'redis', 'dm', 'mongo', 'sqlserver', 'oracle')]
    [string[]]$Only,

    [string]$Rid = 'win-x64',

    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = $PSScriptRoot
$srcRoot = Join-Path $root 'src'

$targets = [ordered]@{
    sqlite   = @{ Project = 'Connector.Sqlite'; Exe = 'db-sqlite' }
    mysql    = @{ Project = 'Connector.MySql'; Exe = 'db-mysql' }
    postgres = @{ Project = 'Connector.PostgreSql'; Exe = 'db-postgres' }
    duckdb   = @{ Project = 'Connector.DuckDb'; Exe = 'db-duckdb' }
    clickhouse = @{ Project = 'Connector.ClickHouse'; Exe = 'db-clickhouse' }
    redis    = @{ Project = 'Connector.Redis'; Exe = 'db-redis' }
    dm       = @{ Project = 'Connector.Dm'; Exe = 'db-dm' }
    mongo    = @{ Project = 'Connector.Mongo'; Exe = 'db-mongo' }
    sqlserver = @{ Project = 'Connector.SqlServer'; Exe = 'db-sqlserver' }
    oracle   = @{ Project = 'Connector.Oracle'; Exe = 'db-oracle' }
}

$names = if ($Only) { $Only } else { @($targets.Keys) }
$names = @($names | Where-Object { Test-Path (Join-Path $srcRoot $targets[$_].Project) })

if ($names.Count -eq 0) {
    throw '没有可构建的项目'
}

$sdk = (& dotnet --version).Trim()
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# 关掉常驻编译服务，避免 VBCSCompiler / MSBuild 节点持有 obj 下的 dll，
# 导致 ILCompiler 报 “file is being used by another process”。
& dotnet build-server shutdown *> $null

foreach ($name in $names) {
    $target = $targets[$name]
    $projectDir = Join-Path $srcRoot $target.Project
    $projectFile = Join-Path $projectDir ($target.Project + '.csproj')
    $outDir = Join-Path $root ("bin/{0}-{1}" -f $name, $Rid)

    if ($Clean) {
        Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $projectDir 'obj') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $projectDir 'bin') -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Write-Host ("==> publish {0} ({1})" -f $name, $Rid) -ForegroundColor Cyan
    $watch = [Diagnostics.Stopwatch]::StartNew()

    & dotnet publish $projectFile -c Release -r $Rid -p:PublishAot=true -o $outDir -m:1 -nodeReuse:false -p:UseSharedCompilation=false
    if ($LASTEXITCODE -ne 0) {
        throw ("publish 失败: {0}" -f $name)
    }

    $watch.Stop()

    Get-ChildItem $outDir -Filter '*.pdb' -File | Remove-Item -Force -ErrorAction SilentlyContinue

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# local-connector-db build info')
    $lines.Add(("library    : {0}" -f $name))
    $lines.Add(("rid        : {0}" -f $Rid))
    $lines.Add(("dotnet sdk : {0}" -f $sdk))
    $lines.Add(("built at   : {0}" -f $stamp))
    $lines.Add(("elapsed    : {0:N1}s" -f $watch.Elapsed.TotalSeconds))
    $lines.Add('')
    $lines.Add(("{0,-46} {1,12}  {2}" -f 'file', 'size(bytes)', 'sha256'))

    foreach ($file in (Get-ChildItem $outDir -File | Where-Object { $_.Name -ne 'BUILD-INFO.txt' } | Sort-Object Name)) {
        # 安全软件会在 exe 落地后短暂持有句柄，重试几次再放弃
        $hash = $null
        for ($attempt = 0; $attempt -lt 10 -and -not $hash; $attempt++) {
            try {
                $hash = (Get-FileHash $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            }
            catch {
                Start-Sleep -Milliseconds 400
            }
        }

        if (-not $hash) {
            $hash = '(locked)'
        }

        $lines.Add(("{0,-46} {1,12}  {2}" -f $file.Name, $file.Length, $hash))
    }

    $lines | Set-Content -LiteralPath (Join-Path $outDir 'BUILD-INFO.txt') -Encoding UTF8

    $total = (Get-ChildItem $outDir -File | Measure-Object -Property Length -Sum).Sum
    Write-Host ("    -> {0}  ({1:N2} MB, {2:N1}s)" -f $outDir, ($total / 1MB), $watch.Elapsed.TotalSeconds) -ForegroundColor Green
}
