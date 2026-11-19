@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"

rem ============================================================
rem  local-skill-tools 制品重建（bin 目录误删后跑这个）
rem
rem  用法：
rem    rebuild.bat             只重建 win-x64（宿主平台）
rem    rebuild.bat linux       只重建 linux-x64（Windows 上交叉编译）
rem    rebuild.bat osx         只重建 osx-arm64（交叉编译，自动拉 macOS SDK）
rem    rebuild.bat all         重建三平台（win-x64 + linux-x64 + osx-arm64）
rem    rebuild.bat verify      只校验 win-x64 的现存制品
rem    rebuild.bat verify all  只校验三平台
rem
rem  前置（构建时）：.NET SDK 11、PowerShell 7+（pwsh）。
rem  首次构建要联网（拉 NuGet 包 + PublishAotCross 的 Zig / MacOSX.SDK 工具链）。
rem ============================================================

if "%~1"=="" set "PAUSE_ON_EXIT=1"

set "MODE=build"
if /i "%~1"=="verify" (
    set "MODE=verify"
    shift
)

set "RIDS="
:parse
if "%~1"=="" goto :parsed
set "TOK=%~1"
set "KNOWN=0"
if /i "%TOK%"=="all" ( set "RIDS=%RIDS% win-x64 linux-x64 osx-arm64" & set "KNOWN=1" )
if /i "%TOK%"=="win" ( set "RIDS=%RIDS% win-x64" & set "KNOWN=1" )
if /i "%TOK%"=="win-x64" ( set "RIDS=%RIDS% win-x64" & set "KNOWN=1" )
if /i "%TOK%"=="linux" ( set "RIDS=%RIDS% linux-x64" & set "KNOWN=1" )
if /i "%TOK%"=="linux-x64" ( set "RIDS=%RIDS% linux-x64" & set "KNOWN=1" )
if /i "%TOK%"=="osx" ( set "RIDS=%RIDS% osx-arm64" & set "KNOWN=1" )
if /i "%TOK%"=="osx-arm64" ( set "RIDS=%RIDS% osx-arm64" & set "KNOWN=1" )
if /i "%TOK%"=="mac" ( set "RIDS=%RIDS% osx-arm64" & set "KNOWN=1" )
if /i "%TOK%"=="macos" ( set "RIDS=%RIDS% osx-arm64" & set "KNOWN=1" )
if "%KNOWN%"=="0" (
    echo [ERROR] 未知目标: %TOK%（可选: win / linux / osx / all）
    if defined PAUSE_ON_EXIT pause
    exit /b 2
)
shift
goto :parse

:parsed
if "%RIDS%"=="" set "RIDS=win-x64"

echo ============================================
echo  local-skill-tools 制品重建
echo ============================================

if /i "%MODE%"=="verify" goto :check_verify

where dotnet >nul 2>nul
if errorlevel 1 goto :no_dotnet
where pwsh >nul 2>nul
if errorlevel 1 goto :no_pwsh
if not exist "src\Directory.Build.props" goto :no_src
if not exist "build.ps1" goto :no_src
for /f "delims=" %%v in ('dotnet --version 2^>nul') do set "SDK_VER=%%v"
echo [i] dotnet SDK : %SDK_VER%
goto :checks_done

:check_verify
if not exist "bin" goto :no_bin

:checks_done
echo [i] 目标 RID   : %RIDS%
if /i "%MODE%"=="verify" echo [i] 模式       : 仅校验
echo.

set "TOOLS=sqlite:db-sqlite mysql:db-mysql postgres:db-postgres duckdb:db-duckdb clickhouse:db-clickhouse redis:db-redis dm:db-dm mongo:db-mongo sqlserver:db-sqlserver oracle:db-oracle ssh:net-ssh sftp:net-sftp"

if /i "%MODE%"=="build" (
    for %%R in (%RIDS%) do (
        for %%T in (%TOOLS%) do (
            for /f "tokens=1,2 delims=:" %%A in ("%%T") do (
                call :build_one %%A %%B %%R
                if errorlevel 1 goto :failed
            )
        )
    )
)

echo.
echo ==^> 校验产物
set "MISSING=0"
set "OSX_HINT=0"
for %%T in (%TOOLS%) do (
    for /f "tokens=1,2 delims=:" %%A in ("%%T") do (
        for %%R in (%RIDS%) do (
            if not exist "bin\%%A-%%R\%%B*" (
                echo [MISS] bin\%%A-%%R 缺少可执行文件
                set "MISSING=1"
            ) else (
                if /i "%%A-%%R"=="sqlserver-linux-x64" (
                    dir /b "bin\%%A-%%R\*icu*" >nul 2>nul
                    if errorlevel 1 (
                        echo [MISS] bin\%%A-%%R 缺少 ICU 文件
                        set "MISSING=1"
                    )
                )
            )
            if /i "%%R"=="osx-arm64" set "OSX_HINT=1"
        )
    )
)

if "%MISSING%"=="1" goto :failed

if "%OSX_HINT%"=="1" (
    echo.
    echo [i] macOS：从别的机器拷贝/下载的制品带 quarantine 标记，首次运行前执行
    echo     xattr -dr com.apple.quarantine bin\^<db^>-osx-arm64
)

where pwsh >nul 2>nul
if not errorlevel 1 (
    for /f "delims=" %%S in ('pwsh -NoProfile -Command "'{0:N1}' -f ((Get-ChildItem -Recurse -File 'bin' | Measure-Object Length -Sum).Sum/1MB)"') do echo [i] bin 总大小 : %%S MB
)

echo.
echo [OK] 制品重建完成
if defined PAUSE_ON_EXIT pause
exit /b 0

rem ------------------------------------------------------------
:build_one
echo ==^> 构建 %~1 %~3
pwsh -NoProfile -File "build.ps1" -Only %~1 -Rid %~3 -Clean
if errorlevel 1 (
    rem 偶发文件锁（MSB4175 / "file is being used by another process"），重试一次
    echo [WARN] %~1 %~3 首次失败，关闭编译服务后重试
    dotnet build-server shutdown >nul 2>nul
    ping -n 4 127.0.0.1 >nul
    pwsh -NoProfile -File "build.ps1" -Only %~1 -Rid %~3 -Clean
)
if errorlevel 1 (
    echo [ERROR] %~1 %~3 构建失败
    exit /b 1
)
exit /b 0

rem ------------------------------------------------------------
:no_dotnet
echo [ERROR] 找不到 dotnet。请安装 .NET SDK 11：https://dotnet.microsoft.com/download
if defined PAUSE_ON_EXIT pause
exit /b 1

:no_pwsh
echo [ERROR] 找不到 pwsh（PowerShell 7+）。安装：winget install Microsoft.PowerShell
if defined PAUSE_ON_EXIT pause
exit /b 1

:no_src
echo [ERROR] 当前目录不像仓库根目录（缺 build.ps1 或 src\Directory.Build.props）
echo         请把本文件放在 local-skill-tools 目录下运行。
if defined PAUSE_ON_EXIT pause
exit /b 1

:no_bin
echo [ERROR] 找不到 bin 目录：先跑一次构建，或从 release 解压制品
if defined PAUSE_ON_EXIT pause
exit /b 1

:failed
if defined PAUSE_ON_EXIT pause
exit /b 1
