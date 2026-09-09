# Changelog

## 2.1.1 - Release candidate fixes

- Treat search input literally and restore grid state after filter failures.
- Install correctly from source folders containing square brackets.
- Preserve security warnings when an executable matches a known application name.

## 2.1.0 - Initial release candidate

- Startup inventory across registry entries, folders, scheduled tasks, services and Store apps.
- Staged changes with mandatory snapshots, verified readback and operation/batch undo.
- Cancellable scans, local baseline comparisons and share-safe diagnostic exports.
- Responsive dark interface with saved zoom and reduced-motion controls.
- Portable installation, versioned ZIP downloads and SHA256 checksums.
- Windows PowerShell CI, regression tests and bundled license notices.

This is a release candidate until the clean-machine gates in [docs/RELEASE.md](docs/RELEASE.md) have been completed. Automated checks do not claim reboot or multi-machine validation.
