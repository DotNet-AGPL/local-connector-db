#Requires -Version 7.0
<#
.SYNOPSIS
    SSH / SFTP 冒烟测试。

.DESCRIPTION
    需要一台可登录的测试服务器与密码（不写入仓库）。未设置环境变量时整组跳过。

    必需环境变量：
        LCDB_TEST_SSH_HOST      例如 10.0.2.74
        LCDB_TEST_SSH_USER      例如 root
        LCDB_TEST_SSH_PASSWORD  测试账号密码

    可选：
        LCDB_TEST_SSH_PORT      默认 22
        LCDB_TEST_SSH_REMOTE    远端临时目录，默认 /tmp/lcdb-net-test

.EXAMPLE
    $env:LCDB_TEST_SSH_HOST='10.0.2.74'; $env:LCDB_TEST_SSH_USER='root'
    $env:LCDB_TEST_SSH_PASSWORD='***'
    .\tests\net\run.ps1
#>
[CmdletBinding()]
param(
    [switch]$KeepRemote
)

$ErrorActionPreference = 'Stop'

$hostName = $env:LCDB_TEST_SSH_HOST
$user = $env:LCDB_TEST_SSH_USER
$password = $env:LCDB_TEST_SSH_PASSWORD
$port = if ($env:LCDB_TEST_SSH_PORT) { [int]$env:LCDB_TEST_SSH_PORT } else { 22 }
$remote = if ($env:LCDB_TEST_SSH_REMOTE) { $env:LCDB_TEST_SSH_REMOTE } else { '/tmp/lcdb-net-test' }

if (-not $hostName -or -not $user -or -not $password) {
    Write-Host '[SKIP] 未设置 LCDB_TEST_SSH_HOST / USER / PASSWORD，跳过 SSH/SFTP 测试'
    exit 0
}

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ssh = Join-Path $root 'bin/ssh-win-x64/net-ssh.exe'
$sftp = Join-Path $root 'bin/sftp-win-x64/net-sftp.exe'
$target = "$user@$hostName"
$work = Join-Path ([IO.Path]::GetTempPath()) ('lcdb-net-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

$passed = 0
$failed = 0

function Invoke-Net([string]$exe, [string[]]$argv) {
    $null = $password | & $exe @argv 2>&1
    return $LASTEXITCODE
}

function Assert-True([bool]$condition, [string]$name) {
    if ($condition) {
        Write-Host "[ OK   ] $name"
        $script:passed++
    }
    else {
        Write-Host "[ FAIL ] $name"
        $script:failed++
    }
}

New-Item -ItemType Directory -Path $work -Force | Out-Null
Set-Content -Path (Join-Path $work 'a.txt') -Value 'hello net' -Encoding utf8NoBOM
New-Item -ItemType Directory -Path (Join-Path $work 'dir/sub') -Force | Out-Null
Set-Content -Path (Join-Path $work 'dir/b.txt') -Value 'b' -Encoding utf8NoBOM
Set-Content -Path (Join-Path $work 'dir/sub/c.txt') -Value 'ccc' -Encoding utf8NoBOM

$common = @('-p', "$port", '--password-stdin', '--insecure')

try {
    $out = $password | & $ssh exec $target @common -- 'echo lcdb-ok' 2>&1
    Assert-True (($LASTEXITCODE -eq 0) -and (($out -join "`n") -match 'lcdb-ok')) 'ssh exec'

    $code = Invoke-Net $ssh (@('exec', $target) + $common + @('--', 'exit 7'))
    Assert-True ($code -eq 7) 'ssh 退出码透传'

    $code = Invoke-Net $ssh (@('exec', $target) + $common + @('--', 'false'))
    Assert-True ($code -ne 0) 'ssh 失败命令非零退出'

    $code = Invoke-Net $sftp (@('mkdir', $target, $remote) + $common)
    Assert-True ($code -eq 0) 'sftp mkdir'

    $code = Invoke-Net $sftp (@('put', $target, (Join-Path $work 'a.txt'), "$remote/a.txt") + $common)
    Assert-True ($code -eq 0) 'sftp put 文件'

    $code = Invoke-Net $sftp (@('put', $target, (Join-Path $work 'dir'), "$remote/dir", '-r') + $common)
    Assert-True ($code -eq 0) 'sftp put 目录 -r'

    $code = Invoke-Net $sftp (@('get', $target, "$remote/a.txt", (Join-Path $work 'back.txt')) + $common)
    Assert-True (($code -eq 0) -and ((Get-Content (Join-Path $work 'back.txt') -Raw).Trim() -eq 'hello net')) 'sftp get 文件'

    $code = Invoke-Net $sftp (@('get', $target, "$remote/dir", (Join-Path $work 'dir-back'), '-r') + $common)
    Assert-True (($code -eq 0) -and (Test-Path (Join-Path $work 'dir-back/sub/c.txt'))) 'sftp get 目录 -r'
}
finally {
    if (-not $KeepRemote) {
        $null = Invoke-Net $sftp (@('rm', $target, $remote, '-r') + $common)
    }

    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "[net] 通过 $passed 个，失败 $failed 个"

if ($failed -gt 0) {
    exit 1
}
