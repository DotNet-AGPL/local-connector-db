#!/usr/bin/env bash
# Oracle 就绪探针（容器内置 sqlplus）。
# sqlplus -s 的输出会带前后空白，必须裁掉再做精确匹配。
set -uo pipefail

name="$1"
password="$2"
service="${3:-FREEPDB1}"
port="${4:-1521}"

output="$(nerdctl exec "$name" bash -lc \
    "echo 'SELECT 1 FROM DUAL;' | sqlplus -s system/${password}@//localhost:${port}/${service}" 2>/dev/null \
    | tr -d '\r\t' | tr -s ' ' | sed 's/^ *//; s/ *$//' | grep -E '^1$' | head -1)"

[ "$output" = "1" ]
