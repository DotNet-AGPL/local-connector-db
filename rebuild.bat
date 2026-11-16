@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"

rem ============================================================
rem  local-connector-db 制品重建（bin 目录误删后跑这个）
rem
rem  用法：
rem     rebuild.bat          重建 win-x64 + linux-x64 全部制品
rem     rebuild.bat win      只重建 win-x64
rem     rebuild.bat linux    只重建 linux-x64
rem     rebuild.bat verify   只校验现有制品，不构建
rem
rem  前置：.NET SDK 11、PowerShell 7+（pwsh）。
rem  首次构建要联网（拉 NuGet 包 + PublishAotCross 的 Zig 工具链）。
rem ============================================================

set "RIDS=win-x64 linux-x64"
set "DO_BUILD=1"
if /i "%~1"=="win"      set "RIDS=win-x64"
if /i "%~1"=="win-x64"  set "RIDS=win-x64"
if /i "%~1"=="linux"    set "RIDS=linux-x64"
if /i "%~1"=="linux-x64" set "RIDS=linux-x64"
if /i "%~1"=="verify"   set "DO_BUILD=0"

echo ============================================
echo  local-connector-db 制品重建
echo ============================================

where dotnet >nul 2>nul
if errorlevel 1 goto :no_dotnet
where pwsh >nul 2>nul
if errorlevel 1 goto :no_pwsh
if not exist "src\Directory.Build.props" goto :no_src
if not exist "build.ps1" goto :no_src

for /f "delims=" %%v in ('dotnet --version 2^>nul') do set "SDK_VER=%%v"
echo [i] dotnet SDK : %SDK_VER%
echo [i] 目标 RID   : %RIDS%
if "%DO_BUILD%"=="0" echo [i] 模式       : 仅校验
echo.

if "%DO_BUILD%"=="1" (
    for %%R in (%RIDS%) do (
        for %%D in (sqlite mysql postgres duckdb clickhouse redis dm mongo sqlserver oracle) do (
            call :build_one %%D %%R
            if errorlevel 1 goto :failed
        )
    )
)

echo.
call :verify
if errorlevel 1 goto :failed

echo.
echo [OK] 制品重建完成
if "%~1"=="" pause
exit /b 0

rem ------------------------------------------------------------
:build_one
echo ==^> 构建 %~1 %~2
pwsh -NoProfile -File "build.ps1" -Only %~1 -Rid %~2 -Clean
if errorlevel 1 (
    rem 偶发文件锁（MSB4175 / "file is being used by another process"），重试一次
    echo [WARN] %~1 %~2 首次失败，关闭编译服务后重试
    dotnet build-server shutdown >nul 2>nul
    ping -n 4 127.0.0.1 >nul
    pwsh -NoProfile -File "build.ps1" -Only %~1 -Rid %~2 -Clean
)
if errorlevel 1 (
    echo [ERROR] %~1 %~2 构建失败
    exit /b 1
)
exit /b 0

rem ------------------------------------------------------------
rem  win-x64：全部走系统 NLS / 不变模式，不需要 ICU 文件
rem  linux-x64：只有 sqlserver 是非不变全球化，必须带 app-local ICU
rem ------------------------------------------------------------
:verify
echo ==^> 校验产物
set "MISSING=0"
for %%D in (sqlite mysql postgres duckdb clickhouse redis dm mongo sqlserver oracle) do (
    for %%R in (%RIDS%) do (
        if not exist "bin\%%D-%%R\db-%%D*" (
            echo [MISS] bin\%%D-%%R 缺少可执行文件
            set "MISSING=1"
        ) else (
            if /i "%%D-%%R"=="sqlserver-linux-x64" (
                dir /b "bin\%%D-%%R\*icu*" >nul 2>nul
                if errorlevel 1 (
                    echo [MISS] bin\%%D-%%R 缺少 ICU 文件
                    set "MISSING=1"
                )
            )
        )
    )
)

if "%MISSING%"=="1" (
    echo [ERROR] 有制品缺失，见上面的 [MISS]
    exit /b 1
)

for /f "delims=" %%S in ('pwsh -NoProfile -Command "'{0:N1}' -f ((Get-ChildItem -Recurse -File 'bin' | Measure-Object Length -Sum).Sum/1MB)"') do echo [i] bin 总大小 : %%S MB
exit /b 0

rem ------------------------------------------------------------
:no_dotnet
echo [ERROR] 找不到 dotnet。请安装 .NET SDK 11：https://dotnet.microsoft.com/download
if "%~1"=="" pause
exit /b 1

:no_pwsh
echo [ERROR] 找不到 pwsh（PowerShell 7+）。安装：winget install Microsoft.PowerShell
if "%~1"=="" pause
exit /b 1

:no_src
echo [ERROR] 当前目录不像 skill 根目录（缺 build.ps1 或 src\Directory.Build.props）
echo         请把本文件放在 local-connector-db 目录下运行。
if "%~1"=="" pause
exit /b 1

:failed
if "%~1"=="" pause
exit /b 1
