#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
APP_PATH="$ROOT_DIR/build/Sleepless.app"
CONTENTS="$APP_PATH/Contents"
EXECUTABLE="$CONTENTS/MacOS/Sleepless"
PRODUCT="$ROOT_DIR/.build/release/Sleepless"
ICON_WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sleepless-app-icon.XXXXXX")
ICONSET_DIR="$ICON_WORK_DIR/AppIcon.iconset"
trap 'rm -rf "$ICON_WORK_DIR"' EXIT HUP INT TERM

cd "$ROOT_DIR"
swift build --configuration release
if [ ! -x "$PRODUCT" ]; then
    printf '%s\n' "Expected executable not found: $PRODUCT" >&2
    exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS"
cp "$PRODUCT" "$EXECUTABLE"
chmod 755 "$EXECUTABLE"
mkdir -p "$CONTENTS/Resources"
swift "$ROOT_DIR/Scripts/render-app-icon.swift" "$ICONSET_DIR"
swift "$ROOT_DIR/Scripts/assemble-app-icon.swift" "$ICONSET_DIR" "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Sleepless</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.sleepless.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Sleepless</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist"
"$ROOT_DIR/Scripts/check-app-icon.sh" "$APP_PATH"
if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$APP_PATH"
    codesign --verify --deep --strict "$APP_PATH"
fi

printf 'Created %s\n' "$APP_PATH"