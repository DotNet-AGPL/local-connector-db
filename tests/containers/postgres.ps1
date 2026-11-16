#Requires -Version 7.0
<#
.SYNOPSIS
    PostgreSQL 测试库（WSL + nerdctl）。

.DESCRIPTION
    固定端口 15432，容器名 lcdb-postgres，库名 lcdb，用户 postgres，密码 lcdb_pw。
    用 host 网络：CNI 的 -p 端口映射在 WSL 重启后会残留错误规则（TCP 通但握手超时）。
    时区固定 Asia/Shanghai。

.EXAMPLE
    .\postgres.ps1 -Action up
    .\postgres.ps1 -Action seed
    .\postgres.ps1 -Action down
#>
[CmdletBinding()]
param(
    [ValidateSet('up', 'down', 'status', 'seed', 'reset')]
    [string]$Action = 'up',

    [int]$Port = 15432
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')

$Name = 'lcdb-postgres'
$Image = 'docker.m.daocloud.io/library/postgres:17'
$Password = 'lcdb_pw'
$SeedSql = Join-Path $PSScriptRoot 'seed/postgres.sql'
$SeedSh = Join-Path $PSScriptRoot 'shell/seed-postgres.sh'
$PingSh = Join-Path $PSScriptRoot 'shell/ping-postgres.sh'
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

function Test-PostgresReady {
    $probe = Invoke-WslScript -ScriptPath $PingSh -Arguments @($Name, $Password, "$Port") -AllowFailure
    return $probe.Code -eq 0
}

function Get-RunArguments {
    return @(
        '--restart=always',
        '--network', 'host',
        '-e', "POSTGRES_PASSWORD=$Password",
        '-e', 'POSTGRES_DB=lcdb',
        '-e', 'TZ=Asia/Shanghai',
        $Image,
        '-c', "port=$Port",
        '-c', 'timezone=Asia/Shanghai'
    )
}

function Invoke-Recreate {
    Remove-Container -Name $Name
    Invoke-WslScript -ScriptPath $CleanupNameSh -Arguments @($Name) -AllowFailure | Out-Null
    Invoke-WslScript -ScriptPath $KillPortSh -Arguments @("$Port") -AllowFailure | Out-Null

    Ensure-Container -Name $Name -RunArguments (Get-RunArguments)
    Wait-Condition -Probe { Test-PostgresReady } -What 'PostgreSQL' -TimeoutSeconds 240
}

function Ensure-Postgres {
    Invoke-WslScript -ScriptPath $CleanupNameSh -Arguments @($Name) -AllowFailure | Out-Null

    Ensure-Container -Name $Name -RunArguments (Get-RunArguments)
    Wait-Condition -Probe { Test-PostgresReady } -What 'PostgreSQL' -TimeoutSeconds 240

    $address = Resolve-WslAddress

    if (-not (Test-PortFromWindows -Address $address -Port $Port)) {
        Write-Host '    Windows 侧端口不可达，重建容器' -ForegroundColor Yellow
        Invoke-Recreate
    }
}

function Invoke-Seed {
    $address = Resolve-WslAddress
    $healthy = (Test-ContainerRunning -Name $Name) -and (Test-PortFromWindows -Address $address -Port $Port)

    if (-not $healthy) {
        Ensure-Postgres
    }

    Invoke-WslScript -ScriptPath $SeedSh -Arguments @(
        $Name,
        (ConvertTo-WslPath -Path $SeedSql),
        $Password,
        "$Port"
    ) | Out-Null
}

switch ($Action) {
    'up' {
        Ensure-Postgres
        Invoke-Seed
        Write-Host ("PostgreSQL 就绪: 127.0.0.1:{0} (postgres/{1}, db=lcdb)" -f $Port, $Password) -ForegroundColor Green
    }

    'seed' {
        Invoke-Seed
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
