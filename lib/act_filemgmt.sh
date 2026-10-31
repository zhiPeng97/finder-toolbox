#!/bin/bash
# lib/act_filemgmt.sh — 压缩 / 解压 / 切换隐藏文件 / 在 Finder 中定位

act_zip() {
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        ft_alert "请先选择要压缩的文件或文件夹"
        return 1
    fi
    ft_hud "正在压缩" "${#FT_PATHS[@]} 项"
    ft_log "zip start: ${FT_PATHS[*]}"

    local p d b out
    local created=() failed=()
    for p in "${FT_PATHS[@]}"; do
        if [ ! -e "$p" ]; then
            failed+=("${p##*/}")
            continue
        fi
        d=$(dirname_safe "$p")
        b="${p##*/}"
        split_name "$b"
        [ -z "$FT_STEM" ] && FT_STEM="$b"
        out=$(uniq_path "$d" "$FT_STEM" ".zip")

        if [ -d "$p" ]; then
            # 目录保留自身层级，与 Finder「压缩」行为一致
            if "$FT_DITTO" -c -k --sequesterRsrc --keepParent "$p" "$out" 2>>"$FT_LOG"; then
                created+=("$out")
            else
                "$FT_RM" -f "$out" 2>/dev/null
                failed+=("$b")
            fi
        else
            # 文件不保留父级，避免包里多一层同名目录
            if "$FT_DITTO" -c -k --sequesterRsrc "$p" "$out" 2>>"$FT_LOG"; then
                created+=("$out")
            else
                "$FT_RM" -f "$out" 2>/dev/null
                failed+=("$b")
            fi
        fi
    done

    ft_log "zip done: created=${#created[@]} failed=${#failed[@]}"
    if [ "${#failed[@]}" -gt 0 ]; then
        local joined
        joined=$(printf '%s\n' "${failed[@]}")
        ft_alert "部分项目压缩失败" "失败：\n${joined}\n\n常见原因：权限不足、磁盘空间不足或源文件已被移动。"
        return 1
    fi
    if [ "${#created[@]}" -gt 0 ]; then
        ft_reveal "${created[@]}"
        ft_hud "已压缩 ${#created[@]} 项" "每个项目各自生成独立 zip"
    fi
}

act_unzip() {
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        ft_alert "请先选择要解压的 ZIP 文件"
        return 1
    fi

    local p zips=() other=0
    for p in "${FT_PATHS[@]}"; do
        case "$p" in
            *.zip|*.ZIP|*.Zip) zips+=("$p") ;;
            *) other=$((other + 1)) ;;
        esac
    done

    if [ "${#zips[@]}" -eq 0 ]; then
        ft_alert "没有可解压的 ZIP 文件" "当前选择中包含 ${other} 个项目，但都不是 .zip 文件。V1.0 仅支持 ZIP 格式。"
        return 0
    fi

    ft_log "unzip start: ${zips[*]}"
    local d b stem dest
    local created=() failed=()
    for p in "${zips[@]}"; do
        d=$(dirname_safe "$p")
        b="${p##*/}"
        stem="${b%.*}"
        [ -z "$stem" ] && stem="$b"
        dest=$(uniq_dir "$d" "$stem")

        # mkdir 不带 -p：原子占位，避免并发解压撞名
        if ! "$FT_MKDIR" "$dest" 2>/dev/null; then
            failed+=("$b")
            continue
        fi
        if "$FT_DITTO" -x -k "$p" "$dest" 2>>"$FT_LOG"; then
            created+=("$dest")
        else
            "$FT_RMDIR" "$dest" 2>/dev/null
            failed+=("$b")
        fi
    done

    ft_log "unzip done: created=${#created[@]} failed=${#failed[@]}"
    if [ "${#failed[@]}" -gt 0 ]; then
        local joined
        joined=$(printf '%s\n' "${failed[@]}")
        ft_alert "部分 ZIP 解压失败" "失败：\n${joined}\n\n常见原因：压缩包已加密、文件损坏或磁盘空间不足。"
    fi
    if [ "${#created[@]}" -gt 0 ]; then
        ft_reveal "${created[@]}"
        ft_hud "已解压 ${#created[@]} 个压缩包" "解压到同名文件夹"
    fi
    if [ "$other" -gt 0 ] && [ "${#failed[@]}" -eq 0 ]; then
        ft_log "unzip skipped non-zip: $other"
    fi
}

act_toggle_hidden() {
    local new_value label
    if hidden_files_shown; then
        new_value="false"
        label="隐藏隐藏文件"
    else
        new_value="true"
        label="显示隐藏文件"
    fi

    if ! "$FT_DEFAULTS" write com.apple.finder AppleShowAllFiles -bool "$new_value" 2>>"$FT_LOG"; then
        ft_alert "无法修改 Finder 偏好设置" "请检查当前用户是否拥有偏好设置写入权限。"
        return 1
    fi
    ft_log "toggle hidden: $new_value (method=${FT_TOGGLE_METHOD:-relaunch})"
    if [ "$new_value" = "true" ]; then
        ft_write_hidden_state 1
    else
        ft_write_hidden_state 0
    fi

    if [ "${FT_TOGGLE_METHOD:-relaunch}" = "relaunch" ]; then
        # 偏好已落盘，Finder 重启不影响本进程；延后重启避免回执异常
        ( sleep 0.4; "$FT_KILLALL" Finder >/dev/null 2>&1 ) >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
    ft_hud "$label" "Finder 即将刷新"
}

act_reveal() {
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        ft_alert "请先选择要定位的项目"
        return 1
    fi
    local p existing=()
    for p in "${FT_PATHS[@]}"; do
        [ -e "$p" ] && existing+=("$p")
    done
    if [ "${#existing[@]}" -eq 0 ]; then
        ft_alert "项目已不存在" "选中的文件或文件夹可能已被移动或删除。"
        return 1
    fi
    ft_reveal "${existing[@]}"
    ft_log "reveal: ${#existing[@]} 项"
}
