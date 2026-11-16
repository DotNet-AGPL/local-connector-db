#Requires -Version 7.0
<#
.SYNOPSIS
    用 Node 版脚本生成对拍基线（expected/<db>/*.txt）。每个库只在迁移前跑一次。

.DESCRIPTION
    基线一旦固化，回归测试就不再需要 Node。

.EXAMPLE
    .\gen-baseline.ps1
    .\gen-baseline.ps1 -Db mysql -Force
#>
[CmdletBinding()]
param(
    [ValidateSet('sqlite', 'mysql', 'postgres', 'clickhouse', 'redis', 'dm')]
    [string]$Provider = 'sqlite',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot ("cases-$Provider.ps1"))

if (-not (Test-Path $NodeScriptDir)) {
    Write-Host ("Node 版 {0} 脚本已移除（迁移完成），基线不再需要重新生成。" -f $Provider) -ForegroundColor Yellow
    Write-Host ("现有基线: {0}" -f (Join-Path $ExpectedDir $Provider)) -ForegroundColor Yellow
    Write-Host '如需按新语义调整期望值，请直接编辑 expected/*.txt 再运行 run.ps1 复核。' -ForegroundColor Yellow
    exit 1
}

$target = Join-Path $ExpectedDir $Provider
New-Item -ItemType Directory -Force -Path $target | Out-Null

Initialize-TestData
Initialize-WslKeepAlive | Out-Null

$generated = 0

foreach ($case in $Script:CaseList) {
    $context = New-CaseContext -Case $case
    $runTarget = Get-RunTarget -Kind 'node' -Case $case -Context $context

    $result = Invoke-Native -FilePath $runTarget.File -ArgumentList $runTarget.Args -WorkDir $context.Work
    $normalized = Normalize-Output -Code $result.Code -Stdout $result.Stdout -Stderr $result.Stderr -WorkDir $context.Work

    Set-Content -LiteralPath (Join-Path $target ($case.Name + '.txt')) -Value $normalized -Encoding utf8 -NoNewline

    Remove-Item $context.Work -Recurse -Force -ErrorAction SilentlyContinue
    $generated++
}

Write-Host ("[{0}] 基线已生成: {1} 个用例 -> {2}" -f $Provider, $generated, $target) -ForegroundColor Green
