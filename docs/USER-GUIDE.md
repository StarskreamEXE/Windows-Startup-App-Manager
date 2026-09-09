# Windows Startup App Manager — User Guide

## Start and scan

Download and run the **Setup EXE** from the GitHub release page for a self-contained install.
Alternatively, double-click **Launch.bat** to run from the extracted ZIP/source folder, or **Install.bat** to install.
The launcher requests administrator approval for machine-wide settings. Use your own
Windows account; entering another administrator's credentials changes the current-user
registry and startup folder being inspected.

Scanning runs in the background. **Cancel scan** or Escape stops it; the last completed
inventory and staged changes remain available. Controls that would overlap the scan are
disabled. **Scan details** explains unavailable providers or errors. A partial inventory
does not prove that an entry is absent from Windows.

## Stage and apply startup changes

1. Search by name, publisher, command, or path. Categories control which sources appear.
2. Select a row and read its description, impact evidence, signature and configuration.
3. Tick or untick **On**. This stages a change; it does not modify Windows.
4. Press **Apply (N)** and review the complete list.
5. Confirm. Required recovery snapshots and a durable journal are saved before writing.
6. The app reads back Windows settings to verify each result and refreshes in the background.

Failed changes remain staged. If configuration changed outside the app, review the fresh
details, discard that intention, and stage it again. Do not repeatedly retry an uncertain
write. **Discard** clears staged intentions, not installed programs.

Disabling startup does not stop an already-running process, task or service. Disabled
entries remain visible; use **Enabled only** if you want to hide them.

## Services and protected entries

Services are hidden by default under Categories. Viewing them does not enable editing.
Use **Tools > Advanced service changes** and accept the warning to enable edits for this
session. Apply presents service transitions explicitly.

Enabling a disabled service sets **Automatic**; its historical startup type is unknown.
Undo restores the exact saved startup type and delayed-start setting. Changes can affect
dependent functionality. RunOnce and policy-managed Store startup entries are read-only.

## Undo and recover

- **Undo last** or Ctrl+Z restores one successful operation after confirmation.
- **Tools > Undo last Apply batch** restores the most recent batch in reverse order,
  stopping if a restoration fails.
- Apply or discard pending intentions before undo.
- Undo refuses to overwrite configuration that no longer matches the applied snapshot.
- **Tools > Recover interrupted change** reviews unfinished or uncertain writes and offers
  to restore their saved pre-change state. Preserve the journal and backups before recovery.
- History from older versions without operation IDs remains visible but is not automatically
  undone. Review those changes manually in the relevant Windows management tool.

Recovery is not a system restore point or a complete system backup. Do not edit, remove,
or replace the journal to bypass a recovery warning.

## Interpret diagnostics

The **Risk** column is heuristic guidance about disabling an entry, not a verified
application identity or malware diagnosis. Details show the evidence separately from
security indicators. Microsoft signatures and Windows-host paths alone do not establish
that a startup entry is essential.

| Label | Interpretation |
|---|---|
| Critical | A pattern matches a potentially important component; verify before changing |
| Suspicious | Indicators warrant investigation, not a malware verdict |
| Broken | The resolved executable was not found or was inaccessible; verify path and access |
| Caution | Review functionality you may depend on |
| Optional | A convenience/updater pattern matched; actual impact can differ |
| Unknown | Insufficient evidence |

Flags include MISSING, UNSIGNED, BAD-SIG, TEMP-PATH, SYSTEM, DELAYED, UPDATER, MS,
SLOW and ONE-SHOT. Unsigned software is not necessarily unsafe.

**Slow starters** filters attributable measurements of at least 3,000 ms. Boot measurements
use the latest exact-path Windows event within 30 days, capped at 1,000 events.
Shared executable hosts and ambiguous duplicate paths are excluded. Details show timestamp
and confidence. Blank means no usable recent evidence, not fast. Times cannot be added
together to predict boot savings.

## Baselines

**File > Save local baseline** saves the scanned inventory to JSON.
**File > Compare with baseline** shows added, removed and changed entries with before/after
values. Comparison is read-only; it never restores settings. Saving/comparing is blocked
until a complete scan avoids false removal results. Baselines contain private names, paths and commands.

## Exports and reports

**Export** offers CSV, JSON, TXT and HTML for the current view or entire inventory.
**Report** creates a self-contained HTML report containing machine/user identity,
inventory, risk/category breakdowns, boot evidence and recent changes.

For sharing, choose **Export > Share-safe view as ...**, **Export > Share-safe HTML report**,
or **File > Generate share-safe report**. These replace entry names with numbered labels
and omit free-text details, publishers, paths, commands, machine identity and change
history. They retain only bounded diagnostic categories, states, flags and timing values.
Review every output before sharing; ordinary exports and reports are not share-safe.
CSV formula-like strings are prefixed with an apostrophe for spreadsheet safety.

## Display and keyboard

- Ctrl+wheel zooms from 75% to 150%; Ctrl+0 or the footer reset link restores 100%.
- Zoom is saved between launches. **View > Reduced motion** disables the animated byline
  and is also saved.
- Tab navigates controls; Ctrl+F focuses search; Space stages selected grid entries.
- Ctrl+S opens Apply; Ctrl+Z opens Undo; F5 scans; Escape cancels a scan; F1 opens Help.
- Columns fit available width. Secondary fields remain in details when hidden from the
  compact grid. Details stack at narrow widths and scroll vertically.

## Runtime files

| Location inside the app folder | Purpose |
|---|---|
| logs/startup-manager.log | Operational diagnostics |
| logs/changes.jsonl | Durable preparation, result and recovery journal |
| logs/preferences.json | Zoom and reduced motion |
| backups/batch_<id>.json | Exact provider settings captured before Apply |
| backups/*.reg | Supplemental registry exports from File > Backup registry now |
| exports/ | List exports |
| reports/ | HTML reports |

Install also registers per-user fonts, shortcuts and an Installed-apps entry. Applying
writes only the selected startup settings. Startup registrations are not deleted; exact
undo may remove approval metadata created by the app when it was originally absent.
Uninstall preserves the app directory under a timestamped name and retains shared fonts.

## Development and support

Run with Windows PowerShell 5.1, not PowerShell 7:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Start-StartupManager.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1
```

The entry's -NoElevate switch skips elevation for development/read-only inspection; access
may be incomplete and writes may fail. The -Elevated switch is internal relaunch metadata.
Tests use Pester 3.4.0 and isolated data, never real startup mutations.

See [Troubleshooting](TROUBLESHOOTING.md), [Release validation](RELEASE.md),
[Contributing](../CONTRIBUTING.md) and [Architecture](ARCHITECTURE.md).
