#!/bin/bash
# Assembles a self-contained runner tree from the Wine install, the x86_64 dylibs, the Steam
# bridge, Mono/Gecko and the graphics overlays:
#
#   bin/ lib/wine/{x86_64-unix,x86_64-windows,i386-windows}/   Wine (make install-lib)
#   lib/*.dylib                     freetype, gnutls, SDL2, MoltenVK (@rpath ids; the unix .so
#                                   files carry an rpath to here)
#   lib/renderers/dxmt/             DXMT v0.80     (DX10/11 -> Metal)   WINEDLLPATH_PREPEND
#   lib/renderers/d3dmetal/         Apple D3DMetal (DX11/12 -> Metal)   WINEDLLPATH_PREPEND
#   lib/external/                   D3DMetal.framework + libd3dshared.dylib
#   share/wine/{mono,gecko}/
#   runner.json
#
# Usage: scripts/assemble-runner.sh [runner-id]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID="${1:-selfbuilt-cx26.3-r1}"
OUT="$ROOT/dist/runners/$ID"
INSTALL="$ROOT/build/wine-install"
BUILD="$ROOT/build/wine-x86_64"
DEPS="$ROOT/build/deps"
DL="$ROOT/downloads"
WORK="$ROOT/build/assemble-work"

fetch() { # url sha256 file
    local out="$DL/$3"
    mkdir -p "$DL"
    [ -f "$out" ] || { curl -fsSL -o "$out.part" "$1" && mv "$out.part" "$out"; }
    echo "$2  $out" | shasum -a 256 -c - >/dev/null
}

[ -x "$INSTALL/bin/wine" ] || { echo "no Wine install, run scripts/build-wine.sh" >&2; exit 1; }
rm -rf "$OUT" "$WORK"
mkdir -p "$OUT" "$WORK"
cp -R "$INSTALL/" "$OUT/"

# --- host libraries -----------------------------------------------------------------------
# build-deps.sh already gave every dylib an @rpath id and @rpath sibling references; -a keeps
# the version symlinks (libnettle.8.dylib -> libnettle.8.x.dylib) that those ids may name.
cp -a "$DEPS"/lib/*.dylib "$OUT/lib/"
for lib in libfreetype.6.dylib libgnutls.30.dylib libSDL2-2.0.0.dylib libMoltenVK.dylib; do
    [ -e "$OUT/lib/$lib" ] || { echo "missing $lib" >&2; exit 1; }
done
# Nothing may still point into the build machine's deps prefix.
if otool -L "$OUT"/lib/*.dylib "$OUT"/lib/wine/x86_64-unix/*.so | grep -q "$DEPS"; then
    otool -L "$OUT"/lib/*.dylib "$OUT"/lib/wine/x86_64-unix/*.so | grep -B3 "$DEPS" >&2
    echo "absolute deps paths left" >&2; exit 1
fi

# --- Steam bridge -------------------------------------------------------------------------
for arch in x86_64 i386; do
    cp "$BUILD/dlls/lsteamclient/$arch-windows/lsteamclient.dll" "$OUT/lib/wine/$arch-windows/lsteamclient.dll"
done
cp "$BUILD/dlls/lsteamclient/lsteamclient.so" "$OUT/lib/wine/x86_64-unix/lsteamclient.so"
codesign --remove-signature "$OUT/lib/wine/x86_64-unix/lsteamclient.so" 2>/dev/null || true
mkdir -p "$OUT/share/steamplay"
cp "$ROOT/build/bridge/steam.exe" "$OUT/share/steamplay/steam.exe"

# --- Mono (shared install dir) and Gecko (MSIs, hashes as in dlls/appwiz.cpl/addons.c) -----
mkdir -p "$OUT/share/wine/mono" "$OUT/share/wine/gecko"
fetch https://dl.winehq.org/wine/wine-mono/10.4.1/wine-mono-10.4.1-x86.tar.xz \
    a16606ef0724202e6a6848ece6e0cbba64d11e2f11aefe744af1d93c6d9f99bb wine-mono-10.4.1-x86.tar.xz
tar -xJf "$DL/wine-mono-10.4.1-x86.tar.xz" -C "$OUT/share/wine/mono"
fetch https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86.msi \
    26cecc47706b091908f7f814bddb074c61beb8063318e9efc5a7f789857793d6 wine-gecko-2.47.4-x86.msi
fetch https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86_64.msi \
    e590b7d988a32d6aa4cf1d8aa3aa3d33766fdd4cf4c89c2dcc2095ecb28d066f wine-gecko-2.47.4-x86_64.msi
cp "$DL"/wine-gecko-2.47.4-x86.msi "$DL"/wine-gecko-2.47.4-x86_64.msi "$OUT/share/wine/gecko/"

# --- DXMT v0.80 (MIT) -----------------------------------------------------------------------
fetch https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz \
    8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d dxmt-v0.80-builtin.tar.gz
tar -xzf "$DL/dxmt-v0.80-builtin.tar.gz" -C "$WORK"
dx="$WORK/v0.80"
R="$OUT/lib/renderers/dxmt"
mkdir -p "$R/x86_64-windows" "$R/i386-windows" "$R/x86_64-unix"
cp "$dx"/x86_64-windows/*.dll "$R/x86_64-windows/"
cp "$dx"/i386-windows/*.dll "$R/i386-windows/"
# winemetal is not a Wine builtin, so wineboot only writes its system32 placeholder when the
# runner itself carries it; its unix half sits next to winemac.so/ntdll.so for its rpath.
cp "$dx/x86_64-windows/winemetal.dll" "$OUT/lib/wine/x86_64-windows/"
cp "$dx/i386-windows/winemetal.dll" "$OUT/lib/wine/i386-windows/"
cp "$dx/x86_64-unix/winemetal.so" "$OUT/lib/wine/x86_64-unix/"
ln -s ../../../wine/x86_64-unix/winemetal.so "$R/x86_64-unix/winemetal.so"

# --- D3DMetal from Game Porting Toolkit 3.0 (Apple licence: personal, non-commercial) ------
# Gcenx's repack of Apple's GPTK 3.0 redistributable. Apple's licence allows non-commercial
# redistribution on Apple hardware; it is fetched here and never committed.
fetch https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz \
    d377683937340f914823dbb2e1252b329cbf834ff58907d0293db8cebf0e392e game-porting-toolkit-3.0-3.tar.xz
mkdir -p "$WORK/gptk"
tar -xJf "$DL/game-porting-toolkit-3.0-3.tar.xz" -C "$WORK/gptk"
g="$WORK/gptk/Game Porting Toolkit.app/Contents/Resources/wine/lib"
mkdir -p "$OUT/lib/external"
cp -R "$g/external/D3DMetal.framework" "$OUT/lib/external/"
cp "$g/external/libd3dshared.dylib" "$OUT/lib/external/"
R="$OUT/lib/renderers/d3dmetal"
mkdir -p "$R/x86_64-windows" "$R/x86_64-unix"
for d in d3d10 d3d11 d3d12 dxgi nvapi64 atidxx64; do
    cp "$g/wine/x86_64-windows/$d.dll" "$R/x86_64-windows/$d.dll"
    ln -s ../../../external/libd3dshared.dylib "$R/x86_64-unix/$d.so"
done
# DLSS -> MetalFX: the MetalFX NGX shim takes nvngx's place (as the MacPorts d3dmetal port does)
cp "$g/wine/x86_64-windows/nvngx-on-metalfx.dll" "$R/x86_64-windows/nvngx.dll"
ln -s ../../../external/libd3dshared.dylib "$R/x86_64-unix/nvngx.so"
cp "$WORK/gptk/Game Porting Toolkit.app/Contents/Resources/License.rtf" "$OUT/lib/external/D3DMetal-License.rtf" 2>/dev/null || true

# --- manifest -------------------------------------------------------------------------------
wine_version="$("$OUT/bin/wine" --version 2>/dev/null || echo unknown)"
cat > "$OUT/runner.json" <<EOF
{
  "id": "$ID",
  "kind": "selfbuilt",
  "arch": "x86_64",
  "wine": "$wine_version",
  "base": "CrossOver 26.3.0 sources",
  "patches": "$(cd "$ROOT/src/wine" && git rev-parse --short HEAD)",
  "renderers": { "dxmt": "v0.80", "d3dmetal": "3.0" },
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
rm -rf "$WORK"
du -sh "$OUT"
echo "runner: $OUT"
