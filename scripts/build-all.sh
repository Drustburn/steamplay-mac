#!/bin/bash
# Builds everything from scratch: x86_64 host libraries, the patched Wine runner, the Steam
# bridge, the NotProton fork, and assembles dist/runners/<id>. Nothing here touches Steam;
# installing is scripts/install.sh.
#
# Usage: scripts/build-all.sh [runner-id]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID="${1:-selfbuilt-cx26.3-r1}"
LOGS="$ROOT/build/logs"
mkdir -p "$LOGS"

step() { printf '\n==> %s\n' "$*"; }
run() { # name command...
    local name="$1"; shift
    if ! "$@" > "$LOGS/$name.log" 2>&1; then
        echo "failed: $name (see build/logs/$name.log)" >&2
        tail -20 "$LOGS/$name.log" >&2
        exit 1
    fi
}

step "checking prerequisites"
[ "$(uname -m)" = arm64 ] || { echo "Apple Silicon only" >&2; exit 1; }
xcode-select -p >/dev/null 2>&1 || { echo "install the Xcode Command Line Tools: xcode-select --install" >&2; exit 1; }
arch -x86_64 /usr/bin/true 2>/dev/null || { echo "install Rosetta 2: softwareupdate --install-rosetta" >&2; exit 1; }
command -v brew >/dev/null || { echo "Homebrew is required (https://brew.sh)" >&2; exit 1; }
missing=""
for f in mingw-w64 bison flex meson ninja ccache cmake pkgconf autoconf llvm lld nasm freetype; do
    brew list --versions "$f" >/dev/null 2>&1 || missing="$missing $f"
done
[ -z "$missing" ] || { echo "brew install$missing" >&2; exit 1; }
git -C "$ROOT" submodule update --init notproton >/dev/null 2>&1 || true
[ -f "$ROOT/notproton/Makefile" ] || { echo "notproton submodule missing (git submodule update --init)" >&2; exit 1; }

step "x86_64 host libraries (gmp, nettle, gnutls, freetype, SDL2, MoltenVK, FFmpeg)"
run deps "$ROOT/scripts/build-deps.sh"

step "Wine sources (CrossOver 26.3.0 + patches/series + lsteamclient)"
[ -d "$ROOT/src/wine/.git" ] || run prepare "$ROOT/scripts/prepare-wine-src.sh"

step "Wine (native tools, then the x86_64 runner build; this is the long one)"
run wine "$ROOT/scripts/build-wine.sh"

step "steam.exe shim (stock wine-11.15 tree)"
run shim "$ROOT/scripts/build-steam-shim.sh"

step "Valve's Windows Steam DLLs (Valve CDN, hash-checked)"
run valve "$ROOT/scripts/fetch-valve-bridge.sh"

step "NotProton fork: Dobby, notproton.dylib, overlay shim, helpers"
[ -f "$ROOT/notproton/vendor/dobby/CMakeLists.txt" ] || {
    git clone -q --no-checkout https://github.com/jmpews/Dobby.git "$ROOT/notproton/vendor/dobby"
    git -C "$ROOT/notproton/vendor/dobby" checkout -q 5dfc8546954ce3b3198132ab13fddb89ee92cdd7
}
[ -f "$ROOT/notproton/build/dobby/libdobby.a" ] || run dobby make -C "$ROOT/notproton" dobby
run notproton make -C "$ROOT/notproton" out/notproton.dylib overlay-shim iconmaker appinfo
mkdir -p "$ROOT/build/helpers"
clang -O2 -mmacosx-version-min=14.0 -o "$ROOT/build/helpers/pe-d3d" "$ROOT/notproton/helpers/pe-d3d.c"
swiftc -O -target arm64-apple-macos14.0 -framework AppKit -framework IOKit \
    -o "$ROOT/build/helpers/syshud" "$ROOT/notproton/helpers/syshud.swift"

step "assembling runner $ID (Mono, Gecko, DXMT, D3DMetal)"
run assemble "$ROOT/scripts/assemble-runner.sh" "$ID"

printf '\nDone: %s\nNext: scripts/install.sh support && scripts/install.sh steam\n' "$ROOT/dist/runners/$ID"
