#!/bin/bash
# install.sh — 安装/升级 Finder 工具箱（访达扩展版，幂等）
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUPPORT="$HOME/Library/Application Support/FinderToolbox"
LOG_DIR="$HOME/Library/Logs/FinderToolbox"
VERSION=$(/bin/cat "$ROOT/VERSION" 2>/dev/null || echo "0.0.0")
WITH_QUICKACTIONS=0
FINALIZE_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --with-quick-actions) WITH_QUICKACTIONS=1 ;;
        --finalize) FINALIZE_ONLY=1 ;;
    esac
done

STEP=0
step() { STEP=$((STEP + 1)); printf '\n\033[1m[%s] %s\033[0m\n' "$STEP" "$1"; }
ok() { printf '    \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$1"; }
fail() { printf '    \033[31m✗\033[0m %s\n' "$1"; exit 1; }

printf '\033[1mFinder 工具箱 V%s 安装程序（访达扩展版）\033[0m\n' "$VERSION"

if [ "$FINALIZE_ONLY" = "0" ]; then
    step "环境预检"
    [ "$(/usr/bin/uname -s)" = "Darwin" ] || fail "仅支持 macOS"
    [ -x /usr/bin/swiftc ] || fail "缺少 swiftc：请安装 Xcode 或 Command Line Tools"
    [ -w "$HOME/Applications" ] || /bin/mkdir -p "$HOME/Applications"
    ok "macOS $(/usr/bin/sw_vers -productVersion) ($(/usr/bin/uname -m))"

    step "校验与构建"
    for f in "$ROOT"/bin/toolbox "$ROOT"/lib/*.sh "$ROOT"/install.sh "$ROOT"/uninstall.sh "$ROOT"/tools/*.sh; do
        /bin/bash -n "$f" || fail "语法错误：$f"
    done
    ok "Shell 语法检查通过"

    /bin/bash "$ROOT/ui/build.sh" >/dev/null || fail "构建失败（ui/build.sh）"
    ok "宿主 App 与访达扩展构建完成"

    step "安装运行时"
    /bin/mkdir -p "$SUPPORT/state" "$LOG_DIR"
    /bin/rm -rf "$SUPPORT/bin" "$SUPPORT/lib" "$SUPPORT/templates"
    /usr/bin/ditto "$ROOT/bin" "$SUPPORT/bin"
    /usr/bin/ditto "$ROOT/lib" "$SUPPORT/lib"
    /usr/bin/ditto "$ROOT/templates" "$SUPPORT/templates"
    /bin/chmod +x "$SUPPORT/bin/toolbox"
    [ -f "$SUPPORT/config.sh" ] || /usr/bin/ditto "$ROOT/config.example.sh" "$SUPPORT/config.sh"
    ok "运行时：$SUPPORT"
fi

# 载入项目源码树里的库（不用 $SUPPORT 里的旧副本，避免升级时行为不一致）
# shellcheck disable=SC1090
. "$ROOT/lib/common.sh"
# shellcheck disable=SC1090
. "$ROOT/lib/extension.sh"
if [ "$FINALIZE_ONLY" = "1" ]; then
    # 仅收尾时也要把运行时刷新一遍，避免残留旧脚本
    /bin/mkdir -p "$SUPPORT/state" "$LOG_DIR"
    /bin/rm -rf "$SUPPORT/bin" "$SUPPORT/lib" "$SUPPORT/templates"
    /usr/bin/ditto "$ROOT/bin" "$SUPPORT/bin"
    /usr/bin/ditto "$ROOT/lib" "$SUPPORT/lib"
    /usr/bin/ditto "$ROOT/templates" "$SUPPORT/templates"
    /bin/chmod +x "$SUPPORT/bin/toolbox"
fi

if [ ! -f "$SUPPORT/state/original_hidden_pref" ]; then
    /usr/bin/defaults read com.apple.finder AppleShowAllFiles 2>/dev/null \
        >"$SUPPORT/state/original_hidden_pref" || echo "UNSET" >"$SUPPORT/state/original_hidden_pref"
fi

step "安装访达扩展"
ft_ext_install "$ROOT/build/FinderToolbox.app"
if ft_ext_installed; then
    ok "已安装：$FT_APP"
else
    fail "App 安装失败"
fi

ENABLED=0
ft_ext_enabled && ENABLED=1

if [ "$ENABLED" = "1" ]; then
    ok "扩展已启用"
else
    warn "扩展尚未启用（需要你在系统设置里勾选一次）"
fi

step "清理重复入口"
if [ "$ENABLED" = "1" ] && [ "$WITH_QUICKACTIONS" = "0" ]; then
    for name in 新建文件 开发工具 文件管理 开发者工具箱; do
        [ -d "$HOME/Library/Services/$name.workflow" ] && /bin/rm -rf "$HOME/Library/Services/$name.workflow"
    done
    /usr/bin/touch "$HOME/Library/Services" 2>/dev/null || true
    ok "已移除旧版「服务」入口（避免与扩展重复）"
    /usr/bin/killall Finder 2>/dev/null || true
else
    if [ "$WITH_QUICKACTIONS" = "1" ] || [ "$ENABLED" = "0" ]; then
        warn "回退：安装 3 个「服务」入口，保证右键仍可用"
        /bin/bash "$ROOT/tools/build-services.sh" >/dev/null 2>&1 || true
        for name in 新建文件 开发工具 文件管理; do
            if [ -d "$ROOT/build/services/$name.workflow" ]; then
                /bin/rm -rf "$HOME/Library/Services/$name.workflow"
                /usr/bin/ditto "$ROOT/build/services/$name.workflow" "$HOME/Library/Services/$name.workflow"
            fi
        done
        /usr/bin/touch "$HOME/Library/Services" 2>/dev/null || true
        /usr/bin/killall Finder 2>/dev/null || true
    fi
fi

# 同步隐藏文件状态给扩展（决定菜单标题）
if "$FT_DEFAULTS" read com.apple.finder AppleShowAllFiles 2>/dev/null | /usr/bin/grep -qE '^(1|true|YES)$'; then
    ft_write_hidden_state 1
else
    ft_write_hidden_state 0
fi

step "验证"
STATUS=$(ft_ext_status 2>/dev/null || echo "enabled=0")
printf '    %s\n' "$(printf '%s' "$STATUS" | /usr/bin/tr '\n' ' ')"
if [ "$ENABLED" = "1" ]; then
    ok "扩展已就绪"
else
    warn "扩展等待启用"
fi
[ -x "$SUPPORT/bin/toolbox" ] && ok "命令行：$SUPPORT/bin/toolbox"

printf '\n\033[1m安装完成。\033[0m\n'
if [ "$ENABLED" = "1" ]; then
    /bin/cat <<'EOF'

验证：
  1. 右键任意文件 / 文件夹 / 窗口空白处，应直接看到三个一级项：
     新建文件 / 开发工具 / 文件管理
  2. 点「新建文件 → Markdown (.md)」应生成 未命名.md 并选中
  3. 空白处右键时，开发工具与文件管理里需要选中对象的项应为灰色
EOF
else
    /bin/cat <<'EOF'

还需要你手动启用一次（系统要求，无法脚本化）：
  系统设置 → 通用 → 登录项与扩展 → 扩展 → 访达 → 勾选「Finder 工具箱」

启用后执行：
  ./install.sh --finalize      # 清理回退用的「服务」入口，避免两套菜单
EOF
fi
