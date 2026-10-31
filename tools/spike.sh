#!/bin/bash
# tools/spike.sh — P0 探针：验证访达扩展能否把菜单项插到右键菜单顶层
#   bash tools/spike.sh install   构建并安装探针
#   bash tools/spike.sh status    查看扩展进程与日志
#   bash tools/spike.sh remove    卸载探针
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP="$ROOT/build/ZZSpike.app"
APPEX="$APP/Contents/PlugIns/ZZSpikeExt.appex"
DEST="$HOME/Applications/ZZSpike.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
EXT_ID="com.adam.findertoolbox.spike.finder"
CONTAINER_LOG="$HOME/Library/Containers/$EXT_ID/Data/Documents/spike.log"

build() {
    /bin/rm -rf "$APP"
    /bin/mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS"
    /bin/mkdir -p "$ROOT/build/spike-src"

    /bin/cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.adam.findertoolbox.spike</string>
<key>CFBundleExecutable</key><string>ZZSpike</string>
<key>CFBundleName</key><string>ZZSpike</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

    /bin/cat >"$APPEX/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.adam.findertoolbox.spike.finder</string>
<key>CFBundleExecutable</key><string>ZZSpikeExt</string>
<key>CFBundleName</key><string>ZZSpikeExt</string>
<key>CFBundleDisplayName</key><string>ZZSpike</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSExtension</key><dict>
  <key>NSExtensionPointIdentifier</key><string>com.apple.FinderSync</string>
  <key>NSExtensionPrincipalClass</key><string>ZZSpikeExt.ZZSpikeExtension</string>
  <key>NSExtensionAttributes</key><dict/>
</dict>
</dict></plist>
PLIST

    /bin/cat >"$ROOT/build/spike-src/main.swift" <<'SWIFT'
import Cocoa
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
app.run()
SWIFT

    /bin/cat >"$ROOT/build/spike-src/appex.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
</dict></plist>
PLIST

    /bin/cat >"$ROOT/build/spike-src/host.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST

    echo "编译宿主…"
    /usr/bin/swiftc -O -module-name ZZSpikeHost -target "arm64-apple-macos13.0" \
        -framework Cocoa -o "$APP/Contents/MacOS/ZZSpike" "$ROOT/build/spike-src/main.swift" || return 1

    echo "编译扩展…"
    /usr/bin/swiftc -O -parse-as-library -application-extension \
        -module-name ZZSpikeExt -target "arm64-apple-macos13.0" \
        -framework Cocoa -framework FinderSync \
        -Xlinker -e -Xlinker _NSExtensionMain \
        -o "$APPEX/Contents/MacOS/ZZSpikeExt" "$ROOT/ui/spike/ZZSpikeExt.swift" || return 1

    /bin/chmod +x "$APP/Contents/MacOS/ZZSpike" "$APPEX/Contents/MacOS/ZZSpikeExt"
    /bin/echo -n 'APPL????' >"$APP/Contents/PkgInfo"
    /bin/echo -n 'XPC!????' >"$APPEX/Contents/PkgInfo"

    echo "签名…"
    /usr/bin/codesign --force --sign - \
        --identifier "$EXT_ID" --entitlements "$ROOT/build/spike-src/appex.entitlements" "$APPEX" || return 1
    /usr/bin/codesign --force --sign - \
        --identifier com.adam.findertoolbox.spike --entitlements "$ROOT/build/spike-src/host.entitlements" "$APP" || return 1

    /usr/bin/codesign --verify --strict "$APPEX" || return 1
    /usr/bin/codesign --verify --deep --strict "$APP" || return 1
    echo "构建完成：$APP"
}

install_spike() {
    build || { echo "构建失败"; exit 1; }
    /usr/bin/pkill -f "ZZSpikeExt.appex" 2>/dev/null
    /bin/rm -rf "$DEST"
    /usr/bin/ditto "$APP" "$DEST"
    /usr/bin/xattr -c "$DEST" 2>/dev/null

    "$LSREG" -f "$DEST" 2>/dev/null
    /usr/bin/pluginkit -a "$DEST/Contents/PlugIns/ZZSpikeExt.appex" 2>&1
    /usr/bin/open -g "$DEST"
    sleep 2
    /usr/bin/pluginkit -e use -i "$EXT_ID" 2>&1
    echo "election rc=$?"
    /usr/bin/killall Finder 2>/dev/null
    sleep 2

    echo
    echo "扩展进程：$(/usr/bin/pgrep -fl ZZSpikeExt.appex | head -2)"
    echo "容器日志：$CONTAINER_LOG"
    echo
    echo "下一步：在访达里右键空白处，观察是否有「ZZSpike 顶层一 / 顶层二」直接出现在第一层。"
}

status() {
    echo "== 进程 =="; /usr/bin/pgrep -fl ZZSpikeExt.appex || echo "（未运行）"
    echo; echo "== 日志 =="; if [ -f "$CONTAINER_LOG" ]; then /usr/bin/tail -30 "$CONTAINER_LOG"; else echo "（暂无，说明还没触发菜单）"; fi
    echo; echo "== 系统日志（近 5 分钟）=="
    /usr/bin/log show --last 5m --predicate 'subsystem == "com.adam.findertoolbox.spike"' --style compact 2>/dev/null | /usr/bin/tail -10
}

remove_spike() {
    /usr/bin/pkill -f "ZZSpikeExt.appex" 2>/dev/null
    /usr/bin/pluginkit -r "$DEST/Contents/PlugIns/ZZSpikeExt.appex" 2>/dev/null
    /bin/rm -rf "$DEST"
    "$LSREG" -u "$DEST" 2>/dev/null
    /bin/rm -rf "$HOME/Library/Containers/$EXT_ID"
    /usr/bin/killall Finder 2>/dev/null
    echo "探针已移除"
}

case "${1:-install}" in
    install) install_spike ;;
    status) status ;;
    remove) remove_spike ;;
    *) echo "用法：bash tools/spike.sh [install|status|remove]" ;;
esac
