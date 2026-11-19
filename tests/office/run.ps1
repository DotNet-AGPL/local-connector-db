#Requires -Version 7.0
<#
.SYNOPSIS
    file-office 功能测试：读、转、模板填充。

.DESCRIPTION
    不依赖基线文件，全部用「生成 → 回读 → 断言」的方式验证，跨平台可跑。

.EXAMPLE
    .\tests\office\run.ps1
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

$work = Join-Path ([IO.Path]::GetTempPath()) ('lcdb-office-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

$script:passed = 0
$script:failed = 0

function Invoke-Office {
    param([string[]]$Arguments)

    $out = & $exe @Arguments 2>$null
    return @{ Code = $LASTEXITCODE; Text = ($out -join "`n") }
}

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Name)

    if ($Text -like "*$Needle*") {
        Write-Host ("[ OK   ] {0}" -f $Name) -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host ("[ FAIL ] {0}：未找到 '{1}'" -f $Name, $Needle) -ForegroundColor Red
        Write-Host ("       实际: {0}" -f $Text.Replace("`n", '|'))
        $script:failed++
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Name)

    if ($Condition) {
        Write-Host ("[ OK   ] {0}" -f $Name) -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host ("[ FAIL ] {0}" -f $Name) -ForegroundColor Red
        $script:failed++
    }
}

try {
    $sampleMd = Join-Path $work 'sample.md'
    @(
        '# 测试标题'
        ''
        '正文 **加粗**'
        ''
        '| 名称 | 数量 |'
        '|---|---|'
        '| A | 1 |'
    ) | Set-Content -LiteralPath $sampleMd -Encoding utf8

    # md -> docx
    $docx = Join-Path $work 'sample.docx'
    $r = Invoke-Office @('convert', $sampleMd, $docx)
    Assert-True (($r.Code -eq 0) -and (Test-Path $docx)) 'md → docx'

    # docx -> text
    $r = Invoke-Office @('text', $docx)
    Assert-Contains $r.Text '测试标题' 'docx 文本'
    Assert-Contains $r.Text '正文 加粗' 'docx 粗体文本'

    # docx -> md
    $r = Invoke-Office @('md', $docx)
    Assert-Contains $r.Text '# 测试标题' 'docx → md'

    # info
    $r = Invoke-Office @('info', $docx)
    Assert-Contains $r.Text '"format": "Docx"' 'info 格式识别'

    # docx -> pdf
    $pdf = Join-Path $work 'sample.pdf'
    $r = Invoke-Office @('convert', $docx, $pdf)
    Assert-True (($r.Code -eq 0) -and (Test-Path $pdf)) 'docx → pdf'

    $r = Invoke-Office @('info', $pdf)
    Assert-Contains $r.Text '"format": "Pdf"' 'pdf 识别'
    Assert-Contains $r.Text '"pages"' 'pdf 页数'

    # pdf -> text
    $r = Invoke-Office @('text', $pdf)
    Assert-Contains $r.Text '测试标题' 'pdf 文本提取'

    # 模板填充（xlsx 夹具）
    $template = Join-Path $PSScriptRoot 'fixtures/template.xlsx'
    $vars = Join-Path $work 'vars.json'
    '{"customerName":"示例客户","total":1268.0,"items":[{"name":"A","qty":2},{"name":"B","qty":5}]}' |
        Set-Content -LiteralPath $vars -Encoding utf8

    $filled = Join-Path $work 'filled.xlsx'
    $r = Invoke-Office @('fill', $template, $vars, '-o', $filled)
    Assert-True (($r.Code -eq 0) -and (Test-Path $filled)) 'xlsx 模板填充'

    $r = Invoke-Office @('text', $filled)
    Assert-Contains $r.Text '示例客户' '填充：标量值'
    Assert-Contains $r.Text 'A	2' '填充：循环第 1 行'
    Assert-Contains $r.Text 'B	5' '填充：循环第 2 行'
    Assert-Contains $r.Text '1268.00' '填充：合计'

    # 不支持的转换
    $r = Invoke-Office @('convert', $docx, (Join-Path $work 'bad.xlsx'))
    Assert-True ($r.Code -eq 1) 'docx → xlsx 拒绝'
}
finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("[office] 通过 {0} 个，失败 {1} 个" -f $script:passed, $script:failed) -ForegroundColor Cyan

if ($script:failed -gt 0) {
    exit 1
}
