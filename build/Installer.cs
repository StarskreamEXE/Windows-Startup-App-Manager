using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

[assembly: AssemblyTitle("Windows Startup App Manager Setup")]
[assembly: AssemblyProduct("STARTUP.manager Setup")]
[assembly: AssemblyCompany("skreamb0t")]
[assembly: AssemblyVersion("2.1.0.0")]
[assembly: AssemblyFileVersion("2.1.0.0")]

namespace StartupManagerSetup
{
    public static class Payload
    {
        public static string GetSafePath(string destination, string entryName)
        {
            if (String.IsNullOrEmpty(entryName) || Path.IsPathRooted(entryName) || entryName.IndexOf(':') >= 0)
                throw new InvalidDataException("Invalid archive entry path.");
            string relative = entryName.Replace('/', '\\').TrimEnd('\\');
            foreach (string segment in relative.Split('\\'))
            {
                if (String.IsNullOrEmpty(segment) || segment == "." || segment == ".." ||
                    segment.EndsWith(".", StringComparison.Ordinal) || segment.EndsWith(" ", StringComparison.Ordinal) ||
                    segment.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
                    Regex.IsMatch(segment, @"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)", RegexOptions.IgnoreCase))
                    throw new InvalidDataException("Unsafe archive entry: " + entryName);
            }
            string root = Path.GetFullPath(destination).TrimEnd('\\') + "\\";
            string target = Path.GetFullPath(Path.Combine(root, relative));
            if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Archive entry escapes extraction directory.");
            return target;
        }

        static void RejectReparsePoints(string path)
        {
            string current = Path.GetFullPath(path);
            while (!String.IsNullOrEmpty(current))
            {
                if ((Directory.Exists(current) || File.Exists(current)) &&
                    (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Extraction through a link is not permitted: " + current);
                current = Path.GetDirectoryName(current);
            }
        }

        public static void Extract(Stream payload, string destination)
        {
            string root = Path.GetFullPath(destination);
            if (Directory.Exists(root) || File.Exists(root))
                throw new IOException("Extraction destination must not already exist.");
            RejectReparsePoints(root);
            using (var archive = new ZipArchive(payload, ZipArchiveMode.Read, true))
            {
                if (archive.Entries.Count > 5000) throw new InvalidDataException("Archive has too many entries.");
                var targets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                long total = 0;
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string target = GetSafePath(root, entry.FullName);
                    if (!targets.Add(target)) throw new InvalidDataException("Duplicate archive destination.");
                    if ((entry.ExternalAttributes & (int)FileAttributes.ReparsePoint) != 0 ||
                        ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000)
                        throw new InvalidDataException("Archive links are not supported.");
                    total = checked(total + entry.Length);
                    if (total > 512L * 1024 * 1024) throw new InvalidDataException("Archive exceeds the extraction size limit.");
                }
                Directory.CreateDirectory(root);
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string target = GetSafePath(root, entry.FullName);
                    RejectReparsePoints(target);
                    if (entry.FullName.EndsWith("/", StringComparison.Ordinal) || entry.FullName.EndsWith("\\", StringComparison.Ordinal))
                    {
                        Directory.CreateDirectory(target);
                        continue;
                    }
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    RejectReparsePoints(target);
                    using (Stream input = entry.Open())
                    using (var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        input.CopyTo(output);
                }
            }
        }
    }

    static class Installer
    {
        const string Title = "Windows Startup App Manager Setup";

        static void ExtractEmbedded(string destination)
        {
            using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("StartupManager.Payload.zip"))
            {
                if (payload == null) throw new InvalidDataException("The bundled application payload is missing.");
                Payload.Extract(payload, destination);
            }
        }

        [STAThread]
        static int Main(string[] arguments)
        {
            if (arguments.Length == 2 && arguments[0].Equals("/extract-only", StringComparison.OrdinalIgnoreCase))
            {
                try { ExtractEmbedded(arguments[1]); return 0; }
                catch { return 1; }
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            if (arguments.Length != 0)
            {
                MessageBox.Show("Usage: double-click to install, or /extract-only <new folder> to inspect the payload without installation.", Title);
                return 1;
            }
            if (MessageBox.Show("Install or upgrade STARTUP.manager for your Windows account?\n\nExisting logs, backups, reports and preferences are preserved. Close an existing app window first.\n\nSetup needs no administrator access. Opening the app afterward requests administrator approval.", Title,
                MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return 0;

            int exitCode = 1;
            string staging = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "StartupManager", "Setup", Guid.NewGuid().ToString("N"));
            using (var form = new Form())
            using (var worker = new BackgroundWorker())
            {
                form.Text = Title;
                form.ClientSize = new Size(490, 110);
                form.StartPosition = FormStartPosition.CenterScreen;
                form.FormBorderStyle = FormBorderStyle.FixedDialog;
                form.ControlBox = false;
                var label = new Label { Text = "Extracting the bundled application...", AutoSize = false, Location = new Point(20, 20), Size = new Size(450, 28) };
                var progress = new ProgressBar { Style = ProgressBarStyle.Marquee, Location = new Point(20, 60), Size = new Size(450, 22) };
                form.Controls.Add(label);
                form.Controls.Add(progress);
                worker.WorkerReportsProgress = true;
                worker.ProgressChanged += delegate(object sender, ProgressChangedEventArgs args) { label.Text = (string)args.UserState; };
                worker.DoWork += delegate
                {
                    ExtractEmbedded(staging);
                    worker.ReportProgress(0, "Installing files, fonts and shortcuts...");
                    string app = Path.Combine(staging, "Windows-Startup-App-Manager");
                    string script = Path.Combine(app, "Install.ps1");
                    if (!File.Exists(script)) throw new InvalidDataException("Install.ps1 is missing from the payload.");
                    string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
                    var start = new ProcessStartInfo(powershell, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" -Launch")
                    {
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        WorkingDirectory = app,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true
                    };
                    var output = new StringBuilder();
                    using (var process = new Process { StartInfo = start })
                    {
                        DataReceivedEventHandler capture = delegate(object sender, DataReceivedEventArgs args)
                        {
                            if (args.Data != null) lock (output) { output.AppendLine(args.Data); }
                        };
                        process.OutputDataReceived += capture;
                        process.ErrorDataReceived += capture;
                        if (!process.Start()) throw new IOException("Windows PowerShell could not be started.");
                        process.BeginOutputReadLine();
                        process.BeginErrorReadLine();
                        process.WaitForExit();
                        File.WriteAllText(Path.Combine(staging, "setup.log"), output.ToString(), new UTF8Encoding(false));
                        if (process.ExitCode != 0) throw new IOException("Installation or app launch failed (exit " + process.ExitCode + ").\n\nDetails: " + Path.Combine(staging, "setup.log"));
                    }
                };
                worker.RunWorkerCompleted += delegate(object sender, RunWorkerCompletedEventArgs args)
                {
                    if (args.Error == null)
                    {
                        exitCode = 0;
                        MessageBox.Show(form, "Installation completed and app launch requested.\n\nSetup files and its log are preserved at:\n" + staging, Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                    }
                    else
                        MessageBox.Show(form, args.Error.Message + "\n\nSetup files, if extracted, remain at:\n" + staging, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                    form.Close();
                };
                form.Shown += delegate { worker.RunWorkerAsync(); };
                Application.Run(form);
            }
            return exitCode;
        }
    }
}
