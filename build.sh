#!/bin/bash
# Збирає "build/Easy CamSorter.app".
#
#   ./build.sh                       — для цього Mac
#   UNIVERSAL=1 ./build.sh           — для Apple Silicon і Intel (потрібен Xcode)
#   VERSION=1.2.0 ./build.sh         — записати номер версії в застосунок (його порівнює Sparkle)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Easy CamSorter.app"
ARGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARGS+=(--arch arm64 --arch x86_64)
fi

# Вивід збірки без шуму "ld: warning"; помилку збірки не ковтаємо.
set +e
swift build "${ARGS[@]}" --product EasyCamSorter 2>&1 | grep -v "ld: warning"
status=${PIPESTATUS[0]}
set -e
[[ $status -eq 0 ]] || { echo "❌ Збірка не вдалася"; exit 1; }
BIN_DIR="$(swift build "${ARGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/EasyCamSorter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/EasyCamSorter"
# Sparkle (автооновлення); ditto зберігає символьні посилання всередині фреймворку.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
fi

# Локальний підпис (ad-hoc): без нього macOS на Apple Silicon не запустить застосунок.
# --deep підписує й вкладені частини Sparkle (Autoupdate, Updater.app, XPC-сервіси).
codesign --force --deep --sign - "$APP"

echo "✅ Готово: $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/EasyCamSorter"))"
