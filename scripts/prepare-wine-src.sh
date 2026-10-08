#!/bin/bash
# Recreates src/wine: the CrossOver 26.3.0 Wine sources (LGPL, published by CodeWeavers) with
# patches/series applied, one git commit per patch, then the Steam bridge sources laid in.
#
# Usage: scripts/prepare-wine-src.sh [--force]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DL="$ROOT/downloads"
WINE="${WINE_SRC_DIR:-$ROOT/src/wine}"
CX_URL=https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz
CX_SHA=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
TARBALL="$DL/crossover-sources-26.3.0.tar.gz"

if [ -e "$WINE" ]; then
    [ "${1:-}" = "--force" ] || { echo "$WINE exists; pass --force to recreate it" >&2; exit 1; }
    rm -rf "$WINE"
fi

mkdir -p "$DL" "$ROOT/src" "$ROOT/sources"
[ -f "$TARBALL" ] || { curl -fSL -o "$TARBALL.part" "$CX_URL" && mv "$TARBALL.part" "$TARBALL"; }
echo "$CX_SHA  $TARBALL" | shasum -a 256 -c - >/dev/null

# The whole drop (wine plus the freetype/gnutls/glib/... sources build-deps.sh uses).
if [ ! -d "$ROOT/sources/sources/wine" ]; then
    tar -xzf "$TARBALL" -C "$ROOT/sources"
fi
cp -Rp "$ROOT/sources/sources/wine" "$WINE"

git_c() { git -C "$WINE" -c user.name=steamplay-mac -c user.email=steamplay-mac@localhost "$@"; }
git_c init -q
git_c add -A
git_c commit -q -m "CrossOver 26.3.0 sources (Wine 11.0), pristine"

while read -r entry; do
    case "$entry" in ''|'#'*) continue ;; esac
    p="$ROOT/patches/$entry"
    [ -f "$p" ] || { echo "missing patch $entry" >&2; exit 1; }
    if head -1 "$p" | grep -q '^From [0-9a-f]\{40\} '; then
        git_c am -q --3way "$p"            # mbox: keeps the original author
    else
        (cd "$WINE" && patch -p1 -s --no-backup-if-mismatch < "$p")
        git_c add -A
        git_c commit -q -m "$(basename "$entry" .patch)" -m "Applied from patches/$entry"
    fi
    echo "applied $entry"
done < "$ROOT/patches/series"

printf 'dlls/lsteamclient/\nprograms/steam.exe/\n' >> "$WINE/.git/info/exclude"
"$ROOT/scripts/fetch-steam-sources.sh" --into "$WINE"
echo "src/wine ready at $(git -C "$WINE" rev-parse --short HEAD)"
