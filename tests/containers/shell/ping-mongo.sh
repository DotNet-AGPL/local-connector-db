#!/usr/bin/env bash
# MongoDB 就绪探针。
# 写成脚本的原因：wsl.exe 传参时会吃掉反斜杠/破坏引号，--eval 的 JS 无法直接拼在命令行里。
set -uo pipefail

name="$1"
user="$2"
password="$3"
port="${4:-27017}"

output="$(nerdctl exec "$name" mongosh --quiet --port "$port" -u "$user" -p "$password" \
    --authenticationDatabase admin --eval 'db.adminCommand({ping:1}).ok' 2>/dev/null | tr -d '\r' | tail -1)"

[ "$output" = "1" ]
