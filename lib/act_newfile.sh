#!/bin/bash
# lib/act_newfile.sh — 新建文件（7 种）

act_new_file() {
    local kind="$1" ext=".${1}" dir tpl target
    case "$kind" in
        md|txt|json|js|vue|css|html) ;;
        *)
            ft_alert "未知的文件类型" "$kind"
            return 1
            ;;
    esac

    if ! dir=$(resolve_target_dir); then
        ft_alert "无法确定目标文件夹" "请先选中一个文件夹（或文件夹内的任意文件）后再试。"
        return 1
    fi
    if [ ! -d "$dir" ]; then
        ft_alert "目标文件夹不存在" "$dir"
        return 1
    fi
    if [ ! -w "$dir" ]; then
        ft_alert "没有写入权限" "无法在以下位置创建文件：\n${dir}"
        return 1
    fi

    tpl="$FT_TEMPLATES/default.$kind"
    [ -f "$tpl" ] || tpl=/dev/null

    if ! target=$(atomic_create "$dir" "${FT_NEW_FILE_BASENAME:-未命名}" "$ext" "$tpl"); then
        ft_alert "创建文件失败" "目标文件夹：\n${dir}"
        return 1
    fi

    ft_log "newfile: $target"
    ft_reveal "$target"
    ft_hud "已创建文件" "$(basename_of "$target")"
}

basename_of() {
    local p="${1%/}"
    printf '%s' "${p##*/}"
}
