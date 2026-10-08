#!/bin/bash
# steamplay-mac installer. Uses NotProton's support layout so the forked notproton.dylib and
# its run script find everything where they expect it:
#   ~/Library/Application Support/notproton/{runners/<id>,runners/current,bridge,signatures,...}
#
#   install.sh support [runner-id]   runner, bridge, signatures, helpers (touches nothing of Steam)
#   install.sh steam                 inject notproton.dylib into /Applications/Steam.app
#   install.sh block-updates         stop the Steam bootstrapper from updating (and undoing) itself
#   install.sh hud on|off            Apple's Metal HUD for every game (small, top right, FPS)
#   install.sh uninstall-steam       restore Steam.app's Info.plist and remove the dylib
#   install.sh status
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NP="$ROOT/notproton"
SUP="$HOME/Library/Application Support/notproton"
STEAM_APP=/Applications/Steam.app
PLIST="$STEAM_APP/Contents/Info.plist"
DYLIB_DST="$STEAM_APP/Contents/MacOS/notproton.dylib"
BACKUP="$SUP/backups/Info.plist.before-notproton"
PB=/usr/libexec/PlistBuddy
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

die() { echo "error: $*" >&2; exit 1; }
steam_running() { pgrep -x steam_osx >/dev/null 2>&1; }

install_file() { # src dst
    mkdir -p "$(dirname "$2")"
    cp -f "$1" "$2.new" && mv -f "$2.new" "$2"
}

cmd_support() {
    local id="${1:-selfbuilt-cx26.3-r1}"
    local runner="$ROOT/dist/runners/$id"
    [ -f "$runner/runner.json" ] || die "no runner at $runner (scripts/assemble-runner.sh)"
    [ -f "$NP/out/notproton.dylib" ] || die "notproton.dylib not built (make -C notproton out/notproton.dylib)"
    [ -f "$ROOT/build/bridge/steamclient64.dll" ] || die "Valve bridge files missing (scripts/fetch-valve-bridge.sh)"

    mkdir -p "$SUP/runners"
    rm -rf "$SUP/runners/$id.new"
    ditto "$runner" "$SUP/runners/$id.new"
    xattr -dr com.apple.quarantine "$SUP/runners/$id.new" 2>/dev/null || true
    rm -rf "$SUP/runners/$id"
    mv "$SUP/runners/$id.new" "$SUP/runners/$id"
    ln -sfn "$id" "$SUP/runners/current"
    echo "runner: $SUP/runners/current -> $id"

    local B="$SUP/bridge"
    mkdir -p "$B/legacycompat" "$B/i386-windows" "$B/x86_64-windows" "$B/x86_64-unix"
    for f in steamclient.dll steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do
        install_file "$ROOT/build/bridge/$f" "$B/$f"
    done
    for f in "$ROOT"/build/bridge/legacycompat/*; do install_file "$f" "$B/legacycompat/${f##*/}"; done
    install_file "$runner/share/steamplay/steam.exe" "$B/steam.exe"
    install_file "$runner/lib/wine/x86_64-windows/lsteamclient.dll" "$B/lsteamclient.dll"
    install_file "$runner/lib/wine/x86_64-windows/lsteamclient.dll" "$B/x86_64-windows/lsteamclient.dll"
    install_file "$runner/lib/wine/i386-windows/lsteamclient.dll" "$B/i386-windows/lsteamclient.dll"
    install_file "$runner/lib/wine/x86_64-unix/lsteamclient.so" "$B/x86_64-unix/lsteamclient.so"
    codesign --remove-signature "$B/x86_64-unix/lsteamclient.so" 2>/dev/null || true
    # A CrossOver-era bridge kept binary-patched ntdlls here; they do not belong to this runner.
    rm -rf "$B/wine"
    echo "bridge: $B"

    mkdir -p "$SUP/signatures/macos.arm64"
    cp -f "$NP"/signatures/macos.arm64/*.json "$SUP/signatures/macos.arm64/"
    install_file "$NP/out/overlay-shim.dylib" "$SUP/overlay-shim.dylib"
    install_file "$NP/out/iconmaker" "$SUP/iconmaker"
    install_file "$NP/out/appinfo" "$SUP/appinfo"
    install_file "$ROOT/build/helpers/pe-d3d" "$SUP/pe-d3d"
    install_file "$ROOT/build/helpers/syshud" "$SUP/syshud"
    install_file "$NP/out/notproton.dylib" "$SUP/notproton.dylib"
    sed -n 's/.*NOTPROTON_VERSION[^"]*"\([^"]*\)".*/\1/p' "$NP/dylib/version.h" | head -1 > "$SUP/dylib.version"
    echo "helpers, signatures, dylib: $SUP"
}

cmd_steam() {
    [ -d "$STEAM_APP" ] || die "$STEAM_APP not found"
    [ -f "$SUP/notproton.dylib" ] || die "run '$0 support' first"
    if steam_running; then
        echo "quitting Steam..."
        osascript -e 'quit app "Steam"' >/dev/null 2>&1 || true
        for _ in $(seq 1 60); do steam_running || break; sleep 0.5; done
        steam_running && die "Steam is still running, quit it and retry"
    fi
    local current
    current="$($PB -c 'Print :LSEnvironment:DYLD_INSERT_LIBRARIES' "$PLIST" 2>/dev/null || true)"
    if [ -n "$current" ] && [ "$current" != "$DYLIB_DST" ]; then
        die "Steam already injects $current; not touching it"
    fi
    mkdir -p "$(dirname "$BACKUP")"
    [ -f "$BACKUP" ] || cp -p "$PLIST" "$BACKUP"
    echo "Info.plist backup: $BACKUP"

    install_file "$SUP/notproton.dylib" "$DYLIB_DST"
    $PB -c 'Print :LSEnvironment' "$PLIST" >/dev/null 2>&1 || $PB -c 'Add :LSEnvironment dict' "$PLIST"
    $PB -c 'Delete :LSEnvironment:DYLD_INSERT_LIBRARIES' "$PLIST" 2>/dev/null || true
    $PB -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string $DYLIB_DST" "$PLIST"
    # The bootstrapper carries the hardened runtime, which drops DYLD_INSERT_LIBRARIES; an
    # ad-hoc signature without it lets the insert through (and replaces Valve's signature).
    codesign -f -s - "$DYLIB_DST"
    codesign -f -s - "$STEAM_APP/Contents/MacOS/steam_osx"
    codesign -f -s - "$STEAM_APP"
    "$LSREGISTER" -f "$STEAM_APP" >/dev/null 2>&1 || true
    echo "Steam patched. Start Steam; Windows games get 'Steam Play (Wine, self-built)'."
}

cmd_block_updates() {
    local cfg="$HOME/Library/Application Support/Steam/steam.cfg"
    grep -q '^BootStrapperInhibitUpdateOnLaunch=enable' "$cfg" 2>/dev/null && { echo "already blocked"; return; }
    printf 'BootStrapperInhibitUpdateOnLaunch=enable\n' >> "$cfg"
    echo "updates blocked via $cfg (delete that line to allow updates again)"
}

# global.env holds defaults for every game (a game's launch options still win).
cmd_hud() {
    local env="$SUP/global.env"
    mkdir -p "$SUP"; touch "$env"
    grep -v '^MTL_HUD_ENABLED=' "$env" > "$env.new" || true
    case "${1:-}" in
        on) echo 'MTL_HUD_ENABLED=1' >> "$env.new"; echo "Metal HUD on for all games (next launch)" ;;
        off) echo "Metal HUD off" ;;
        *) rm -f "$env.new"; die "usage: $0 hud on|off" ;;
    esac
    mv "$env.new" "$env"
}

cmd_uninstall_steam() {
    steam_running && die "quit Steam first"
    if [ -f "$BACKUP" ]; then
        cp -p "$BACKUP" "$PLIST"
    else
        $PB -c 'Delete :LSEnvironment:DYLD_INSERT_LIBRARIES' "$PLIST" 2>/dev/null || true
    fi
    rm -f "$DYLIB_DST"
    codesign -f -s - "$STEAM_APP/Contents/MacOS/steam_osx"
    codesign -f -s - "$STEAM_APP"
    "$LSREGISTER" -f "$STEAM_APP" >/dev/null 2>&1 || true
    echo "Steam restored (ad-hoc signed; reinstall Steam from steampowered.com for Valve's signature)."
}

cmd_status() {
    echo "runner:   $(readlink "$SUP/runners/current" 2>/dev/null || echo none)"
    echo "steam:    insert=$($PB -c 'Print :LSEnvironment:DYLD_INSERT_LIBRARIES' "$PLIST" 2>/dev/null || echo none)"
    echo "dylib:    $( [ -f "$DYLIB_DST" ] && shasum -a 256 "$DYLIB_DST" | cut -c1-16 || echo absent)"
    echo "compat:   $(ls "$HOME/Library/Application Support/Steam/compatibilitytools.d" 2>/dev/null | tr '\n' ' ')"
}

case "${1:-}" in
    support) shift; cmd_support "$@" ;;
    steam) cmd_steam ;;
    block-updates) cmd_block_updates ;;
    hud) shift; cmd_hud "$@" ;;
    uninstall-steam) cmd_uninstall_steam ;;
    status) cmd_status ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
esac
