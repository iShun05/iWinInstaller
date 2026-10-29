using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Threading.Tasks;
using System.Windows.Forms;

[assembly: AssemblyVersion("3.6.0.0")]
[assembly: AssemblyFileVersion("3.6.0.0")]

static class Launcher {
    static readonly object LogLock = new object();
    static string LogPath;
    static Action<int, string> Progress;
    [STAThread] static int Main(string[] args) {
        Application.EnableVisualStyles();
        string logs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "iWinInstaller");
        LogPath = Path.Combine(logs, "arranque-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Process.GetCurrentProcess().Id + ".log");
        try {
            Directory.CreateDirectory(logs);
            Environment.CurrentDirectory = logs;
            Log("iWinInstaller v3.6; Windows " + Environment.OSVersion + "; 64 bits: " + Environment.Is64BitOperatingSystem + "; proceso x86: " + !Environment.Is64BitProcess);
#if SETUP
            bool quiet = Array.IndexOf(args, "--silent") >= 0;
            if (quiet) { Install(); return 0; }
            using (Form form = new Form()) {
                form.Text = "iWinInstaller v3.6"; form.Width = 560; form.Height = 230;
                form.StartPosition = FormStartPosition.CenterScreen;
                form.FormBorderStyle = FormBorderStyle.FixedDialog; form.ControlBox = false;
                form.BackColor = System.Drawing.Color.Black; form.ForeColor = System.Drawing.Color.White;
                form.Font = new System.Drawing.Font("Segoe UI", 11F);
                Label heading = new Label { Dock = DockStyle.Top, Height = 62, Text = "Instala. Elige. Listo.", Font = new System.Drawing.Font("Segoe UI", 20F, System.Drawing.FontStyle.Bold), Padding = new Padding(20, 16, 0, 0) };
                Label label = new Label { Dock = DockStyle.Fill, Text = "Preparando los archivos incluidos… Si iWinInstaller está abierto, ciérralo para continuar.", Padding = new Padding(20), AutoSize = false };
                ProgressBar bar = new ProgressBar { Dock = DockStyle.Bottom, Style = ProgressBarStyle.Marquee, Height = 8 };
                form.Controls.Add(label); form.Controls.Add(heading); form.Controls.Add(bar);
                Progress = delegate(int step, string status) {
                    try { form.BeginInvoke(new Action(delegate {
                        if (form.IsDisposed) return;
                        label.Text = status;
                        if (step > 0) { bar.Style = ProgressBarStyle.Continuous; bar.Value = Math.Min(100, step * 100 / 7); }
                    })); } catch { }
                };
                Exception failure = null;
                form.Shown += async delegate {
                    try { await Task.Run((Action)Install); } catch (Exception e) { failure = e; }
                    form.Close();
                };
                Application.Run(form);
                if (failure != null) throw failure;
            }
            Process.Start(Path.Combine(InstallDirectory(), "iWinInstaller.exe"));
#else
            string root = AppDomain.CurrentDomain.BaseDirectory;
            try {
                if (Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar).Equals(InstallDirectory(), StringComparison.OrdinalIgnoreCase)) {
                    foreach (string previous in Directory.GetDirectories(Path.GetDirectoryName(InstallDirectory()), "iWinInstaller.previous-*")) {
                        try { Directory.Delete(previous, true); } catch { }
                    }
                }
            } catch { }
            foreach (string name in new[] { "iWinInstaller.ps1", "apps.json", "profiles.json", "lifecycle.ps1", "install.ps1", "launch.ps1" })
                if (!File.Exists(Path.Combine(root, name))) throw new FileNotFoundException("Falta un archivo esencial. Ejecuta de nuevo iWinInstaller-Setup.exe.", name);
            string manifest = File.ReadAllText(Path.Combine(root, "integrity.sha256"));
            foreach (string name in new[] { "iWinInstaller.ps1", "apps.json", "profiles.json", "lifecycle.ps1", "install.ps1", "launch.ps1", "iWinInstaller.exe" }) {
                string expected = null;
                foreach (string line in manifest.Split('\n')) if (line.Trim().EndsWith("  " + name)) expected = line.Substring(0, 64);
                using (SHA256 sha = SHA256.Create()) using (FileStream file = File.OpenRead(Path.Combine(root, name))) {
                    string actual = BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "").ToLowerInvariant();
                    if (expected != actual) throw new Exception("Archivo esencial dañado: " + name + ". Ejecuta de nuevo iWinInstaller-Setup.exe.");
                }
            }
            if (Array.IndexOf(args, "--uninstall") >= 0) {
                foreach(Process running in Process.GetProcessesByName("iWinInstaller")) {
                    using(running) {
                        if(running.Id == Process.GetCurrentProcess().Id) continue;
                        string path; try { path=running.MainModule.FileName; } catch { continue; }
                        if(String.Equals(path,Path.Combine(InstallDirectory(),"iWinInstaller.exe"),StringComparison.OrdinalIgnoreCase))
                            throw new Exception("Cierra la ventana de iWinInstaller antes de desinstalar y vuelve a intentarlo.");
                    }
                }
                string ps = PowerShellPath();
                ProcessStartInfo remove = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(root, "install.ps1") + "\" -Uninstall -WaitForPid " + Process.GetCurrentProcess().Id);
                remove.UseShellExecute=false; remove.CreateNoWindow=true;
                remove.EnvironmentVariables["PSModulePath"]=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),"WindowsPowerShell","Modules")+";"+Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","WindowsPowerShell","v1.0","Modules");
                Process.Start(remove); return 0;
            }
            if (Array.IndexOf(args, "--update-only") >= 0) return RunPowerShell(Path.Combine(root, "iWinInstaller.ps1"), "-AutoUpdate", logs, null);
            if (!Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar).Equals(InstallDirectory(), StringComparison.OrdinalIgnoreCase)) {
                int installed = RunPowerShell(Path.Combine(root, "install.ps1"), "-Silent", logs, null, root.TrimEnd(Path.DirectorySeparatorChar));
                if (installed != 0) throw new Exception("No se pudo instalar la aplicación: " + installed);
                Process.Start(Path.Combine(InstallDirectory(), "iWinInstaller.exe")); return 0;
            }
            int code = RunPowerShell(Path.Combine(root, "launch.ps1"), "", logs, null);
            if (code != 0) throw new Exception("La aplicación terminó con el código " + code + ". El diagnóstico contiene los detalles disponibles.");
#endif
            return 0;
        } catch (Exception e) {
            Log(e.ToString());
            string report = LogPath;
            try {
                string downloads = Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders", "{374DE290-123F-4565-9164-39C4925E467B}", null) as string;
                downloads = String.IsNullOrEmpty(downloads) ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads") : Environment.ExpandEnvironmentVariables(downloads);
                Directory.CreateDirectory(downloads);
                report = Path.Combine(downloads, "iWinInstaller-error-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".txt");
                File.Copy(LogPath, report, true);
            } catch { }
            if (Array.IndexOf(args, "--silent") < 0 && Array.IndexOf(args, "--update-only") < 0)
                MessageBox.Show("No se pudo completar la operación.\n" + e.Message + "\n\n" + (File.Exists(report) ? "Diagnóstico guardado en:\n" + report : e.Message + "\nNo se pudo guardar el diagnóstico."), "iWinInstaller", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
    static void Log(string text) {
        // La salida de un proceso llega por hilos auxiliares: un fallo de disco no debe derribar el lanzador.
        lock (LogLock) {
            try {
                string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                if (!String.IsNullOrEmpty(profile)) text = text.Replace(profile, "%USERPROFILE%");
                text = System.Text.RegularExpressions.Regex.Replace(text, @"(?<![A-Za-z0-9_-])(?:gh[pousr]_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{20,})", "[OCULTO]");
                text = System.Text.RegularExpressions.Regex.Replace(text, @"(?i)(Authorization\s*:\s*(?:Bearer|token)\s+)\S+", "$1[OCULTO]");
                text = System.Text.RegularExpressions.Regex.Replace(text, @"(?i)([?&](?:token|access_token|key|signature|sig)=)[^&\s]+", "$1[OCULTO]");
                text = System.Text.RegularExpressions.Regex.Replace(text, @"(?i)(https?://)[^/\s@]+@", "$1[OCULTO]@");
                text = System.Text.RegularExpressions.Regex.Replace(text, @"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "[CORREO OCULTO]");
                File.AppendAllText(LogPath, DateTime.Now.ToString("O") + " " + text + Environment.NewLine);
            } catch { }
        }
    }
    static string InstallDirectory() { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "iWinInstaller"); }
    static string PowerShellPath() {
        // En Windows de 64 bits, un EXE x86 usa el host nativo para evitar redirección de registro y Program Files.
        if(Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess)
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"Sysnative","WindowsPowerShell","v1.0","powershell.exe");
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell","v1.0","powershell.exe");
    }
    static int RunPowerShell(string script, string arguments, string root, string package, string localSource = null) {
        string ps = PowerShellPath();
        if (!File.Exists(ps)) throw new FileNotFoundException("Windows PowerShell, incluido en Windows 10/11, no está disponible.", ps);
        ProcessStartInfo start = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + script + "\" " + arguments);
        start.UseShellExecute = false; start.CreateNoWindow = true; start.WorkingDirectory = root;
        start.RedirectStandardOutput = true; start.RedirectStandardError = true;
        string programFiles=Environment.GetEnvironmentVariable("ProgramW6432");
        if(String.IsNullOrEmpty(programFiles))programFiles=Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        if(Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess) {
            start.EnvironmentVariables["ProgramFiles"]=programFiles;
            string common=Environment.GetEnvironmentVariable("CommonProgramW6432");
            if(!String.IsNullOrEmpty(common))start.EnvironmentVariables["CommonProgramFiles"]=common;
            start.EnvironmentVariables["PROCESSOR_ARCHITECTURE"]=Environment.GetEnvironmentVariable("PROCESSOR_ARCHITEW6432")??"AMD64";
            start.EnvironmentVariables.Remove("PROCESSOR_ARCHITEW6432");
        }
        // No hereda modulos de PowerShell 7 al ejecutar el host 5.1 de Windows.
        string systemModules=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","WindowsPowerShell","v1.0","Modules");
        start.EnvironmentVariables["PSModulePath"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "WindowsPowerShell", "Modules") + ";" + Path.Combine(programFiles, "WindowsPowerShell", "Modules") + ";" + systemModules;
        start.EnvironmentVariables.Remove("IWIN_SOURCE_DIRECTORY");
        start.EnvironmentVariables.Remove("IWIN_PACKAGE_PATH");
        if(localSource != null) start.EnvironmentVariables["IWIN_SOURCE_DIRECTORY"] = localSource;
        if (package != null) start.EnvironmentVariables["IWIN_PACKAGE_PATH"] = package;
        else start.EnvironmentVariables["IWIN_HOST_PID"] = Process.GetCurrentProcess().Id.ToString();
        using (Process process = new Process()) {
            process.StartInfo = start;
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) {
                Log(e.Data);
                var match = System.Text.RegularExpressions.Regex.Match(e.Data, @"^\[(\d)/7\]\s*(.*)");
                if (Progress != null && match.Success) Progress(Int32.Parse(match.Groups[1].Value), match.Groups[2].Value);
            } };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) Log(e.Data); };
            process.Start(); process.BeginOutputReadLine(); process.BeginErrorReadLine();
            process.WaitForExit(); return process.ExitCode;
        }
    }
#if SETUP
    static void Install() {
        // Windows bloquea imagenes y ejecutables abiertos; no se reemplazan hasta que cierre la app.
        foreach (Process running in Process.GetProcessesByName("iWinInstaller")) {
            using (running) {
                if (running.Id == Process.GetCurrentProcess().Id) continue;
                string path;
                try { path = running.MainModule.FileName; } catch { continue; }
                if (String.Equals(path, Path.Combine(InstallDirectory(), "iWinInstaller.exe"), StringComparison.OrdinalIgnoreCase)) {
                    Log("Esperando que se cierre la aplicacion antes de reemplazarla.");
                    if (Progress != null) Progress(0, "Cierra la ventana de iWinInstaller para continuar con la reparación.");
                    if (!running.WaitForExit(10800000)) throw new Exception("Cierra iWinInstaller y vuelve a ejecutar el instalador.");
                }
            }
        }
        string temp = Path.Combine(Path.GetTempPath(), "iwin-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temp);
        try {
            string zip = Path.Combine(temp, "app.zip");
            using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            using (FileStream output = File.Create(zip)) { if (input == null) throw new Exception("Falta el paquete incluido."); input.CopyTo(output); }
            DriveInfo drive = new DriveInfo(Path.GetPathRoot(InstallDirectory()));
            if (drive.AvailableFreeSpace < new FileInfo(zip).Length * 3) throw new IOException("Falta espacio libre para preparar e instalar el paquete. Libera al menos 1 GB y vuelve a intentarlo.");
            string expected;
            using (StreamReader reader = new StreamReader(Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.sha256"))) expected = reader.ReadToEnd().Trim();
            string actual;
            using (SHA256 sha = SHA256.Create()) using (FileStream file = File.OpenRead(zip)) actual = BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "").ToLowerInvariant();
            if (actual != expected) throw new Exception("El paquete incluido está dañado. Descarga de nuevo el EXE.");
            Log("Paquete SHA256 comprobado: " + actual);
            string script = Path.Combine(temp, "install.ps1");
            using (ZipArchive archive = ZipFile.OpenRead(zip)) {
                ZipArchiveEntry entry = archive.GetEntry("iWinInstaller/install.ps1");
                if (entry == null) throw new Exception("El paquete no contiene el instalador.");
                entry.ExtractToFile(script);
            }
            int code = RunPowerShell(script, "-Silent", temp, zip);
            if (code != 0) throw new Exception("La instalación terminó con el código " + code);
            if (!File.Exists(Path.Combine(InstallDirectory(), "iWinInstaller.exe"))) throw new Exception("No se encontró el ejecutable instalado.");
        } finally { try { Directory.Delete(temp, true); } catch { } }
    }
#endif
}
