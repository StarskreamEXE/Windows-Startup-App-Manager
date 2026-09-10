# Security

## Reporting a vulnerability

Do not publish personal paths, registry exports, task XML, credentials, or a working exploit in a public issue.

Use [GitHub private vulnerability reporting](https://github.com/StarskreamEXE/Windows-Startup-App-Manager/security/advisories/new) when available. If GitHub does not offer a private report, open an issue containing only a request for a private reporting channel; wait for a private channel before sharing details. Never post the vulnerability itself as that request.

Include the app version, Windows build, affected provider, expected and actual behavior, and minimal reproduction steps using disposable entries. State whether changes were applied and whether recovery succeeded. There is no guaranteed response time or bug-bounty program.

## Support and trust boundaries

Security fixes target the latest release. Older releases and development snapshots are not separately maintained.

This app can change startup configuration and normally runs elevated. Only run copies from a source you trust. Keep the install directory and recovery files protected from other users. Do not import someone else's backup or run commands from an untrusted report. Administrator access does not make the app's risk labels a security guarantee.

The app is not antivirus, a malware removal tool, or a complete inventory of every Windows persistence mechanism. Startup applications may restore their own entries, and organization policy may override local settings. Do not use this app to circumvent managed-device policy.

Logs, backups, saved baselines, and full reports may contain personal information. Keep them private. Review share-safe exports before posting. Do not disable Windows security controls to work around a warning.
