#!/bin/sh
# Build a release binary and wrap it in DeskDragon.app (no Dock icon, launches like a normal Mac app).
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -v "search path" | tail -2
APP=DeskDragon.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DeskDragon "$APP/Contents/MacOS/DeskDragon"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>DeskDragon</string>
  <key>CFBundleIdentifier</key><string>dev.maxwell.deskdragon</string>
  <key>CFBundleName</key><string>DeskDragon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "built $APP  (open it with: open $APP)"
