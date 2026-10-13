#!/bin/bash
# Packs a built runner and the NotProton fork into dist/steamplay-mac-<version>.dmg, which holds:
#
#   Install steamplay-mac.app     applet (installer/steamplay-mac.applescript) whose
#                                 Contents/Resources/payload has the layout of a checkout:
#                                 scripts/, dist/runners/<id>, notproton/{out,signatures,...},
#                                 build/helpers; scripts/install.sh does the installing
#   Uninstall steamplay-mac.app   the same applet in uninstall mode
#   Read me.txt, Licenses/
#
# Nothing of Valve's or Apple's goes into the image. The runner is copied without D3DMetal;
# install.sh fetches it and Valve's DLLs, hash-checked, on the user's Mac.
# A dirty checkout gets a "-dirty" version: its source links would not match, so do not
# hand that one out.
#
# Usage: scripts/make-dmg.sh [runner-id]        (after scripts/build-all.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID="${1:-selfbuilt-cx26.3-r2}"
RUNNER="$ROOT/dist/runners/$ID"
NP="$ROOT/notproton"
STAGE="$ROOT/build/dmg"
VOL="$STAGE/steamplay-mac"

die() { echo "error: $*" >&2; exit 1; }

[ -f "$RUNNER/runner.json" ] || die "no runner at $RUNNER (scripts/build-all.sh)"
for f in pe-d3d syshud; do
    [ -x "$ROOT/build/helpers/$f" ] || die "build/helpers/$f missing (scripts/build-all.sh)"
done
# The run script is compiled into notproton.dylib, so bring the dylib up to date first.
make -s -C "$NP" out/notproton.dylib overlay-shim aion2-compat iconmaker appinfo >/dev/null

commit="$(git -C "$ROOT" rev-parse --short HEAD)"
np_commit="$(git -C "$NP" rev-parse --short HEAD)"
version="$(date +%Y.%m.%d)-$commit"
if [ -n "$(git -C "$ROOT" status --porcelain)" ] || [ -n "$(git -C "$NP" status --porcelain --untracked-files=no)" ]; then
    version="$version-dirty"
    echo "warning: uncommitted changes, building $version (for testing, not for handing out)" >&2
fi
DMG="$ROOT/dist/steamplay-mac-$version.dmg"

rm -rf "$STAGE"
mkdir -p "$VOL/Licenses"

# --- the installer applet and its payload ---------------------------------------------------
applet() { # mode name
    local app="$VOL/$2.app"
    sed -e "s/@MODE@/$1/" -e "s/@RUNNER_ID@/$ID/" "$ROOT/installer/steamplay-mac.applescript" > "$STAGE/$1.applescript"
    osacompile -o "$app" "$STAGE/$1.applescript"
    local plist="$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.drustburn.steamplay-mac.$1" "$plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string io.github.drustburn.steamplay-mac.$1" "$plist"
    /usr/libexec/PlistBuddy -c "Set :NSAppleEventsUsageDescription Quits Steam before Steam.app is modified." "$plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$plist" 2>/dev/null || true
    mkdir -p "$app/Contents/Resources/payload/scripts"
    cp "$ROOT/scripts/install.sh" "$app/Contents/Resources/payload/scripts/"
}

applet install "Install steamplay-mac"
P="$VOL/Install steamplay-mac.app/Contents/Resources/payload"
cp "$ROOT/scripts/fetch-valve-bridge.sh" "$ROOT/scripts/add-d3dmetal.sh" "$P/scripts/"
mkdir -p "$P/dist/runners" "$P/notproton/out" "$P/notproton/signatures/macos.arm64" \
    "$P/notproton/dylib" "$P/notproton/app/Sources/NotProtonApp/Resources" "$P/build/helpers"
ditto "$RUNNER" "$P/dist/runners/$ID"
R="$P/dist/runners/$ID/lib"
rm -rf "$R/external/D3DMetal.framework" "$R/external/libd3dshared.dylib" "$R/external/D3DMetal-License.rtf" \
    "$R/external/d3dmetal4" "$R/renderers/d3dmetal" "$R/renderers/d3dmetal4"
for f in notproton.dylib overlay-shim.dylib compat_cpuid.dylib iconmaker appinfo; do cp "$NP/out/$f" "$P/notproton/out/"; done
cp "$NP"/signatures/macos.arm64/*.json "$P/notproton/signatures/macos.arm64/"
cp "$NP/dylib/version.h" "$P/notproton/dylib/"
cp "$NP/app/Sources/NotProtonApp/Resources/valve-packages.manifest" "$P/notproton/app/Sources/NotProtonApp/Resources/"
cp "$ROOT/build/helpers/pe-d3d" "$ROOT/build/helpers/syshud" "$P/build/helpers/"

# Nothing of Valve's or Apple's may have come along.
leaks="$(find "$P" \( -iname 'D3DMetal*' -o -iname 'libd3dshared*' -o -iname 'steamclient*.dll' \
    -o -iname 'tier0_s*.dll' -o -iname 'vstdlib_s*.dll' \) -print)"
[ -z "$leaks" ] || die "Valve or Apple files in the payload: $leaks"

applet uninstall "Uninstall steamplay-mac"

# --- read-me and licences -------------------------------------------------------------------
sed -e "s/@VERSION@/$version/" -e "s/@COMMIT@/$commit/" -e "s/@NP_COMMIT@/$np_commit/" -e "s/@RUNNER_ID@/$ID/" \
    "$ROOT/installer/README.txt" > "$VOL/Read me.txt"
cp "$ROOT/LICENSE" "$VOL/Licenses/LICENSE.steamplay-mac"
cp "$NP/LICENSE" "$VOL/Licenses/LICENSE.NotProton"
cp "$NP/NOTICE" "$VOL/Licenses/NOTICE.NotProton"
cp "$NP/LICENSE.lsteamclient" "$NP/LICENSE.steam-shim" "$VOL/Licenses/"
cp "$NP/gamefixes/aion2/LICENSE" "$VOL/Licenses/LICENSE.aion2-wine-compat"
cp "$ROOT/src/wine/COPYING.LIB" "$VOL/Licenses/COPYING.LIB.Wine"
cp "$ROOT/src/wine/LICENSE" "$VOL/Licenses/LICENSE.Wine"
tar -xOf "$ROOT/downloads/MoltenVK-1.4.2-macos.tar" MoltenVK/LICENSE > "$VOL/Licenses/LICENSE.MoltenVK" 2>/dev/null \
    || rm -f "$VOL/Licenses/LICENSE.MoltenVK"

# --- sign (ad hoc: not notarised, see Read me) and pack ---------------------------------------
for app in "$VOL"/*.app; do
    xattr -cr "$app"
    codesign --force --deep --sign - "$app"
    codesign --verify --deep --strict "$app"
done
rm -f "$DMG" "$DMG.sha256"
hdiutil create -quiet -volname steamplay-mac -srcfolder "$VOL" -fs APFS -format ULMO -o "$DMG"
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
du -h "$DMG"
echo "dmg: $DMG"
