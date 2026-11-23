#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
APP_PATH=${1:-"$ROOT_DIR/build/Sleepless.app"}
CONTENTS="$APP_PATH/Contents"
PLIST="$CONTENTS/Info.plist"
RESOURCES="$CONTENTS/Resources"

if [ ! -f "$PLIST" ]; then
    printf '%s\n' "App Info.plist not found: $PLIST" >&2
    exit 1
fi
ICON_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")
if [ "$ICON_NAME" != "AppIcon" ]; then
    printf '%s\n' "Unexpected CFBundleIconFile: $ICON_NAME" >&2
    exit 1
fi
ICON_PATH="$RESOURCES/$ICON_NAME.icns"
if [ ! -s "$ICON_PATH" ]; then
    printf '%s\n' "Referenced icon resource is missing or empty: $ICON_PATH" >&2
    exit 1
fi
CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sleepless-icon-check.XXXXXX")
trap 'rm -rf "$CHECK_DIR"' EXIT HUP INT TERM
ICONSET_PATH="$CHECK_DIR/AppIcon.iconset"
iconutil -c iconset -o "$ICONSET_PATH" "$ICON_PATH"

for representation in \
    'icon_16x16.png 16' 'icon_16x16@2x.png 32' \
    'icon_32x32.png 32' 'icon_32x32@2x.png 64' \
    'icon_128x128.png 128' 'icon_128x128@2x.png 256' \
    'icon_256x256.png 256' 'icon_256x256@2x.png 512' \
    'icon_512x512.png 512' 'icon_512x512@2x.png 1024'
do
    set -- $representation
    IMAGE_PATH="$ICONSET_PATH/$1"
    EXPECTED_SIZE=$2
    if [ ! -s "$IMAGE_PATH" ] || ! sips -g pixelWidth -g pixelHeight "$IMAGE_PATH" | awk -v size="$EXPECTED_SIZE" '/pixelWidth:/ {width=$2} /pixelHeight:/ {height=$2} END {exit !(width == size && height == size)}'; then
        printf '%s\n' "Invalid or missing icon representation: $IMAGE_PATH (expected ${EXPECTED_SIZE}x${EXPECTED_SIZE})" >&2
        exit 1
    fi
done

printf 'Verified %s and all 10 icon sizes in %s\n' "$ICON_PATH" "$APP_PATH"