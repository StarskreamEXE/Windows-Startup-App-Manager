# Contributing to Windows Startup App Manager

Bug reports, documentation improvements, and focused code contributions are welcome.

## Report a bug or suggest a change

Open an [issue](https://github.com/StarskreamEXE/Windows-Startup-App-Manager/issues)
with the behavior you expected, what happened, and the steps to reproduce it.
For UI issues, include your Windows version, display scaling, app zoom, and a screenshot
when useful. For startup issues, include the entry type: Run key, startup folder,
scheduled task, service, or Store app task.

Remove personal information from screenshots and logs before sharing them. Include only
the relevant log excerpt, not a complete registry backup or unfiltered startup inventory.

## Set up a development checkout

Use Windows 10 or Windows 11 and **Windows PowerShell 5.1** (`powershell.exe`).
The app uses WinForms and the .NET Framework; no Node.js or Python installation is needed.

```powershell
git clone https://github.com/StarskreamEXE/Windows-Startup-App-Manager.git
cd Windows-Startup-App-Manager
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Start-StartupManager.ps1 -NoElevate
```

`-NoElevate` is useful for UI development. Full access to machine-wide startup settings
requires administrator rights. Avoid applying real startup changes while testing the UI.

Read [the architecture and function contracts](docs/ARCHITECTURE.md) before changing code.
For the user-facing workflow, see [the user guide](docs/USER-GUIDE.md).

## Implementation guidelines

- Keep changes focused and follow the surrounding PowerShell 5.1 style.
- Preserve strict mode and the entry script's explicit module load order.
- Keep checkbox changes staged until the user confirms Apply.
- Enable or disable startup entries; do not delete applications or startup entries.
- Preserve error reporting, backups, change history, and undo behavior.
- Show missing information as unknown rather than inventing values.
- Keep UI changes compatible with display scaling, Ctrl+wheel zoom, and narrow windows.
- Update documentation when behavior or setup instructions change.

## Run tests

The test runner requires **Pester 3.4.0** and checks both tests and PowerShell syntax.
Install that exact version in Windows PowerShell if it is not already available:

```powershell
Install-Module Pester -RequiredVersion 3.4.0 -Scope CurrentUser -Force -SkipPublisherCheck
```

Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1
```

Add regression coverage for behavior changes. Tests must not change real startup state:
use mocked providers or isolated test data and temporary locations.

For layout or zoom changes, also run the desktop smoke check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/UI.Layout.Smoke.ps1
```

It opens test windows and checks resizing, zoom, reset, and staged-change preservation.
Its screenshots and logs go to `%TEMP%\StartupManager-layout-check`.

## Submit a pull request

Use a branch or fork and open a pull request against `main`. Describe the problem,
the resulting behavior, and the commands you ran with their results. Identify any
failing checks. Include before/after screenshots for visual changes.

Keep generated executables, runtime logs, registry backups, and personal reports out
of the commit. The repository's `.gitignore` excludes these runtime files.

## Licensing

Code contributions are made under the project's [MIT license](LICENSE).
Bundled fonts and branding have separate [asset notices](THIRD-PARTY-NOTICES.md).
