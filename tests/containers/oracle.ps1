#Requires -Version 7.0
<#
.SYNOPSIS
    Oracle 测试库（WSL + nerdctl）。

.DESCRIPTION
    gvenzl/oracle-free:23-slim，host 网络 + 1521 端口。
    system 密码 Lcdb_Test123，可插拔库 FREEPDB1，应用用户 lcdb/Lcdb_Test123。
    容器首次启动要 1-2 分钟初始化。
#>
[CmdletBinding()]
param(
    [ValidateSet('up', 'down', 'status', 'reset')]
    [string]$Action = 'up',

    [int]$Port = 1521
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')

$Name = 'lcdb-oracle'
$Image = 'docker.1panel.live/gvenzl/oracle-free:23-slim'
$Password = 'Lcdb_Test123'
$Service = 'FREEPDB1'
$PingSh = Join-Path $PSScriptRoot 'shell/ping-oracle.sh'
$CleanupNameSh = Join-Path $PSScriptRoot 'shell/cleanup-name.sh'
$KillPortSh = Join-Path $PSScriptRoot 'shell/kill-port.sh'

function Resolve-WslAddress {
    $address = (& wsl -d debian-nerdctl -- hostname -I 2>$null | Out-String).Trim().Split(' ')[0]

    if (-not $address) {
        return '127.0.0.1'
    }

    return $address
}

function Test-PortFromWindows {
    param([string]$Address, [int]$Port)

    return (Test-NetConnection -ComputerName $Address -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue)
}

function Test-OracleReady {
    $probe = Invoke-WslScript -ScriptPath $PingSh -Arguments @($Name, $Password, $Service, "$Port") -AllowFailure
    return $probe.Code -eq 0
}

function Get-RunArguments {
    return @(
        '--restart=always',
        '--network', 'host',
        '-e', "ORACLE_PASSWORD=$Password",
        '-e', 'APP_USER=lcdb',
        '-e', "APP_USER_PASSWORD=$Password",
        $Image
    )
}

function Ensure-Oracle {
    Invoke-WslScript -ScriptPath $CleanupNameSh -Arguments @($Name) -AllowFailure | Out-Null

    Ensure-Container -Name $Name -RunArguments (Get-RunArguments)
    Wait-Condition -Probe { Test-OracleReady } -What 'Oracle' -TimeoutSeconds 420

    $address = Resolve-WslAddress

    if (-not (Test-PortFromWindows -Address $address -Port $Port)) {
        Write-Host '    Windows 侧端口不可达，重建容器' -ForegroundColor Yellow
        Remove-Container -Name $Name
        Invoke-WslScript -ScriptPath $KillPortSh -Arguments @("$Port") -AllowFailure | Out-Null
        Ensure-Container -Name $Name -RunArguments (Get-RunArguments)
        Wait-Condition -Probe { Test-OracleReady } -What 'Oracle' -TimeoutSeconds 420
    }
}

switch ($Action) {
    'up' {
        Ensure-Oracle
        Write-Host ("Oracle 就绪: 127.0.0.1:{0} (system/Lcdb_Test123, service={1})" -f $Port, $Service) -ForegroundColor Green
    }

    'status' {
        $exists = Test-ContainerExists -Name $Name
        $running = if ($exists) { Test-ContainerRunning -Name $Name } else { $false }
        Write-Host ("container={0} exists={1} running={2} port={3}" -f $Name, $exists, $running, $Port)
    }

    'down' {
        Remove-Container -Name $Name
    }

    'reset' {
        Remove-Container -Name $Name
        & $PSCommandPath -Action up -Port $Port
    }
}
