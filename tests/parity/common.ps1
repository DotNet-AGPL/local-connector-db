#Requires -Version 7.0
<#
    对拍公共层：进程调用、输出归一化、差异展示。
    与具体数据库无关，由 cases-<db>.ps1 提供用例清单与命令拼装。
#>

[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

function New-CaseWorkspace {
    param([Parameter(Mandatory)][string]$CaseName)

    $work = Join-Path ([IO.Path]::GetTempPath()) ('lcdb-parity-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    return $work
}

<#
    WSL2 空闲会关闭 VM，容器随之停止（且不一定被恢复），
    跑测试期间挂一个 sleep 进程把 VM 保活，脚本退出时清理。
#>
function Initialize-WslKeepAlive {
    param(
        [string]$Distro = 'debian-nerdctl',
        [int]$Minutes = 30
    )

    $process = Start-Process -FilePath 'wsl' `
        -ArgumentList @('-d', $Distro, '--', 'sleep', "$($Minutes * 60)") `
        -PassThru -WindowStyle Hidden

    $global:LcdbWslKeepAlive = $process

    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        if ($global:LcdbWslKeepAlive -and -not $global:LcdbWslKeepAlive.HasExited) {
            Stop-Process -Id $global:LcdbWslKeepAlive.Id -Force -ErrorAction SilentlyContinue
        }
    } | Out-Null

    return $process
}

<#
    用调用运算符而不是 Start-Process：后者把 ArgumentList 拼成命令行，含空格的 SQL 会被拆错。
    stderr 走文件，避免 2> 在管道里变成 ErrorRecord 影响文本比对。
#>
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$WorkDir,
        [int]$Retries = 3
    )

    $errFile = Join-Path $WorkDir 'stderr.txt'
    $stdoutText = ''
    $stderrText = ''
    $code = 0

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        Remove-Item $errFile -Force -ErrorAction SilentlyContinue

        $stdout = & $FilePath @ArgumentList 2> $errFile
        $code = $LASTEXITCODE

        $stdoutText = ($stdout | ForEach-Object { "$_" }) -join "`n"
        $stderrText = if (Test-Path $errFile) { Get-Content -LiteralPath $errFile -Raw -Encoding utf8 } else { '' }
        if ($null -eq $stderrText) { $stderrText = '' }

        if ($code -eq 0 -or -not (Test-TransientFailure -Text $stderrText)) {
            break
        }

        Start-Sleep -Milliseconds 800
    }

    return @{
        Code   = $code
        Stdout = $stdoutText
        Stderr = $stderrText.TrimEnd("`n", "`r")
    }
}

<#
    WSL2 的桥接网络偶发丢 SYN，表现为驱动层的连接超时 / 拒绝。
    这类错误重试即可，不能和真正的配置错误（密码错、库不存在）混为一谈。
#>
function Test-TransientFailure {
    param([string]$Text)

    if (-not $Text) {
        return $false
    }

    return ($Text -match 'Connect Timeout expired' -or
        $Text -match 'Unable to connect to any of the specified MySQL hosts' -or
        $Text -match 'ETIMEDOUT' -or
        $Text -match 'ECONNREFUSED' -or
        $Text -match 'ECONNRESET' -or
        $Text -match 'Connection reset by peer')
}

<#
    统一归一化，保证 node 版与 exe 版可比：
        - CRLF -> LF
        - 临时工作目录 -> <WORK>
        - 毫秒耗时 -> (<time>)
        - checkpoint 三元组数值 -> N
        - 数据库文件大小 / SQLite 版本 / MySQL 版本 -> 占位
#>
function Normalize-Output {
    param(
        [int]$Code,
        [string]$Stdout,
        [string]$Stderr,
        [string]$WorkDir
    )

    $text = "EXIT: $Code`n--- STDOUT ---`n$Stdout`n--- STDERR ---`n$Stderr"
    $text = $text -replace "`r`n", "`n"

    if ($WorkDir) {
        $text = $text.Replace($WorkDir, '<WORK>')
    }

    $text = $text -replace '\(\d+ms\)', '(<time>)'
    $text = $text -replace 'busy=-?\d+ log=-?\d+ checkpointed=-?\d+', 'busy=N log=N checkpointed=N'
    $text = $text -replace '数据库文件大小: [\d.]+ KB', '数据库文件大小: <size> KB'
    $text = $text -replace 'SQLite 版本: [\d.]+', 'SQLite 版本: <ver>'
    $text = $text -replace 'MySQL 版本: [\d.\-a-zA-Z]+', 'MySQL 版本: <ver>'
    $text = $text -replace '主机: \d{1,3}(\.\d{1,3}){3}', '主机: <host>'
    $text = $text -replace '\b\d{1,3}(\.\d{1,3}){3}:\d+', '<host>:<port>'
    $text = $text -replace 'SQLite Error \d+: ', ''

    return $text.TrimEnd("`n", "`r")
}

function Show-TextDiff {
    param(
        [string]$Expected,
        [string]$Actual
    )

    $expectedLines = $Expected -split "`n"
    $actualLines = $Actual -split "`n"
    $max = [Math]::Max($expectedLines.Count, $actualLines.Count)

    for ($i = 0; $i -lt $max; $i++) {
        $left = if ($i -lt $expectedLines.Count) { $expectedLines[$i] } else { '<none>' }
        $right = if ($i -lt $actualLines.Count) { $actualLines[$i] } else { '<none>' }

        if ($left -ne $right) {
            Write-Host ("    L{0} 期望: {1}" -f ($i + 1), $left) -ForegroundColor DarkYellow
            Write-Host ("    L{0} 实际: {1}" -f ($i + 1), $right) -ForegroundColor DarkMagenta
        }
    }
}
