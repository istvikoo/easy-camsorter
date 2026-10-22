#!/bin/bash
# Збирає build/Easy CamSorter.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Easy CamSorter.app"

swift build -c release --product EasyCamSorter 2>&1 | grep -v "ld: warning" || true
BIN="$(swift build -c release --show-bin-path)/EasyCamSorter"
[[ -x "$BIN" ]] || { echo "❌ Збірка не вдалася"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EasyCamSorter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Локальний підпис, щоб macOS запускала застосунок без скарг на цьому Mac.
codesign --force --sign - "$APP"

echo "✅ Готово: $(pwd)/$APP"
