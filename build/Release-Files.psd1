@{
    Version = '2.1.0'
    Files = @(
        'Start-StartupManager.ps1', 'Launch.ps1', 'Launch.bat', 'Install.ps1', 'Install.bat', 'Uninstall.ps1',
        'README.md', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'CONTRIBUTING.md', 'SECURITY.md', 'CHANGELOG.md',
        'build/Build-Exe.ps1', 'build/Build-Release.ps1', 'build/Release-Files.psd1', 'build/Launcher.cs', 'build/app.manifest', 'build/app.ico',
        'build/Build-Setup.ps1', 'build/Installer.cs', 'build/Setup.manifest',
        'assets/skreambot.png', 'assets/github-mark.png',
        'docs/USER-GUIDE.md', 'docs/ARCHITECTURE.md', 'docs/RELEASE.md', 'docs/TROUBLESHOOTING.md',
        'docs/images/windows-startup-manager.png', 'docs/images/windows-startup-report.png',
        'fonts/Inter-Regular.ttf', 'fonts/Inter-Medium.ttf', 'fonts/Inter-SemiBold.ttf',
        'fonts/JetBrainsMono-Regular.ttf', 'fonts/JetBrainsMono-Medium.ttf', 'fonts/JetBrainsMono-SemiBold.ttf', 'fonts/JetBrainsMono-Bold.ttf',
        'fonts/PressStart2P-Regular.ttf', 'fonts/LICENSE-FONTS.md', 'fonts/OFL-Inter.txt', 'fonts/OFL-JetBrainsMono.txt', 'fonts/OFL-PressStart2P.txt',
        'src/Core/Contracts.ps1', 'src/Core/Paths.ps1', 'src/Core/Logging.ps1', 'src/Core/Settings.ps1',
        'src/Providers/StartupApproved.ps1', 'src/Providers/RunKeys.ps1', 'src/Providers/StartupFolders.ps1',
        'src/Providers/ScheduledTasks.ps1', 'src/Providers/Services.ps1', 'src/Providers/StoreApps.ps1',
        'src/Analysis/FileFacts.ps1', 'src/Analysis/BootPerf.ps1', 'src/Analysis/KnownApps.ps1', 'src/Analysis/Risk.ps1',
        'src/Engine/Inventory.ps1', 'src/Engine/Changes.ps1', 'src/Engine/Backup.ps1', 'src/Engine/Baseline.ps1',
        'src/Export/Export.ps1', 'src/Export/Report.ps1',
        'src/UI/Theme.ps1', 'src/UI/MainForm.ps1', 'src/UI/Dialogs.ps1', 'src/UI/NativeControls.cs', 'src/UI/Scan.ps1'
    )
}
