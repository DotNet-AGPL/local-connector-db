#!/usr/bin/env bash
# 释放被残留进程占用的端口（例如上次 CNI portmap 的 sleep 看守进程）。
set -uo pipefail

port="$1"

if command -v ss >/dev/null 2>&1; then
    pids="$(ss -lntp 2>/dev/null | awk -v p=":$port" 'index($0, p) { if (match($0, /pid=[0-9]+/)) print substr($0, RSTART + 4, RLENGTH - 4) }' | sort -u)"
    for pid in $pids; do
        echo "killing pid $pid holding :$port"
        kill -9 "$pid" 2>/dev/null || true
    done
fi
