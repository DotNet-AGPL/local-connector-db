#!/usr/bin/env bash
# 清理指定端口的残留 CNI 分配。
# 场景：容器被删掉/VM 重启后，/var/lib/cni/results 里可能留下旧记录，
# 导致重新创建时报 "port is already allocated"，而 ss 看不到任何监听。
set -euo pipefail

port="$1"

# 1) 删除已不存在容器的 CNI result 记录
running="$(nerdctl ps -q 2>/dev/null || true)"
for file in /var/lib/cni/results/bridge-default-*; do
    [ -e "$file" ] || continue
    id="$(basename "$file" | sed 's/^bridge-default-//' | cut -c1-64)"
    if ! printf '%s\n' "$running" | grep -q "$id"; then
        rm -f "$file"
    fi
done

# 2) 删除该端口的残留 DNAT 跳转规则（只动 CNI 链，不碰用户自己的容器规则）
if command -v iptables >/dev/null 2>&1; then
    while :; do
        num="$(iptables -t nat -L CNI-HOSTPORT-DNAT --line-numbers -n 2>/dev/null \
            | awk -v p="$port" 'index($0, p) > 0 { print $1; exit }')"
        [ -z "${num:-}" ] && break
        iptables -t nat -D CNI-HOSTPORT-DNAT "$num" || break
    done

    for chain in $(iptables -t nat -S 2>/dev/null \
        | awk -v p="--dport $port" '$0 ~ p { for (i = 1; i <= NF; i++) if ($i == "-j") print $(i + 1) }' \
        | sort -u); do
        iptables -t nat -F "$chain" 2>/dev/null || true
        iptables -t nat -X "$chain" 2>/dev/null || true
    done
fi
