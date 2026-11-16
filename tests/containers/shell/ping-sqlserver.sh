#!/usr/bin/env bash
# SQL Server 就绪探针（容器内置 sqlcmd）。
# 写成脚本：wsl.exe 传参时引号/反斜杠会被破坏。
set -uo pipefail

name="$1"
password="$2"
port="${3:-1433}"

output="$(nerdctl exec "$name" /opt/mssql-tools18/bin/sqlcmd \
    -C -S "127.0.0.1,$port" -U sa -P "$password" -Q "SELECT 1" -h -1 -W 2>/dev/null | tr -d '\r' | grep -E '^[[:space:]]*1[[:space:]]*$' | head -1)"

[ -n "$output" ]
