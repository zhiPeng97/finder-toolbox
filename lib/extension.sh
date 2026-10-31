#!/bin/bash
# lib/extension.sh — 访达扩展的安装 / 注册 / 启用 / 状态 / 卸载
# 被 install.sh、uninstall.sh、toolbox selftest 共用

FT_APP_DIR="$HOME/Applications"
FT_APP="$FT_APP_DIR/FinderToolbox.app"
FT_APPEX="$FT_APP/Contents/PlugIns/ToolboxFinder.appex"
FT_EXT_ID="com.adam.findertoolbox.finder"
FT_LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

ft_ext_installed() {
    [ -x "$FT_APP/Contents/MacOS/FinderToolbox" ]
}

# 安装/覆盖 App 并注册扩展（不含启用判定）
# 注意：升级时不要 pluginkit -r，否则会丢掉用户的启用选举，需要重新勾选
ft_ext_install() {
    /usr/bin/pkill -f "ToolboxFinder.appex" 2>/dev/null || true
    /bin/mkdir -p "$FT_APP_DIR"
    /bin/rm -rf "$FT_APP"
    /usr/bin/ditto "$1" "$FT_APP" || return 1
    /usr/bin/xattr -c "$FT_APP" 2>/dev/null || true

    "$FT_LSREGISTER" -f "$FT_APP" 2>/dev/null || true
    /usr/bin/pluginkit -a "$FT_APPEX" 2>/dev/null || true
    /usr/bin/open -g "$FT_APP" 2>/dev/null || true
    sleep 1
    /usr/bin/pluginkit -e use -i "$FT_EXT_ID" 2>/dev/null || true
    /usr/bin/killall Finder 2>/dev/null || true
    sleep 2
    return 0
}

# 输出 app=/appex=/enabled=0|1
ft_ext_status() {
    ft_ext_installed || return 1
    "$FT_APP/Contents/MacOS/FinderToolbox" --status 2>/dev/null
}

ft_ext_enabled() {
    if ft_ext_installed && "$FT_APP/Contents/MacOS/FinderToolbox" --status >/dev/null 2>&1; then
        return 0
    fi
    /usr/bin/pgrep -f "ToolboxFinder.appex" >/dev/null 2>&1
}

ft_ext_open_settings() {
    ft_ext_installed && "$FT_APP/Contents/MacOS/FinderToolbox" --open-settings >/dev/null 2>&1
}

ft_ext_uninstall() {
    /usr/bin/pkill -f "ToolboxFinder.appex" 2>/dev/null || true
    /usr/bin/pluginkit -r "$FT_APPEX" 2>/dev/null || true
    /bin/rm -rf "$FT_APP"
    "$FT_LSREGISTER" -u "$FT_APP" 2>/dev/null || true
    /bin/rm -rf "$HOME/Library/Containers/$FT_EXT_ID" 2>/dev/null || true
    /usr/bin/killall Finder 2>/dev/null || true
    return 0
}

# 把隐藏文件状态同步给扩展（扩展据此显示「显示/隐藏隐藏文件」）
ft_write_hidden_state() {
    local state="$1"
    local dir="$HOME/Library/Containers/$FT_EXT_ID/Data/Library/Application Support/FinderToolbox"
    /bin/mkdir -p "$dir" 2>/dev/null || return 0
    printf '%s' "$state" >"$dir/hidden-state" 2>/dev/null || true
    return 0
}
