#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=DurableQueuerDashboardSample
BUNDLE_ID=com.example.DurableQueuerDashboardSample
MACOS_MIN_VERSION=13.0

source "$ROOT/version.env"

ARCH=${ARCH:-$(uname -m)}
swift build -c "$CONF" --arch "$ARCH"

APP="$ROOT/${APP_NAME}.app"
BUILD_DIR=$(swift build -c "$CONF" --arch "$ARCH" --show-bin-path)
EXECUTABLE="$BUILD_DIR/$APP_NAME"

if [[ ! -f "$EXECUTABLE" ]]; then
  echo "ERROR: Missing executable at $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>DurableQueuer Dashboard Sample</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

shopt -s nullglob
RESOURCE_BUNDLES=("$BUILD_DIR"/*.bundle)
shopt -u nullglob
for bundle in "${RESOURCE_BUNDLES[@]}"; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

xattr -cr "$APP"
codesign --force --sign - "$APP"

echo "Created $APP"
