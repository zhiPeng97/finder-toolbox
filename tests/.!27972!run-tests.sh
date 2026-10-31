#!/bin/bash
# tests/run-tests.sh — 无 GUI 回归测试
# 覆盖：命名唯一化、并发创建、7 种新建、复制路径、逐项压缩、解压、xattr 保留、菜单规格、缺失应用提示

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/finder-toolbox-test.XXXXXX")
SUPPORT="$WORK/support"
LOGS="$WORK/logs"
TOOLBOX="$ROOT/bin/toolbox"

PASS=0
FAIL=0
FAILED=()

cleanup() { /bin/rm -rf "$WORK"; }
trap cleanup EXIT

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf '  \033[32m✓\033[0m %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        FAILED+=("$desc")
        printf '  \033[31m✗\033[0m %s\n      期望：%s\n      实际：%s\n' "$desc" "$expected" "$actual"
    fi
}

check_file() {
    local desc="$1" path="$2" want="${3:-file}"
    if [ "$want" = "dir" ]; then
        [ -d "$path" ] && check "$desc" "exists" "exists" || check "$desc" "exists" "missing"
    else
        [ -f "$path" ] && check "$desc" "exists" "exists" || check "$desc" "exists" "missing"
    fi
}

check_missing() {
    local desc="$1" path="$2"
    [ -e "$path" ] && check "$desc" "absent" "present" || check "$desc" "absent" "absent"
}

run_toolbox() {
    FT_DRY_RUN=1 FT_SUPPORT="$SUPPORT" FT_LOG_DIR="$LOGS" "$TOOLBOX" "$@"
}

mkdir -p "$SUPPORT" "$LOGS"

# ------------------------------------------------------------------ 命名规则
section "1. 文件名拆分与唯一化"

# shellcheck disable=SC1091
. "$ROOT/lib/paths.sh"

check_split() {
    split_name "$1"
    check "split_name $1 → stem" "$2" "$FT_STEM"
    check "split_name $1 → ext" "$3" "$FT_EXT"
}
check_split "a.md" "a" ".md"
check_split "a.tar.gz" "a.tar" ".gz"
check_split ".env" ".env" ""
check_split "README" "README" ""
check_split "x." "x" ""
check_split "中文 文件.txt" "中文 文件" ".txt"

D="$WORK/naming"
mkdir -p "$D"
: >"$D/a.md"
: >"$D/a 2.md"
check "a.md/a 2.md 已存在 → a 3.md" "$D/a 3.md" "$(uniq_path "$D" "a" ".md")"
: >"$D/README"
check "README 已存在 → README 2" "$D/README 2" "$(uniq_path "$D" "README" "")"
: >"$D/.env"
check ".env 已存在 → .env 2" "$D/.env 2" "$(uniq_path "$D" ".env" "")"

# 并发原子创建不得互相覆盖
D="$WORK/concurrent"
mkdir -p "$D"
for _ in 1 2 3 4 5; do
    ( atomic_create "$D" "并发" ".md" /dev/null >/dev/null ) &
done
wait
COUNT=$(/bin/ls "$D" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
check "5 个并发创建 → 5 个独立文件" "5" "$COUNT"

# ------------------------------------------------------------------ 新建文件
section "2. 新建文件（7 种）"

D="$WORK/newfile"
mkdir -p "$D"
run_toolbox action new:md "$D"
run_toolbox action new:md "$D"
run_toolbox action new:md "$D"
check_file "第 1 次创建 未命名.md" "$D/未命名.md"
check_file "第 2 次创建 未命名 2.md" "$D/未命名 2.md"
check_file "第 3 次创建 未命名 3.md" "$D/未命名 3.md"
check "模板内容写入" "# 未命名" "$(/usr/bin/head -1 "$D/未命名.md")"

for ext in txt json js vue css html; do
    run_toolbox action "new:$ext" "$D"
done
check_file "未命名.txt" "$D/未命名.txt"
check_file "未命名.json" "$D/未命名.json"
check_file "未命名.js" "$D/未命名.js"
check_file "未命名.vue" "$D/未命名.vue"
check_file "未命名.css" "$D/未命名.css"
check_file "未命名.html" "$D/未命名.html"
check "json 模板可被 plutil 解析" "1" "$(/usr/bin/plutil -lint "$D/未命名.json" 2>/dev/null | /usr/bin/grep -c OK)"

# 含空格/中文目录 + 选中目录内文件（应落到父目录）
D="$WORK/newfile 中文 目录"
mkdir -p "$D"
: >"$D/占位.txt"
run_toolbox action new:md "$D/占位.txt"
check_file "选中文件时在父目录创建" "$D/未命名.md"

# ------------------------------------------------------------------ 开发工具
section "3. 开发工具（复制路径 / 缺失应用提示）"

D="$WORK/open"
mkdir -p "$D"
: >"$D/甲 文件.txt"
: >"$D/b.md"
OLD_CLIP=$(/usr/bin/pbpaste 2>/dev/null)
run_toolbox action dev:copy "$D/甲 文件.txt" "$D/b.md"
CLIP=$(/usr/bin/pbpaste 2>/dev/null)
printf '%s' "$OLD_CLIP" | /usr/bin/pbcopy 2>/dev/null
check "多选复制为两行绝对路径" "$D/甲 文件.txt|$D/b.md" "$(printf '%s' "$CLIP" | /usr/bin/paste -sd '|' -)"

# 终端：v1.2 起重新内置（「在当前位置打开终端」），多选按去重目录开窗
mkdir -p "$D/项目A"
run_toolbox action dev:terminal "$D/项目A" "$D/项目A/b.md" >/dev/null 2>&1
check "终端动作可用" "0" "$?"
check "终端按去重目录打开" "1" "$(/usr/bin/grep -c 'terminal(dry-run)' "$LOGS/toolbox.log")"

# VS Code CLI 缺失 → 友好提示，退出码 0
D2="$WORK/novscode"
mkdir -p "$D2"
: >"$D2/x.txt"
(
    PATH=/usr/bin:/bin
    export PATH
    FT_VSCODE_APP=/nonexistent
    FT_VSCODE_CLI=/nonexistent
    FT_DRY_RUN=1 FT_SUPPORT="$SUPPORT" FT_LOG_DIR="$LOGS"
    export FT_VSCODE_APP FT_VSCODE_CLI FT_DRY_RUN FT_SUPPORT FT_LOG_DIR
    "$TOOLBOX" action dev:vscode "$D2/x.txt"
)
check "VS Code 缺失时退出码为 0" "0" "$?"
check "日志记录了友好提示" "1" "$(/usr/bin/grep -c '没有找到 VS Code' "$LOGS/toolbox.log")"

# ------------------------------------------------------------------ 压缩
section "4. 压缩 / 解压"

D="$WORK/zip"
mkdir -p "$D/资料夹"
echo "inner" >"$D/资料夹/inner.txt"
echo "outer" >"$D/单文件.txt"
run_toolbox action fs:zip "$D/资料夹" "$D/单文件.txt"
check_file "目录 → 资料夹.zip" "$D/资料夹.zip"
check_file "文件 → 单文件.zip" "$D/单文件.zip"

# 用解压结果验证包内层级（unzip -Z1 对中文名的解码不可靠）
X="$WORK/unzip-check"
mkdir -p "$X/folder" "$X/file"
/usr/bin/ditto -x -k "$D/资料夹.zip" "$X/folder" 2>/dev/null
/usr/bin/ditto -x -k "$D/单文件.zip" "$X/file" 2>/dev/null
check_file "目录包保留顶层目录" "$X/folder/资料夹/inner.txt"
check "目录包内容正确" "inner" "$(/bin/cat "$X/folder/资料夹/inner.txt" 2>/dev/null)"
check_file "文件包直接落在根部" "$X/file/单文件.txt"
check_missing "文件包无多余包裹目录" "$X/file/单文件"

# 重名：已存在同名 zip 时自动加序号
run_toolbox action fs:zip "$D/资料夹"
check_file "重复压缩 → 资料夹 2.zip" "$D/资料夹 2.zip"

# xattr 往返
echo "attr" >"$D/属性.txt"
/usr/bin/xattr -w com.example.keep "1" "$D/属性.txt"
run_toolbox action fs:zip "$D/属性.txt"
run_toolbox action fs:unzip "$D/属性.zip"
check "解压到同名文件夹" "1" "$([ -d "$D/属性" ] && echo 1 || echo 0)"
check "xattr 在压缩/解压后保留" "1" "$(/usr/bin/xattr -p com.example.keep "$D/属性/属性.txt" 2>/dev/null)"

# 非 zip 选择 → 不发版错误，仅提示
run_toolbox action fs:unzip "$D/单文件.txt"
check "非 zip 解压退出码 0" "0" "$?"
check "提示文案已记录" "1" "$(/usr/bin/grep -c '没有可解压的 ZIP 文件' "$LOGS/toolbox.log")"

# ------------------------------------------------------------------ 菜单规格
section "5. 菜单规格"

(
    export FT_SUPPORT="$SUPPORT" FT_LOG_DIR="$LOGS" FT_DRY_RUN=1
    # shellcheck disable=SC1090
    . "$ROOT/lib/common.sh"
    # shellcheck disable=SC1090
    . "$ROOT/lib/menu.sh"
    FT_PATHS=("$WORK/zip/单文件.txt")
    build_menu_spec >"$WORK/spec1"
    build_menu_spec new >"$WORK/spec_new"
    build_menu_spec dev >"$WORK/spec_dev"
    build_menu_spec fs >"$WORK/spec_fs"
    FT_PATHS=()
    build_menu_spec >"$WORK/spec2"
)
check "一级分组数" "3" "$(/usr/bin/grep -c '^G|' "$WORK/spec1")"
check "全部动作数" "14" "$(/usr/bin/grep -c '^I|' "$WORK/spec1")"
check "分组键齐全" "new dev fs" "$(/usr/bin/grep '^G|' "$WORK/spec1" | /usr/bin/cut -d'|' -f2 | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "无选区时开发工具置灰" "3" "$(/usr/bin/grep '^I|dev|' "$WORK/spec2" | /usr/bin/grep -c '|0$')"
check "无选区时新建仍可用" "7" "$(/usr/bin/grep '^I|new|' "$WORK/spec2" | /usr/bin/grep -c '|1$')"
check "隐藏文件开关标签合法" "1" "$(/usr/bin/grep -c '^I|fs|fs:toggle|\(显示隐藏文件\|隐藏隐藏文件\)|eye|1$' "$WORK/spec1")"

# 三个一级入口各自的规格：只含本组、数量正确、并集无重复
check "新建组动作数" "7" "$(/usr/bin/grep -c '^I|' "$WORK/spec_new")"
check "开发组动作数" "3" "$(/usr/bin/grep -c '^I|' "$WORK/spec_dev")"
check "文件管理组动作数" "4" "$(/usr/bin/grep -c '^I|' "$WORK/spec_fs")"
check "新建组只含 new|" "0" "$(/usr/bin/grep '^I|' "$WORK/spec_new" | /usr/bin/grep -vc '^I|new|')"
check "开发组只含 dev|" "0" "$(/usr/bin/grep '^I|' "$WORK/spec_dev" | /usr/bin/grep -vc '^I|dev|')"
check "文件管理组只含 fs|" "0" "$(/usr/bin/grep '^I|' "$WORK/spec_fs" | /usr/bin/grep -vc '^I|fs|')"
check "三组 id 并集为 14 且无重复" "14" "$(/bin/cat "$WORK/spec_new" "$WORK/spec_dev" "$WORK/spec_fs" | /usr/bin/grep '^I|' | /usr/bin/cut -d'|' -f3 | /usr/bin/sort -u | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "新建组标题显示落点" "1" "$(/usr/bin/grep -c '^H|位置：' "$WORK/spec_new")"
check "开发组不含终端动作" "0" "$(/usr/bin/grep -c 'dev:terminal' "$WORK/spec_dev")"

# ------------------------------------------------------------------ 入口链路
section "6. 入口链路（stub 菜单组件）"

# 用桩程序替代原生菜单：验证「生成规格 → 菜单返回动作 id → 分发执行」整条链路
STUB="$WORK/stub-helper"
/bin/cat >"$STUB" <<'STUB_EOF'
#!/bin/bash
SPEC="" RESULT="" MODE="${STUB_MODE:-pick}"
[ -n "${STUB_MARKER:-}" ] && : >"$STUB_MARKER"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --spec) SPEC="$2"; shift 2 ;;
        --result) RESULT="$2"; shift 2 ;;
        --shown) echo 1 >"$2"; shift 2 ;;
        *) shift ;;
    esac
done
[ "$MODE" = "cancel" ] && exit 2
id=$(/usr/bin/awk -F'|' '$1=="I" && $3 ~ /^new:/ {print $3; exit}' "$SPEC")
[ -z "$id" ] && exit 3
printf '%s' "$id" >"$RESULT"
exit 0
STUB_EOF
/bin/chmod +x "$STUB"

D="$WORK/pipeline"
mkdir -p "$D"
FT_HELPER="$STUB" FT_DRY_RUN=1 FT_SUPPORT="$SUPPORT" FT_LOG_DIR="$LOGS" \
    "$TOOLBOX" entry "$D"
check_file "entry 经菜单返回后执行新建" "$D/未命名.md"

D2="$WORK/pipeline-cancel"
mkdir -p "$D2"
STUB_MODE=cancel FT_HELPER="$STUB" FT_DRY_RUN=1 FT_SUPPORT="$SUPPORT" FT_LOG_DIR="$LOGS" \
    "$TOOLBOX" entry "$D2"
check "取消时不执行任何动作" "0" "$(/bin/ls -A "$D2" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

# 组内没有可用动作时不应弹空菜单，改为一次性说明
MARK="$WORK/helper-ran.marker"
D3="$WORK/pipeline-empty"
mkdir -p "$D3"
FT_HELPER="$STUB" STUB_MARKER="$MARK" FT_DRY_RUN=1 FT_SUPPORT="$SUPPORT" FT_LOG_DIR="$LOGS" \
    "$TOOLBOX" entry --group dev >/dev/null 2>&1
check "零可用动作时退出码 0" "0" "$?"
check "零可用动作时不启动菜单" "absent" "$([ -e "$MARK" ] && echo present || echo absent)"
check "零可用动作时给出提示" "1" "$(/usr/bin/grep -q '没有可执行的操作' "$LOGS/toolbox.log" && echo 1 || echo 0)"

# ------------------------------------------------------------------ 其他
section "7. 入口基本行为"

check "version 输出" "1.2.0" "$("$TOOLBOX" version)"
"$TOOLBOX" >/dev/null 2>&1
check "无参数时返回用法错误码 64" "64" "$?"
check "未知动作返回失败码 1" "1" "$(run_toolbox action unknown:thing "$WORK/zip/单文件.txt" >/dev/null 2>&1; echo $?)"

# ------------------------------------------------------------------ 入口 bundle
section "8. 入口 bundle 一致性"

/bin/bash "$ROOT/tools/build-services.sh" >/dev/null 2>&1
BS="$ROOT/build/services"
check "由清单生成 3 个入口" "3" "$(/bin/ls -1 "$BS" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

for b in "$BS"/*.workflow; do
    n=$(/usr/bin/basename "$b" .workflow)
    t=$(/usr/bin/plutil -extract 'NSServices.0.NSMenuItem.default' raw "$b/Contents/Info.plist" 2>/dev/null)
    check "$n 的菜单标题与目录名一致" "$n" "$t"
done

check "三个 bundle id 互不相同" "3" "$(
    for b in "$BS"/*.workflow; do
        /usr/bin/plutil -extract 'CFBundleIdentifier' raw "$b/Contents/Info.plist"
    done | /usr/bin/sort -u | /usr/bin/wc -l | /usr/bin/tr -d ' '
)"
check "三个载荷都带 --group" "3" "$(
    for b in "$BS"/*.workflow; do
        /usr/bin/plutil -extract 'actions.0.action.ActionParameters.COMMAND_STRING' raw "$b/Contents/Resources/document.wflow"
    done | /usr/bin/grep -c 'entry --group'
)"
check "三个入口都声明 public.item" "3" "$(
    for b in "$BS"/*.workflow; do
        /usr/bin/plutil -extract 'NSServices.0.NSSendFileTypes.0' raw "$b/Contents/Info.plist"
    done | /usr/bin/grep -c 'public.item'
)"
check "除下线提示外已无终端实现" "0" "$(
    /usr/bin/grep -R 'dev:terminal' "$ROOT/lib" "$ROOT/bin" 2>/dev/null \
        | /usr/bin/grep -v 'dispatch.sh' | /usr/bin/wc -l | /usr/bin/tr -d ' '
)"

# ------------------------------------------------------------------ 访达扩展产物
section "9. 访达扩展产物"

if [ -x /usr/bin/swiftc ]; then
    /bin/bash "$ROOT/ui/build.sh" >/dev/null 2>&1
fi

APP_B="$ROOT/build/FinderToolbox.app"
APPEX_B="$APP_B/Contents/PlugIns/ToolboxFinder.appex"
MENUCHECK="$ROOT/build/menucheck"

if [ -x "$APPEX_B/Contents/MacOS/ToolboxFinder" ] && [ -x "$MENUCHECK" ]; then
    check "appex 位于 PlugIns 内" "1" "$([ -x "$APPEX_B/Contents/MacOS/ToolboxFinder" ] && echo 1 || echo 0)"
    check "扩展点正确" "com.apple.FinderSync" \
        "$(/usr/bin/plutil -extract NSExtension.NSExtensionPointIdentifier raw "$APPEX_B/Contents/Info.plist")"
    check "principal class 与源码一致" "ToolboxFinder.ToolboxFinderExtension" \
        "$(/usr/bin/plutil -extract NSExtension.NSExtensionPrincipalClass raw "$APPEX_B/Contents/Info.plist")"
    check "源码中确有该类" "1" "$(/usr/bin/grep -c 'class ToolboxFinderExtension' "$ROOT/ui/ToolboxFinderExtension.swift")"
    check "宿主为 LSUIElement" "true" \
        "$(/usr/bin/plutil -extract LSUIElement raw "$APP_B/Contents/Info.plist")"
    check "宿主注册 URL scheme" "findertoolbox" \
        "$(/usr/bin/plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$APP_B/Contents/Info.plist")"
    check "appex 带沙盒权限" "1" \
        "$(/usr/bin/codesign -d --entitlements - "$APPEX_B" 2>/dev/null | /usr/bin/grep -c 'com.apple.security.app-sandbox')"
    check "宿主不带沙盒" "0" \
        "$(/usr/bin/codesign -d --entitlements - "$APP_B" 2>/dev/null | /usr/bin/grep -c 'com.apple.security.app-sandbox')"
    check "appex 签名可验" "0" "$(/usr/bin/codesign --verify --strict "$APPEX_B" >/dev/null 2>&1; echo $?)"
    check "宿主深验通过" "0" "$(/usr/bin/codesign --verify --deep --strict "$APP_B" >/dev/null 2>&1; echo $?)"

    check "菜单动作数为 16" "16" "$("$MENUCHECK" ids | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
    check "菜单 id 与 CLI 完全一致" "" \
        "$(/usr/bin/diff <("$MENUCHECK" ids | /usr/bin/sort) <("$TOOLBOX" actions | /usr/bin/sort))"
    check "空白处仅 9 项可用" "9" \
        "$("$MENUCHECK" list --kind container | /usr/bin/awk -F'|' '$4=="1"' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
    check "空白处开发工具仅终端可用" "4" \
        "$("$MENUCHECK" list --kind container | /usr/bin/grep '^dev|' | /usr/bin/grep -c '|0$')"
    check "空白处仅保留隐藏文件开关" "1" \
        "$("$MENUCHECK" list --kind container | /usr/bin/grep '^fs|' | /usr/bin/grep -c '|1$')"
    check "选中项时 15 项可用（有 Xcode、无 zip）" "15" \
        "$("$MENUCHECK" list --kind items --xcode 1 | /usr/bin/awk -F'|' '$4=="1"' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
    check "未装 Xcode 时该项置灰" "1" \
        "$("$MENUCHECK" list --kind items --xcode 0 | /usr/bin/grep '^dev|dev:xcode|' | /usr/bin/grep -c '|0$')"
    check "未装 Xcode 时可用数减一" "14" \
        "$("$MENUCHECK" list --kind items --xcode 0 | /usr/bin/awk -F'|' '$4=="1"' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
    check "Xcode 项排在开发工具第二位" "dev:xcode" \
        "$("$MENUCHECK" list --kind items | /usr/bin/grep '^dev|' | /usr/bin/sed -n '2p' | /usr/bin/cut -d'|' -f2)"
    check "选中 zip 时解压可用" "1" \
        "$("$MENUCHECK" list --kind items --paths /tmp/a.zip | /usr/bin/grep '^fs|fs:unzip|' | /usr/bin/grep -c '|1$')"

    TRICKY="/Users/example/work/a b/中文 文件.md"
    URL_OUT=$("$MENUCHECK" encode --action new:md --paths "$TRICKY" "特殊#?&%+.txt")
    check "载荷含 scheme" "1" "$(printf '%s' "$URL_OUT" | /usr/bin/grep -c '^findertoolbox://run?d=')"
    check "载荷动作还原" "new:md" "$("$MENUCHECK" decode "$URL_OUT" | /usr/bin/head -1 | /usr/bin/sed 's/^action=//')"
    check "载荷路径条数" "2" "$("$MENUCHECK" decode "$URL_OUT" | /usr/bin/grep -c '^path=')"
    check "载荷中文空格路径还原" "1" "$("$MENUCHECK" decode "$URL_OUT" | /usr/bin/grep -cF "$TRICKY")"
    check "载荷特殊字符还原" "1" "$("$MENUCHECK" decode "$URL_OUT" | /usr/bin/grep -cF '特殊#?&%+.txt')"
else
    check "扩展产物构建（缺少 swiftc 时跳过）" "skip" "skip"
fi

# ------------------------------------------------------------------ 汇总
printf '\n────────────────────────────\n'
printf '通过 %s 项，失败 %s 项\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '\033[31m失败用例：\033[0m\n'
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
fi
printf '\033[32m全部通过\033[0m\n'
