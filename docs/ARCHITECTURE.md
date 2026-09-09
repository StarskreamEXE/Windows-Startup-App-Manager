# Windows Startup App Manager — Architecture

## Runtime and safety boundary

Windows PowerShell 5.1 hosts .NET Framework WinForms. Providers collect startup registrations;
the engine stages, snapshots, journals, applies and verifies explicit user changes.
The application is not an exhaustive autorun scanner or a malware verdict engine.

Source functions share script scope in the UI runspace. Background inventory runs in its
own STA runspace with an isolated state bag. Only completed scan results are transferred
to the UI. No worker thread directly manipulates a WinForms control.

Startup registrations, files, tasks and services are not deleted. Exact recovery may remove
approval/delayed metadata created by the app when absent in the saved state.

## Load order

The authoritative executable list is $LoadOrder in Start-StartupManager.ps1:

1. Core: Contracts, Paths, Settings, Logging.
2. Providers: StartupApproved, RunKeys, StartupFolders, ScheduledTasks, Services, StoreApps.
3. Analysis: FileFacts, BootPerf, KnownApps, Risk.
4. Engine: Inventory, Changes, Backup, Baseline.
5. Export: Export, Report.
6. UI: Theme, Dialogs, Scan, MainForm.

NativeControls.cs is compiled before form creation. DPI awareness is configured on the UI
thread. The asynchronous scan loader loads only its core/provider/analysis/inventory
dependencies, not the main form.

## Core contracts

New-SMEntry is the common schema: provider identity/configuration, Enabled, CanToggle,
and analysis facts. Id is a scan-local row identifier, not persistent identity.
Get-SMEntryIdentity constructs a stable provider-specific identity from hive/leaf/name,
file location, task path/name, service name, or Store startup path.

New-SMPendingChange describes an intention; Add-SMPendingChange attaches BeforeState,
an exact read-only provider snapshot. The Pending dictionary uses string row IDs.
A rescan remaps intentions by stable identity without replacing their original BeforeState.

New-SMChangeRecord includes operationId, batchId, undoOf, identity, before/after,
needsRecovery, provider targeting data and result. Journal actions include prepare, apply,
prepare-undo and undo. Legacy records remain readable but cannot provide exact automatic undo.

Initialize-SMPaths creates runtime paths and initial state. Logging separates best-effort
operational messages from required recovery records. Write-SMChangeRecord flushes durable
journal writes and throws on failure; Get-SMChangeRecords -Strict rejects invalid journal data.

Get-SMPreferences / Save-SMPreferences persist only validated zoom and reduced motion.
Advanced service mode deliberately resets each session.

## Providers

| Kind | Read and write model |
|---|---|
| RunKey | HKCU/HKLM Run registrations, including supported 32-bit views; StartupApproved bytes control enabled state |
| RunOnce | Read-only one-shot registrations |
| Folder | User/common Startup files; shortcut resolution; StartupApproved enabled state |
| Task | Logon/boot/session-triggered scheduled tasks; Settings.Enabled is separate from runtime State |
| Service | Automatic and disabled services; actual type/delayed evidence; enabling sets Automatic |
| Uwp | Packaged startup task state; explicit 0/1/2 handling; policy/unknown states cannot toggle |

Provider errors propagate or are captured as scan warnings. Missing resources and access
failures are not interchangeable. Unknown/policy-managed state must not be written.

Get-SMEntryStateSnapshot records exact approval bytes, task configuration apart from its
enabled flag, service type/delayed/image configuration, or Store state.
Restore-SMEntryStateSnapshot restores those fields without reinstalling registrations.
Task XML is used to detect configuration drift, not to overwrite task definitions.

## Apply and recovery

1. Reject unresolved recovery operations.
2. Verify every staged BeforeState still matches live configuration.
3. Backup-SMChangeBatch writes and validates a durable JSON batch snapshot for every kind.
4. Write a prepare journal record before each setter.
5. Recheck current state, apply through Set-SMEntryState, then read back and verify.
6. Write the result record; remove only successful intentions from Pending.
7. Unknown/partial mutations remain recovery-required and stop further writes.

Invoke-SMApplyChanges returns result[] with Id, Name, Ok, Error, From, To, BatchId,
OperationId, VerifiedState and Backup. Preflight, snapshot and journal failures throw.

Undo-SMLastChange targets one exact successful operation. Undo-SMLastBatch restores the
latest batch in reverse order and stops on failure. Both check expected current snapshots
and use durable preparation/results. A successful undo links to precisely one operation.

Get-SMInterruptedOperations identifies unfinished or recovery-required writes.
Restore-SMInterruptedOperation requires explicit UI confirmation, checks available immutable
configuration evidence, restores the saved state and verifies it before closing the operation.
It is not a general-purpose forced rollback of arbitrary externally changed settings.

Backup-SMRegistry is a supplemental manual export. It validates reg.exe exit status,
Unicode registry header and key sections. Per-key exports are retained alongside the merged
file. The mandatory batch snapshot is independent of this supplemental command.

## Diagnostics and baselines

Get-SMBootPerf bounds event101 retrieval to 30 days / 1,000 events, retaining the latest
measurement per normalized full path. Set-SMBootEvidence excludes shared hosts and
duplicate-path registrations and fills BootMeasuredAt/BootConfidence alongside BootMs.
The report uses this attribution rather than performing a second filename-only match.

Get-SMRiskAssessment is a pure heuristic with RiskEvidence and separate SecurityFlags.
KnownApps patterns are not verified identities. File absence/access problems and empty
measurements must be described conservatively.

Get-SMInventory accepts -Progress and -Cancelled callbacks. It refreshes file-fact caches,
assigns row IDs, enriches entries and publishes ScanWarnings and ScanComplete.
A cancelled scan never replaces UI inventory. Analysis/provider failures remain visible.
Failed or cancelled refreshes mark retained data stale, including in reports. Baseline UI
actions require a complete scan before saving or comparing.

Save-SMBaseline -Entries -Path writes schema1 local JSON; Get-SMBaseline validates/loads it.
Compare-SMBaseline -Baseline -Entries returns Added/Removed/Changed records with Identity,
Name, Kind, Fields, Before and After. Baselines are sensitive local data, not public fixtures.

## UI

Scan.ps1 owns Start/Stop/Complete/Close-SMInventoryScan with BeginInvoke/EndInvoke and
cooperative cancellation plus asynchronous pipeline stop. A WinForms timer polls progress;
overlapping mutations/scans are blocked. Closing cancels a running scan first.
Pending entries that disappear remain visible with warnings, not silently discarded.

MainForm owns user intentions, confirmations, baseline dialogs, scan details and results.
Services require per-session advanced mode. Recovery is mandatory, not an optional checkbox.
Failed intentions remain available for review/discard/restaging.

Responsive fill columns and stacked details avoid horizontal grid scrolling. Ctrl+wheel
changes font sizes from originals, never bitmap scaling. Native dark scrollbars are
reapplied after handle recreation. Reduced motion stops the wordmark timer.
Dialogs and the main grid expose evidence, accessible names and keyboard navigation.

## Export boundary

Export-SMEntries supports csv/json/txt/html and -ShareSafe.
New-SMReport accepts -ShareSafe and -ScanWarnings.
HTML text is escaped; raw columns are restricted to internally constructed markup.
CSV formula-like values are neutralized.

Share-safe mode creates new allowlisted entry objects: numbered names, bounded kind/risk/
signature/flags and numeric measurements. It discards arbitrary strings, provider Data,
paths, commands, user/machine facts and change history. It never mutates source entries.
Ordinary outputs and local baselines contain private data.

## Validation and distribution

Pester3.4.0 unit tests mock setters or use isolated test resources. Run-Tests also parses
PowerShell scripts and compiles native UI C#. UI.Layout.Smoke opens isolated fixture forms
for resize/zoom/motion checks; it never applies live startup settings.

build/Release-Files.psd1 defines version and exact distribution files. Build-Release creates
a versioned ZIP and SHA256SUMS; installers use the same allowlist and rebuild the launcher.
CI runs Windows PowerShell tests and artifact building with pinned actions and read-only
repository permissions. Manual clean-machine/reboot/accessibility gates are documented
in RELEASE.md and are not implied by unit-test success.
