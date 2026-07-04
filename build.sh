#!/bin/bash
# Builds Sortomat.app (release) into ./build/
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Sortomat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/Sortomat "$APP/Contents/MacOS/Sortomat"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Sortomat</string>
    <key>CFBundleDisplayName</key>     <string>Sortomat</string>
    <key>CFBundleIdentifier</key>      <string>ch.lmathis.sortomat</string>
    <key>CFBundleExecutable</key>      <string>Sortomat</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"

echo
echo "Fertig: $APP"
echo "  • Zum Installieren nach /Applications kopieren."
echo "  • Autostart: Systemeinstellungen → Allgemein → Anmeldeobjekte → Sortomat hinzufügen."
