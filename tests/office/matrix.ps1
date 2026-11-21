#Requires -Version 7.0
<#
.SYNOPSIS
    file-office 转换矩阵测试：5 种输入 × 受支持的输出，逐条实跑。

.DESCRIPTION
    夹具全部由工具自己生成（md → docx → pdf / pptx），xlsx 用 fixtures/template.xlsx。
    每条断言：退出码 0、输出存在且非空、能回读出文本。
    结果即 reference/office.md 里矩阵的唯一依据。

.EXAMPLE
    .\tests\office\matrix.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$rid = if ($IsWindows) { 'win-x64' } elseif ($IsMacOS) { 'osx-arm64' } else { 'linux-x64' }
$exe = Join-Path $root "bin/office-$rid/file-office$(if ($IsWindows) { '.exe' } else { '' })"

if (-not (Test-Path $exe)) {
    throw "未找到 $exe，先运行: .\build.ps1 -Only office"
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('lcdb-matrix-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

$script:passed = 0
$script:failed = @()

function Invoke-Office {
    param([string[]]$Arguments)
    $out = & $exe @Arguments 2>$null
    return @{ Code = $LASTEXITCODE; Text = ($out -join "`n") }
}

function Get-Text([string]$path) {
    $r = Invoke-Office @('text', $path)
    if ($r.Code -ne 0) { return '' }
    return $r.Text
}

function Test-Conversion {
    param(
        [string]$Source,
        [string]$Output,
        [string]$Name,
        [string]$Expect = ''
    )

    if (Test-Path $Output) { Remove-Item $Output -Force }

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-Office @('convert', $Source, $Output)
    $watch.Stop()

    if ($r.Code -ne 0 -or -not (Test-Path $Output)) {
        Write-Host ("[ FAIL ] {0}  (exit {1})" -f $Name, $r.Code) -ForegroundColor Red
        $script:failed += $Name
        return
    }

    $size = (Get-Item $Output).Length
    if ($size -le 0) {
        Write-Host ("[ FAIL ] {0}  (输出为空)" -f $Name) -ForegroundColor Red
        $script:failed += $Name
        return
    }

    $text = if ($Output.EndsWith('.md')) { Get-Content -LiteralPath $Output -Raw } else { Get-Text $Output }

    if ($null -eq $text -or $text.Trim().Length -eq 0) {
        Write-Host ("[ FAIL ] {0}  (回读不到文本)" -f $Name) -ForegroundColor Red
        $script:failed += $Name
        return
    }

    if ($Expect -and -not $text.Contains($Expect)) {
        Write-Host ("[ FAIL ] {0}  (缺少哨兵 '{1}')" -f $Name, $Expect) -ForegroundColor Red
        $script:failed += $Name
        return
    }

    Write-Host ("[ OK   ] {0,-22} {1,6} KB {2,7:N0} ms" -f $Name, [math]::Round($size / 1KB, 1), $watch.ElapsedMilliseconds) -ForegroundColor Green
    $script:passed++
}

try {
    $sentinel = 'MATRIX-SENTINEL'

    # ---- 夹具 ----
    $md = Join-Path $work 'seed.md'
    @(
        "# $sentinel"
        ''
        '正文用于矩阵测试。'
        ''
        '| 名称 | 数量 |'
        '|---|---|'
        '| A | 1 |'
    ) | Set-Content -LiteralPath $md -Encoding utf8

    $docx = Join-Path $work 'seed.docx'
    Test-Conversion -Source $md -Output $docx -Name '夹具 md→docx' -Expect $sentinel

    $pdf = Join-Path $work 'seed.pdf'
    Test-Conversion -Source $docx -Output $pdf -Name '夹具 docx→pdf' -Expect $sentinel

    $pptx = Join-Path $work 'seed.pptx'
    Test-Conversion -Source $docx -Output $pptx -Name '夹具 docx→pptx' -Expect $sentinel

    $xlsx = Join-Path $PSScriptRoot 'fixtures/template.xlsx'

    # ---- 矩阵：每行 5 个输入 × 受支持输出 ----
    $row = @(
        @{ Name = 'docx'; Path = $docx; Sentinel = $sentinel }
        @{ Name = 'xlsx'; Path = $xlsx; Sentinel = '' }
        @{ Name = 'pptx'; Path = $pptx; Sentinel = '' }   # 转回 docx 会退化，只要求有文本
        @{ Name = 'pdf';  Path = $pdf;  Sentinel = '' }
        @{ Name = 'md';   Path = $md;   Sentinel = $sentinel }
    )

    $targets = @('.docx', '.pptx', '.pdf', '.md')

    foreach ($source in $row) {
        foreach ($extension in $targets) {
            $output = Join-Path $work ("{0}-to-{1}{2}" -f $source.Name, $extension.TrimStart('.'), $extension)
            Test-Conversion -Source $source.Path -Output $output -Name ("{0} → {1}" -f $source.Name, $extension.TrimStart('.')) -Expect $source.Sentinel
        }
    }

    # xlsx 只能作为输出，当且仅当输入是电子表格
    Test-Conversion -Source $xlsx -Output (Join-Path $work 'xlsx-to-xlsx.xlsx') -Name 'xlsx → xlsx'
}
finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("[matrix] 通过 {0} 个，失败 {1} 个" -f $script:passed, $script:failed.Count) -ForegroundColor Cyan

if ($script:failed.Count -gt 0) {
    $script:failed | ForEach-Object { Write-Host ("  ✗ {0}" -f $_) -ForegroundColor Red }
    exit 1
}
