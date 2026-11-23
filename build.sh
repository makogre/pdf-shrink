#!/bin/bash
# Baut "PDF Shrink.app" (native SwiftUI-App, kein Browser) und installiert sie
# nach ~/Applications.
set -e
cd "$(cd "$(dirname "$0")" && pwd)"

APP="PDF Shrink.app"
EXEC="PDF Shrink"
INSTALL=1
[ "$1" = "--no-install" ] && INSTALL=0
PB=/usr/libexec/PlistBuddy
# Xcode-SDK explizit: xcrun zeigt hier sonst auf die CommandLineTools, wo kein
# macOS-SDK liegt.
SDK="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
[ -d "$SDK" ] || SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

echo "→ kompilieren"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
env -u SDKROOT xcrun swiftc \
  -swift-version 5 -parse-as-library -O \
  -sdk "$SDK" -target arm64-apple-macos14.0 \
  -o "$APP/Contents/MacOS/$EXEC" Sources/*.swift

echo "→ Bundle zusammensetzen"
cp icon/app.icns "$APP/Contents/Resources/app.icns"
PLIST="$APP/Contents/Info.plist"
cat > "$PLIST" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PDF Shrink</string>
  <key>CFBundleDisplayName</key><string>PDF Shrink</string>
  <key>CFBundleIdentifier</key><string>local.pdfshrink.native</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>PDF Shrink</string>
  <key>CFBundleIconFile</key><string>app</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>PDF Shrink liest hier abgelegte PDFs und speichert das verkleinerte Ergebnis daneben.</string>
  <key>NSDesktopFolderUsageDescription</key>
  <string>PDF Shrink liest PDFs vom Schreibtisch und speichert das verkleinerte Ergebnis daneben.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>PDF Shrink liest PDFs aus dem Downloads-Ordner und speichert das verkleinerte Ergebnis daneben.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>PDF-Dokument</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
    </dict>
  </array>
</dict>
</plist>
PL
plutil -lint "$PLIST" >/dev/null

# Ad-hoc-Signatur: ohne stabile Code-Identität fragt macOS nie nach Zugriff auf
# Dokumente/Schreibtisch/Downloads - die App scheitert dann stillschweigend.
echo "→ ad-hoc signieren"
codesign --force --sign - --timestamp=none "$APP" 2>&1 | sed 's/^/   /'

if [ "$INSTALL" = "0" ]; then
  echo
  echo "Gebaut (nicht installiert): $PWD/$APP"
  exit 0
fi

DEST="$HOME/Applications"
mkdir -p "$DEST"
echo "→ installieren nach $DEST"
rm -rf "$DEST/$APP"
cp -R "$APP" "$DEST/$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST/$APP" 2>/dev/null || true
touch "$DEST/$APP"
killall Dock 2>/dev/null || true

echo
echo "Fertig:  open \"$DEST/$APP\""
