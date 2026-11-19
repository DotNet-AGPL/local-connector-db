#Requires -Version 7.0
<#
.SYNOPSIS
    把 bin/<tool>-<rid>/ 组装成可直接放进 ~/.agents/skills 的发布包。

.DESCRIPTION
    两种粒度，每个包都是完整 skill（同名根目录，可安全叠加解压）：

      platform  单平台：local-skill-tools-v1.0.0-sqlite-win-x64.zip
      all       三平台：local-skill-tools-v1.0.0-sqlite-all.tar.gz

    Windows 单平台出 zip；单平台 unix 与三平台包出 tar.gz（保留执行位）。
    包内只有运行所需文件：SKILL.md、README.md、LICENSE、SOURCE.md、reference/ 与 bin/。

.EXAMPLE
    .\pack.ps1 -Mode platform -Rid win-x64 -Version 1.0.0 -SmokeTest
    .\pack.ps1 -Mode all -Version 1.0.0 -SmokeTest
    .\pack.ps1 -Mode both -Version 1.0.0 -Tools sqlite,mysql
#>
[CmdletBinding()]
param(
    [ValidateSet('platform', 'all', 'both')]
    [string]$Mode = 'platform',

    [ValidateSet('win-x64', 'linux-x64', 'osx-arm64')]
    [string]$Rid,

    [Parameter(Mandatory)]
    [string]$Version,

    # 只打指定工具；省略表示全部
    [string[]]$Tools,

    [string]$OutputDir = (Join-Path $PSScriptRoot 'artifacts'),

    # 从压缩包解出来实跑（只对宿主平台的二进制生效）
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = $PSScriptRoot
$allRids = @('win-x64', 'linux-x64', 'osx-arm64')

$toolTable = [ordered]@{
    sqlite     = 'db-sqlite'
    mysql      = 'db-mysql'
    postgres   = 'db-postgres'
    duckdb     = 'db-duckdb'
    clickhouse = 'db-clickhouse'
    redis      = 'db-redis'
    dm         = 'db-dm'
    mongo      = 'db-mongo'
    sqlserver  = 'db-sqlserver'
    oracle     = 'db-oracle'
    ssh        = 'net-ssh'
    sftp       = 'net-sftp'
    office     = 'file-office'
}

function Resolve-HostRid {
    if ($IsWindows) { return 'win-x64' }

    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()

    if ($IsMacOS) {
        if ($arch -eq 'Arm64') { return 'osx-arm64' }
        throw "Intel Mac（$arch）没有制品：仅支持 osx-arm64"
    }

    if ($arch -eq 'X64') { return 'linux-x64' }
    throw "当前 Linux 架构 $arch 没有制品：仅支持 linux-x64"
}

$hostRid = Resolve-HostRid

if (-not $Rid) { $Rid = $hostRid }

if (-not $Tools) { $Tools = @($toolTable.Keys) }

$unknown = @($Tools | Where-Object { -not $toolTable.Contains($_) })
if ($unknown.Count -gt 0) {
    throw ("未知工具: {0}（可选: {1}）" -f ($unknown -join ', '), ($toolTable.Keys -join ', '))
}

$version = $Version.TrimStart('v')
$tag = "v$version"

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null }

$stagingRoot = Join-Path $OutputDir '.staging'

function Test-ToolTree {
    param([string]$Tool, [string]$TargetRid)

    $exe = $toolTable[$Tool] + $(if ($TargetRid -eq 'win-x64') { '.exe' } else { '' })
    $dir = Join-Path $root ("bin/{0}-{1}" -f $Tool, $TargetRid)

    if (-not (Test-Path (Join-Path $dir $exe))) {
        return "缺少可执行文件: $dir/$exe"
    }

    $nativeChecks = switch ("$Tool-$TargetRid") {
        'sqlite-win-x64'    { @('e_sqlite3.dll') }
        'duckdb-win-x64'    { @('duckdb.dll') }
        'duckdb-linux-x64'  { @('libduckdb.so') }
        'duckdb-osx-arm64'  { @('libduckdb.dylib') }
        'sqlserver-win-x64' { @('Microsoft.Data.SqlClient.SNI.dll') }
        default             { @() }
    }

    foreach ($native in $nativeChecks) {
        if (-not (Test-Path (Join-Path $dir $native))) {
            return "缺少原生依赖: $dir/$native"
        }
    }

    if ("$Tool-$TargetRid" -eq 'sqlserver-linux-x64' -and
        -not (Get-ChildItem $dir -Filter '*icu*' -ErrorAction SilentlyContinue)) {
        return "缺少 app-local ICU: $dir"
    }

    return $null
}

<#
    包内的可执行位不能依赖构建机残留：Actions artifact 会丢 mode，
    所以统一在打包前显式设置（可执行 755，其余 644，目录 755）。
#>
function Set-PackageModes {
    param([string]$PackageRoot)

    if ($IsWindows) { return }

    & chmod -R u+rwX,go+rX $PackageRoot

    foreach ($dir in Get-ChildItem (Join-Path $PackageRoot 'bin') -Directory) {
        foreach ($file in Get-ChildItem $dir.FullName -File) {
            if ($file.Name -match '^(db-|net-|file-)') {
                & chmod 755 $file.FullName
            }
            else {
                & chmod 644 $file.FullName
            }
        }
    }
}

function New-Package {
    param(
        [string]$Tool,
        [string[]]$TargetRids,
        [string]$Suffix
    )

    $pkgRoot = Join-Path $stagingRoot 'local-skill-tools'
    Remove-Item $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $pkgRoot 'bin') | Out-Null

    Copy-Item (Join-Path $root 'SKILL.md') $pkgRoot
    Copy-Item (Join-Path $root 'README.md') $pkgRoot
    Copy-Item (Join-Path $root 'LICENSE') $pkgRoot
    Copy-Item (Join-Path $root 'reference') (Join-Path $pkgRoot 'reference') -Recurse

    foreach ($targetRid in $TargetRids) {
        Copy-Item (Join-Path $root ("bin/{0}-{1}" -f $Tool, $targetRid)) (Join-Path $pkgRoot 'bin') -Recurse

        $toolDir = Join-Path (Join-Path $pkgRoot 'bin') ("{0}-{1}" -f $Tool, $targetRid)

        # 调试产物不随包分发：pdb 与 macOS 的 dSYM（原生构建会自动生成，体积可达二进制两倍）
        Get-ChildItem $toolDir -Filter '*.pdb' -File -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force
        Get-ChildItem $toolDir -Directory -Filter '*.dSYM' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    }

    $sourceNotes = @"
# 源码获取（AGPL-3.0-or-later）

本目录是 **local-skill-tools $tag** 的二进制分发包，不含源码；包含的工具见 bin/ 下所列目录。

对应源码（同一版本）：

- 仓库：https://github.com/DotNet-AGPL/local-skill-tools
- 标签：https://github.com/DotNet-AGPL/local-skill-tools/tree/$tag
- 归档：https://github.com/DotNet-AGPL/local-skill-tools/archive/refs/tags/$tag.tar.gz

本项目以 GNU Affero General Public License v3.0 or later 发布，全文见 LICENSE。
修改后分发（含打包成容器或制品）或以网络服务形式提供时，需同样以 AGPL 提供对应源码。

包内第三方组件（MySqlConnector、Npgsql、Microsoft.Data.Sqlite、DuckDB.NET、
MongoDB.Driver、StackExchange.Redis、Oracle.ManagedDataAccess.Core、Microsoft.Data.SqlClient、
DM.DmProvider、ClickHouse.Driver、SSH.NET、Wisdom.Office（MIT）等）各自保留原有许可证，不受本项目授权影响。

构建信息（SDK 版本、构建时间、各文件 SHA256）见 bin/<tool>-<rid>/BUILD-INFO.txt。
"@

    Set-Content -LiteralPath (Join-Path $pkgRoot 'SOURCE.md') -Value $sourceNotes -Encoding UTF8

    Set-PackageModes -PackageRoot $pkgRoot

    $useZip = ($TargetRids.Count -eq 1 -and $TargetRids[0] -eq 'win-x64')
    $extension = if ($useZip) { '.zip' } else { '.tar.gz' }
    $name = "local-skill-tools-$tag-$Tool-$Suffix$extension"
    $archivePath = Join-Path $OutputDir $name

    if (Test-Path $archivePath) { Remove-Item $archivePath -Force }

    if ($useZip) {
        Compress-Archive -Path $pkgRoot -DestinationPath $archivePath -CompressionLevel Optimal
    }
    else {
        & tar -czf $archivePath -C $stagingRoot 'local-skill-tools'
        if ($LASTEXITCODE -ne 0) { throw "tar 打包失败: $name" }
    }

    $hash = (Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath "$archivePath.sha256" -Value ("{0}  {1}" -f $hash, $name) -Encoding UTF8

    $sizeMb = (Get-Item $archivePath).Length / 1MB
    Write-Host ("    {0,-52} {1,7:N1} MB" -f $name, $sizeMb) -ForegroundColor Green

    return $archivePath
}

<#
    只解当前宿主平台那一份来跑，避免在 Linux 上尝试执行 exe。
#>
function Invoke-SmokeTest {
    param([string]$ArchivePath, [string[]]$TargetRids, [string]$Tool)

    if ($hostRid -notin $TargetRids) { return }

    $probe = Join-Path ([IO.Path]::GetTempPath()) ('lcdb-pack-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $probe | Out-Null

    try {
        if ($ArchivePath.EndsWith('.zip')) {
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $probe
        }
        else {
            & tar -xzf $ArchivePath -C $probe
            if ($LASTEXITCODE -ne 0) { throw "解包失败: $ArchivePath" }
        }

        $pkgRoot = Join-Path $probe 'local-skill-tools'
        $exeSuffix = if ($hostRid -eq 'win-x64') { '.exe' } else { '' }
        $outFile = Join-Path $probe 'out.json'
        $errFile = Join-Path $probe 'err.txt'

        # Start-Process 走真实的 OS 重定向，比 & 的文件重定向在各平台上更稳定。
        # 刚解压出来的 exe 会被安全软件短暂持有句柄，所以带重试。
        function Invoke-Packaged {
            param([string]$FilePath, [string[]]$Arguments)

            for ($attempt = 1; $attempt -le 6; $attempt++) {
                try {
                    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru `
                        -RedirectStandardOutput $outFile -RedirectStandardError $errFile

                    return $process.ExitCode
                }
                catch {
                    if ($attempt -eq 6) { throw }
                    Start-Sleep -Milliseconds 800
                }
            }
        }

        if ($Tool -eq 'duckdb') {
            $exe = Join-Path $pkgRoot ("bin/duckdb-{0}/db-duckdb{1}" -f $hostRid, $exeSuffix)
            $code = Invoke-Packaged -FilePath $exe -Arguments @('query', ':memory:', '-q', '"SELECT 42 AS answer"')
            if ($code -ne 0) { throw ("duckdb 冒烟失败: " + (Get-Content $errFile -Raw)) }
            if (((Get-Content $outFile -Raw | ConvertFrom-Json)[0].answer) -ne 42) { throw 'duckdb 返回值异常' }
        }
        elseif ($Tool -eq 'sqlite') {
            $exe = Join-Path $pkgRoot ("bin/sqlite-{0}/db-sqlite{1}" -f $hostRid, $exeSuffix)
            $db = Join-Path $probe 'smoke.db'
            Invoke-Packaged -FilePath $exe -Arguments @('connect', $db) | Out-Null
            $code = Invoke-Packaged -FilePath $exe -Arguments @('query', $db, '-q', '"SELECT 1 AS ok"')
            if ($code -ne 0) { throw ("sqlite 冒烟失败: " + (Get-Content $errFile -Raw)) }
            if (((Get-Content $outFile -Raw | ConvertFrom-Json)[0].ok) -ne 1) { throw 'sqlite 返回值异常' }
        }
        else {
            # 其它工具只验证二进制能加载：无参数时应打印用法（stdout 或 stderr）并以 1 退出
            $exeName = $toolTable[$Tool] + $exeSuffix
            $exe = Get-ChildItem (Join-Path $pkgRoot 'bin') -Recurse -File -Filter $exeName | Select-Object -First 1 -ExpandProperty FullName
            $code = Invoke-Packaged -FilePath $exe -Arguments @()

            $stdout = ''
            $stderr = ''
            if (Test-Path $outFile) { $raw = Get-Content -LiteralPath $outFile -Raw; if ($null -ne $raw) { $stdout = $raw } }
            if (Test-Path $errFile) { $raw = Get-Content -LiteralPath $errFile -Raw; if ($null -ne $raw) { $stderr = $raw } }

            if ($code -ne 1 -or ($stdout + $stderr).Trim().Length -eq 0) {
                throw ("{0} 冒烟失败: 退出码 {1}" -f $Tool, $code)
            }
        }

        Write-Host ("    [smoke] {0} OK" -f $Tool) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- 目标组合 ----
$jobs = @()

if ($Mode -in 'platform', 'both') {
    $jobs += @{ Rids = @($Rid); Suffix = $Rid }
}

if ($Mode -in 'all', 'both') {
    $jobs += @{ Rids = $allRids; Suffix = 'all' }
}

Write-Host ("==> 打包 {0}（{1}）" -f $tag, (($jobs | ForEach-Object { $_.Suffix }) -join ', ')) -ForegroundColor Cyan

# ---- 先校验，避免打一半才发现缺文件 ----
$problems = @()

foreach ($job in $jobs) {
    foreach ($tool in $Tools) {
        foreach ($targetRid in $job.Rids) {
            $problem = Test-ToolTree -Tool $tool -TargetRid $targetRid
            if ($problem) { $problems += $problem }
        }
    }
}

if ($problems.Count -gt 0) {
    $problems | Select-Object -Unique | ForEach-Object { Write-Host "  [MISS] $_" -ForegroundColor Red }
    throw ("制品不完整，先运行: bash rebuild.sh {0}" -f (($jobs | ForEach-Object { $_.Rids }) | Select-Object -Unique -join ' '))
}

if ($IsWindows -and ($jobs | Where-Object { $_.Rids | Where-Object { $_ -ne 'win-x64' } })) {
    Write-Warning '在 Windows 上为 unix 打包会丢失可执行位；正式发布请走 .github/workflows/release.yml'
}

# ---- 打包 ----
$built = @()

foreach ($tool in $Tools) {
    foreach ($job in $jobs) {
        $archive = New-Package -Tool $tool -TargetRids $job.Rids -Suffix $job.Suffix
        $built += $archive

        if ($SmokeTest) {
            Invoke-SmokeTest -ArchivePath $archive -TargetRids $job.Rids -Tool $tool
        }
    }
}

Remove-Item $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue

$totalMb = ($built | ForEach-Object { (Get-Item $_).Length } | Measure-Object -Sum).Sum / 1MB
Write-Host ''
Write-Host ("[OK] {0} 个包，合计 {1:N1} MB -> {2}" -f $built.Count, $totalMb, $OutputDir) -ForegroundColor Cyan
