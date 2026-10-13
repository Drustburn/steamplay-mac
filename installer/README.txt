steamplay-mac @VERSION@
=======================

Windows Steam games in the macOS Steam client, with a self-built Wine.
Deutsch weiter unten.

INSTALL
1. Install Steam for macOS in /Applications and start it once.
2. Double-click "Install steamplay-mac".
   If macOS says it cannot check the app for malicious software: open System Settings →
   Privacy & Security, scroll down and click "Open Anyway" next to "Install steamplay-mac".
   The app is not notarised by Apple, which is why macOS asks.
3. When the installer asks for App Management, switch it on in System Settings → Privacy &
   Security → App Management, then click Try Again. It needs this to modify Steam.app.
4. Start Steam. Windows-only games get an Install button and run with
   "Steam Play (Wine, self-built)".

While installing, the installer downloads Valve's Windows Steam DLLs (from Valve's CDN) and
Apple's D3DMetal (Game Porting Toolkit 3.0, Gcenx's repack on GitHub), about 340 MB, and checks
each against a pinned hash. Neither is part of this disk image.

UNINSTALL
Double-click "Uninstall steamplay-mac". Valve's own signature on Steam.app only comes back if you
reinstall Steam from steampowered.com.

RISKS
Steam.app is modified and re-signed ad hoc. Running games under Wine is not supported by their
publishers; online games and anti-cheat are at your own risk. Logs: ~/Library/Logs/steamplay-mac-*.log

---

INSTALLIEREN
1. Steam für macOS in /Programme installieren und einmal starten.
2. "Install steamplay-mac" doppelklicken.
   Meldet macOS, dass es die App nicht auf Schadsoftware prüfen kann: Systemeinstellungen →
   Datenschutz & Sicherheit öffnen, nach unten scrollen und bei "Install steamplay-mac" auf
   "Dennoch öffnen" klicken. Die App ist nicht von Apple notarisiert, deshalb fragt macOS nach.
3. Fragt der Installer nach der App-Verwaltung: unter Systemeinstellungen → Datenschutz &
   Sicherheit → App-Verwaltung einschalten und dann "Erneut versuchen" klicken. Die Berechtigung
   ist nötig, um Steam.app zu verändern.
4. Steam starten. Reine Windows-Spiele bekommen einen Installieren-Knopf und laufen mit
   "Steam Play (Wine, self-built)".

Während der Installation lädt der Installer Valves Windows-Steam-DLLs (von Valves CDN) und Apples
D3DMetal (Game Porting Toolkit 3.0, Gcenx' Repack auf GitHub) herunter, zusammen etwa 340 MB, und
prüft beides gegen feste Prüfsummen. Keins davon ist Teil dieses Disk-Images.

DEINSTALLIEREN
"Uninstall steamplay-mac" doppelklicken. Valves eigene Signatur auf Steam.app kommt nur zurück,
wenn du Steam von steampowered.com neu installierst.

RISIKEN
Steam.app wird verändert und ad hoc neu signiert. Die Hersteller unterstützen ihre Spiele unter
Wine nicht; Online-Spiele und Anti-Cheat auf eigenes Risiko. Logs: ~/Library/Logs/steamplay-mac-*.log

---

SOURCE CODE AND LICENCES / QUELLCODE UND LIZENZEN
This disk image contains binaries built from:
- steamplay-mac, commit @COMMIT@: https://github.com/Drustburn/steamplay-mac
  (build scripts, Wine patches, and the NotProton fork as a submodule; GPL-3.0)
- NotProton fork, commit @NP_COMMIT@: https://github.com/Drustburn/NotProton (GPL-3.0)
- Wine from the CrossOver 26.3.0 sources (LGPL-2.1+):
  https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz
  with the patches in patches/ of the commit above
- Valve's lsteamclient from Proton (see Licenses/LICENSE.lsteamclient), DXMT v0.80 (MIT),
  MoltenVK (Apache-2.0), FFmpeg (LGPL), SDL2 (zlib), gnutls/nettle/gmp (LGPL), FreeType,
  Wine Mono and Wine Gecko
- aion2-wine-compat by Yuki-fox (MIT, Licenses/LICENSE.aion2-wine-compat):
  https://github.com/Yuki-fox/aion2-wine-compat, copied into the NotProton fork's gamefixes/aion2
Runner: @RUNNER_ID@. The licence texts are in the Licenses folder.

CodeWeavers' CrossOver funds most of the Wine development for macOS. If you can, buy it:
https://www.codeweavers.com/crossover
