#!/bin/bash
# lib/act_open.sh — 开发工具：终端 / Xcode / VS Code / HBuilderX / 复制路径

# 解析 Xcode 应用位置：用户配置 → 常见安装位置 → xcode-select 指向
resolve_xcode_app() {
    local c
    for c in "${FT_XCODE_APP:-}" "/Applications/Xcode.app" "/Applications/Xcode-beta.app" "$HOME/Applications/Xcode.app"; do
        if [ -n "$c" ] && [ -d "$c" ]; then
            printf '%s' "$c"
            return 0
        fi
    done
    c=$(/usr/bin/xcode-select -p 2>/dev/null)
    case "$c" in
        */Contents/Developer)
            printf '%s' "${c%/Contents/Developer}"
            return 0
            ;;
    esac
    return 1
}

# 用 Xcode 打开：优先 xed（Xcode 自带 CLI），否则 open -a
act_open_xcode() {
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        ft_alert "请先选择一个文件或文件夹"
        return 1
    fi

    local app
    if ! app=$(resolve_xcode_app); then
        ft_alert "未安装 Xcode" "该操作需要 Xcode：\n• App Store 搜索 Xcode 安装\n• 或只装命令行工具：xcode-select --install\n\n安装完成后右键菜单里的该项会自动变为可用。"
        return 0
    fi

    if [ "${FT_DRY_RUN:-0}" = "1" ]; then
        ft_log "xcode(dry-run): app=$app paths=${FT_PATHS[*]}"
        ft_hud "已在 Xcode 打开" "${#FT_PATHS[@]} 项"
        return 0
    fi

    local xed="$app/Contents/Developer/usr/bin/xed"
    local p
    if [ -x "$xed" ]; then
        for p in "${FT_PATHS[@]}"; do
            "$xed" "$p" >/dev/null 2>&1
        done
    else
        for p in "${FT_PATHS[@]}"; do
            "$FT_OPEN" -a "$app" "$p" >/dev/null 2>&1
        done
    fi

    ft_log "xcode: ${FT_PATHS[*]}"
    ft_hud "已在 Xcode 打开" "${#FT_PATHS[@]} 项"
}

# 数组去重，结果写入 FT_UNIQ
ft_uniq_paths() {
    local p u found
    FT_UNIQ=()
    for p in "$@"; do
        found=0
        for u in ${FT_UNIQ[@]+"${FT_UNIQ[@]}"}; do
            if [ "$u" = "$p" ]; then
                found=1
                break
            fi
        done
        [ "$found" -eq 0 ] && FT_UNIQ+=("$p")
    done
}

# 在当前位置打开终端：多选时按去重后的目录开窗，不会炸出一堆窗口
act_open_terminal() {
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        ft_alert "请先选择一个文件或文件夹"
        return 1
    fi
    local p app dirs=()
    for p in "${FT_PATHS[@]}"; do
        if [ -d "$p" ]; then
            dirs+=("$p")
        else
            dirs+=("$(dirname_safe "$p")")
        fi
    done
    ft_uniq_paths ${dirs[@]+"${dirs[@]}"}

    app="${FT_TERMINAL_APP:-/System/Applications/Utilities/Terminal.app}"
    [ -d "$app" ] || app="/System/Applications/Utilities/Terminal.app"

    if [ "${FT_DRY_RUN:-0}" = "1" ]; then
        ft_log "terminal(dry-run): ${FT_UNIQ[*]}"
        ft_hud "已在终端中打开" "${#FT_UNIQ[@]} 个位置"
        return 0
    fi

    for p in ${FT_UNIQ[@]+"${FT_UNIQ[@]}"}; do
        "$FT_OPEN" -a "$app" "$p" >/dev/null 2>&1
    done
    ft_log "terminal: ${FT_UNIQ[*]}"
    ft_hud "已在终端中打开" "${#FT_UNIQ[@]} 个位置"
}

# 依次尝试：用户配置 → 常见安装位置 → PATH
resolve_vscode_cli() {
    local c
    if [ -n "${FT_VSCODE_CLI:-}" ] && [ -x "$FT_VSCODE_CLI" ]; then
        printf '%s' "$FT_VSCODE_CLI"
        return 0
    fi
    for c in \
        "${FT_VSCODE_APP:-/Applications/Visual Studio Code.app}/Contents/Resources/app/bin/code" \
        "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
        "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code"; do
        if [ -x "$c" ]; then
            printf '%s' "$c"
            return 0
        fi
    done
    c=$(command -v code 2>/dev/null)
    if [ -n "$c" ] && [ -x "$c" ]; then
        printf '%s' "$c"
        return 0
    fi
    return 1
}

act_open_vscode() {
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        ft_alert "请先选择一个文件或文件夹"
        return 1
    fi
    unset VSCODE_IPC_HOOK_CLI

    local cli
    if ! cli=$(resolve_vscode_cli); then
        ft_alert "没有找到 VS Code 命令行工具" "已安装 VS Code 但未注册 code 命令时，请打开 VS Code：\n1. 按 ⇧⌘P 打开命令面板\n2. 执行 Shell Command: Install 'code' command in PATH\n\n若尚未安装，请访问 code.visualstudio.com 下载。"
        return 0
    fi

    local p all_dirs=1
    for p in "${FT_PATHS[@]}"; do
        if [ ! -d "$p" ]; then
            all_dirs=0
            break
        fi
    done

    if [ "${FT_DRY_RUN:-0}" = "1" ]; then
        ft_log "vscode(dry-run): cli=$cli all_dirs=$all_dirs paths=${FT_PATHS[*]}"
        ft_hud "已在 VS Code 打开" "${#FT_PATHS[@]} 项"
        return 0
    fi

    if [ "$all_dirs" = "1" ] && [ "${#FT_PATHS[@]}" -gt 1 ]; then
        "$cli" -n "${FT_PATHS[@]}" >/dev/null 2>&1
    else
        "$cli" "${FT_PATHS[@]}" >/dev/null 2>&1
    fi
    ft_log "vscode: ${FT_PATHS[*]}"
    ft_hud "已在 VS Code 打开" "${#FT_PATHS[@]} 项"
}

act_open_hbuilderx() {
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        ft_alert "请先选择一个文件或文件夹"
        return 1
    fi
    local app="$FT_HBUILDERX_APP"
    if [ ! -d "$app" ]; then
        for app in "/Applications/HBuilderX.app" "$HOME/Applications/HBuilderX.app"; do
            [ -d "$app" ] && break
        done
    fi
    if [ ! -d "$app" ]; then
        ft_alert "没有找到 HBuilderX" "请确认已安装 HBuilderX（默认位置 /Applications/HBuilderX.app），或在 config.sh 中修改 FT_HBUILDERX_APP。"
        return 0
    fi
    local p
    if [ "${FT_DRY_RUN:-0}" = "1" ]; then
        ft_log "hbuilderx(dry-run): ${FT_PATHS[*]}"
        ft_hud "已在 HBuilderX 打开" "${#FT_PATHS[@]} 项"
        return 0
    fi
    for p in "${FT_PATHS[@]}"; do
        "$FT_OPEN" -a "$app" "$p" >/dev/null 2>&1
    done
    ft_log "hbuilderx: ${FT_PATHS[*]}"
    ft_hud "已在 HBuilderX 打开" "${#FT_PATHS[@]} 项"
}

act_copy_path() {
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        ft_alert "请先选择要复制路径的项目"
        return 1
    fi
    local p out=()
    for p in "${FT_PATHS[@]}"; do
        if [ "${FT_COPY_TRAILING_SLASH:-0}" = "1" ] && [ -d "$p" ]; then
            out+=("${p}/")
        else
            out+=("$p")
        fi
    done
    printf '%s\n' "${out[@]}" | "$FT_PBCOPY"
    ft_log "copy-path: ${#out[@]} 项"
    ft_hud "已复制 ${#out[@]} 个绝对路径"
}
