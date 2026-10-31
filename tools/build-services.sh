#!/bin/bash
# tools/build-services.sh — 由 manifest + 模板生成三个 Quick Action bundle
# 输出：build/services/<标题>.workflow
# 这样三份 bundle 不会各自漂移：标题、bundle id、载荷 --group 都来自同一份清单。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/services/manifest.tsv"
TEMPLATE_DIR="$ROOT/services/template"
OUT_DIR="$ROOT/build/services"
VERSION=$(/bin/cat "$ROOT/VERSION")

[ -f "$MANIFEST" ] || {
    echo "缺少清单：$MANIFEST" >&2
    exit 1
}

/bin/rm -rf "$OUT_DIR"
/bin/mkdir -p "$OUT_DIR"

while IFS=$'\t' read -r group title bundle_id; do
    [ -z "${group:-}" ] && continue
    case "$group" in \#*) continue ;; esac

    bundle="$OUT_DIR/$title.workflow"
    /bin/mkdir -p "$bundle/Contents/Resources"

    payload='exec "$HOME/Library/Application Support/FinderToolbox/bin/toolbox" entry --group '
    payload="${payload}${group} \"\$@\""

    /usr/bin/sed -e "s|@@TITLE@@|${title}|g" \
        -e "s|@@BUNDLE_ID@@|${bundle_id}|g" \
        -e "s|@@VERSION@@|${VERSION}|g" \
        "$TEMPLATE_DIR/Info.plist.in" >"$bundle/Contents/Info.plist"

    /usr/bin/sed -e "s|@@PAYLOAD@@|${payload}|g" \
        -e "s|@@UUID1@@|$(/usr/bin/uuidgen)|g" \
        -e "s|@@UUID2@@|$(/usr/bin/uuidgen)|g" \
        -e "s|@@UUID3@@|$(/usr/bin/uuidgen)|g" \
        "$TEMPLATE_DIR/document.wflow.in" >"$bundle/Contents/Resources/document.wflow"

    /usr/bin/plutil -lint "$bundle/Contents/Info.plist" >/dev/null
    /usr/bin/plutil -lint "$bundle/Contents/Resources/document.wflow" >/dev/null
    echo "生成 $title.workflow ($bundle_id, --group $group)"
done <"$MANIFEST"

COUNT=$(/bin/ls -1 "$OUT_DIR" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
echo "共 $COUNT 个入口 → $OUT_DIR"
