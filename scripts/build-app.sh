#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
swift build -c release --product MixManifest
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/MixManifest.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/MixManifest" "$APP/Contents/MacOS/MixManifest"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MixManifest</string>
<key>CFBundleDisplayName</key><string>MixManifest</string>
<key>CFBundleIdentifier</key><string>dev.mixmanifest.app</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleShortVersionString</key><string>0.2.2</string>
<key>CFBundleExecutable</key><string>MixManifest</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources/THIRD_PARTY_LICENSES"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE-MIT"
cp THIRD_PARTY_LICENSES/* "$APP/Contents/Resources/THIRD_PARTY_LICENSES/"
codesign --force --sign - "$APP"
printf 'Built: %s/%s\n' "$PWD" "$APP"
