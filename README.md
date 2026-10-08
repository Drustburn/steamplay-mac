# steamplay-mac

Play Windows games from the **native macOS Steam client** on Apple Silicon. You install them in
Steam and click Play, much like Steam Play/Proton on Linux. Instead of a licensed CrossOver
install, the runner is a **Wine you build yourself**.

> **Status: experimental (October 2026).** It works end to end on an M3 Max with macOS 26.6 and
> Steam client 1791249696 (beta). See [What has been tested](#what-has-been-tested). Expect rough
> edges, and read [Risks](#risks) before installing.

## How it works

This is a fork of [NotProton](https://github.com/NotProtonNot/NotProton) (GPL-3.0).
NotProton's `notproton.dylib` is loaded into macOS Steam. It switches on Steam's built-in Steam
Play machinery, which macOS Steam ships but keeps inactive, and registers a compatibility tool.
Upstream NotProton runs games with a licensed CrossOver Preview. Supporting other runners is not
a goal of that project, so this fork adds a runner you build from public sources:

| | NotProton | steamplay-mac |
|---|---|---|
| Wine | CrossOver Preview 27 (licence required) | CrossOver 26.3 **sources** (Wine 11.0, LGPL), built locally |
| Steam bridge in ntdll | binary detours at offsets pinned per CrossOver build | Valve's Proton patches ported **into the source** |
| Extra Wine fixes | – | [Highball](https://github.com/gauthierpiarrette/highball-engine) series: msync leak, Unity `GetLastError`, fibers, CoreAudio dropouts, Xbox sign-in, … |
| Graphics backend | CrossOver's `CX_GRAPHICS_BACKEND` | own selection. *Auto* reads the game's PE imports: DX12 → D3DMetal, DX10/11 → DXMT, otherwise wined3d |
| D3DMetal | CrossOver's copy | Apple Game Porting Toolkit 3.0 |
| DXMT | bundled with CrossOver | v0.80 |
| msync | off by default | on by default |
| Video (Media Foundation) | GStreamer | FFmpeg 7.1 through winedmo |

The game path is: Steam → compat tool `run` script → per-game `.app` launcher (macOS Game Mode) →
x86_64 Wine under Rosetta 2 → `steam.exe` shim → game. Inside the game process, Valve's
`steamclient64.dll` is trampolined into the builtin `lsteamclient`. Its Unix half talks to the
macOS client's `steamclient.dylib`, so Steam features (overlay, achievements, cloud) work.

## What has been tested

- **Smoke tests** (`tests/d3dprobe.c`):
  - D3D11 through **DXMT**: feature level 11_0, adapter "Apple M3 Max".
  - D3D11 and D3D12 through **D3DMetal**: DXR tier 1.1.
  - wined3d as the fallback.
- **AION 2** (Steam 3393110, UE5, DX12, NC Guard anti-cheat), with no launch options:
  - NC Guard initialises completely (`initialize:: done`).
  - The Steam overlay attaches.
  - The 3D title screen renders through D3DMetal (picked automatically).
  - The game reaches the global server list at a steady 60 fps (Metal HUD). Character creation
    could not be tested on launch day, because the servers were full.

  CrossOver 26 and other Wine/GPTK setups hang at the splash screen.

## Requirements

- An Apple Silicon Mac with macOS 14 or later (tested on macOS 26), Rosetta 2, and the Xcode
  Command Line Tools.
- [Homebrew](https://brew.sh) with these packages:
  ```sh
  brew install mingw-w64 bison flex meson ninja ccache cmake pkgconf autoconf llvm lld nasm freetype
  ```
- About 15 GB of free disk space for the build. A full build takes about 20–30 minutes on an M3 Max.

## Build

```sh
git clone --recursive https://github.com/Drustburn/steamplay-mac.git
cd steamplay-mac
scripts/build-all.sh
```

Every step can also be run on its own:

| Script | Does |
|---|---|
| `build-deps.sh` | x86_64 gmp, nettle, gnutls, freetype, SDL2, MoltenVK and FFmpeg, cross-compiled natively with `-arch x86_64` |
| `prepare-wine-src.sh` | downloads the CrossOver 26.3.0 sources (sha256-pinned) and applies `patches/series` |
| `fetch-steam-sources.sh` | adds Valve's Proton `lsteamclient` (pinned commit, content digest) |
| `build-wine.sh` | builds the native Wine tools, then the x86_64 Wine with new WoW64 (i386 + x86_64 PE) |
| `build-steam-shim.sh` | NotProton's `steam.exe` shim, built in a stock wine-11.15 tree |
| `fetch-valve-bridge.sh` | Valve's Windows Steam DLLs from Valve's CDN, sha256-checked |
| `assemble-runner.sh` | runner tree with bundled libraries, Mono, Gecko, DXMT and D3DMetal |

Everything downloaded is checked against a pinned hash. Nothing from Valve or Apple is committed
to this repository.

## Install

```sh
scripts/install.sh support        # runner, bridge, helpers -> ~/Library/Application Support/notproton
scripts/install.sh steam          # inject the dylib into /Applications/Steam.app
scripts/install.sh block-updates  # optional, recommended (see Risks)
```

`install.sh hud on` turns on Apple's Metal Performance HUD for every game. It sits small in the
top-right corner and shows FPS and frame time. The defaults are `MTL_HUD_ALIGNMENT=topright`,
`MTL_HUD_SCALE=0.1` and `MTL_HUD_ELEMENTS=fps,frameinterval`. You can override any
[HUD variable](https://developer.apple.com/documentation/xcode/customizing-metal-performance-hud)
per game as a launch option, for example `MTL_HUD_ELEMENTS=fps,gputime,memory %command%`. Settings
for all games go in `~/Library/Application Support/notproton/global.env`, one `KEY=VALUE` per line;
a game's own launch options take precedence.

`install.sh steam` needs your terminal to have permission to modify other apps. Enable it in
**System Settings → Privacy & Security → App Management**.

Then start Steam. Windows-only games get an **Install** button and default to the compatibility
tool **Steam Play (Wine, self-built)**. Per game, use *Properties → Compatibility* to pick the
graphics backend (Automatic / D3DMetal / DXMT / WineD3D) and to toggle MetalFX/DLSS, the Metal
HUD, AVX, msync and Retina mode. You can also set these as launch options, for example
`CX_GRAPHICS_BACKEND=d3dmetal %command%`.

To uninstall: `scripts/install.sh uninstall-steam`. To get Valve's original signature back,
reinstall Steam.

## Logs

| What | Where |
|---|---|
| dylib (hooks, signature resolution) | `~/Library/Application Support/notproton/notproton.log` |
| per-game run script (prefix, bridge, graphics choice) | `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/notproton-run.log` |
| Wine output of the game | `~/Library/Application Support/notproton/launchers/<appid>/notproton-wine.log` |

For more detail, add `WINEDEBUG=+seh,+loaddll %command%` to the game's launch options.

## Risks

- **Steam.app is modified.** Its `Info.plist` gets an `LSEnvironment` insert (a backup is made
  first), and Valve's code signature is replaced by an ad-hoc one.
- **Steam updates.** An update can undo the patch, and a much newer client may need new signature
  databases. In that case the dylib hooks nothing and Steam behaves normally.
  `install.sh block-updates` stops the bootstrapper from updating itself.
- **Online games and anti-cheat.** Running games under Wine is not supported by their publishers.
  Use at your own risk.
- **Rosetta 2.** Apple has announced that general Rosetta support ends after macOS 27. The runner
  is x86_64.

## Repository layout

```
patches/series        order in which patches are applied to the CrossOver sources
patches/highball/     Highball engine patches (LGPL-2.1)
patches/valve/        ValveSoftware/wine commits, applied as-is; ported/ holds the originals of our port
patches/local/        our patches (ntdll lsteamclient port, build registration)
notproton/            submodule: Drustburn/NotProton, branch selfbuilt-wine
scripts/              build and install scripts
tests/d3dprobe.c      D3D11/D3D12 device probe
```

## Credits and licences

- **[NotProton](https://github.com/NotProtonNot/NotProton)** (GPL-3.0): the Steam-side work
  (`notproton.dylib`, the run script, the `lsteamclient` macOS port, the `steam.exe` shim). This
  project is a fork of it.
- **CodeWeavers**: the [CrossOver sources](https://www.codeweavers.com/crossover/source) (LGPL),
  including the D3DMetal/DXMT glue and msync. If you can, buy CrossOver. It funds most Wine
  development.
- **Highball engine** by gauthierpiarrette (LGPL-2.1): the macOS patches in `patches/highball/`.
- **Valve**: [Proton](https://github.com/ValveSoftware/Proton) and its
  [Wine](https://github.com/ValveSoftware/wine) (`lsteamclient` and the steamclient
  trampolines). `lsteamclient` and the Steam DLLs are fetched at build or install time.
- **[DXMT](https://github.com/3Shain/dxmt)** by Feifan He (v0.80, MIT).
- **D3DMetal**, from Apple's Game Porting Toolkit, through
  [Gcenx's repack](https://github.com/Gcenx/game-porting-toolkit): Apple licence, personal and
  non-commercial use on Apple hardware.
- **Wine** (LGPL-2.1+), **MoltenVK** (Apache-2.0), **FFmpeg** (LGPL), **SDL2** (zlib),
  **gnutls/nettle/gmp** (LGPL), **FreeType** (FTL/GPL).

The scripts and patches in this repository are GPL-3.0 (see `LICENSE`). Patches to Wine keep
Wine's licence.

This project is not affiliated with Valve, CodeWeavers, Apple, NCSOFT or the NotProton author.
