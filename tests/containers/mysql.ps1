#Requires -Version 7.0
<#
.SYNOPSIS
    MySQL 测试库（WSL + nerdctl）。

.DESCRIPTION
    固定端口 13306，容器名 lcdb-mysql，库名 lcdb，root 密码 lcdb_pw。
    时区固定 Asia/Shanghai（服务端 +08:00），保证对拍基线不随机器变化。

.EXAMPLE
    .\mysql.ps1 -Action up
    .\mysql.ps1 -Action seed
    .\mysql.ps1 -Action status
    .\mysql.ps1 -Action down
#>
[CmdletBinding()]
param(
    [ValidateSet('up', 'down', 'status', 'seed', 'reset')]
    [string]$Action = 'up',

    [int]$Port = 13306
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')

$Name = 'lcdb-mysql'
$Image = 'docker.m.daocloud.io/library/mysql:8.0'
$Password = 'lcdb_pw'
$SeedSql = Join-Path $PSScriptRoot 'seed/mysql.sql'
$SeedSh = Join-Path $PSScriptRoot 'shell/seed-mysql.sh'

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

function Invoke-Recreate {
    Remove-Container -Name $Name
    Invoke-WslScript -ScriptPath (Join-Path $PSScriptRoot 'shell/cleanup-name.sh') -Arguments @($Name) -AllowFailure | Out-Null
    Invoke-WslScript -ScriptPath (Join-Path $PSScriptRoot 'shell/free-port.sh') -Arguments @("$Port") -AllowFailure | Out-Null

    Ensure-Container -Name $Name -RunArguments @(
        '--restart=always',
        '--network', 'host',
        '-e', "MYSQL_ROOT_PASSWORD=$Password",
        '-e', 'TZ=Asia/Shanghai',
        $Image,
        '--default-time-zone=+08:00',
        "--port=$Port",
        '--skip-name-resolve',
        '--character-set-server=utf8mb4',
        '--collation-server=utf8mb4_0900_ai_ci'
    )

    Wait-Condition -Probe { Test-MySqlReady } -What 'MySQL' -TimeoutSeconds 240
}

function Ensure-MySql {
    # 自愈：先清掉上次失败留下的 name store / 端口分配残留
    Invoke-WslScript -ScriptPath (Join-Path $PSScriptRoot 'shell/cleanup-name.sh') -Arguments @($Name) -AllowFailure | Out-Null
    Invoke-WslScript -ScriptPath (Join-Path $PSScriptRoot 'shell/free-port.sh') -Arguments @("$Port") -AllowFailure | Out-Null

    Ensure-Container -Name $Name -RunArguments @(
        '--restart=always',
        '--network', 'host',
        '-e', "MYSQL_ROOT_PASSWORD=$Password",
        '-e', 'TZ=Asia/Shanghai',
        $Image,
        '--default-time-zone=+08:00',
        "--port=$Port",
        '--skip-name-resolve',
        '--character-set-server=utf8mb4',
        '--collation-server=utf8mb4_0900_ai_ci'
    )

    Wait-Condition -Probe { Test-MySqlReady } -What 'MySQL' -TimeoutSeconds 240

    # WSL 重启后容器会被恢复，但 CNI 的端口映射规则可能没重建：
    # 容器内部健康、Windows 侧却连不上。此时重建容器以重新生成规则。
    $address = Resolve-WslAddress

    if (-not (Test-PortFromWindows -Address $address -Port $Port)) {
        Write-Host '    Windows 侧端口不可达，重建容器以刷新端口映射' -ForegroundColor Yellow
        Invoke-Recreate
    }
}

function Invoke-Seed {
    # 环境会间歇性抖动（WSL/containerd 重启），每个用例前都确认容器在跑且端口可达，
    # 不可达就走完整自愈（必要时重建容器重新生成端口映射）。
    $address = Resolve-WslAddress
    $healthy = (Test-ContainerRunning -Name $Name) -and (Test-PortFromWindows -Address $address -Port $Port)

    if (-not $healthy) {
        Ensure-MySql
    }

    Invoke-WslScript -ScriptPath $SeedSh -Arguments @(
        $Name,
        (ConvertTo-WslPath -Path $SeedSql),
        $Password
    ) | Out-Null
}

function Test-MySqlReady {
    $probe = Invoke-WslScript -ScriptPath (Join-Path $PSScriptRoot 'shell/ping-mysql.sh') -Arguments @($Name, $Password) -AllowFailure
    return $probe.Code -eq 0
}

switch ($Action) {
    'up' {
        Ensure-MySql
        Invoke-Seed
        Write-Host ("MySQL 就绪: 127.0.0.1:{0} (root/{1}, db=lcdb)" -f $Port, $Password) -ForegroundColor Green
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
