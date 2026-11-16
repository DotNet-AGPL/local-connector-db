#!/usr/bin/env bash
# 清理 nerdctl 的 name store 残留。
# 场景：创建容器时中途失败（例如端口被占），containerd 里没有这个容器，
# 但 /var/lib/nerdctl/*/names/<ns>/<name> 里留了一条映射，
# 之后重建会报 name "xxx" is already used by ID "yyy"。
set -euo pipefail

name="$1"
namespace="${2:-default}"

for file in /var/lib/nerdctl/*/names/"$namespace"/"$name"; do
    [ -e "$file" ] || continue
    id="$(cat "$file" 2>/dev/null || true)"
    if [ -z "$id" ]; then
        rm -f "$file"
        continue
    fi
    if ! nerdctl inspect "$id" >/dev/null 2>&1; then
        rm -f "$file"
    fi
done
