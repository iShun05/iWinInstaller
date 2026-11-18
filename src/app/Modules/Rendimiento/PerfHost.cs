using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Text.RegularExpressions;

namespace IWinInstaller.App.Modules.Rendimiento
{
    public sealed class ProcInfo
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public long WorkingSetMb { get; set; }
        public bool HasWindow { get; set; }
    }

    /// <summary>
    /// Todo lo que la sección Rendimiento hace con procesos y planes de energía, detrás de una interfaz para probar
    /// el perfil de juego y las acciones sin Windows. Nunca mata procesos: solo pide cerrar la ventana principal.
    /// </summary>
    public interface IPerfHost
    {
        /// <summary>GUID en minúsculas del plan de energía activo, o null.</summary>
        string ActivePowerScheme();
        bool PowerSchemeExists(string guid);
        bool SetPowerScheme(string guid);
        /// <summary>Procesos en marcha (sin la ruta del ejecutable: usa PathOf para los que haga falta, porque leerla es lento).</summary>
        List<ProcInfo> Processes();
        string PathOf(int pid);
        /// <summary>Pide al proceso que cierre su ventana principal (CloseMainWindow); true si la petición se aceptó.</summary>
        bool CloseGracefully(int pid);
        bool IsRunning(int pid);
        ProcessPriorityClass? PriorityOf(int pid);
        bool SetPriority(int pid, ProcessPriorityClass priority);
        bool Launch(string path);
    }

    /// <summary>Coincidencia de nombres de proceso: sin .exe, sin mayúsculas y con * final como prefijo.</summary>
    public static class ProcessMatcher
    {
        public static bool Matches(string processName, string pattern)
        {
            if (string.IsNullOrEmpty(processName) || string.IsNullOrEmpty(pattern)) return false;
            if (pattern.EndsWith("*", StringComparison.Ordinal))
                return processName.StartsWith(pattern.Substring(0, pattern.Length - 1), StringComparison.OrdinalIgnoreCase);
            return string.Equals(processName, pattern, StringComparison.OrdinalIgnoreCase);
        }

        public static bool MatchesAny(string processName, IEnumerable<string> patterns)
        {
            return patterns != null && patterns.Any(p => Matches(processName, p));
        }

        /// <summary>Nombre de proceso válido para añadir a mano: letras, números, guiones y puntos, sin ruta ni «.exe».</summary>
        public static string CleanCustomName(string text)
        {
            string name = (text ?? "").Trim().Trim('"');
            int slash = Math.Max(name.LastIndexOf('\\'), name.LastIndexOf('/'));
            if (slash >= 0) name = name.Substring(slash + 1);
            if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name = name.Substring(0, name.Length - 4);
            return name.Length >= 2 && name.Length <= 60 && Regex.IsMatch(name, @"^[A-Za-z0-9][A-Za-z0-9 _.\-]*$") ? name : null;
        }
    }

    /// <summary>Implementación real: procesos del usuario y powercfg.</summary>
    public sealed class WindowsPerfHost : IPerfHost
    {
        private static bool Expected(Exception e)
        {
            return e is Win32Exception || e is InvalidOperationException || e is NotSupportedException || e is ArgumentException;
        }

        private static string PowerCfg(string arguments)
        {
            var info = new ProcessStartInfo("powercfg.exe", arguments)
            {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
            };
            using (var process = Process.Start(info))
            {
                string output = process.StandardOutput.ReadToEnd();
                if (!process.WaitForExit(8000)) { try { process.Kill(); } catch (InvalidOperationException) { } return null; }
                return process.ExitCode == 0 ? output : null;
            }
        }

        private static string FirstGuid(string text)
        {
            var match = Regex.Match(text ?? "", @"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
            return match.Success ? match.Value.ToLowerInvariant() : null;
        }

        public string ActivePowerScheme()
        {
            try { return FirstGuid(PowerCfg("/getactivescheme")); }
            catch (Exception e) when (Expected(e)) { return null; }
        }

        public bool PowerSchemeExists(string guid)
        {
            try
            {
                string all = PowerCfg("/list");
                return all != null && all.IndexOf(guid, StringComparison.OrdinalIgnoreCase) >= 0;
            }
            catch (Exception e) when (Expected(e)) { return false; }
        }

        public bool SetPowerScheme(string guid)
        {
            try { return PowerCfg("/setactive " + guid) != null; }
            catch (Exception e) when (Expected(e)) { return false; }
        }

        public List<ProcInfo> Processes()
        {
            var list = new List<ProcInfo>();
            Process[] all;
            try { all = Process.GetProcesses(); }
            catch (Exception e) when (Expected(e)) { return list; }
            foreach (var p in all)
            {
                try
                {
                    var info = new ProcInfo { Id = p.Id, Name = p.ProcessName, WorkingSetMb = p.WorkingSet64 / (1024 * 1024), HasWindow = p.MainWindowHandle != IntPtr.Zero };
                    list.Add(info);
                }
                catch (Exception e) when (Expected(e)) { /* terminó mientras se leía */ }
                finally { p.Dispose(); }
            }
            return list;
        }

        public string PathOf(int pid)
        {
            try { using (var p = Process.GetProcessById(pid)) return p.MainModule == null ? null : p.MainModule.FileName; }
            catch (Exception e) when (Expected(e)) { return null; }
        }

        public bool CloseGracefully(int pid)
        {
            try
            {
                using (var p = Process.GetProcessById(pid))
                    return p.MainWindowHandle != IntPtr.Zero && p.CloseMainWindow();
            }
            catch (Exception e) when (Expected(e)) { return false; }
        }

        public bool IsRunning(int pid)
        {
            try { using (var p = Process.GetProcessById(pid)) return !p.HasExited; }
            catch (Exception e) when (Expected(e)) { return false; }
        }

        public ProcessPriorityClass? PriorityOf(int pid)
        {
            try { using (var p = Process.GetProcessById(pid)) return p.PriorityClass; }
            catch (Exception e) when (Expected(e)) { return null; }
        }

        public bool SetPriority(int pid, ProcessPriorityClass priority)
        {
            // Nunca tiempo real: puede bloquear el sistema
            if (priority == ProcessPriorityClass.RealTime) return false;
            try { using (var p = Process.GetProcessById(pid)) { p.PriorityClass = priority; return p.PriorityClass == priority; } }
            catch (Exception e) when (Expected(e)) { return false; }
        }

        public bool Launch(string path)
        {
            try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); return true; }
            catch (Exception e) when (Expected(e)) { return false; }
        }
    }
}
