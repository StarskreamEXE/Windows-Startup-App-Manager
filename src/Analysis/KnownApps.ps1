# Knowledge base: plain-English explanations for common startup items.
# Order matters - specific patterns before generic ones. First match wins.

Set-StrictMode -Version 2.0

function New-SMKA { param($M,$W,$E,$D,$R) @{ Match=$M; What=$W; Explain=$E; DisableEffect=$D; Risk=$R } }

$script:SMKnownApps = @(
    # ---- Windows / security / drivers -------------------------------------------------
    (New-SMKA 'SecurityHealth|SecurityHealthSystray' 'Windows Security tray icon' 'Shows the shield icon in the tray and surfaces Windows Security alerts. Not the antivirus engine itself.' 'The shield icon disappears from the tray. Defender keeps protecting you, but you may miss alerts.' 'Caution')
    (New-SMKA 'MsMpEng|Windows Defender|WinDefend|Sense\b' 'Microsoft Defender' 'The built-in antivirus / EDR engine.' 'Do not disable. You lose real-time malware protection.' 'Critical')
    (New-SMKA 'RtkAudUService|Realtek.*Audio|RAVBg64|RAVCpl64' 'Realtek audio service' 'Realtek HD audio helper. Handles jack detection, audio effects and the Realtek control panel.' 'Sound usually keeps working, but headphone jack auto-switching and audio effects may stop.' 'Critical')
    (New-SMKA 'NVDisplay|NVIDIA Display Container|nvcontainer' 'NVIDIA display driver container' 'Hosts NVIDIA Control Panel, telemetry and driver helper services.' 'Do not disable. NVIDIA Control Panel and some GPU features stop working.' 'Critical')
    (New-SMKA 'NVIDIA App|GeForce Experience|NvBackend|ShadowPlay|NvNode' 'NVIDIA App / GeForce Experience' 'Game optimisation, driver updates, overlay and ShadowPlay recording.' 'No overlay or instant replay until you open the app manually. Drivers still work.' 'Optional')
    (New-SMKA 'AMD.*Radeon|RadeonSoftware|AMDRSServ|StartCN' 'AMD Radeon software' 'AMD graphics control panel and helper.' 'Radeon Settings overlay/tray goes away; the driver itself keeps working.' 'Caution')
    (New-SMKA 'Intel.*Graphics|igfx|IntelGraphics' 'Intel graphics helper' 'Intel graphics command center / hotkeys.' 'Intel hotkeys and tray settings stop; display still works.' 'Caution')
    (New-SMKA 'Intel.*(DSA|Driver.*Support)' 'Intel Driver & Support Assistant' 'Checks for Intel driver updates in the background.' 'No automatic Intel driver update checks.' 'Optional')
    (New-SMKA 'OneDrive' 'Microsoft OneDrive sync' 'Keeps your OneDrive folder in sync with the cloud.' 'Files in OneDrive stop syncing until you open OneDrive yourself.' 'Caution')
    (New-SMKA 'MicrosoftEdgeUpdate|EdgeUpdate' 'Microsoft Edge updater' 'Background update task for Edge and WebView2.' 'Edge still updates when you open it; background updates stop.' 'Optional')
    (New-SMKA 'MicrosoftEdgeAutoLaunch|msedge\.exe.*--no-startup-window' 'Edge pre-launch (startup boost)' 'Starts Edge silently at logon so it opens faster later.' 'Edge takes slightly longer to open the first time. Nothing else changes. Safe to disable.' 'Optional')
    (New-SMKA '\bTeams\b|MSTeams' 'Microsoft Teams' 'Opens Teams at logon.' 'Teams will not be running until you open it; you will not get calls/messages until then.' 'Caution')
    (New-SMKA 'Phone Link|YourPhone' 'Phone Link' 'Connects Windows to your phone for notifications/messages.' 'Phone notifications stop until you open Phone Link.' 'Optional')
    (New-SMKA 'PowerToys' 'Microsoft PowerToys' 'Utilities such as FancyZones, PowerToys Run, Keyboard Manager.' 'All PowerToys features (window snapping, Run launcher, key remaps) are off until you start it.' 'Caution')
    (New-SMKA 'Windows Terminal|WindowsTerminal' 'Windows Terminal' 'Launches Terminal at logon (or its quake-mode hotkey).' 'Terminal does not pre-launch. Safe.' 'Optional')
    (New-SMKA 'Ctfmon|ctfmon' 'Text input framework' 'Language bar, IME and touch keyboard input.' 'Do not disable. Typing in some languages and the on-screen keyboard can break.' 'Critical')
    (New-SMKA 'npcap' 'Npcap packet-capture driver watchdog' 'Keeps the Npcap driver (used by Wireshark, Nmap) registered.' 'Wireshark/Nmap capture may fail until Npcap is repaired.' 'Caution')

    # ---- browsers / updaters -----------------------------------------------------------
    (New-SMKA 'GoogleChromeAutoLaunch|chrome\.exe.*--no-startup-window' 'Google Chrome background mode' 'Keeps Chrome running in the background for extensions and notifications.' 'Chrome only runs when you open it. Push notifications from sites stop until then. Safe.' 'Optional')
    (New-SMKA 'GoogleUpdater|GoogleUpdate|Google Update' 'Google updater' 'Updates Chrome, Drive and other Google software in the background.' 'Google apps update only when opened. Safe.' 'Optional')
    (New-SMKA 'GoogleUserPEH|PlatformExperienceHelper' 'Google platform experience helper' 'Google telemetry / experience helper task.' 'Nothing user-visible. Safe.' 'Optional')
    (New-SMKA 'Google Drive|GoogleDriveFS' 'Google Drive for desktop' 'Syncs Google Drive to your PC.' 'Drive files stop syncing until you open it.' 'Caution')
    (New-SMKA 'Brave' 'Brave browser helper/updater' 'Brave background launch or updater.' 'Brave only runs when opened. Safe.' 'Optional')
    (New-SMKA 'Firefox|Mozilla' 'Firefox / Mozilla helper' 'Firefox background agent or updater.' 'Firefox only runs when opened. Safe.' 'Optional')
    (New-SMKA '\bOpera\b' 'Opera browser helper' 'Opera auto-launch or updater.' 'Opera only runs when opened. Safe.' 'Optional')

    # ---- cloud / comms -----------------------------------------------------------------
    (New-SMKA 'Dropbox' 'Dropbox sync' 'Keeps your Dropbox folder in sync.' 'Dropbox stops syncing until opened.' 'Caution')
    (New-SMKA 'Discord' 'Discord' 'Opens Discord at logon.' 'Discord is not running until you open it; you will not hear calls/pings until then.' 'Caution')
    (New-SMKA '\bSlack\b' 'Slack' 'Opens Slack at logon.' 'No Slack notifications until you open it.' 'Caution')
    (New-SMKA '\bZoom\b' 'Zoom' 'Zoom launcher / updater.' 'Zoom opens only when you join a meeting. Safe.' 'Optional')
    (New-SMKA 'signal-desktop|Signal' 'Signal Desktop' 'Opens Signal at logon.' 'No Signal desktop notifications until you open it.' 'Caution')
    (New-SMKA 'Telegram' 'Telegram Desktop' 'Opens Telegram at logon.' 'No Telegram desktop notifications until you open it.' 'Caution')
    (New-SMKA 'WhatsApp' 'WhatsApp Desktop' 'Opens WhatsApp at logon.' 'No WhatsApp desktop notifications until you open it.' 'Caution')
    (New-SMKA 'Spotify' 'Spotify' 'Opens Spotify (often minimised) at logon.' 'Spotify opens only when you launch it. Safe.' 'Optional')
    (New-SMKA 'iTunes|iCloud|Apple.*Mobile|AppleMobileDeviceService|Bonjour' 'Apple helper' 'iTunes/iCloud helper or device service.' 'iPhone sync/iCloud photos may not run until you open the Apple app.' 'Caution')
    (New-SMKA 'Adobe.*Creative Cloud|CCXProcess|CCLibrary|Creative Cloud' 'Adobe Creative Cloud' 'Adobe app launcher, updater and font sync.' 'Adobe apps still open. Fonts/cloud sync and updates run only when you open Creative Cloud. Safe.' 'Optional')
    (New-SMKA 'AdobeGCClient|AGS|Adobe Genuine' 'Adobe Genuine Service' 'Adobe licence verification.' 'Usually nothing changes. If Adobe apps complain, re-enable.' 'Optional')
    (New-SMKA 'Adobe.*(Acrobat|ARM|Update)' 'Adobe Acrobat updater' 'Checks for Acrobat/Reader updates.' 'Acrobat updates only when you run it. Safe.' 'Optional')
    (New-SMKA 'Adobe' 'Adobe helper' 'Adobe background helper.' 'Adobe apps still open normally. Safe.' 'Optional')

    # ---- gaming ------------------------------------------------------------------------
    (New-SMKA 'Steam' 'Steam' 'Opens Steam at logon (downloads, friends, cloud saves).' 'Steam is not running until you launch it or a game; games take a few seconds longer the first time.' 'Optional')
    (New-SMKA 'Epic.*Games|EpicGamesLauncher' 'Epic Games Launcher' 'Opens Epic launcher at logon.' 'Epic opens only when you launch it. Safe.' 'Optional')
    (New-SMKA '\bEA (app|Desktop)|EABackgroundService|EADesktop|\bOrigin\b' 'EA app' 'EA launcher background service.' 'EA opens only when you launch a game. Safe.' 'Optional')
    (New-SMKA 'Ubisoft|Uplay' 'Ubisoft Connect' 'Ubisoft launcher.' 'Opens only when you launch a game. Safe.' 'Optional')
    (New-SMKA 'GOG|Galaxy' 'GOG Galaxy' 'GOG launcher.' 'Opens only when you launch it. Safe.' 'Optional')
    (New-SMKA 'Battle\.net|Blizzard' 'Battle.net' 'Blizzard launcher.' 'Opens only when you launch it. Safe.' 'Optional')
    (New-SMKA 'Xbox|GameBar|GamingServices' 'Xbox / Game Bar' 'Xbox app, Game Bar overlay or Gaming Services.' 'Game Bar overlay (Win+G) or Xbox app features may not work until opened.' 'Caution')

    # ---- peripherals / RGB -------------------------------------------------------------
    (New-SMKA 'Logitech|LGHUB|Logi' 'Logitech software' 'G HUB / Options+ - profiles, macros, lighting.' 'Mouse/keyboard still work with default settings; custom buttons, DPI profiles and lighting are off.' 'Caution')
    (New-SMKA 'Razer|Synapse' 'Razer Synapse' 'Razer profiles, macros, lighting.' 'Devices still work with defaults; custom settings and lighting are off.' 'Caution')
    (New-SMKA 'Corsair|iCUE' 'Corsair iCUE' 'Corsair lighting, fans, profiles.' 'Fans/AIO fall back to firmware defaults; lighting and macros are off.' 'Caution')
    (New-SMKA 'SteelSeries' 'SteelSeries GG' 'SteelSeries device software.' 'Devices work with defaults; custom settings off.' 'Caution')
    (New-SMKA 'MSI.*(Center|Afterburner)|RTSS' 'MSI Center / Afterburner' 'Fan curves, overclocks, overlay.' 'Custom fan curves and overclocks are not applied until you open it.' 'Caution')
    (New-SMKA 'Armoury|ASUS|LightingService' 'ASUS Armoury Crate / Aura' 'ASUS lighting and device software.' 'Lighting and fan profiles fall back to defaults.' 'Caution')
    (New-SMKA 'Wacom|Tablet' 'Tablet driver helper' 'Pen tablet driver settings.' 'Pen may lose pressure sensitivity or custom buttons.' 'Caution')

    # ---- dev / virtualisation / AI -------------------------------------------------------
    (New-SMKA 'Docker' 'Docker Desktop' 'Starts the Docker engine at logon.' 'Containers do not start until you open Docker Desktop. Safe if you do not need them at boot.' 'Optional')
    (New-SMKA 'WSL|wsl\.exe' 'Windows Subsystem for Linux' 'WSL background launch.' 'Linux distros start on first use instead. Safe.' 'Optional')
    (New-SMKA 'VMware' 'VMware helper' 'VMware tray / services.' 'VMs do not auto-start; VMware Workstation still opens.' 'Caution')
    (New-SMKA 'VirtualBox|VBox' 'VirtualBox helper' 'VirtualBox tray / services.' 'VMs do not auto-start. Safe.' 'Optional')
    (New-SMKA 'MEmu|MEmuSVC' 'MEmu Android emulator service' 'Background service for the MEmu emulator.' 'MEmu still works when you open it. Safe.' 'Optional')
    (New-SMKA 'BlueStacks' 'BlueStacks service' 'Android emulator background service.' 'BlueStacks still works when opened. Safe.' 'Optional')
    (New-SMKA 'LM Studio|lmstudio' 'LM Studio' 'Local LLM app; may keep its server running.' 'The local model server is not running until you open LM Studio.' 'Optional')
    (New-SMKA 'Ollama' 'Ollama' 'Local LLM server.' 'Apps that call Ollama fail until you start it.' 'Caution')
    (New-SMKA 'Claude|claude-bridge|OpenClaw|skream-agent' 'Claude / automation agent' 'A watchdog or bridge for Claude Code / your automation stack.' 'Remote access or automation that depends on this agent stops working until you start it.' 'Caution')
    (New-SMKA '\bGit\b|GitHub Desktop' 'Git helper' 'GitHub Desktop or Git credential helper.' 'Safe; run it when needed.' 'Optional')
    (New-SMKA 'Java.*Update|jusched' 'Java updater' 'Checks for Java updates.' 'Java updates only when you run it. Safe.' 'Optional')
    (New-SMKA '(node|python|pythonw)\.exe' 'Script-launched background agent' 'A Node or Python script started at logon - usually a custom tool, bot or watchdog.' 'Whatever that script does stops. Check the command line to know what it is.' 'Caution')
    (New-SMKA 'electron\.app\.' 'Electron app auto-launch' 'An Electron-based app (chat, notes, tools) registered itself to start at logon.' 'The app opens only when you launch it.' 'Optional')

    # ---- utilities --------------------------------------------------------------------
    (New-SMKA 'Everything' 'Everything (voidtools search)' 'Instant file search; keeps its index in memory.' 'Search is slower to start the first time you open Everything. Safe.' 'Optional')
    (New-SMKA 'Ditto' 'Ditto clipboard manager' 'Clipboard history.' 'No clipboard history until you open Ditto.' 'Optional')
    (New-SMKA 'ShareX|Greenshot|Lightshot|Snagit' 'Screenshot tool' 'Screenshot / capture hotkeys.' 'Capture hotkeys do not work until you open the tool.' 'Optional')
    (New-SMKA 'AutoHotkey|\.ahk' 'AutoHotkey script' 'A custom hotkey/macro script.' 'Your custom hotkeys stop working.' 'Caution')
    (New-SMKA 'Rainmeter' 'Rainmeter' 'Desktop widgets.' 'Widgets are gone until you open Rainmeter. Safe.' 'Optional')
    (New-SMKA 'Wallpaper Engine|wallpaper32|wallpaper64' 'Wallpaper Engine' 'Animated wallpapers.' 'Static wallpaper until you open it. Safe.' 'Optional')
    (New-SMKA 'f\.lux|\bflux\b' 'f.lux' 'Screen colour temperature.' 'No warm-tint at night until you open it.' 'Optional')
    (New-SMKA 'Grammarly' 'Grammarly' 'Grammar checker helper.' 'No system-wide grammar checks until opened. Safe.' 'Optional')
    (New-SMKA '1Password|Bitwarden|KeePass|LastPass|Dashlane' 'Password manager' 'Keeps your password manager available for autofill.' 'Browser autofill may not work until you open the app.' 'Caution')
    (New-SMKA 'qBittorrent|uTorrent|Transmission' 'Torrent client' 'Opens the torrent client at logon.' 'Downloads/seeding stop until you open it. Safe.' 'Optional')
    (New-SMKA '\bOBS\b' 'OBS Studio' 'Streaming/recording app.' 'Opens only when you launch it. Safe.' 'Optional')
    (New-SMKA 'Notion|Obsidian|Evernote' 'Notes app' 'Opens the notes app at logon.' 'Opens only when you launch it. Safe.' 'Optional')
    (New-SMKA 'Malwarebytes|Bitdefender|Norton|McAfee|Avast|\bAVG\b|Kaspersky|\bESET\b|Sophos|Webroot' 'Third-party antivirus' 'Security software.' 'Do not disable unless you are replacing it. You lose protection.' 'Critical')
    (New-SMKA 'CCleaner' 'CCleaner' 'Cleaner tray helper.' 'Nothing important. Safe.' 'Optional')
    (New-SMKA 'Windhawk' 'Windhawk' 'Windows customisation mods.' 'Your Windhawk mods are not applied.' 'Caution')
    (New-SMKA 'AutoLock|RemoveWatermark' 'Custom logon tweak' 'A user-created task that tweaks the desktop at logon.' 'The tweak stops applying.' 'Optional')

    # ---- generic last-resort patterns ---------------------------------------------------
    (New-SMKA 'watchdog|daemon|agent' 'Background agent / watchdog' 'A custom background process that keeps something else alive.' 'Whatever it watches will no longer be restarted automatically.' 'Caution')
    (New-SMKA 'update|updater|upgrade|maintenance' 'Auto-updater' 'Checks for updates for an installed app.' 'The app updates only when you open it. Safe.' 'Optional')
    (New-SMKA 'crash|report|telemetry|feedback|diagnostic' 'Crash reporter / telemetry' 'Sends crash or usage data to the vendor.' 'Nothing user-visible. Safe.' 'Optional')
    (New-SMKA 'helper|tray|launcher|scheduler' 'Tray helper / launcher' 'A small helper that sits in the tray for an installed app.' 'The app still works when you open it. Safe.' 'Optional')
)

function Find-SMKnownApp {
    [CmdletBinding()]
    param([string] $Name = '', [string] $Command = '')
    $hay = "$Name | $Command"
    foreach ($k in $script:SMKnownApps) {
        if ($hay -imatch $k.Match) { return $k }
    }
    return $null
}
