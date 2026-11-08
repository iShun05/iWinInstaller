using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using IWinInstaller.App.Engine;

namespace IWinInstaller.App.Shell
{
    /// <summary>
    /// Abre la ventana clásica (PowerShell) para los módulos que aún no tiene la interfaz nueva.
    /// Desaparece en v4.7, cuando todos los módulos estén portados.
    /// </summary>
    public sealed class LegacyBridge
    {
        private readonly string _root;
        private Process _classic;

        public LegacyBridge(string root) { _root = root; }

        public bool IsAvailable { get { return File.Exists(Path.Combine(_root, "iWinInstaller.ps1")); } }

        /// <summary>Abre la ventana clásica o la trae al frente si ya está abierta.</summary>
        public void Open()
        {
            if (_classic != null && !_classic.HasExited)
            {
                IntPtr handle = _classic.MainWindowHandle;
                if (handle != IntPtr.Zero) { ShowWindow(handle, 9); SetForegroundWindow(handle); }
                return;
            }
            _classic = Process.Start(CreateStartInfo());
        }

        /// <summary>Modo de prueba de CI: ejecuta la ventana clásica en modo prueba y devuelve su código.</summary>
        public int RunTest(TimeSpan timeout)
        {
            using (var process = Process.Start(CreateStartInfo()))
            {
                if (!process.WaitForExit((int)timeout.TotalMilliseconds)) { try { process.Kill(); } catch (InvalidOperationException) { } return 1; }
                return process.ExitCode;
            }
        }

        private ProcessStartInfo CreateStartInfo()
        {
            var start = new ProcessStartInfo(EngineClient.PowerShellPath(),
                "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + Path.Combine(_root, "iWinInstaller.ps1") + "\"");
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WorkingDirectory = _root;
            return start;
        }

        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
}
