#!/bin/sh
# Audit a folder of MAME ROM sets against the MAME version in deps/mame/mamearcade_headless.dylib.
# Usage: tools/romaudit.sh [rom-dir]   (default: OpenEmu's Arcade ROM folder)
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAME="$ROOT/deps/mame"
ROMDIR="${1:-$HOME/Library/Application Support/OpenEmu/Game Library/roms/Arcade}"
OUT="$ROOT/build/romaudit"

mkdir -p "$(dirname "$OUT")"
if [ ! -x "$OUT" ] || [ "$ROOT/tools/romaudit.m" -nt "$OUT" ] || [ "$MAME/mamearcade_headless.dylib" -nt "$OUT" ]; then
    clang -arch "$(lipo -archs "$MAME/mamearcade_headless.dylib")" -fobjc-arc -framework Foundation \
        -I "$MAME/src/osd/headless/public" \
        "$MAME/mamearcade_headless.dylib" -Wl,-rpath,"$MAME" \
        -o "$OUT" "$ROOT/tools/romaudit.m"
    # same fix-up as the Xcode build phase: the dylib's install name is a bare filename
    install_name_tool -change mamearcade_headless.dylib @rpath/mamearcade_headless.dylib "$OUT"
fi

exec "$OUT" "$ROMDIR"
