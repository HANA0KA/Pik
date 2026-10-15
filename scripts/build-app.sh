#!/bin/bash
# Arma dist/Pik.app (release, firma ad-hoc). Uso: scripts/build-app.sh [--debug] [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
INSTALL=0
for a in "$@"; do
  case "$a" in
    --debug) CONFIG=debug ;;
    --install) INSTALL=1 ;;
  esac
done

VERSION="1.3.0"
BUILD="$(date +%Y%m%d%H%M)"
APP="dist/Pik.app"

ARCHS=()
[ "$CONFIG" = release ] && ARCHS=(--arch arm64 --arch x86_64)   # binario universal

echo "▸ Compilando ($CONFIG${ARCHS:+, universal})…"
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --product Pik 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | grep -E ": error:|Build complete|^error: " || true
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Pik"
[ -x "$BIN" ] || { echo "No se generó el binario"; exit 1; }

echo "▸ Armando $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pik"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/MenuBarIconTemplate*.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Pik</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.pik.desktop</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Pik</string>
  <key>CFBundleDisplayName</key><string>Pik</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Pik</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.pik.desktop</string>
    <key>CFBundleURLSchemes</key><array><string>pik</string></array>
  </dict></array>
  <key>NSCameraUsageDescription</key><string>Pik usa la cámara para mostrarte en la burbuja y grabar solo cámara.</string>
  <key>NSMicrophoneUsageDescription</key><string>Pik usa el micrófono para grabar tu voz y escuchar la palabra «Pik».</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Pik transcribe tus grabaciones y escucha «Pik» en tu Mac.</string>
  <key>NSScreenCaptureUsageDescription</key><string>Pik graba tu pantalla, ventanas y áreas.</string>
  <key>NSAppleEventsUsageDescription</key><string>Pik puede pedirle a Finder que muestre tus archivos.</string>
  <key>NSLocalNetworkUsageDescription</key><string>Pik comparte tus videos por enlace dentro de tu red local.</string>
  <key>NSBonjourServices</key><array/>
</dict>
</plist>
PLIST

cat > dist/Pik.entitlements <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.camera</key><true/>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.network.server</key><true/>
  <key>com.apple.security.network.client</key><true/>
</dict>
</plist>
ENT

echo "▸ Firmando (ad-hoc, requisito estable por identificador)…"
# Sin certificado de desarrollador, el requisito por defecto es el hash del binario y macOS (TCC) olvida los permisos
# (calendario, cámara, micrófono…) en cada compilación. Con un requisito por identificador se conservan.
codesign --force --deep --sign - --requirements '=designated => identifier "com.pik.desktop"' --entitlements dist/Pik.entitlements "$APP" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --deep --strict "$APP" && echo "  firma ok"
codesign -dr - "$APP" 2>&1 | grep -q 'identifier "com.pik.desktop"' || { echo "✘ la firma no quedó con el requisito estable"; exit 1; }

if [ "$INSTALL" = 1 ]; then
  DEST="$HOME/Desktop/Pik.app"
  rm -rf "$DEST"; cp -R "$APP" "$DEST"
  echo "▸ Copiada a $DEST"
fi
if [ "$CONFIG" = release ]; then
  echo "▸ Empaquetando dist/Pik.zip…"
  (cd dist && rm -f Pik.zip && ditto -c -k --keepParent Pik.app Pik.zip)
fi
echo "✔ $APP  ($(lipo -archs "$APP/Contents/MacOS/Pik"))"
