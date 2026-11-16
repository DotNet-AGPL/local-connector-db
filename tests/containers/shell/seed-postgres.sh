#!/usr/bin/env bash
# 灌入 PostgreSQL 种子数据。种子文件先拷进容器，避免 wsl.exe 传参吃掉重定向。
set -euo pipefail

name="$1"
seed_path="$2"
password="$3"
port="${4:-5432}"

nerdctl cp "$seed_path" "$name:/tmp/lcdb-seed.sql"
nerdctl exec "$name" env PGPASSWORD="$password" \
    psql -h 127.0.0.1 -p "$port" -U postgres -d lcdb -v ON_ERROR_STOP=1 -q -f /tmp/lcdb-seed.sql
