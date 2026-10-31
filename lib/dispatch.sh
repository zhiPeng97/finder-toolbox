#!/bin/bash
# lib/dispatch.sh — 动作 id → 实现函数

# 全部动作 id（供 menucheck / 测试做漂移比对）
FT_ACTION_IDS="new:md new:txt new:json new:js new:vue new:css new:html dev:terminal dev:xcode dev:vscode dev:hbuilderx dev:copy fs:zip fs:unzip fs:toggle fs:reveal"

dispatch() {
    local id="$1"
    ft_log "dispatch: $id (${#FT_PATHS[@]} 项)"

    case "$id" in
        new:md|new:txt|new:json|new:js|new:vue|new:css|new:html)
            act_new_file "${id#new:}"
            ;;
        dev:terminal) act_open_terminal ;;
        dev:vscode) act_open_vscode ;;
        dev:xcode) act_open_xcode ;;
        dev:hbuilderx) act_open_hbuilderx ;;
        dev:copy) act_copy_path ;;
        fs:zip) act_zip ;;
        fs:unzip) act_unzip ;;
        fs:toggle) act_toggle_hidden ;;
        fs:reveal) act_reveal ;;
        *)
            ft_log "unknown action id: $id"
            ft_alert "未知的操作" "$id"
            return 1
            ;;
    esac
}
