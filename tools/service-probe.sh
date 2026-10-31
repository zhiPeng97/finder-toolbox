#!/bin/bash
# tools/service-probe.sh — 探针：判定访达「空白处右键」到底能否出现自定义服务，以及会传入什么对象
#
# 用法：
#   bash tools/service-probe.sh make     生成并安装 ZZProbe.workflow（含 4 种输入形态）
#   bash tools/service-probe.sh clean    移除探针
#   bash tools/service-probe.sh log      查看探针执行日志
#
# 判定方式：在访达里分别「选中文件右键」与「空白处右键」，看四个探针项各出现哪些，
# 再点一次，看桌面是否出现 ZZ探针-时间-argN.txt（N = 服务收到的项目数）。

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPLATE_BUNDLE="$ROOT/build/services/新建文件.workflow"
SERVICES_DIR="$HOME/Library/Services"
PROBE="$SERVICES_DIR/ZZProbe.workflow"
RUNNER="$HOME/.finder-toolbox-probe.sh"
LOG_DIR="$HOME/Library/Logs/FinderToolbox"
LOG="$LOG_DIR/probe.log"
PBS=/System/Library/CoreServices/pbs

usage() {
    /bin/cat <<'EOF'
用法：
  bash tools/service-probe.sh make     安装探针（4 种输入形态）
  bash tools/service-probe.sh clean    移除探针
  bash tools/service-probe.sh log      查看探针日志
EOF
}

write_runner() {
    /bin/cat >"$RUNNER" <<'RUNNER_EOF'
#!/bin/bash
# 探针载荷：记录收到了什么、由谁调用，并在桌面留一个可见证据
# 注意：Automator 的 inputMethod=0 表示路径从 stdin 传入，因此 argv 与 stdin 都要看
LOG_DIR="$HOME/Library/Logs/FinderToolbox"
LOG="$LOG_DIR/probe.log"
args=()
for a in "$@"; do args+=("$a"); done
if [ "${#args[@]}" -eq 0 ] && [ ! -t 0 ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && args+=("$line")
    done
fi
mkdir -p "$LOG_DIR" 2>/dev/null
{
    printf '%s ' "$(/bin/date '+%H:%M:%S')"
    printf 'argc=%s ' "${#args[@]}"
    printf 'ppid=%s\n' "$(/bin/ps -o comm= -p "$PPID" 2>/dev/null)"
    i=1
    for a in ${args[@]+"${args[@]}"}; do
        printf '    arg%d=[%s]\n' "$i" "$a"
        i=$((i + 1))
    done
} >>"$LOG"
/bin/touch "$HOME/Desktop/ZZ探针-$(/bin/date +%H%M%S)-arg${#args[@]}.txt" 2>/dev/null
/usr/bin/osascript -e "display notification \"argc=${#args[@]}\" with title \"ZZ探针已执行\"" >/dev/null 2>&1
exit 0
RUNNER_EOF
    /bin/chmod +x "$RUNNER"
}

write_info_plist() {
    /bin/cat >"$1" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleIdentifier</key>
	<string>com.adam.findertoolbox.probe</string>
	<key>CFBundleName</key>
	<string>ZZProbe</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>ZZ探针-无输入</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
		</dict>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>ZZ探针-文件</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.item</string>
			</array>
		</dict>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>ZZ探针-目录</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.directory</string>
			</array>
		</dict>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>ZZ探针-无输入FilePath</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSTextContent</key>
				<string>FilePath</string>
			</dict>
		</dict>
	</array>
</dict>
</plist>
PLIST_EOF
}

do_make() {
    if [ ! -d "$TEMPLATE_BUNDLE" ]; then
        echo "缺少模板 bundle，先构建：bash tools/build-services.sh" >&2
        /bin/bash "$ROOT/tools/build-services.sh" >/dev/null 2>&1 || exit 1
    fi
    write_runner

    local stage
    stage=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/zzprobe.XXXXXX")
    /usr/bin/ditto "$TEMPLATE_BUNDLE" "$stage/ZZProbe.workflow"
    write_info_plist "$stage/ZZProbe.workflow/Contents/Info.plist"

    # 把载荷换成探针脚本（其余 action 结构沿用已验证的模板）
    /usr/bin/plutil -replace 'actions.0.action.ActionParameters.COMMAND_STRING' -string \
        'exec /bin/bash "$HOME/.finder-toolbox-probe.sh" "$@"' \
        "$stage/ZZProbe.workflow/Contents/Resources/document.wflow" || {
        echo "替换载荷失败" >&2
        exit 1
    }

    /bin/rm -rf "$PROBE"
    /usr/bin/ditto "$stage/ZZProbe.workflow" "$PROBE"
    /usr/bin/xattr -c "$PROBE" 2>/dev/null || true
    /bin/rm -rf "$stage"

    "$PBS" -update >/dev/null 2>&1 || true
    /usr/bin/touch "$SERVICES_DIR"
    sleep 2
    /usr/bin/killall Finder >/dev/null 2>&1 || true
    sleep 1

    echo "探针已安装：$PROBE"
    echo
    echo "请在访达里做三次观察（每次只记录看到了什么）："
    echo "  A. 打开一个文件夹窗口（例如 work），在【空白处】右键 → 快速操作"
    echo "  B. 选中一个【文件】右键 → 快速操作"
    echo "  C. 选中一个【文件夹】右键 → 快速操作"
    echo
    echo "四个探针项：无输入 / 文件 / 目录 / 无输入FilePath —— 分别记下哪些出现。"
    echo "然后点其中任意一个，看桌面是否出现 ZZ探针-时间-argN.txt（N 表示服务收到的项目数）。"
    echo
    echo "查看详细日志：bash tools/service-probe.sh log"
}

do_clean() {
    /bin/rm -rf "$PROBE"
    /bin/rm -f "$RUNNER"
    "$PBS" -update >/dev/null 2>&1 || true
    /usr/bin/touch "$SERVICES_DIR" 2>/dev/null || true
    sleep 2
    /usr/bin/killall Finder >/dev/null 2>&1 || true
    echo "探针已移除（日志保留在 ${LOG} ）"
}

do_log() {
    if [ -f "$LOG" ]; then
        /usr/bin/tail -40 "$LOG"
    else
        echo "暂无日志（${LOG} ）——说明还没有点过探针项"
    fi
}

case "${1:-}" in
    make) do_make ;;
    clean) do_clean ;;
    log) do_log ;;
    *) usage ;;
esac
