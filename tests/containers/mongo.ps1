#Requires -Version 7.0
<#
.SYNOPSIS
    MongoDB 测试库（WSL + nerdctl）。

.DESCRIPTION
    固定端口 27018，容器名 lcdb-mongo，root 账号 lcdb/lcdb_pw（authenticationDatabase=admin）。
    用 host 网络：CNI 的 -p 端口映射在 WSL 重启后会残留错误规则。
#>
[CmdletBinding()]
param(
    [ValidateSet('up', 'down', 'status', 'reset')]
    [string]$Action = 'up',

    [int]$Port = 27018
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')

$Name = 'lcdb-mongo'
$Image = 'docker.m.daocloud.io/library/mongo:6.0'
$User = 'lcdb'
$Password = 'lcdb_pw'
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

function Test-MongoReady {
    $probe = Invoke-WslScript -ScriptPath (Join-Path $PSScriptRoot 'shell/ping-mongo.sh') -Arguments @($Name, $User, $Password, "$Port") -AllowFailure
    return $probe.Code -eq 0
}

function Get-RunArguments {
    return @(
        '--restart=always',
        '--network', 'host',
        '-e', "MONGO_INITDB_ROOT_USERNAME=$User",
        '-e', "MONGO_INITDB_ROOT_PASSWORD=$Password",
        $Image,
        '--port', "$Port"
    )
}

function Ensure-Mongo {
    Invoke-WslScript -ScriptPath $CleanupNameSh -Arguments @($Name) -AllowFailure | Out-Null

    Ensure-Container -Name $Name -RunArguments (Get-RunArguments)
    Wait-Condition -Probe { Test-MongoReady } -What 'MongoDB' -TimeoutSeconds 240

    $address = Resolve-WslAddress

    if (-not (Test-PortFromWindows -Address $address -Port $Port)) {
        Write-Host '    Windows 侧端口不可达，重建容器' -ForegroundColor Yellow
        Remove-Container -Name $Name
        Invoke-WslScript -ScriptPath $KillPortSh -Arguments @("$Port") -AllowFailure | Out-Null
        Ensure-Container -Name $Name -RunArguments (Get-RunArguments)
        Wait-Condition -Probe { Test-MongoReady } -What 'MongoDB' -TimeoutSeconds 240
    }
}

switch ($Action) {
    'up' {
        Ensure-Mongo
        Write-Host ("MongoDB 就绪: 127.0.0.1:{0} ({1}/{2})" -f $Port, $User, $Password) -ForegroundColor Green
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
