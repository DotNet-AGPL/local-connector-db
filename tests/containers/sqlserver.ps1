#Requires -Version 7.0
<#
.SYNOPSIS
    SQL Server 测试库（WSL + nerdctl）。

.DESCRIPTION
    固定端口 14330，容器名 lcdb-sqlserver，SA 密码 Lcdb_Test123!
    用 host 网络 + MSSQL_TCP_PORT，避开 1433 与其它服务冲突。
#>
[CmdletBinding()]
param(
    [ValidateSet('up', 'down', 'status', 'reset')]
    [string]$Action = 'up',

    [int]$Port = 14330
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')

$Name = 'lcdb-sqlserver'
$Image = 'mcr.microsoft.com/mssql/server:2022-latest'
$Password = 'Lcdb_Test123!'
$PingSh = Join-Path $PSScriptRoot 'shell/ping-sqlserver.sh'
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

function Test-SqlServerReady {
    $probe = Invoke-WslScript -ScriptPath $PingSh -Arguments @($Name, $Password, "$Port") -AllowFailure
    return $probe.Code -eq 0
}

function Get-RunArguments {
    return @(
        '--restart=always',
        '--network', 'host',
        '-e', 'ACCEPT_EULA=Y',
        '-e', "MSSQL_SA_PASSWORD=$Password",
        '-e', 'MSSQL_PID=Developer',
        '-e', "MSSQL_TCP_PORT=$Port",
        $Image
    )
}

function Ensure-SqlServer {
    Invoke-WslScript -ScriptPath $CleanupNameSh -Arguments @($Name) -AllowFailure | Out-Null

    Ensure-Container -Name $Name -RunArguments (Get-RunArguments)
    Wait-Condition -Probe { Test-SqlServerReady } -What 'SQL Server' -TimeoutSeconds 300

    $address = Resolve-WslAddress

    if (-not (Test-PortFromWindows -Address $address -Port $Port)) {
        Write-Host '    Windows 侧端口不可达，重建容器' -ForegroundColor Yellow
        Remove-Container -Name $Name
        Invoke-WslScript -ScriptPath $KillPortSh -Arguments @("$Port") -AllowFailure | Out-Null
        Ensure-Container -Name $Name -RunArguments (Get-RunArguments)
        Wait-Condition -Probe { Test-SqlServerReady } -What 'SQL Server' -TimeoutSeconds 300
    }
}

switch ($Action) {
    'up' {
        Ensure-SqlServer
        Write-Host ("SQL Server 就绪: 127.0.0.1:{0} (sa/Lcdb_Test123!)" -f $Port) -ForegroundColor Green
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
