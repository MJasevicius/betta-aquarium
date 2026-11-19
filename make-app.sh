#!/bin/zsh
# Builds "Betta Aquarium.app" (with an icon the fish draws itself) and puts it in ~/Applications.
#
#   ./make-app.sh
#
# Then open it from there (or Spotlight), and turn on "Open at Login" in the fish's menu.

set -e
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/BettaAquarium"
NAME="Betta Aquarium"
APP="dist/$NAME.app"

rm -rf "$APP" dist/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist/AppIcon.iconset
cp "$BIN" "$APP/Contents/MacOS/BettaAquarium"

# the icon: the fish just after it has drawn itself
"$BIN" --icon dist/icon_1024.png
for s in 16 32 128 256 512; do
    sips -z $s $s dist/icon_1024.png --out "dist/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) dist/icon_1024.png --out "dist/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>io.github.mjasevicius.betta-aquarium</string>
    <key>CFBundleExecutable</key><string>BettaAquarium</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocationUsageDescription</key><string>To find the weather and the times of sunrise and sunset where you are, if you ask it to.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>To find the weather and the times of sunrise and sunset where you are, if you ask it to.</string>
</dict>
</plist>
EOF

# the screen saver: the same tank, built from the same sources (all but the app's own), inside the app,
# which installs it from its settings
SAVER="dist/$NAME.saver"
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS"
S=Sources/BettaAquarium
swiftc -Ounchecked -module-name BettaSaver -emit-library -o "$SAVER/Contents/MacOS/BettaSaver" \
    $S/Fish.swift $S/Tables.swift $S/Motion.swift $S/Betta.swift $S/Tank.swift $S/Renderer.swift $S/Scenery.swift \
    $S/Life.swift $S/Settings.swift $S/Weather.swift $S/Lighting.swift Saver/SaverView.swift \
    -framework ScreenSaver -framework MetalKit
cat > "$SAVER/Contents/Info.plist" <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>io.github.mjasevicius.betta-aquarium.saver</string>
    <key>CFBundleExecutable</key><string>BettaSaver</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>NSPrincipalClass</key><string>BettaSaverView</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF2
codesign --force --sign - "$SAVER" 2>/dev/null
cp -R "$SAVER" "$APP/Contents/Resources/"

codesign --force --sign - "$APP" 2>/dev/null

mkdir -p ~/Applications
rm -rf ~/Applications/"$NAME.app"
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/$NAME.app"
