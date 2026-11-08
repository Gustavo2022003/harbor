#!/bin/bash
# Compila e empacota o Harbor como .app
#
# Uso:
#   scripts/build.sh            # gera build/Harbor.app
#   scripts/build.sh --run      # gera e abre
#   scripts/build.sh --install  # copia para /Applications e abre
#   scripts/build.sh --dist     # também gera dist/Harbor-<versão>.zip e .dmg
#
# Assinatura: usa o certificado "Harbor Dev" (scripts/setup-signing.sh) se existir;
# senão, assina ad-hoc. Pode ser sobrescrito com SIGN_IDENTITY=...
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Harbor"
APP="build/${APP_NAME}.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  if security find-certificate -c "Harbor Dev" >/dev/null 2>&1; then
    SIGN_IDENTITY="Harbor Dev"
  else
    SIGN_IDENTITY="-"
  fi
fi

echo "▸ Compilando Harbor $VERSION ($BUILD_NUMBER)…"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Harbor "$APP/Contents/MacOS/Harbor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST" 2>/dev/null || true

echo "▸ Assinando com: $([[ $SIGN_IDENTITY == "-" ]] && echo "ad-hoc" || echo "$SIGN_IDENTITY")"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"

# Registra o app (esquema harbor:// etc.) no LaunchServices
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x $LSREGISTER ]] && "$LSREGISTER" -f "$APP" || true

echo "✅ $APP"

case "${1:-}" in
  --run)
    pkill -x Harbor 2>/dev/null || true
    open "$APP"
    ;;
  --install)
    pkill -x Harbor 2>/dev/null || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP" /Applications/
    open "/Applications/${APP_NAME}.app"
    echo "✅ Instalado em /Applications"
    ;;
  --dist)
    mkdir -p dist
    ZIP="dist/${APP_NAME}-${VERSION}.zip"
    DMG="dist/${APP_NAME}-${VERSION}.dmg"
    rm -f "$ZIP" "$DMG"
    ditto -c -k --keepParent "$APP" "$ZIP"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "✅ $ZIP"
    echo "✅ $DMG"
    ;;
esac
