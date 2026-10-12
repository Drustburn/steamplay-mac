-- steamplay-mac installer and uninstaller. scripts/make-dmg.sh compiles this twice into
-- applets, with @MODE@ set to install or uninstall. Contents/Resources/payload has the layout
-- of a checkout and scripts/install.sh does the work; this asks, shows progress and turns
-- failures into something a person can act on.

property mode : "@MODE@"
property runnerID : "@RUNNER_ID@"
property appManagementURL : "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles"

on t(en, de)
	if (user locale of (system info)) starts with "de" then return de
	return en
end t

on run
	if mode is "uninstall" then
		uninstall()
	else
		install()
	end if
end run

on install()
	set home to POSIX path of (path to home folder)
	set installSh to quoted form of ((POSIX path of (path to me)) & "Contents/Resources/payload/scripts/install.sh")
	set logFile to home & "Library/Logs/steamplay-mac-install.log"
	set cacheDir to home & "Library/Caches/steamplay-mac"
	set envs to "export STEAMPLAY_DOWNLOADS=" & quoted form of cacheDir & " STEAMPLAY_BRIDGE=" & quoted form of (cacheDir & "/bridge") & "; "

	if not requirementsMet() then return

	display dialog t("steamplay-mac lets the macOS Steam client run Windows games with a self-built Wine.

The installer will:
• quit Steam
• download Valve's Windows Steam DLLs (about 100 MB) and Apple's D3DMetal (about 240 MB), each checked against a pinned hash
• install the Wine runner into ~/Library/Application Support/notproton
• modify /Applications/Steam.app: it loads notproton.dylib, and Valve's signature is replaced by an ad-hoc one

This is experimental. Online games and anti-cheat: at your own risk.", "Mit steamplay-mac startet der macOS-Steam-Client Windows-Spiele über ein selbst gebautes Wine.

Der Installer wird:
• Steam beenden
• Valves Windows-Steam-DLLs (ca. 100 MB) und Apples D3DMetal (ca. 240 MB) herunterladen und jeweils gegen eine feste Prüfsumme prüfen
• das Wine-Paket nach ~/Library/Application Support/notproton installieren
• /Applications/Steam.app verändern: Steam lädt notproton.dylib, und Valves Signatur wird durch eine Ad-hoc-Signatur ersetzt

Das Projekt ist experimentell. Online-Spiele und Anti-Cheat: auf eigenes Risiko.") buttons {t("Cancel", "Abbrechen"), t("Install", "Installieren")} default button 2 cancel button 1 with title "steamplay-mac" with icon note

	set blockLabel to t("Block updates", "Updates blockieren")
	set answer to button returned of (display dialog t("Stop Steam from updating itself? Recommended: a Steam update can undo the patch. The uninstaller allows updates again.", "Soll Steam sich nicht mehr selbst aktualisieren? Empfohlen, denn ein Steam-Update kann die Anpassung rückgängig machen. Der Deinstaller erlaubt Updates wieder.") buttons {t("Allow updates", "Updates erlauben"), blockLabel} default button 2 with title "steamplay-mac" with icon note)
	set blockUpdates to (answer is blockLabel)

	do shell script "mkdir -p " & quoted form of (home & "Library/Logs") & " && date > " & quoted form of logFile

	set progress total steps to 3
	set progress completed steps to 0
	set progress description to t("Installing steamplay-mac", "steamplay-mac wird installiert")
	set progress additional description to t("Downloading Valve's Steam DLLs and D3DMetal, copying the Wine runner. This takes a few minutes…", "Valves Steam-DLLs und D3DMetal werden geladen, das Wine-Paket wird kopiert. Das dauert ein paar Minuten…")
	if not runLogged(envs & installSh & " support " & runnerID, logFile) then return
	set progress completed steps to 1
	set progress additional description to t("Patching Steam…", "Steam wird angepasst…")
	if not runTouchingSteam(envs & installSh & " steam", logFile) then return
	set progress completed steps to 2
	if blockUpdates then
		if not runLogged(envs & installSh & " block-updates", logFile) then return
	end if
	set progress completed steps to 3

	set openLabel to t("Open Steam", "Steam öffnen")
	set answer to button returned of (display dialog t("steamplay-mac is installed.

Start Steam: Windows-only games get an Install button and run with “Steam Play (Wine, self-built)”. Per game, Properties → Compatibility picks the graphics backend and options.", "steamplay-mac ist installiert.

Starte Steam: Reine Windows-Spiele bekommen einen Installieren-Knopf und laufen mit „Steam Play (Wine, self-built)“. Pro Spiel wählst du unter Eigenschaften → Kompatibilität das Grafik-Backend und weitere Optionen.") buttons {t("Done", "Fertig"), openLabel} default button 2 with title "steamplay-mac" with icon note)
	if answer is openLabel then do shell script "open -a Steam"
end install

on uninstall()
	set home to POSIX path of (path to home folder)
	set installSh to quoted form of ((POSIX path of (path to me)) & "Contents/Resources/payload/scripts/install.sh")
	set logFile to home & "Library/Logs/steamplay-mac-uninstall.log"

	display dialog t("This removes steamplay-mac:
• Steam is quit and Steam.app restored (Valve's own signature only comes back if you reinstall Steam from steampowered.com)
• Steam may update itself again
• the Wine runner and helpers in ~/Library/Application Support/notproton are deleted

Your games and their Windows prefixes in Steam's compatdata folder stay.", "Das entfernt steamplay-mac:
• Steam wird beendet und Steam.app wiederhergestellt (Valves eigene Signatur kommt nur zurück, wenn du Steam von steampowered.com neu installierst)
• Steam darf sich wieder selbst aktualisieren
• das Wine-Paket und die Hilfsprogramme in ~/Library/Application Support/notproton werden gelöscht

Deine Spiele und ihre Windows-Prefixe im compatdata-Ordner von Steam bleiben erhalten.") buttons {t("Cancel", "Abbrechen"), t("Uninstall", "Deinstallieren")} default button 2 cancel button 1 with title "steamplay-mac" with icon caution

	do shell script "mkdir -p " & quoted form of (home & "Library/Logs") & " && date > " & quoted form of logFile
	if not runTouchingSteam(installSh & " uninstall", logFile) then return
	do shell script "rm -rf " & quoted form of (home & "Library/Caches/steamplay-mac")
	display dialog t("steamplay-mac has been removed.", "steamplay-mac wurde entfernt.") buttons {"OK"} default button 1 with title "steamplay-mac" with icon note
end uninstall

on requirementsMet()
	if (do shell script "uname -m") is not "arm64" then
		display alert "steamplay-mac" message t("steamplay-mac needs a Mac with Apple silicon.", "steamplay-mac braucht einen Mac mit Apple-Chip.") as critical
		return false
	end if
	if ((do shell script "sw_vers -productVersion | cut -d. -f1") as integer) < 14 then
		display alert "steamplay-mac" message t("steamplay-mac needs macOS 14 or later.", "steamplay-mac braucht macOS 14 oder neuer.") as critical
		return false
	end if
	if (do shell script "test -d /Applications/Steam.app && echo yes || echo no") is "no" then
		set getLabel to t("Get Steam", "Steam herunterladen")
		set answer to button returned of (display alert "steamplay-mac" message t("Steam is not in the Applications folder. Install Steam for macOS, start it once, then open this installer again.", "Steam ist nicht im Programme-Ordner. Installiere Steam für macOS, starte es einmal und öffne dann diesen Installer erneut.") buttons {"OK", getLabel} default button 2)
		if answer is getLabel then open location "https://store.steampowered.com/about/"
		return false
	end if
	if (do shell script "/usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null && echo yes || echo no") is "no" then
		display dialog t("Windows games run under Rosetta 2, which is not installed yet. Install it now? Apple's licence for Rosetta applies.", "Windows-Spiele laufen unter Rosetta 2, das noch nicht installiert ist. Jetzt installieren? Es gilt Apples Lizenz für Rosetta.") buttons {t("Cancel", "Abbrechen"), t("Install Rosetta", "Rosetta installieren")} default button 2 cancel button 1 with title "steamplay-mac" with icon note
		try
			do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges
		on error errText number errNum
			if errNum is -128 then error number -128
			display alert "steamplay-mac" message errText as critical
			return false
		end try
	end if
	return true
end requirementsMet

-- Runs one install.sh step, its output appended to the log; a failure shows the log's end.
on runLogged(cmd, logFile)
	try
		do shell script cmd & " >> " & quoted form of logFile & " 2>&1"
		return true
	on error
		showFailure(logFile)
		return false
	end try
end runLogged

-- Like runLogged, for steps that write into /Applications/Steam.app. macOS lets only apps
-- the user allowed under App Management do that; the first try fails, so point there and retry.
on runTouchingSteam(cmd, logFile)
	repeat
		try
			do shell script cmd & " >> " & quoted form of logFile & " 2>&1"
			return true
		on error
			set tailText to do shell script "tail -n 20 " & quoted form of logFile
			if tailText does not contain "Operation not permitted" then
				showFailure(logFile)
				return false
			end if
			do shell script "open " & quoted form of appManagementURL
			display dialog t("macOS did not let the installer modify Steam.

In System Settings → Privacy & Security → App Management, switch this app on. If it is not listed, add it with +. Then click Try Again.", "macOS hat dem Installer nicht erlaubt, Steam zu verändern.

Schalte diese App unter Systemeinstellungen → Datenschutz & Sicherheit → App-Verwaltung ein. Steht sie nicht in der Liste, füge sie mit + hinzu. Klicke dann auf „Erneut versuchen“.") buttons {t("Cancel", "Abbrechen"), t("Try Again", "Erneut versuchen")} default button 2 cancel button 1 with title "steamplay-mac" with icon caution
		end try
	end repeat
end runTouchingSteam

on showFailure(logFile)
	set tailText to do shell script "tail -n 12 " & quoted form of logFile
	set showLabel to t("Show Log", "Log anzeigen")
	set answer to button returned of (display alert t("Something went wrong", "Etwas ist schiefgegangen") message tailText as critical buttons {showLabel, "OK"} default button 2)
	if answer is showLabel then do shell script "open -e " & quoted form of logFile
end showFailure
