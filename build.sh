#!/bin/bash
# Usage Pace 빌드 스크립트
# 사용법: ./build.sh            → ~/Applications/UsagePace.app 으로 빌드
#         OUT_DIR=/some/dir ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="UsagePace"
# 번들 ID (GitHub 계정 기반, 바꾸면 사용자 설정이 초기화되니 고정)
BUNDLE_ID="io.github.iamguno.usagepace"
# 버전: 릴리스마다 올림 (CFBundleShortVersionString / CFBundleVersion)
VERSION="${VERSION:-0.1.4}"
BUILD_NUMBER="${BUILD_NUMBER:-5}"
OUT_DIR="${OUT_DIR:-$HOME/Applications}"   # OneDrive 폴더 밖에 빌드 (코드서명 문제 방지)
APP="$OUT_DIR/$APP_NAME.app"

mkdir -p "$OUT_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"

# OneDrive 동기화가 빌드 중 파일을 건드리지 않도록 임시 폴더에 복사해서 컴파일
SRC_TMP="$(mktemp -d)"
trap 'rm -rf "$SRC_TMP"' EXIT
mkdir -p "$SRC_TMP/app" "$SRC_TMP/bridge"
cp Sources/*.swift "$SRC_TMP/app/"
cp Bridge/*.swift "$SRC_TMP/bridge/"

# Apple Silicon + Intel 범용(universal) 빌드. ARCHS="arm64" 로 한쪽만 빌드 가능
ARCHS="${ARCHS:-arm64 x86_64}"
APP_BINS=(); BRIDGE_BINS=()
for arch in $ARCHS; do
  swiftc -swift-version 5 -O -parse-as-library \
    -target "$arch-apple-macos13.0" \
    "$SRC_TMP"/app/*.swift \
    -o "$SRC_TMP/$APP_NAME-$arch" 2> >(grep -v "libswiftCompatibilityPacks" >&2)
  # Claude Code status line 도우미 (Foundation만 사용하는 작은 실행 파일)
  swiftc -swift-version 5 -O \
    -target "$arch-apple-macos13.0" \
    "$SRC_TMP"/bridge/main.swift \
    -o "$SRC_TMP/bridge-$arch" 2> >(grep -v "libswiftCompatibilityPacks" >&2)
  APP_BINS+=("$SRC_TMP/$APP_NAME-$arch"); BRIDGE_BINS+=("$SRC_TMP/bridge-$arch")
done
lipo -create "${APP_BINS[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
lipo -create "${BRIDGE_BINS[@]}" -output "$APP/Contents/Helpers/usagepace-statusline"

# 앱 아이콘 (다시 만들기: ./tools/make_icon.sh)
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 번역 파일 (언어 추가 시 Resources/<코드>.lproj 를 만들면 자동 포함)
LOCALIZATIONS=""
for dir in Resources/*.lproj; do
  plutil -lint "$dir/Localizable.strings" >/dev/null || { echo "❌ 번역 파일 오류: $dir"; exit 1; }
  cp -R "$dir" "$APP/Contents/Resources/"
  LOCALIZATIONS+="    <string>$(basename "$dir" .lproj)</string>"$'\n'
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Usage Pace</string>
  <key>CFBundleDisplayName</key><string>Usage Pace</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
$LOCALIZATIONS  </array>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 배포용: 모든 사용자가 읽을 수 있게 (OneDrive에서 복사하면 권한이 좁아질 수 있음)
chmod -R u+rwX,go+rX,go-w "$APP"
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Helpers/usagepace-statusline"
codesign --force --sign - "$APP"
echo "✅ 빌드 완료: $APP"
