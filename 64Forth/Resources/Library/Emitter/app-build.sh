#!/bin/sh
# Build a stand-alone .app: emit-run + 64EMIT02 image in Resources/app.img.
# Public domain. Pattern mirrors TCOM *-build.sh / app-build.sh.template.
#
#   ./app-build.sh NAME image.img [out-dir]
#   ./app-build.sh Gfx EmitterSmoke/gfx.img
#   → ./Gfx.app  (or out-dir/Gfx.app)
set -e

NAME="${1:?usage: app-build.sh NAME image.img [out-dir]}"
IMG="${2:?usage: app-build.sh NAME image.img [out-dir]}"
OUT="${3:-.}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$ROOT/runner"
BIN="$(basename "$NAME")"
APP_DIR="$OUT/$BIN.app"

if [ ! -f "$IMG" ]; then
  echo "app-build: image not found: $IMG" >&2
  exit 1
fi

# 1) Build / refresh emit-run
( cd "$RUNNER" && ./build-run.sh )

# 2) Bundle
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$RUNNER/emit-run" "$APP_DIR/Contents/MacOS/$BIN"
chmod +x "$APP_DIR/Contents/MacOS/$BIN"
cp "$IMG" "$APP_DIR/Contents/Resources/app.img"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$BIN</string>
  <key>CFBundleIdentifier</key><string>com.win32forth.64emitter.$BIN</string>
  <key>CFBundleName</key><string>$BIN</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>0.6</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# Optional icon: NAME.png beside the requested name path, or ./BIN.png
PNG=""
if [ -f "${NAME}.png" ]; then PNG="${NAME}.png"
elif [ -f "$OUT/$BIN.png" ]; then PNG="$OUT/$BIN.png"
elif [ -f "$BIN.png" ]; then PNG="$BIN.png"
fi
if [ -n "$PNG" ]; then
  ICONSET="$OUT/$BIN.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  sips -z 16 16     "$PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32     "$PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64     "$PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256   "$PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512   "$PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/$BIN.icns"
  rm -rf "$ICONSET"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $BIN" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $BIN" "$APP_DIR/Contents/Info.plist"
  echo "Icon: $PNG → $APP_DIR/Contents/Resources/$BIN.icns"
fi

codesign --force -s - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
echo "  image: $APP_DIR/Contents/Resources/app.img"
echo "Run: open $APP_DIR"
echo "Headless: EMIT_HEADLESS=1 $APP_DIR/Contents/MacOS/$BIN"
