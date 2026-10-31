#!/bin/bash
# lib/common.sh — 常量、日志、提示、单实例锁
# 注意：本机 PATH 中存在覆盖 zip 等命令的 shim，所有外部命令一律使用绝对路径。

FT_VERSION="1.2.0"
FT_APP_TITLE="Finder 工具箱"

FT_SUPPORT="${FT_SUPPORT:-$HOME/Library/Application Support/FinderToolbox}"
FT_LOG_DIR="${FT_LOG_DIR:-$HOME/Library/Logs/FinderToolbox}"
FT_LOG="$FT_LOG_DIR/toolbox.log"
FT_STATE="$FT_SUPPORT/state"
FT_HELPER="${FT_HELPER:-$FT_SUPPORT/ui/ToolboxMenu.app/Contents/MacOS/ToolboxMenu}"
FT_TEMPLATES="$FT_SUPPORT/templates"

FT_OPEN=/usr/bin/open
FT_DITTO=/usr/bin/ditto
FT_DEFAULTS=/usr/bin/defaults
FT_KILLALL=/usr/bin/killall
FT_OSASCRIPT=/usr/bin/osascript
FT_PBCOPY=/usr/bin/pbcopy
FT_MKDIR=/bin/mkdir
FT_RMDIR=/bin/rmdir
FT_RM=/bin/rm
FT_CAT=/bin/cat
FT_MV=/bin/mv
FT_DATE=/bin/date
FT_STAT=/usr/bin/stat
FT_PBS=/System/Library/CoreServices/pbs
FT_UNAME=/usr/bin/uname

# ---- 可覆盖默认值（依次被 config.sh 覆盖）----
: "${FT_TERMINAL_APP:=/System/Applications/Utilities/Terminal.app}"
: "${FT_XCODE_APP:=}"
: "${FT_VSCODE_APP:=/Applications/Visual Studio Code.app}"
: "${FT_VSCODE_CLI:=}"
: "${FT_HBUILDERX_APP:=/Applications/HBuilderX.app}"
: "${FT_NEW_FILE_BASENAME:=未命名}"
: "${FT_MENU_TIMEOUT:=300}"          # 菜单可保持打开的最长秒数
: "${FT_MENU_START_TIMEOUT:=5}"      # 等待菜单弹出的秒数，超时降级
: "${FT_SELECT_TIMEOUT:=5}"          # 向 Finder 询问选区的超时秒数
: "${FT_USE_INSERTION_LOCATION:=1}"  # 无选区时是否向 Finder 询问当前文件夹
: "${FT_TOGGLE_METHOD:=relaunch}"    # relaunch | prefonly
: "${FT_COPY_TRAILING_SLASH:=0}"     # 复制路径时是否给目录补尾斜杠
: "${FT_NOTIFY:=1}"                  # 是否发送成功提示
: "${FT_DRY_RUN:=0}"                 # 1 = 不弹窗、不打开 Finder（用于自动化测试）

[ -r "$FT_SUPPORT/config.sh" ] && . "$FT_SUPPORT/config.sh"

FT_PATHS=()
FT_LOCK_HELD=0
FT_GROUP=""

ft_log() {
    [ -d "$FT_LOG_DIR" ] || "$FT_MKDIR" -p "$FT_LOG_DIR" 2>/dev/null
    if [ -f "$FT_LOG" ]; then
        local size
        size=$("$FT_STAT" -f%z "$FT_LOG" 2>/dev/null || echo 0)
        [ "${size:-0}" -gt 524288 ] && "$FT_MV" -f "$FT_LOG" "$FT_LOG.1" 2>/dev/null
    fi
    printf '%s [%s] %s\n' "$("$FT_DATE" '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >>"$FT_LOG" 2>/dev/null
    return 0
}

# ft_alert "标题" "补充说明" —— 阻塞式对话框，任何环境都能显示
ft_alert() {
    local msg="${1:-操作失败}" info="${2:-}"
    ft_log "ALERT: $msg | $info"
    [ "${FT_DRY_RUN:-0}" = "1" ] && return 0
    [ -d "${TMPDIR:-/tmp}" ] || TMPDIR=/tmp
    local tmp="$TMPDIR/finder-toolbox-alert.$$.applescript"
    "$FT_CAT" >"$tmp" <<'APPLESCRIPT'
on run argv
	set msgText to item 1 of argv
	set infoText to item 2 of argv
	set appTitle to item 3 of argv
	set body to my lfToCr(msgText)
	if infoText is not "" then set body to body & return & return & my lfToCr(infoText)
	display dialog body buttons {"好"} default button 1 with icon caution with title appTitle
end run

on lfToCr(t)
	set out to ""
	repeat with i from 1 to count of characters of t
		set ch to character i of t
		if ch is linefeed then
			set out to out & return
		else
			set out to out & ch
		end if
	end repeat
	return out
end lfToCr
APPLESCRIPT
    "$FT_OSASCRIPT" "$tmp" "$msg" "$info" "$FT_APP_TITLE" >/dev/null 2>&1
    local rc=$?
    "$FT_RM" -f "$tmp"
    return $rc
}

# ft_hud "标题" ["副标题"] —— 非阻塞成功提示
ft_hud() {
    local title="${1:-开发者工具箱}" sub="${2:-}"
    ft_log "HUD: $title | $sub"
    [ "${FT_DRY_RUN:-0}" = "1" ] && return 0
    [ "${FT_NOTIFY:-1}" = "1" ] || return 0
    [ -d "${TMPDIR:-/tmp}" ] || TMPDIR=/tmp
    local tmp="$TMPDIR/finder-toolbox-hud.$$.applescript"
    "$FT_CAT" >"$tmp" <<'APPLESCRIPT'
on run argv
	set theTitle to item 1 of argv
	set theSub to item 2 of argv
	set appTitle to item 3 of argv
	if theSub is "" then
		display notification theTitle with title appTitle
	else
		display notification theSub with title appTitle
	end if
end run
APPLESCRIPT
    "$FT_OSASCRIPT" "$tmp" "$title" "$sub" "$FT_APP_TITLE" >/dev/null 2>&1
    "$FT_RM" -f "$tmp"
    return 0
}

# ft_reveal <路径…> —— 在 Finder 中定位（自动化测试下跳过）
ft_reveal() {
    [ "${FT_DRY_RUN:-0}" = "1" ] && return 0
    "$FT_OPEN" -R "$@" >/dev/null 2>&1
    return 0
}

ft_lock_path() {
    printf '%s/menu.lock%s' "$FT_STATE" "${FT_GROUP:+.$FT_GROUP}"
}

ft_lock_acquire() {
    local lock
    lock=$(ft_lock_path)
    [ -d "$FT_STATE" ] || "$FT_MKDIR" -p "$FT_STATE" 2>/dev/null
    if "$FT_MKDIR" "$lock" 2>/dev/null; then
        FT_LOCK_HELD=1
        printf '%s' "$$" >"$lock/pid" 2>/dev/null
        return 0
    fi
    local pid
    pid=$("$FT_CAT" "$lock/pid" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    "$FT_RM" -rf "$lock" 2>/dev/null
    "$FT_MKDIR" "$lock" 2>/dev/null || return 1
    FT_LOCK_HELD=1
    printf '%s' "$$" >"$lock/pid" 2>/dev/null
    return 0
}

ft_lock_release() {
    if [ "${FT_LOCK_HELD:-0}" = "1" ]; then
        "$FT_RM" -rf "$(ft_lock_path)" 2>/dev/null
        FT_LOCK_HELD=0
    fi
}
