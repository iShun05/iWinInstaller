using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Text;
using Microsoft.Win32;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>Implementación real de IGameEnvironment (contexto del usuario; la app es asInvoker).</summary>
    public sealed class WindowsGameEnvironment : IGameEnvironment
    {
        public string LocalAppData { get { return Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData); } }
        public string ProgramData { get { return Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData); } }

        private static RegistryKey Open(string key, bool write)
        {
            if (string.IsNullOrEmpty(key)) return null;
            int slash = key.IndexOf('\\');
            string hive = slash < 0 ? key : key.Substring(0, slash);
            string path = slash < 0 ? "" : key.Substring(slash + 1);
            RegistryHive root;
            if (hive.Equals("HKCU", StringComparison.OrdinalIgnoreCase)) root = RegistryHive.CurrentUser;
            else if (hive.Equals("HKLM", StringComparison.OrdinalIgnoreCase)) root = RegistryHive.LocalMachine;
            else return null;
            // Vista de 64 bits en Windows de 64 bits: así WOW6432Node se lee con su nombre literal
            var view = Environment.Is64BitOperatingSystem ? RegistryView.Registry64 : RegistryView.Default;
            var baseKey = RegistryKey.OpenBaseKey(root, view);
            if (path.Length == 0) return baseKey;
            try { return write ? baseKey.CreateSubKey(path, true) : baseKey.OpenSubKey(path, false); }
            finally { baseKey.Dispose(); }
        }

        public object GetValue(string key, string name)
        {
            try
            {
                using (var k = Open(key, false))
                {
                    if (k == null) return null;
                    object value = k.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                    if (value is byte[] || value is string) return value;
                    if (value is int) return value;
                    return null;
                }
            }
            catch (Exception ex) when (ex is System.Security.SecurityException || ex is UnauthorizedAccessException || ex is IOException) { return null; }
        }

        public string[] SubKeyNames(string key)
        {
            try
            {
                using (var k = Open(key, false)) return k == null ? new string[0] : k.GetSubKeyNames();
            }
            catch (Exception ex) when (ex is System.Security.SecurityException || ex is UnauthorizedAccessException || ex is IOException) { return new string[0]; }
        }

        public void SetValue(string key, string name, object value, RegKind kind)
        {
            using (var k = Open(key, true))
            {
                if (k == null) throw new IOException("No se pudo abrir " + key);
                var regKind = kind == RegKind.Binary ? RegistryValueKind.Binary : kind == RegKind.DWord ? RegistryValueKind.DWord : RegistryValueKind.String;
                k.SetValue(name, value, regKind);
            }
        }

        public void DeleteValue(string key, string name)
        {
            using (var k = Open(key, true))
                if (k != null) k.DeleteValue(name, false);
        }

        public bool FileExists(string path) { return !string.IsNullOrEmpty(path) && File.Exists(path); }
        public bool DirectoryExists(string path) { return !string.IsNullOrEmpty(path) && Directory.Exists(path); }
        public string ReadAllText(string path) { return File.ReadAllText(path, Encoding.UTF8); }

        public string[] GetFiles(string directory, string pattern)
        {
            try { return Directory.GetFiles(directory, pattern, SearchOption.TopDirectoryOnly); }
            catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException) { return new string[0]; }
        }

        public string[] GetDirectories(string directory)
        {
            try { return Directory.GetDirectories(directory); }
            catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException) { return new string[0]; }
        }

        public string CompanyName(string path)
        {
            try { return FileVersionInfo.GetVersionInfo(path).CompanyName; }
            catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException) { return null; }
        }

        public bool AnyProcessRunning(IEnumerable<string> names)
        {
            Process[] all = null;
            try
            {
                foreach (string name in names)
                {
                    if (!name.EndsWith("*", StringComparison.Ordinal))
                    {
                        var found = Process.GetProcessesByName(name);
                        bool any = found.Length > 0;
                        foreach (var p in found) p.Dispose();
                        if (any) return true;
                        continue;
                    }
                    if (all == null) all = Process.GetProcesses();
                    string prefix = name.Substring(0, name.Length - 1);
                    if (all.Any(p => p.ProcessName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))) return true;
                }
                return false;
            }
            finally
            {
                if (all != null) foreach (var p in all) p.Dispose();
            }
        }

        public int GpuCount()
        {
            try
            {
                int count = 0;
                using (var searcher = new ManagementObjectSearcher("SELECT Name, PNPDeviceID FROM Win32_VideoController"))
                using (var results = searcher.Get())
                {
                    foreach (ManagementBaseObject gpu in results)
                    {
                        using (gpu)
                        {
                            string name = Convert.ToString(gpu["Name"]) ?? "";
                            string pnp = Convert.ToString(gpu["PNPDeviceID"]) ?? "";
                            if (name.IndexOf("Basic Display", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                            if (name.IndexOf("Remote", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                            if (!pnp.StartsWith("PCI\\", StringComparison.OrdinalIgnoreCase)) continue;
                            count++;
                        }
                    }
                }
                return count;
            }
            catch (Exception ex) when (ex is ManagementException || ex is System.Runtime.InteropServices.COMException || ex is UnauthorizedAccessException) { return -1; }
        }
    }
}
