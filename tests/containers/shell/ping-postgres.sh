#!/usr/bin/env bash
# 就绪探针：必须真正认证并查到数据才算就绪（pg_isready 不校验认证）。
# 注意要显式 -h/-p：容器里的 psql 默认走 5432 的 Unix socket，而我们把端口改成了 15432。
set -euo pipefail

name="$1"
password="$2"
port="${3:-5432}"

nerdctl exec "$name" env PGPASSWORD="$password" \
    psql -h 127.0.0.1 -p "$port" -U postgres -d lcdb -t -A -c 'SELECT 1' >/dev/null 2>&1
