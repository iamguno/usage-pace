#!/bin/bash
# 앱 아이콘(.icns) 생성: tools/make_icon.swift로 크기별 PNG를 그린 뒤 iconutil로 묶음
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp tools/make_icon.swift "$TMP/"
swiftc -swift-version 5 -parse-as-library "$TMP/make_icon.swift" -o "$TMP/make_icon"
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  "$TMP/make_icon" bars-dark "$SET/icon_${s}x${s}.png" $s
  "$TMP/make_icon" bars-dark "$SET/icon_${s}x${s}@2x.png" $((s*2))
done
mkdir -p Assets
iconutil -c icns "$SET" -o Assets/AppIcon.icns
"$TMP/make_icon" bars-dark Assets/AppIcon-1024.png 1024
echo "✅ Assets/AppIcon.icns"
