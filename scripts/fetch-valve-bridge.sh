#!/bin/bash
# Fetches the genuine Valve Windows binaries the bridge needs (steamclient(64).dll,
# tier0_s64.dll, vstdlib_s64.dll, legacycompat/*) from Valve's CDN into build/bridge,
# following notproton/app/.../valve-packages.manifest: every package zip and every file
# taken out of it is checked against the manifest's sha256. Nothing of Valve's is committed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/notproton/app/Sources/NotProtonApp/Resources/valve-packages.manifest"
CACHE="$ROOT/downloads/valve"
OUT="$ROOT/build/bridge"
mkdir -p "$CACHE" "$OUT"

bases=$(awk '$1=="base"{print $2}' "$MANIFEST")

fetch_package() { # file sha
    local dst="$CACHE/$1"
    if [ -f "$dst" ] && echo "$2  $dst" | shasum -a 256 -c - >/dev/null 2>&1; then return 0; fi
    for b in $bases; do
        if curl -fsSL --connect-timeout 10 -o "$dst.part" "$b/$1" \
            && echo "$2  $dst.part" | shasum -a 256 -c - >/dev/null 2>&1; then
            mv "$dst.part" "$dst"; return 0
        fi
    done
    rm -f "$dst.part"; echo "could not fetch $1 with the pinned hash" >&2; return 1
}

while read -r kind id file sha; do
    [ "$kind" = package ] || continue
    fetch_package "$file" "$sha"
    rm -rf "$CACHE/x-$id" && mkdir -p "$CACHE/x-$id" && unzip -q -o "$CACHE/$file" -d "$CACHE/x-$id"
done < <(grep '^package ' "$MANIFEST")

while read -r kind bridge pkg inner sha; do
    [ "$kind" = file ] || continue
    src="$CACHE/x-$pkg/$inner"
    [ -f "$src" ] || src="$(find "$CACHE/x-$pkg" -ipath "*/$inner" | head -1)"
    [ -n "$src" ] && [ -f "$src" ] || { echo "$inner not in $pkg" >&2; exit 1; }
    echo "$sha  $src" | shasum -a 256 -c - >/dev/null || { echo "hash mismatch: $inner" >&2; exit 1; }
    mkdir -p "$(dirname "$OUT/$bridge")"
    cp -f "$src" "$OUT/$bridge"
    echo "bridge: $bridge"
done < <(grep '^file ' "$MANIFEST")
