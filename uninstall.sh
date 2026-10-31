#!/bin/bash
# uninstall.sh — 卸载访达扩展、宿主 App、运行时，并还原系统设置
set -euo pipefail

SUPPORT="$HOME/Library/Application Support/FinderToolbox"
SERVICES_DIR="$HOME/Library/Services"
LOG_DIR="$HOME/Library/Logs/FinderToolbox"
PBS=/System/Library/CoreServices/pbs

KEEP_HIDDEN=0
PURGE_LOGS=0
for arg in "$@"; do
    case "$arg" in
        --keep-hidden-pref) KEEP_HIDDEN=1 ;;
        --purge-logs) PURGE_LOGS=1 ;;
        *)
            echo "未知参数：$arg" >&2
            echo "用法：./uninstall.sh [--keep-hidden-pref] [--purge-logs]" >&2
            exit 64
            ;;
    esac
done

echo "正在卸载 Finder 工具箱…"

if [ -f "$SUPPORT/lib/common.sh" ] && [ -f "$SUPPORT/lib/extension.sh" ]; then
    # shellcheck disable=SC1091
    . "$SUPPORT/lib/common.sh"
    # shellcheck disable=SC1091
    . "$SUPPORT/lib/extension.sh"
    ft_ext_uninstall
    echo "  ✓ 已移除访达扩展与宿主 App"
fi

for name in 新建文件 开发工具 文件管理 开发者工具箱; do
    if [ -d "$SERVICES_DIR/$name.workflow" ]; then
        /bin/rm -rf "$SERVICES_DIR/$name.workflow"
        echo "  ✓ 已移除服务入口：$name"
    fi
done

if [ "$KEEP_HIDDEN" = "0" ] && [ -f "$SUPPORT/state/original_hidden_pref" ]; then
    ORIGINAL=$(/bin/cat "$SUPPORT/state/original_hidden_pref")
    if [ "$ORIGINAL" = "UNSET" ] || [ -z "$ORIGINAL" ]; then
        /usr/bin/defaults delete com.apple.finder AppleShowAllFiles 2>/dev/null || true
        echo "  ✓ 已还原隐藏文件设置为系统默认"
    else
        /usr/bin/defaults write com.apple.finder AppleShowAllFiles -bool "$ORIGINAL" 2>/dev/null || true
        echo "  ✓ 已还原隐藏文件设置为 $ORIGINAL"
    fi
else
    [ "$KEEP_HIDDEN" = "1" ] && echo "  · 保留当前隐藏文件设置"
fi

/bin/rm -rf "$SUPPORT"
echo "  ✓ 已移除运行时文件"

if [ "$PURGE_LOGS" = "1" ]; then
    /bin/rm -rf "$LOG_DIR"
    echo "  ✓ 已移除日志"
else
    echo "  · 日志保留在 $LOG_DIR"
fi

"$PBS" -update >/dev/null 2>&1 || true
/usr/bin/touch "$SERVICES_DIR" 2>/dev/null || true
sleep 1
/usr/bin/killall Finder >/dev/null 2>&1 || true
echo "卸载完成。"
