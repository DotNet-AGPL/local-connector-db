#!/usr/bin/env bash
# 诊断容器为何停止（wsl.exe 传参对引号不友好，所有命令都放脚本里）
set -uo pipefail

echo "--- containers ---"
nerdctl ps -a --format '{{.Names}} {{.Status}}'

echo "--- state(lcdb-mysql) ---"
nerdctl inspect lcdb-mysql 2>/dev/null | grep -E '"ExitCode"|"OOMKilled"|"Status"|"Error"' | head -10

echo "--- memory ---"
free -m | head -3

echo "--- oom ---"
dmesg 2>/dev/null | grep -iE 'oom|killed process' | tail -5

echo "--- uptime ---"
uptime
