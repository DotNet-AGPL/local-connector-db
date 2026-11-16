#!/usr/bin/env bash
# ============================================================
#  local-connector-db 制品重建（bin 目录误删后跑这个）
#
#  用法：
#    bash rebuild.sh               按宿主自动选 RID 重建
#                                  Linux→linux-x64 / macOS(Apple Silicon)→osx-arm64
#                                  Windows Git Bash→win-x64
#    bash rebuild.sh win           只重建 win-x64
#    bash rebuild.sh linux         只重建 linux-x64
#    bash rebuild.sh osx           只重建 osx-arm64
#    bash rebuild.sh all           重建三平台（win-x64 + linux-x64 + osx-arm64）
#    bash rebuild.sh verify        只校验宿主平台的现存制品
#    bash rebuild.sh verify all    只校验三平台
#
#  前置（构建时）：.NET SDK 11、PowerShell 7+（pwsh）。首次构建需联网
#  （拉 NuGet 包与 PublishAotCross 的 Zig / MacOSX.SDK 工具链）。
#  校验模式只用 bash。
# ============================================================
set -uo pipefail

cd "$(dirname "$0")" || exit 1

LIBS=(sqlite mysql postgres duckdb clickhouse redis dm mongo sqlserver oracle)

detect_host_rid() {
    local kernel machine
    kernel="$(uname -s 2>/dev/null || true)"
    machine="$(uname -m 2>/dev/null || true)"

    case "$kernel" in
        MINGW* | MSYS* | CYGWIN*)
            echo "win-x64"
            ;;
        Darwin*)
            if [ "$machine" = "arm64" ]; then
                echo "osx-arm64"
            else
                echo "[ERROR] Intel Mac（$machine）暂无制品：PublishAotCross 只支持 osx-arm64" >&2
                return 1
            fi
            ;;
        Linux*)
            if [ "$machine" = "x86_64" ] || [ "$machine" = "amd64" ]; then
                echo "linux-x64"
            else
                echo "[ERROR] 当前 Linux 架构 $machine 暂无制品（仅支持 linux-x64）" >&2
                return 1
            fi
            ;;
        *)
            echo "[ERROR] 无法识别宿主平台: ${kernel:-unknown}" >&2
            return 1
            ;;
    esac
}

resolve_rids() {
    if [ "$#" -eq 0 ]; then
        detect_host_rid || exit 1
        return
    fi

    local token
    for token in "$@"; do
        case "$token" in
            all) echo "win-x64 linux-x64 osx-arm64" ;;
            win | win-x64) echo "win-x64" ;;
            linux | linux-x64) echo "linux-x64" ;;
            osx | osx-arm64 | mac | macos) echo "osx-arm64" ;;
            *)
                echo "[ERROR] 未知目标: $token（可选: win / linux / osx / all）" >&2
                exit 2
                ;;
        esac
    done
}

MODE=build
if [ "${1:-}" = "verify" ]; then
    MODE=verify
    shift
fi

RID_LIST="$(resolve_rids "$@")" || exit $?
# shellcheck disable=SC2206  # 有意按空格拆分成数组
RIDS=($RID_LIST)

if [ "${#RIDS[@]}" -eq 0 ]; then
    echo "[ERROR] 没有可构建的目标"
    exit 1
fi

echo "============================================"
echo " local-connector-db 制品重建"
echo "============================================"

if [ "$MODE" = "build" ]; then
    command -v dotnet >/dev/null 2>&1 || { echo "[ERROR] 找不到 dotnet，请安装 .NET SDK 11"; exit 1; }
    command -v pwsh >/dev/null 2>&1 || { echo "[ERROR] 找不到 pwsh（PowerShell 7+）"; exit 1; }
    [ -f build.ps1 ] || { echo "[ERROR] 当前目录不像仓库根目录（缺 build.ps1）"; exit 1; }
    echo "[i] dotnet SDK : $(dotnet --version)"
else
    [ -d bin ] || { echo "[ERROR] 找不到 bin 目录"; exit 1; }
fi

echo "[i] 目标 RID   : ${RIDS[*]}"
[ "$MODE" = "verify" ] && echo "[i] 模式       : 仅校验"
echo

if [ "$MODE" = "build" ]; then
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
# osx-arm64：sqlserver 用 macOS 系统 ICU，同样不需要 app-local ICU
echo "==> 校验产物"
missing=0
osx_hint=0

for db in "${LIBS[@]}"; do
    for rid in "${RIDS[@]}"; do
        dir="bin/${db}-${rid}"

        if ! compgen -G "${dir}/db-${db}*" >/dev/null; then
            echo "[MISS] ${dir} 缺少可执行文件"
            missing=1
            continue
        fi

        if [ "$rid" != "win-x64" ]; then
            [ -x "${dir}/db-${db}" ] || echo "[WARN] ${dir}/db-${db} 没有执行权限（chmod +x 修）"
        fi

        if [ "${db}-${rid}" = "sqlserver-linux-x64" ] && ! compgen -G "${dir}/*icu*" >/dev/null; then
            echo "[MISS] ${dir} 缺少 ICU 文件"
            missing=1
        fi

        if [ "$rid" = "osx-arm64" ]; then
            osx_hint=1
        fi
    done
done

if [ "$missing" = "1" ]; then
    echo "[ERROR] 有制品缺失，见上面的 [MISS]"
    exit 1
fi

if [ "$osx_hint" = "1" ]; then
    echo
    echo "[i] macOS：从别的机器拷贝/下载的制品会带 quarantine 标记，首次运行前执行"
    echo "    xattr -dr com.apple.quarantine bin/<db>-osx-arm64"
fi

echo "[i] bin 总大小 : $(du -sm bin 2>/dev/null | cut -f1) MB"
echo
echo "[OK] 制品重建完成"
