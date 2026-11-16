#Requires -Version 7.0
<#
.SYNOPSIS
    对拍测试：跑 .NET 版 exe，与 expected/<db>/ 下的基线逐字比对。

.DESCRIPTION
    基线由 gen-baseline.ps1 用 Node 版一次性生成，之后回归不依赖 Node。
    预期差异（SKILL.md 记录的行为修正）只报告，不判失败。

.EXAMPLE
    .\run.ps1
    .\run.ps1 -Db mysql
    .\run.ps1 -Db mysql -Filter select
#>
[CmdletBinding()]
param(
    [ValidateSet('sqlite', 'mysql', 'postgres', 'clickhouse', 'redis', 'dm')]
    [string]$Provider = 'sqlite',

    [string]$Filter = '',

    [switch]$ShowDiff
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot ("cases-$Provider.ps1"))

$expectedBase = Join-Path $ExpectedDir $Provider

if (-not (Test-Path $ExePath)) {
    throw ("未找到 {0}，请先运行: .\build.ps1 -Only {1}" -f $ExePath, $Provider)
}

Initialize-TestData
Initialize-WslKeepAlive | Out-Null

$passed = 0
$expectedDiffs = 0
$failed = @()

foreach ($case in $Script:CaseList) {
    if ($Filter -and -not $case.Name.Contains($Filter)) {
        continue
    }

    $expectedFile = Join-Path $expectedBase ($case.Name + '.txt')

    if (-not (Test-Path $expectedFile)) {
        $failed += $case.Name
        Write-Host ("[MISS ] {0}  (缺少基线 {1})" -f $case.Name, $expectedFile) -ForegroundColor Red
        continue
    }

    $expected = (Get-Content -LiteralPath $expectedFile -Raw -Encoding utf8)
    $context = New-CaseContext -Case $case
    $target = Get-RunTarget -Kind 'exe' -Case $case -Context $context

    $result = Invoke-Native -FilePath $target.File -ArgumentList $target.Args -WorkDir $context.Work
    $actual = Normalize-Output -Code $result.Code -Stdout $result.Stdout -Stderr $result.Stderr -WorkDir $context.Work

    if ($case.Mode -eq 'exit') {
        $actual = ($actual -split "`n" | Select-Object -First 1) -join "`n"
        $expected = ($expected -split "`n" | Select-Object -First 1) -join "`n"
    }

    Remove-Item $context.Work -Recurse -Force -ErrorAction SilentlyContinue

    if ($actual -eq $expected) {
        $passed++
        Write-Host ("[ OK   ] {0}" -f $case.Name) -ForegroundColor Green
    }
    elseif ($case.ContainsKey('ExpectDiff') -and $case.ExpectDiff) {
        $expectedDiffs++
        Write-Host ("[ DIFF ] {0}  (预期差异)" -f $case.Name) -ForegroundColor Yellow

        if ($ShowDiff) {
            Show-TextDiff -Expected $expected -Actual $actual
        }
    }
    else {
        $failed += $case.Name
        Write-Host ("[FAIL ] {0}" -f $case.Name) -ForegroundColor Red
        Show-TextDiff -Expected $expected -Actual $actual
    }
}

Write-Host ''
Write-Host ("[{0}] 通过 {1} 个，预期差异 {2} 个，失败 {3} 个" -f $Provider, $passed, $expectedDiffs, $failed.Count) -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    exit 1
}
