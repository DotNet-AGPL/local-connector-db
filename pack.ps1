#Requires -Version 7.0
<#
.SYNOPSIS
    把 bin/<tool>-<rid>/ 组装成可直接放进 ~/.agents/skills 的发布包。

.DESCRIPTION
    产物只包含运行所需的东西：SKILL.md、reference/、LICENSE、SOURCE.md 与当前平台的
    bin/ 目录，不含 src/、tests/、构建脚本。
    Windows 出 zip；Linux / macOS 出 tar.gz（zip 在 Windows 上打包会丢执行位）。

.EXAMPLE
    .\pack.ps1 -Rid win-x64 -Version 1.0.0
    .\pack.ps1 -Rid linux-x64 -Version 1.0.0 -SmokeTest
    .\pack.ps1 -Version 1.0.0 -SmokeTest          # RID 按宿主推断
#>
[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'linux-x64', 'osx-arm64')]
    [string]$Rid,

    [Parameter(Mandatory)]
    [string]$Version,

    [string]$OutputDir = (Join-Path $PSScriptRoot 'artifacts'),

    # 解包到临时目录并实际跑两条查询，确认包里没有缺失文件
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = $PSScriptRoot
$srcRoot = Join-Path $root 'src'

# 工具表：<目录名前缀>:<可执行文件名>，与 build.ps1 / rebuild.sh 保持一致
$tools = [ordered]@{
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

if (-not $Rid) { $Rid = Resolve-HostRid }

$version = $Version.TrimStart('v')
$tag = "v$version"
$pkgName = 'local-skill-tools'
$isWindowsRid = $Rid -eq 'win-x64'
$exeSuffix = if ($isWindowsRid) { '.exe' } else { '' }

$stagingRoot = Join-Path $OutputDir '.staging'
$stage = Join-Path $stagingRoot $pkgName
$archiveName = "$pkgName-$tag-$Rid" + $(if ($isWindowsRid) { '.zip' } else { '.tar.gz' })
$archivePath = Join-Path $OutputDir $archiveName

Write-Host ("==> 打包 {0}（{1}）" -f $tag, $Rid) -ForegroundColor Cyan

# ---- 1. 校验制品 ----
$missing = @()

foreach ($tool in $tools.Keys) {
    $exe = $tools[$tool]
    $dir = Join-Path $root ("bin/{0}-{1}" -f $tool, $Rid)
    $file = Join-Path $dir ($exe + $exeSuffix)

    if (-not (Test-Path $file)) {
        $missing += "缺少可执行文件: $file"
        continue
    }

    $nativeChecks = switch ("$tool-$Rid") {
        'sqlite-win-x64'     { @('e_sqlite3.dll') }
        'duckdb-win-x64'     { @('duckdb.dll') }
        'duckdb-linux-x64'   { @('libduckdb.so') }
        'duckdb-osx-arm64'   { @('libduckdb.dylib') }
        'sqlserver-win-x64'  { @('Microsoft.Data.SqlClient.SNI.dll') }
        default              { @() }
    }

    foreach ($native in $nativeChecks) {
        if (-not (Test-Path (Join-Path $dir $native))) {
            $missing += "缺少原生依赖: $(Join-Path $dir $native)"
        }
    }

    if ("$tool-$Rid" -eq 'sqlserver-linux-x64' -and
        -not (Get-ChildItem $dir -Filter '*icu*' -ErrorAction SilentlyContinue)) {
        $missing += "缺少 app-local ICU: $dir"
    }
}

if ($missing.Count -gt 0) {
    $missing | ForEach-Object { Write-Host "  [MISS] $_" -ForegroundColor Red }
    throw "制品不完整，先运行: bash rebuild.sh $Rid"
}

# ---- 2. 组装 ----
if (Test-Path $stagingRoot) { Remove-Item $stagingRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'bin') | Out-Null

Copy-Item (Join-Path $root 'SKILL.md') $stage
Copy-Item (Join-Path $root 'README.md') $stage
Copy-Item (Join-Path $root 'LICENSE') $stage
Copy-Item (Join-Path $root 'reference') (Join-Path $stage 'reference') -Recurse

foreach ($tool in $tools.Keys) {
    Copy-Item (Join-Path $root ("bin/{0}-{1}" -f $tool, $Rid)) (Join-Path $stage 'bin') -Recurse
    Get-ChildItem (Join-Path $stage 'bin' ("{0}-{1}" -f $tool, $Rid)) -Filter '*.pdb' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force
}

$sourceNotes = @"
# 源码获取（AGPL-3.0-or-later）

本目录是 **$pkgName $tag** 的 $Rid 二进制分发包，不含源码。

对应源码（同一版本）：

- 仓库：https://github.com/DotNet-AGPL/$pkgName
- 标签：https://github.com/DotNet-AGPL/$pkgName/tree/$tag
- 归档：https://github.com/DotNet-AGPL/$pkgName/archive/refs/tags/$tag.tar.gz

本项目以 GNU Affero General Public License v3.0 or later 发布，全文见 [LICENSE](LICENSE)。
修改后分发（含打包成容器或制品）或以网络服务形式提供时，需同样以 AGPL 提供对应源码。

包内第三方组件（MySqlConnector、Npgsql、Microsoft.Data.Sqlite、DuckDB.NET、
MongoDB.Driver、StackExchange.Redis、Oracle.ManagedDataAccess.Core、Microsoft.Data.SqlClient、
DM.DmProvider、ClickHouse.Driver、SSH.NET 等）各自保留原有许可证，不受本项目授权影响。

构建信息（SDK 版本、构建时间、各文件 SHA256）见 bin/<tool>-$Rid/BUILD-INFO.txt。
"@

Set-Content -LiteralPath (Join-Path $stage 'SOURCE.md') -Value $sourceNotes -Encoding UTF8

# ---- 3. 压缩 ----
if (Test-Path $archivePath) { Remove-Item $archivePath -Force }

if ($isWindowsRid) {
    Compress-Archive -Path $stage -DestinationPath $archivePath -CompressionLevel Optimal
}
else {
    # 在 Windows 上打 unix 包时，tar 拿不到可执行位（Windows 文件系统没有该属性）。
    # 正式发布走 CI：Linux / macOS runner 上 publish 出来的文件本身是 755，tar 会原样保留。
    if ($IsWindows) {
        Write-Warning "在 Windows 上为 $Rid 打包会丢失可执行位；请用 .github/workflows/release.yml 或对应平台的机器出包"
    }

    & tar -czf $archivePath -C $stagingRoot $pkgName
    if ($LASTEXITCODE -ne 0) { throw "tar 打包失败" }
}

$sizeMb = (Get-Item $archivePath).Length / 1MB
$hash = (Get-FileHash $archivePath -Algorithm SHA256).Hash
Set-Content -LiteralPath "$archivePath.sha256" -Value ("{0}  {1}" -f $hash.ToLowerInvariant(), $archiveName) -Encoding UTF8

Write-Host ("    -> {0}  ({1:N1} MB)" -f $archivePath, $sizeMb) -ForegroundColor Green
Write-Host ("    sha256: {0}" -f $hash.ToLowerInvariant())

# ---- 4. 冒烟测试：从压缩包解出来跑，确认脱离仓库也能用 ----
if ($SmokeTest) {
    $probe = Join-Path ([IO.Path]::GetTempPath()) ('lcdb-pack-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $probe | Out-Null

    try {
        if ($isWindowsRid) {
            Expand-Archive -LiteralPath $archivePath -DestinationPath $probe
        }
        else {
            & tar -xzf $archivePath -C $probe
            if ($LASTEXITCODE -ne 0) { throw "解包失败" }
        }

        $pkgRoot = Join-Path $probe $pkgName
        $duckdb = Join-Path $pkgRoot ("bin/duckdb-{0}/{1}{2}" -f $Rid, 'db-duckdb', $exeSuffix)
        $sqlite = Join-Path $pkgRoot ("bin/sqlite-{0}/{1}{2}" -f $Rid, 'db-sqlite', $exeSuffix)

        if (-not $isWindowsRid) {
            & chmod +x $duckdb $sqlite
        }

        $outFile = Join-Path $probe 'out.json'
        $errFile = Join-Path $probe 'err.txt'

        & $duckdb query ':memory:' -q 'SELECT 42 AS answer' 1>$outFile 2>$errFile
        if ($LASTEXITCODE -ne 0) { throw ("duckdb 冒烟失败: " + (Get-Content $errFile -Raw)) }

        $answer = (Get-Content $outFile -Raw | ConvertFrom-Json)[0].answer
        if ($answer -ne 42) { throw "duckdb 返回异常: $answer" }

        $db = Join-Path $probe 'smoke.db'
        & $sqlite connect $db *> $null
        & $sqlite query $db -q 'SELECT 1 AS ok' 1>$outFile 2>$errFile
        if ($LASTEXITCODE -ne 0) { throw ("sqlite 冒烟失败: " + (Get-Content $errFile -Raw)) }

        $ok = (Get-Content $outFile -Raw | ConvertFrom-Json)[0].ok
        if ($ok -ne 1) { throw "sqlite 返回异常: $ok" }

        Write-Host "    冒烟测试: duckdb + sqlite 通过（已从压缩包解出运行）" -ForegroundColor Green
    }
    finally {
        Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Remove-Item $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ("[OK] {0}" -f $archiveName) -ForegroundColor Cyan
