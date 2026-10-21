#!/bin/bash
# Lays Apple's D3DMetal into a runner tree. assemble-runner.sh calls it for a build, and
# install.sh calls it for a runner from the DMG, which ships without anything of Apple's:
#
#   lib/external/{D3DMetal.framework,libd3dshared.dylib}   D3DMetal 3 (GPTK 3.0)
#   lib/renderers/d3dmetal/                                its PE side    WINEDLLPATH_PREPEND
#   lib/external/d3dmetal4/, lib/renderers/d3dmetal4/      D3DMetal 4 (GPTK 4, macOS 27), optional
#
# Usage: scripts/add-d3dmetal.sh <runner-dir>
# STEAMPLAY_DOWNLOADS moves the download cache (default: downloads/ in the checkout).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="${1:?usage: add-d3dmetal.sh <runner-dir>}"
DL="${STEAMPLAY_DOWNLOADS:-$ROOT/downloads}"
[ -d "$RUNNER/lib/wine" ] || { echo "not a runner: $RUNNER" >&2; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/add-d3dmetal.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fetch() { # url sha256 file
    local out="$DL/$3"
    mkdir -p "$DL"
    [ -f "$out" ] || { curl -fsSL -o "$out.part" "$1" && mv "$out.part" "$out"; }
    echo "$2  $out" | shasum -a 256 -c - >/dev/null
}

# --- D3DMetal from Game Porting Toolkit 3.0 (Apple licence: personal, non-commercial) ------
# Gcenx's repack of Apple's GPTK 3.0 redistributable, fetched here and never committed or
# bundled. Only the D3DMetal parts are unpacked.
fetch https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz \
    d377683937340f914823dbb2e1252b329cbf834ff58907d0293db8cebf0e392e game-porting-toolkit-3.0-3.tar.xz
a="Game Porting Toolkit.app/Contents/Resources"
members=("$a/wine/lib/external")
for d in d3d10 d3d11 d3d12 dxgi nvapi64 atidxx64 nvngx-on-metalfx; do
    members+=("$a/wine/lib/wine/x86_64-windows/$d.dll")
done
tar -xJf "$DL/game-porting-toolkit-3.0-3.tar.xz" -C "$WORK" "${members[@]}"
tar -xJf "$DL/game-porting-toolkit-3.0-3.tar.xz" -C "$WORK" "$a/License.rtf" 2>/dev/null || true
g="$WORK/$a/wine/lib"
mkdir -p "$RUNNER/lib/external"
rm -rf "$RUNNER/lib/external/D3DMetal.framework" "$RUNNER/lib/renderers/d3dmetal"
cp -R "$g/external/D3DMetal.framework" "$RUNNER/lib/external/"
cp -f "$g/external/libd3dshared.dylib" "$RUNNER/lib/external/"
R="$RUNNER/lib/renderers/d3dmetal"
mkdir -p "$R/x86_64-windows" "$R/x86_64-unix"
for d in d3d10 d3d11 d3d12 dxgi nvapi64 atidxx64; do
    cp "$g/wine/x86_64-windows/$d.dll" "$R/x86_64-windows/$d.dll"
    ln -s ../../../external/libd3dshared.dylib "$R/x86_64-unix/$d.so"
done
# DLSS -> MetalFX: the MetalFX NGX shim takes nvngx's place (as the MacPorts d3dmetal port does)
cp "$g/wine/x86_64-windows/nvngx-on-metalfx.dll" "$R/x86_64-windows/nvngx.dll"
ln -s ../../../external/libd3dshared.dylib "$R/x86_64-unix/nvngx.so"
# NGX in a game's Streamline opens _nvngx.dll in system32 before nvngx.dll, and Wine loads a
# builtin by its name, so the copy the run script puts there needs a builtin of that name.
cp "$R/x86_64-windows/nvngx.dll" "$R/x86_64-windows/_nvngx.dll"
ln -s ../../../external/libd3dshared.dylib "$R/x86_64-unix/_nvngx.so"
if [ -f "$WORK/$a/License.rtf" ]; then cp "$WORK/$a/License.rtf" "$RUNNER/lib/external/D3DMetal-License.rtf"; fi
echo "D3DMetal 3.0: $RUNNER/lib/external"

# --- D3DMetal 4 from Game Porting Toolkit 4 (optional; macOS 27, Apple licence) -----------
# Apple's download sits behind a developer login and a licence you accept when you open the
# disk image, so nothing is fetched here: open the image in Finder (and the evaluation
# environment image inside it, if there is one), or point GPTK4 at a folder holding its
# redist/. Only redist/lib is taken, into its own directories next to D3DMetal 3; the run
# script uses it for CX_GRAPHICS_BACKEND=d3dmetal4 on macOS 27.
gptk4_lib=""
for base in ${GPTK4:+"$GPTK4"} /Volumes/*[Pp]orting* /Volumes/*[Ee]valuation* /Volumes/*GPTK*; do
    [ -d "$base" ] || continue
    while IFS= read -r fw; do
        plist="$fw/Versions/A/Resources/Info.plist"
        v="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
        case "$v" in 4*) gptk4_lib="${fw%/external/D3DMetal.framework}"; break 2 ;; esac
    done < <(find "$base" -maxdepth 5 -type d -path '*/lib/external/D3DMetal.framework' 2>/dev/null)
done
if [ -z "$gptk4_lib" ]; then
    echo "D3DMetal 4: no Game Porting Toolkit 4 image open, left out"
    exit 0
fi
for f in "$gptk4_lib/external/D3DMetal.framework" "$gptk4_lib/external/libd3dshared.dylib"; do
    codesign --verify --strict "$f" || { echo "D3DMetal 4: bad signature on $f" >&2; exit 1; }
    auth="$(codesign -dv --verbose=4 "$f" 2>&1 || true)"
    case "$auth" in
        *"Authority=Software Signing"*) ;;
        *) echo "D3DMetal 4: $f is not signed by Apple" >&2; exit 1 ;;
    esac
done
plist="$gptk4_lib/external/D3DMetal.framework/Versions/A/Resources/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist" 2>/dev/null || true)"
E="$RUNNER/lib/external/d3dmetal4"
R="$RUNNER/lib/renderers/d3dmetal4"
rm -rf "$E" "$R"
mkdir -p "$E" "$R/x86_64-windows" "$R/x86_64-unix"
cp -R "$gptk4_lib/external/D3DMetal.framework" "$E/"
cp "$gptk4_lib/external/libd3dshared.dylib" "$E/"
for d in d3d10 d3d11 d3d12 dxgi nvapi64 atidxx64; do
    if [ -f "$gptk4_lib/wine/x86_64-windows/$d.dll" ]; then
        cp "$gptk4_lib/wine/x86_64-windows/$d.dll" "$R/x86_64-windows/$d.dll"
        ln -s ../../../external/d3dmetal4/libd3dshared.dylib "$R/x86_64-unix/$d.so"
    else
        case "$d" in d3d11|d3d12|dxgi) echo "D3DMetal 4: no $d.dll in $gptk4_lib" >&2; exit 1 ;; esac
        echo "D3DMetal 4: no $d.dll, left out"
    fi
done
if [ -f "$gptk4_lib/wine/x86_64-windows/nvngx-on-metalfx.dll" ]; then
    cp "$gptk4_lib/wine/x86_64-windows/nvngx-on-metalfx.dll" "$R/x86_64-windows/nvngx.dll"
    ln -s ../../../external/d3dmetal4/libd3dshared.dylib "$R/x86_64-unix/nvngx.so"
    cp "$R/x86_64-windows/nvngx.dll" "$R/x86_64-windows/_nvngx.dll"
    ln -s ../../../external/d3dmetal4/libd3dshared.dylib "$R/x86_64-unix/_nvngx.so"
fi
lic="$(find "$gptk4_lib/../.." -maxdepth 3 -iname 'licen[cs]e*.rtf' 2>/dev/null | head -1 || true)"
if [ -n "$lic" ]; then cp "$lic" "$E/D3DMetal-License.rtf"; fi
echo "D3DMetal $version (macOS ${min:-?}+) from $gptk4_lib"
