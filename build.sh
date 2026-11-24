#!/bin/zsh
# Builds Thermal Map.app and installs it to /Applications. No Xcode needed (Command Line Tools swiftc).
set -e
cd "${0:A:h}"
APP="build/Thermal Map.app"
mkdir -p build
swiftc -O -swift-version 5 Sources/**/*.swift -o build/ThermalMap
if [[ ! -f build/AppIcon.icns ]]; then
  swiftc -O Tools/icon.swift -o build/iconmaker && ./build/iconmaker build/icon1024.png
  rm -rf build/AppIcon.iconset && mkdir build/AppIcon.iconset
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon1024.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon1024.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/ThermalMap "$APP/Contents/MacOS/ThermalMap"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Thermal Map</string>
  <key>CFBundleDisplayName</key><string>Thermal Map</string>
  <key>CFBundleIdentifier</key><string>com.lou15.thermalmap</string>
  <key>CFBundleExecutable</key><string>ThermalMap</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"
DEST="${DEST:-/Applications}"
if [[ -w "$DEST/Thermal Map.app" ]]; then
  # bundle is owned by louis, so it can be refreshed in place without touching root-owned /Applications
  rsync -a --delete "$APP/" "$DEST/Thermal Map.app/"
else
  mkdir -p "$DEST" && rm -rf "$DEST/Thermal Map.app" && cp -R "$APP" "$DEST/"
fi
echo "installed $DEST/Thermal Map.app"
