// StartupManager.exe - native launcher stub.
// Requests administrator via its manifest (UAC once), then starts the
// PowerShell app that lives next to it. Nothing else.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Reflection;

[assembly: AssemblyTitle("Windows Startup App Manager")]
[assembly: AssemblyProduct("STARTUP.manager")]
[assembly: AssemblyCompany("skreamb0t")]
[assembly: AssemblyVersion("2.1.1.0")]
[assembly: AssemblyFileVersion("2.1.1.0")]

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string dir    = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "Start-StartupManager.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Start-StartupManager.ps1 was not found next to StartupManager.exe:\n\n" + script +
                            "\n\nRe-run the installer or keep the exe inside the StartupManager folder.",
                            "Startup Manager", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                 @"WindowsPowerShell\v1.0\powershell.exe");
        var psi = new ProcessStartInfo(ps,
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" -Elevated")
        {
            UseShellExecute  = false,
            CreateNoWindow   = true,
            WorkingDirectory = dir
        };
        try { Process.Start(psi); }
        catch (Exception ex)
        {
            MessageBox.Show("Could not start PowerShell:\n\n" + ex.Message, "Startup Manager",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
