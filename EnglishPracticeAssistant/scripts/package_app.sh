#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BIN_DIR="$(swift build -c debug --show-bin-path)"
BIN_PATH="$BIN_DIR/EnglishPracticeAssistant"

if [[ ! -f "$BIN_PATH" ]]; then
  echo "Executable not found at: $BIN_PATH"
  exit 1
fi

APP_DIR="$ROOT_DIR/dist/EnglishPracticeAssistant.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/EnglishPracticeAssistant"
chmod +x "$MACOS_DIR/EnglishPracticeAssistant"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>EnglishPracticeAssistant</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.englishpracticeassistant</string>
  <key>CFBundleName</key>
  <string>EnglishPracticeAssistant</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAccessibilityUsageDescription</key>
  <string>Needs Accessibility access to read selected text in other apps.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>Needs Input Monitoring to listen for hotkeys.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign to help with permissions on some systems; ignore failures.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" || true
fi

echo "App bundle created at: $APP_DIR"
