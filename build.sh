#!/bin/bash
# Builds FlowLocal.app (menu bar app) next to this script. Requires Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/FlowLocal"

APP="FlowLocal.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FlowLocal"
[ -f Resources/AppIcon.icns ] || swift scripts/make_icon.swift Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.flowlocal.app</string>
  <key>CFBundleName</key><string>FlowLocal</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>FlowLocal</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>FlowLocal lê o texto da janela em foco (OCR local) para acertar nomes e termos.</string>
  <key>NSMicrophoneUsageDescription</key><string>FlowLocal grava sua voz para transcrever localmente.</string>
</dict></plist>
PLIST

# A fixed designated requirement (bundle id only) keeps the Accessibility / Input Monitoring / Microphone grants
# valid across rebuilds; the default ad-hoc requirement pins the exact binary hash, so every rebuild silently revokes them.
codesign --force --sign - --identifier local.flowlocal.app -r='designated => identifier "local.flowlocal.app"' "$APP"
echo "Built $(pwd)/$APP"
