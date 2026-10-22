#!/bin/bash
# Збирає "build/Easy CamSorter.app".
#
#   ./build.sh                       — для цього Mac
#   UNIVERSAL=1 ./build.sh           — для Apple Silicon і Intel (потрібен Xcode)
#   VERSION=1.2.0 ./build.sh         — записати номер версії в застосунок
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
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/EasyCamSorter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EasyCamSorter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi

# Локальний підпис (ad-hoc): без нього macOS на Apple Silicon не запустить застосунок.
codesign --force --sign - "$APP"

echo "✅ Готово: $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/EasyCamSorter"))"
