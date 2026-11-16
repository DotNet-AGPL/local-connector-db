#!/usr/bin/env bash
# 就绪探针：必须真正认证成功才算就绪。
# 不能用 mysqladmin ping：它在 "Access denied" 时同样返回 0，会在初始化临时实例阶段误判。
set -euo pipefail

name="$1"
password="$2"

nerdctl exec "$name" mysql --default-character-set=utf8mb4 -uroot -p"$password" -e 'SELECT 1' >/dev/null 2>&1
