# Release checklist

## Build prerequisites

Use 64-bit Windows PowerShell 5.1 on Windows with .NET Framework 4.x and its C# compiler. The app has no NuGet or npm build dependencies. Tests intentionally target Pester **3.4.0**, not the incompatible Pester 5 API.

```powershell
Install-Module Pester -RequiredVersion 3.4.0 -Scope CurrentUser -Force -SkipPublisherCheck
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File build\Build-Release.ps1 -OutputDirectory C:\Temp\startup-manager-release-2.1.0
```

Choose an output directory that does not already exist. The build preserves its staging directory and produces `Windows-Startup-App-Manager-2.1.0.zip`, `Windows-Startup-App-Manager-Setup-2.1.0.exe`, and `SHA256SUMS.txt` covering both downloads. ZIP contents come only from `build/Release-Files.psd1`; runtime data, internal instructions, old screenshots, and Git history are not included. Add new runtime files to that manifest explicitly. The launcher is compiled from the staged source, never reused from an existing binary.

The Setup EXE is a self-contained x64 installer with that exact ZIP embedded. Double-click it to confirm installation; it needs no downloads, external package manager, or administrator access for setup. It extracts into a unique `%LOCALAPPDATA%\StartupManager\Setup\<id>` directory, runs Windows PowerShell `Install.ps1 -Launch`, reports failure/success, and retains `setup.log` and extracted source for inspection. App launch requests administrator approval separately. Close an existing app instance before upgrading. Do not publish the bare `StartupManager.exe` launcher as a standalone download: it requires its neighboring application files.

To inspect the bundled payload without installing, use an extraction path that does not exist:

```powershell
$process = Start-Process .\Windows-Startup-App-Manager-Setup-2.1.0.exe -ArgumentList '/extract-only "C:\Temp\startup-manager-inspect"' -PassThru -Wait
$process.ExitCode
```

Extraction-only returns 0 on success or 1 on failure, with no installation, font registration, shortcuts, elevation, or app launch. Existing destinations, duplicate entries, traversal paths, alternate data streams, reserved device names, archive links, and extraction through existing reparse points are rejected. Normal setup presents errors in a dialog; extraction-only is intentionally noninteractive.

Update the version consistently in `build/Release-Files.psd1`, `build/Launcher.cs`, `build/Installer.cs`, both build manifests, and the changelog. Publish only after reviewing a fresh clone and the exact ZIP/EXE contents. Do not upload the staging directory. Keep normal commit history after the initial public release.

CI runs headless tests and builds downloadable artifacts. It does not create releases, publish the repository, approve security prompts, or prove that startup behavior survives a real Windows reboot.

When the maintainer approves public visibility, enable GitHub private vulnerability reporting
under repository Settings > Advanced Security. GitHub exposes this reporting feature for
public repositories; see [GitHub's configuration guide](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository).

## Clean-machine acceptance matrix

Use disposable virtual machines and snapshots. Record OS build, architecture, display scale, app version, result, and any exception. Automated checks do not substitute for these manual gates.

| Gate | Procedure | Required outcome |
|---|---|---|
| Windows 11 x64 | Fresh standard user and administrator accounts; install into a path containing spaces | Installation completes without startup changes; notices are present; UAC behavior is clear |
| Setup EXE | Double-click Setup, then cancel and accept its confirmation in separate runs; inspect failure on denied destination | Cancellation performs no install; accepted setup reports the actual installer result; no UAC until app launch |
| Windows 10 x64 | Repeat on an appropriately maintained Windows 10 installation | Record actual compatibility; do not infer testing from the manifest |
| Portable | `Install.ps1 -Dest C:\Temp\StartupManager -Portable` | No font, shortcut, or Installed-apps registration; app runs from destination |
| Upgrade | Close app, install newer source into existing destination | Launcher version changes; logs, backups, settings, and reports survive |
| Uninstall | Run installed `Uninstall.ps1`; use `-Portable` only for portable copies | Registration/owned shortcuts removed from use; folder preserved with timestamp; no unrelated shortcuts changed |
| Safe Apply | Disposable user Run entry, startup shortcut, scheduled task, and nonessential test service | Readback agrees with Apply; inspect enabled and disabled cases after refresh and reboot |
| Partial failure | Deny write access to one disposable entry or recovery directory | No false success; pending failures and clear recovery errors remain visible |
| Recovery | Multiple same-named entries in different locations; apply a batch then undo | Exact entries and original settings restored; failed recovery is visible |
| Provider access | Standard user, policy-managed entry, missing boot log | Scan identifies unavailable or restricted information rather than claiming complete coverage |
| UI | 100/125/150/175/200% DPI, narrow/wide window, multi-monitor move, zoom and reset | No clipped controls or sideways scrolling; readable text; keyboard access works |
| Motion | Enable reduced motion, restart, resize and zoom | Preference persists; wordmark animation stops |
| Reports | Full and share-safe exports with synthetic usernames/arguments | HTML remains escaped; share-safe output contains none of the seeded private fields |

Only Windows desktop x64 with Windows PowerShell 5.1 is the release target. Windows Server, ARM64, PowerShell 7, remote/headless use, and cross-user administration are not validated support targets. Do not describe unexecuted matrix rows as passed. Windows 10 compatibility is not a claim about Microsoft's servicing status.

## Verify a download

```powershell
Get-FileHash .\Windows-Startup-App-Manager-2.1.0.zip -Algorithm SHA256
Get-FileHash .\Windows-Startup-App-Manager-Setup-2.1.0.exe -Algorithm SHA256
Get-Content .\SHA256SUMS.txt
```

The hashes must match. A checksum detects changed bytes; it does not establish the publisher's identity. Release binaries are currently unsigned. Code signing and a trusted signing identity require separate maintainer setup.
