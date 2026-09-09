# Troubleshooting

## Setup

Extract the full ZIP before running `Install.bat`. Do not run the executable from inside the archive or move it away from its neighboring files. Use 64-bit Windows PowerShell 5.1 (`powershell.exe`), not PowerShell 7 (`pwsh`). No Python, Node.js, or .NET SDK is required.

For an isolated copy without installed fonts, shortcuts, or app registration:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install.ps1 -Dest C:\Temp\StartupManager -Portable
```

To upgrade, close the app and install the new extracted copy to the same destination. Do not install a directory into itself. Installation preserves existing runtime data and rebuilds the launcher. Portable mode does not undo registration from an earlier normal installation.

Uninstall preserves the app folder with a timestamped `.uninstalled-` suffix. Shared per-user fonts remain installed. For a portable copy, run `Uninstall.ps1 -Portable`; normal uninstall verifies that it is running from the registered installation and only removes its own shortcuts from use.

## Apply, refresh, and recovery

Disabled items remain in the list so they can be re-enabled; they are not deleted. Inspect the confirmed state and pending/error indicators. Applications and organization policy can restore their own startup settings. Refresh before making further changes.

If a backup or recovery journal cannot be written, check free space and write permissions on the app's runtime directories. Do not discard recovery files to clear an error. Keep the error text and a private copy of the relevant logs. Never blindly import a registry export over current configuration.

Service startup type changes can affect Windows functionality. Use a disposable test service for experiments. Do not enable arbitrary disabled services or disable dependencies based only on a risk label.

## Missing entries or measurements

Check scan warnings and provider availability. Access restrictions, device policy, unavailable event logs, and absent boot measurements can limit results. An unknown signature or missing boot measurement is not proof of malware. Boot timings are historical observations, not a prediction of the next boot.

Elevation using a different account changes the user profile being inspected. Avoid cross-user credential elevation when trying to inspect your own HKCU entries. Cross-user inventory is not a supported feature.

## Display and accessibility

Use the zoom reset control or Ctrl+0 first. Ctrl+mouse wheel adjusts app zoom without bitmap scaling. If fonts are unavailable, the app uses fallback fonts; normal installation attempts per-user font installation. Test reduced motion and Windows display scale independently from app zoom.

## Getting help

Include app version, Windows build, provider, and minimal steps with a disposable entry. Review any screenshot or export before attaching it. Do not attach raw backups, registry dumps, full command lines, or personal paths publicly. For sensitive defects, follow [SECURITY.md](../SECURITY.md).
