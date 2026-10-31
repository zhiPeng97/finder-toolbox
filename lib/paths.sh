#!/bin/bash
# lib/paths.sh — 路径解析与唯一化
# 本文件不依赖 common.sh，便于单元测试直接 source。

# split_name "a.tar.gz" → FT_STEM="a.tar" FT_EXT=".gz"
# 规则：点开头的名字（.env / .gitignore）与结尾是点的名字视为无扩展名
split_name() {
    local name="$1"
    FT_STEM=""
    FT_EXT=""
    case "$name" in
        .*)   FT_STEM="$name" ;;
        *.)   FT_STEM="${name%.}" ;;
        *.*)  FT_STEM="${name%.*}"; FT_EXT=".${name##*.}" ;;
        *)    FT_STEM="$name" ;;
    esac
    if [ -z "$FT_STEM" ]; then
        FT_STEM="$name"
        FT_EXT=""
    fi
}

# uniq_path <dir> <stem> <ext> —— 输出不冲突的完整路径（a.md → a 2.md → a 3.md）
uniq_path() {
    local dir="$1" stem="$2" ext="$3" candidate n=2
    candidate="${stem}${ext}"
    while [ -e "$dir/$candidate" ] || [ -L "$dir/$candidate" ]; do
        candidate="${stem} ${n}${ext}"
        n=$((n + 1))
        [ "$n" -gt 999 ] && break
    done
    printf '%s/%s' "$dir" "$candidate"
}

# uniq_dir <parent> <name> —— 目录版唯一化
uniq_dir() {
    uniq_path "$1" "$2" ""
}

# dirname_safe <path>
dirname_safe() {
    local p="${1%/}"
    case "$p" in
        */*)
            p="${p%/*}"
            [ -z "$p" ] && p="/"
            printf '%s' "$p"
            ;;
        *) printf '%s' "." ;;
    esac
}

# insert_location —— 向 Finder 询问当前文件夹（首次会触发自动化授权）
insert_location() {
    local out
    out=$(/usr/bin/osascript -e 'tell application "Finder" to get POSIX path of (insertion location as alias)' 2>/dev/null)
    out="${out%/}"
    [ -n "$out" ] && printf '%s' "$out"
}

# resolve_target_dir —— 依据当前选区决定「新建文件」落在哪里
# 规则：唯一选中且为目录 → 该目录；否则取第一项的父目录；零参数 → 询问 Finder
resolve_target_dir() {
    if [ "${#FT_PATHS[@]}" -eq 0 ]; then
        [ "${FT_USE_INSERTION_LOCATION:-1}" = "1" ] || return 1
        local d
        d=$(insert_location) || return 1
        [ -n "$d" ] || return 1
        printf '%s' "$d"
        return 0
    fi
    if [ "${#FT_PATHS[@]}" -eq 1 ] && [ -d "${FT_PATHS[0]}" ]; then
        printf '%s' "${FT_PATHS[0]}"
        return 0
    fi
    dirname_safe "${FT_PATHS[0]}"
}

# atomic_create <dir> <stem> <ext> <template> —— 原子占位创建，绝不覆盖已有文件
atomic_create() {
    local dir="$1" stem="$2" ext="$3" tpl="$4"
    local n=1 candidate target
    while [ "$n" -le 999 ]; do
        if [ "$n" -eq 1 ]; then
            candidate="${stem}${ext}"
        else
            candidate="${stem} ${n}${ext}"
        fi
        target="$dir/$candidate"
        if ( set -o noclobber; "$FT_CAT_OR_CAT" "$tpl" >"$target" ) 2>/dev/null; then
            printf '%s' "$target"
            return 0
        fi
        n=$((n + 1))
    done
    return 1
}

# cat 的绝对路径在未 source common.sh 时也要可用
FT_CAT_OR_CAT="${FT_CAT_OR_CAT:-/bin/cat}"
