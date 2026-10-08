#!/bin/bash
# Places the Steam bridge sources into a Wine tree (default src/wine, or --into <tree>):
#   dlls/lsteamclient     Valve's Proton lsteamclient at a pinned commit, with NotProton's
#                         three macOS files laid over it (notproton/lsteamclient/*)
#   programs/steam.exe    NotProton's steam.exe shim (a port of Proton 9's steam_helper)
#
# Valve's files are fetched, never committed: they carry Steamworks SDK licensed sources.
# The pins are NotProton's (lsteamclient/fetch.sh, steam-shim/fetch-headers.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NP="$ROOT/notproton"
WINE="$ROOT/src/wine"
[ "${1:-}" = "--into" ] && WINE="$2"
CACHE="$ROOT/downloads/steam"

PROTON_COMMIT=164e0ccd2ea2b1ec2e5d08dc97f65b184c2539ca
LSC_DIGEST=b286df1df46a70d9e2cc674676afcc6e08b1a56ce472e5add0932b86940657bf
OPENVR_COMMIT=f51d87ecf8f7903e859b0aa4d617ff1e5f33db5a
VWINE_COMMIT=015230dc0f78a543032dea0907f6c97304b25ca3

mkdir -p "$CACHE"

# --- lsteamclient -------------------------------------------------------------------------
tarball="$CACHE/proton-$PROTON_COMMIT.tar.gz"
base="$CACHE/lsteamclient-$PROTON_COMMIT"
if [ ! -d "$base" ]; then
    [ -f "$tarball" ] || curl -fsSL -o "$tarball.part" \
        "https://codeload.github.com/ValveSoftware/Proton/tar.gz/$PROTON_COMMIT" && \
        { [ -f "$tarball" ] || mv "$tarball.part" "$tarball"; }
    mkdir -p "$base.part"
    tar -xzf "$tarball" -C "$base.part" --strip-components=2 "*/lsteamclient/"
    mv "$base.part" "$base"
fi

# Content digest as NotProton computes it (sorted relative paths, sha256 of path then data).
got="$(python3 -I - "$base" <<'EOF'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
h = hashlib.sha256()
for p in sorted(q for q in root.rglob("*") if q.is_file()):
    h.update(hashlib.sha256(str(p.relative_to(root)).encode()).digest())
    h.update(hashlib.sha256(p.read_bytes()).digest())
print(h.hexdigest())
EOF
)"
[ "$got" = "$LSC_DIGEST" ] || { echo "lsteamclient digest mismatch: $got" >&2; exit 1; }
echo "lsteamclient: Proton $PROTON_COMMIT verified"

rm -rf "$WINE/dlls/lsteamclient"
cp -R "$base" "$WINE/dlls/lsteamclient"
for f in steamclient_main.c unix_steam_input_manual.cpp unixlib.cpp; do
    [ -f "$WINE/dlls/lsteamclient/$f" ] || { echo "overlay target missing: $f" >&2; exit 1; }
    cp -f "$NP/lsteamclient/$f" "$WINE/dlls/lsteamclient/$f"
done
# Wine 11.0's winbase.h turns strncpy/wcsncpy into macros that break libc++'s <cwchar> once
# a unix .cpp reaches it, so the C headers go in first; the C++ objects need libc++ to link.
# (one prefix header: makedep collapses repeated -include flags)
printf '#include <string.h>\n#include <wchar.h>\n' > "$WINE/dlls/lsteamclient/unix_prefix.h"
cat >> "$WINE/dlls/lsteamclient/Makefile.in" <<'MK'

UNIX_CFLAGS = -include unix_prefix.h
UNIX_LIBS = -lc++
MK

# --- steam.exe shim -----------------------------------------------------------------------
hdr="$CACHE/proton-headers"
while read -r proj commit path dest want; do
    out="$hdr/$dest"
    if [ ! -f "$out" ]; then
        mkdir -p "$(dirname "$out")"
        curl -fsSL -o "$out.part" "https://raw.githubusercontent.com/ValveSoftware/$proj/$commit/$path"
        mv "$out.part" "$out"
    fi
    echo "$want  $out" | shasum -a 256 -c - >/dev/null
done <<EOF
openvr $OPENVR_COMMIT headers/openvr.h openvr/headers/openvr.h 4f1242febb91d23e1a8317b988dbecec63476603f67458872d3b916cd347df32
openvr $OPENVR_COMMIT src/ivrclientcore.h openvr/src/ivrclientcore.h 07c8ce981a59fb7cd1dc30572f0c9972d98e6275e95527f0f7a74a18bc0cf846
wine $VWINE_COMMIT include/wine/heap.h wine/include/wine/heap.h e51df7c87744e3cbea4cd03d1e08573205252eb275166c0d01f87340991550e7
EOF
rm -rf "$hdr/steamworks_sdk_142"
cp -R "$base/steamworks_sdk_142" "$hdr/steamworks_sdk_142"

# Only trees that register programs/steam.exe (the 11.15 shim tree) get the shim; the
# runner's 11.0 tree cannot build it.
if ! grep -q 'WINE_CONFIG_MAKEFILE(programs/steam.exe)' "$WINE/configure.ac"; then
    echo "steam.exe shim: not registered in $WINE, skipped"
    exit 0
fi
shim="$WINE/programs/steam.exe"
rm -rf "$shim"
mkdir -p "$shim"
rsync -a --exclude build.sh --exclude fetch-headers.sh --exclude gen-implib.sh \
    --exclude LICENSE "$NP/steam-shim/" "$shim/"
cp -R "$hdr" "$shim/proton-headers"
echo "steam.exe shim placed"
