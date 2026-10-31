#!/bin/bash
# lib/menu.sh — 生成菜单规格（唯一真源：Swift 只负责渲染）
# 规格协议（每行一段，| 分隔）：
#   H|<标题>                                     禁用标题行
#   G|<分组键>|<标题>|<SF Symbol>                 分组（仅在未指定分组时用于建子菜单）
#   I|<分组键>|<动作 id>|<标题>|<SF Symbol>|<0|1>  动作项，末段为启用位
#
# build_menu_spec [group] —— group 为空输出全部分组（三级菜单，供手动调试与对话框降级）；
#                            指定 new|dev|fs 时只输出该组，供三个一级入口平铺渲染。
# 输出后 FT_ENABLED_COUNT = 本次规格中「可用」的动作数。

hidden_files_shown() {
    local v
    v=$("$FT_DEFAULTS" read com.apple.finder AppleShowAllFiles 2>/dev/null) || v=""
    case "$v" in
        1|true|TRUE|True|YES|yes) return 0 ;;
        *) return 1 ;;
    esac
}

has_zip_selection() {
    local p
    for p in ${FT_PATHS[@]+"${FT_PATHS[@]}"}; do
        case "$p" in
            *.zip|*.ZIP|*.Zip) return 0 ;;
        esac
    done
    return 1
}

# 新建文件的落点预览：不调用 AppleScript，避免「弹菜单前先弹授权」
target_dir_hint() {
    local p
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        printf '当前位置'
        return 0
    fi
    if [ "${#FT_PATHS[@]}" -eq 1 ] && [ -d "${FT_PATHS[0]}" ]; then
        printf '%s' "${FT_PATHS[0]}"
        return 0
    fi
    p="${FT_PATHS[0]%/}"
    case "$p" in
        */*) p="${p%/*}"; [ -z "$p" ] && p="/" ;;
        *) p="." ;;
    esac
    printf '%s' "$p"
}

build_menu_spec() {
    local only="${1:-}"
    local has_paths=0 toggle_title header out=""

    [ "${#FT_PATHS[@]}" -gt 0 ] && has_paths=1

    if hidden_files_shown; then
        toggle_title="隐藏隐藏文件"
    else
        toggle_title="显示隐藏文件"
    fi

    if [ "$only" = "new" ]; then
        header="位置：$(target_dir_hint)"
    elif [ "$has_paths" = "1" ]; then
        header="已选择 ${#FT_PATHS[@]} 项"
    else
        header="未选择项目"
    fi
    out="${out}H|${header}"$'\n'

    if [ -z "$only" ] || [ "$only" = "new" ]; then
        out="${out}G|new|新建文件|square.and.pencil"$'\n'
        out="${out}I|new|new:md|Markdown (.md)|text.document|1"$'\n'
        out="${out}I|new|new:txt|文本文件 (.txt)|doc.text|1"$'\n'
        out="${out}I|new|new:json|JSON 文件 (.json)|curlybraces|1"$'\n'
        out="${out}I|new|new:js|JavaScript (.js)|chevron.left.forwardslash.chevron.right|1"$'\n'
        out="${out}I|new|new:vue|Vue 组件 (.vue)|square.stack.3d.up.fill|1"$'\n'
        out="${out}I|new|new:css|样式表 (.css)|paintbrush.pointed|1"$'\n'
        out="${out}I|new|new:html|HTML 页面 (.html)|globe|1"$'\n'
    fi

    # 开发工具：终端已由系统「新建位于文件夹的终端窗口」提供，不再内置
    if [ -z "$only" ] || [ "$only" = "dev" ]; then
        out="${out}G|dev|开发工具|hammer"$'\n'
        out="${out}I|dev|dev:vscode|用 VS Code 打开|chevron.left.forwardslash.chevron.right|${has_paths}"$'\n'
        out="${out}I|dev|dev:hbuilderx|用 HBuilderX 打开|hammer.fill|${has_paths}"$'\n'
        out="${out}I|dev|dev:copy|复制绝对路径|doc.on.doc|${has_paths}"$'\n'
    fi

    if [ -z "$only" ] || [ "$only" = "fs" ]; then
        local unzip_flag=0
        has_zip_selection && unzip_flag=1
        out="${out}G|fs|文件管理|archivebox"$'\n'
        out="${out}I|fs|fs:zip|压缩为 ZIP|archivebox|${has_paths}"$'\n'
        if [ "$unzip_flag" = "1" ]; then
            out="${out}I|fs|fs:unzip|解压 ZIP|shippingbox|1"$'\n'
        else
            out="${out}I|fs|fs:unzip|解压 ZIP（需选中 .zip）|shippingbox|0"$'\n'
        fi
        out="${out}I|fs|fs:toggle|${toggle_title}|eye|1"$'\n'
        out="${out}I|fs|fs:reveal|在 Finder 中定位|scope|${has_paths}"$'\n'
    fi

    printf '%s' "$out"
    FT_ENABLED_COUNT=$(printf '%s' "$out" | /usr/bin/grep -c '^I|.*|1$')
    [ -z "$FT_ENABLED_COUNT" ] && FT_ENABLED_COUNT=0
    return 0
}
