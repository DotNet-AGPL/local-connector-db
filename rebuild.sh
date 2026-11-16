#!/usr/bin/env bash
# ============================================================
#  local-connector-db 制品重建（bin 目录误删后跑这个）
#
#  用法：
#    bash rebuild.sh          重建 win-x64 + linux-x64 全部制品
#    bash rebuild.sh linux    只重建 linux-x64
#    bash rebuild.sh win      只重建 win-x64（从 Linux 交叉编译 win 未验证）
#    bash rebuild.sh verify   只校验现有制品，不构建
#
#  前置（构建时）：.NET SDK 11、PowerShell 7+（pwsh）。首次构建需联网。
#  校验模式只用 bash，不需要上面两者。
# ============================================================
set -uo pipefail

cd "$(dirname "$0")" || exit 1

DO_BUILD=1
case "${1:-}" in
    win | win-x64) RIDS=(win-x64) ;;
    linux | linux-x64) RIDS=(linux-x64) ;;
    verify) RIDS=(win-x64 linux-x64); DO_BUILD=0 ;;
    *) RIDS=(win-x64 linux-x64); DO_BUILD=1 ;;
esac

LIBS=(sqlite mysql postgres duckdb clickhouse redis dm mongo sqlserver oracle)

echo "============================================"
echo " local-connector-db 制品重建"
echo "============================================"

if [ "$DO_BUILD" = "1" ]; then
    command -v dotnet >/dev/null 2>&1 || { echo "[ERROR] 找不到 dotnet，请安装 .NET SDK 11"; exit 1; }
    command -v pwsh >/dev/null 2>&1 || { echo "[ERROR] 找不到 pwsh（PowerShell 7+）"; exit 1; }
    [ -f build.ps1 ] || { echo "[ERROR] 当前目录不像 skill 根目录（缺 build.ps1）"; exit 1; }
    echo "[i] dotnet SDK : $(dotnet --version)"
else
    [ -d bin ] || { echo "[ERROR] 找不到 bin 目录"; exit 1; }
fi

echo "[i] 目标 RID   : ${RIDS[*]}"
[ "$DO_BUILD" = "0" ] && echo "[i] 模式       : 仅校验"
echo

if [ "$DO_BUILD" = "1" ]; then
    for rid in "${RIDS[@]}"; do
        for db in "${LIBS[@]}"; do
            echo "==> 构建 ${db} (${rid})"
            if ! pwsh -NoProfile -File build.ps1 -Only "$db" -Rid "$rid" -Clean; then
                # 偶发文件锁（MSB4175 / file is being used by another process），重试一次
                echo "[WARN] ${db} (${rid}) 首次失败，关闭编译服务后重试"
                dotnet build-server shutdown >/dev/null 2>&1 || true
                sleep 3
                if ! pwsh -NoProfile -File build.ps1 -Only "$db" -Rid "$rid" -Clean; then
                    echo "[ERROR] ${db} (${rid}) 构建失败"
                    exit 1
                fi
            fi
        done
    done
    echo
fi

# win-x64：全部走系统 NLS / 不变模式，不需要 ICU 文件
# linux-x64：只有 sqlserver 是非不变全球化，必须带 app-local ICU
echo "==> 校验产物"
missing=0
for db in "${LIBS[@]}"; do
    for rid in "${RIDS[@]}"; do
        dir="bin/${db}-${rid}"
        if ! compgen -G "${dir}/db-${db}*" >/dev/null; then
            echo "[MISS] ${dir} 缺少可执行文件"
            missing=1
            continue
        fi
        if [ "$rid" = "linux-x64" ]; then
            [ -x "${dir}/db-${db}" ] || echo "[WARN] ${dir}/db-${db} 没有执行权限（chmod +x 修）"
        fi
        if [ "${db}-${rid}" = "sqlserver-linux-x64" ]; then
            if ! compgen -G "${dir}/*icu*" >/dev/null; then
                echo "[MISS] ${dir} 缺少 ICU 文件"
                missing=1
            fi
        fi
    done
done

if [ "$missing" = "1" ]; then
    echo "[ERROR] 有制品缺失，见上面的 [MISS]"
    exit 1
fi

echo "[i] bin 总大小 : $(du -sm bin 2>/dev/null | cut -f1) MB"
echo
echo "[OK] 制品重建完成"
