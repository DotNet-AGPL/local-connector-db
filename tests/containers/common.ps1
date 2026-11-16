#Requires -Version 7.0
<#
    容器测试库的公共工具：统一走 WSL 里的 nerdctl。

    注意 wsl.exe 的参数传递：含空格的自变量可以正确传递，但反斜杠会被吃掉，
    所以任何需要引号/重定向/复杂语法的容器内命令一律写成 .sh 文件，再用 bash 执行，
    不要试图把 shell 语法塞进 wsl.exe 的参数里。
#>

$script:WslDistro = 'debian-nerdctl'

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $drive = $full.Substring(0, 1).ToLowerInvariant()
    $rest = ($full.Substring(2) -replace '\\', '/')
    return "/mnt/$drive$rest"
}

function Invoke-Nerdctl {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $raw = & wsl -d $script:WslDistro -- nerdctl @Arguments 2>&1
    $code = $LASTEXITCODE
    $lines = @($raw | ForEach-Object { "$_" })
    $text = ($lines -join "`n")

    if (-not $AllowFailure -and $code -ne 0) {
        throw ("nerdctl {0} 失败 (exit {1}): {2}" -f $Arguments[0], $code, $text)
    }

    return [pscustomobject]@{
        Code   = $code
        Output = $text
        Lines  = $lines
    }
}

function Invoke-WslScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [switch]$AllowFailure
    )

    $wslPath = ConvertTo-WslPath -Path $ScriptPath
    $raw = & wsl -d $script:WslDistro -- bash $wslPath @Arguments 2>&1
    $code = $LASTEXITCODE
    $lines = @($raw | ForEach-Object { "$_" })

    if ($code -ne 0 -and -not $AllowFailure) {
        throw ("{0} 执行失败 (exit {1}): {2}" -f (Split-Path $ScriptPath -Leaf), $code, ($lines -join "`n"))
    }

    return [pscustomobject]@{ Code = $code; Lines = $lines; Output = ($lines -join "`n") }
}

function Test-ContainerExists {
    param([Parameter(Mandatory)][string]$Name)

    $result = Invoke-Nerdctl -Arguments @('inspect', $Name) -AllowFailure
    return $result.Code -eq 0
}

function Test-ContainerRunning {
    param([Parameter(Mandatory)][string]$Name)

    $result = Invoke-Nerdctl -Arguments @('inspect', '-f', '{{.State.Running}}', $Name) -AllowFailure

    if ($result.Code -ne 0) {
        return $false
    }

    return ($result.Output.Trim() -eq 'true')
}

function Wait-Condition {
    param(
        [Parameter(Mandatory)][scriptblock]$Probe,
        [Parameter(Mandatory)][string]$What,
        [int]$TimeoutSeconds = 180,
        [int]$IntervalMs = 2000
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()

    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (& $Probe) {
            Write-Host ("    {0} 就绪 ({1:N0}s)" -f $What, $watch.Elapsed.TotalSeconds) -ForegroundColor Green
            return
        }

        Start-Sleep -Milliseconds $IntervalMs
    }

    throw ("等待 {0} 超时 ({1}s)" -f $What, $TimeoutSeconds)
}

function Ensure-Container {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$RunArguments
    )

    if (Test-ContainerExists -Name $Name) {
        if (-not (Test-ContainerRunning -Name $Name)) {
            Write-Host ("    启动已有容器 {0}" -f $Name) -ForegroundColor Cyan
            Invoke-Nerdctl -Arguments @('start', $Name) | Out-Null
        }
        else {
            Write-Host ("    复用运行中的容器 {0}" -f $Name) -ForegroundColor Cyan
        }

        return
    }

    Write-Host ("    创建容器 {0}" -f $Name) -ForegroundColor Cyan
    Invoke-Nerdctl -Arguments (@('run', '-d', '--name', $Name) + $RunArguments) | Out-Null
}

function Remove-Container {
    param([Parameter(Mandatory)][string]$Name)

    if (Test-ContainerExists -Name $Name) {
        Invoke-Nerdctl -Arguments @('rm', '-f', $Name) | Out-Null
        Write-Host ("    已删除容器 {0}" -f $Name) -ForegroundColor Yellow
    }
}
