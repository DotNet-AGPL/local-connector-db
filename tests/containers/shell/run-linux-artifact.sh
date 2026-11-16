#!/usr/bin/env bash
# 在 WSL 内验证 linux-x64 制品。
# /mnt/c 没有执行位，必须先拷到 ~ 再 chmod；整目录拷贝，保证原生库（如 libduckdb.so）同目录。
set -euo pipefail

library="$1"
shift

repo_root="${LCDB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
src_dir="$repo_root/bin/${library}-linux-x64"
dst_dir="$HOME/lcdb-test/${library}"

rm -rf "$dst_dir"
mkdir -p "$dst_dir"
cp -r "$src_dir"/. "$dst_dir"/
chmod +x "$dst_dir/db-${library}"

exec "$dst_dir/db-${library}" "$@"
