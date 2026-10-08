#!/bin/bash
# Builds NotProton's steam.exe shim (Proton 9 steam_helper port) in a stock Wine 11.15 tree.
# The runner's CrossOver 26.3 tree is Wine 11.0, which has neither WINE_EXTERNAL nor the PE
# libc++ the shim links (CXX_PE_LIBS). The shim is a PE program importing only Win32 DLLs,
# so the Wine version it is built in does not need to match the runner.
#
# Same pins and configure as notproton/bridge/setup-wine-tree.sh: a cross configure for the
# x86_64 host that runs natively on arm64.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NP="$ROOT/notproton"
SRC="$ROOT/build/wine-11.15-src"
BUILD="$ROOT/build/wine-11.15-shim"
OUT="$ROOT/build/bridge"
WINE_COMMIT=2df1ee28039cf84776eb1421ed90bd154cebb65f

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ ! -d "$SRC/.git" ]; then
    git clone --quiet --depth 1 --branch wine-11.15 https://gitlab.winehq.org/wine/wine.git "$SRC"
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$WINE_COMMIT" ] || { echo "wine-11.15 is not at $WINE_COMMIT" >&2; exit 1; }

if ! grep -q 'WINE_CONFIG_MAKEFILE(programs/steam.exe)' "$SRC/configure.ac"; then
    git -C "$SRC" apply "$NP/bridge/register-components.diff"
fi

# configure's makedep pass needs every listed source present, lsteamclient included.
"$ROOT/scripts/fetch-steam-sources.sh" --into "$SRC"

if [ ! -f "$BUILD/Makefile" ]; then
    mkdir -p "$BUILD"
    (cd "$BUILD" && "$SRC/configure" --enable-archs=i386,x86_64 --without-freetype --without-x \
        --disable-tests --host=x86_64-apple-darwin CC="clang -arch x86_64" CXX="clang++ -arch x86_64")
fi
grep -q '^host_cpu = x86_64' "$BUILD/config.status" 2>/dev/null || grep -q "host_cpu='x86_64'" "$BUILD/config.status"

make -C "$BUILD" -j"$(sysctl -n hw.ncpu)" programs/steam.exe/x86_64-windows/steam.exe
mkdir -p "$OUT"
cp -f "$BUILD/programs/steam.exe/x86_64-windows/steam.exe" "$OUT/steam.exe"
size=$(stat -f %z "$OUT/steam.exe")
[ "$size" -gt 1000000 ] || { echo "steam.exe is only $size bytes, the link dropped objects" >&2; exit 1; }
echo "built $OUT/steam.exe ($size bytes)"
