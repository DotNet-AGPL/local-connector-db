#!/usr/bin/env bash
# 在 WSL 内部起一个脱离会话的常驻进程，避免 VM 因空闲被回收导致容器被停掉。
set -euo pipefail

setsid sleep 7200 >/dev/null 2>&1 < /dev/null &
echo "keepalive started: $!"
