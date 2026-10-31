#!/bin/bash
# ui/build.sh — 构建宿主 App + 访达扩展 + 诊断工具（ad-hoc 签名）
set -euo pipefail

UI_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$UI_DIR/.." && pwd)
APP="$ROOT/build/FinderToolbox.app"
APPEX="$APP/Contents/PlugIns/ToolboxFinder.appex"
SWIFTC=/usr/bin/swiftc
CODESIGN=/usr/bin/codesign
ARCH=$(/usr/bin/uname -m)
TARGET="$ARCH-apple-macos13.0"

[ -x "$SWIFTC" ] || { echo "缺少 swiftc：请安装 Xcode 或 Command Line Tools" >&2; exit 1; }

for plist in "$UI_DIR/Info.host.plist" "$UI_DIR/Info.appex.plist" \
             "$UI_DIR/entitlements.host.plist" "$UI_DIR/entitlements.appex.plist"; do
    /usr/bin/plutil -lint "$plist" >/dev/null
done

/bin/rm -rf "$APP"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
             "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
/usr/bin/ditto "$UI_DIR/Info.host.plist" "$APP/Contents/Info.plist"
/usr/bin/ditto "$UI_DIR/Info.appex.plist" "$APPEX/Contents/Info.plist"
/usr/bin/ditto "$UI_DIR/menu.json" "$APP/Contents/Resources/menu.json"
/usr/bin/ditto "$UI_DIR/menu.json" "$APPEX/Contents/Resources/menu.json"
/bin/echo -n 'APPL????' >"$APP/Contents/PkgInfo"
/bin/echo -n 'XPC!????' >"$APPEX/Contents/PkgInfo"

echo "编译访达扩展…"
"$SWIFTC" -O -parse-as-library -application-extension \
    -module-name ToolboxFinder -target "$TARGET" \
    -framework Cocoa -framework FinderSync \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APPEX/Contents/MacOS/ToolboxFinder" \
    "$UI_DIR/ToolboxMenuModel.swift" "$UI_DIR/ToolboxFinderExtension.swift"

echo "编译宿主…"
"$SWIFTC" -O -parse-as-library \
    -module-name FinderToolbox -target "$TARGET" \
    -framework Cocoa -framework FinderSync \
    -o "$APP/Contents/MacOS/FinderToolbox" \
    "$UI_DIR/ToolboxMenuModel.swift" "$UI_DIR/ToolboxHost.swift"

echo "编译诊断工具…"
"$SWIFTC" -O -parse-as-library \
    -module-name MenuCheck -target "$TARGET" \
    -framework Foundation \
    -o "$ROOT/build/menucheck" \
    "$UI_DIR/ToolboxMenuModel.swift" "$UI_DIR/MenuDiagnostics.swift"

/bin/chmod +x "$APP/Contents/MacOS/FinderToolbox" "$APPEX/Contents/MacOS/ToolboxFinder" "$ROOT/build/menucheck"

echo "签名（内层 appex 先签，外层 App 后签）…"
"$CODESIGN" --force --sign - --identifier com.adam.findertoolbox.finder \
    --entitlements "$UI_DIR/entitlements.appex.plist" "$APPEX" 2>&1 | /usr/bin/grep -v "replacing existing signature" || true
"$CODESIGN" --force --sign - --identifier com.adam.findertoolbox \
    --entitlements "$UI_DIR/entitlements.host.plist" "$APP" 2>&1 | /usr/bin/grep -v "replacing existing signature" || true

# 关键校验：沙盒权限必须真的签进 appex，否则 pkd 不加载（V1.2 踩过这个坑）
if ! "$CODESIGN" -d --entitlements - "$APPEX" 2>/dev/null | /usr/bin/grep -q "com.apple.security.app-sandbox"; then
    echo "错误：appex 缺少 app-sandbox 权限，扩展不会被系统加载" >&2
    exit 1
fi
"$CODESIGN" --verify --strict "$APPEX"
"$CODESIGN" --verify --deep --strict "$APP"

echo "构建完成：$APP"
echo "诊断工具：$ROOT/build/menucheck"
