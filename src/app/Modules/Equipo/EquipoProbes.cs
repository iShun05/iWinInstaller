using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management;
using IWinInstaller.App.Core;
using IWinInstaller.App.Modules.Tools;
using Microsoft.Win32;

namespace IWinInstaller.App.Modules.Equipo
{
    /// <summary>
    /// Lecturas del equipo para el preset y el panel de salud. Solo WMI y registro con los permisos del usuario, bajo demanda:
    /// no lanza PowerShell, no instala drivers y no deja nada en marcha.
    /// </summary>
    public static class EquipoProbes
    {
        private const string RunKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
        private const string ApprovedKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\";

        private static bool Expected(Exception e)
        {
            return e is ManagementException || e is UnauthorizedAccessException || e is System.Security.SecurityException ||
                   e is IOException || e is InvalidOperationException || e is System.Runtime.InteropServices.COMException;
        }

        // ---------- Hardware ----------

        public static HardwareInfo Hardware()
        {
            var hw = new HardwareInfo();
            bool battery = false;
            var chassis = new List<int>();
            try
            {
                foreach (var row in Query(@"root\cimv2", "SELECT Manufacturer, Model, TotalPhysicalMemory FROM Win32_ComputerSystem"))
                {
                    hw.Manufacturer = Text(row, "Manufacturer");
                    hw.Model = Text(row, "Model");
                    long bytes;
                    if (long.TryParse(Text(row, "TotalPhysicalMemory"), NumberStyles.Integer, CultureInfo.InvariantCulture, out bytes)) hw.RamGb = bytes / 1073741824.0;
                }
                foreach (var row in Query(@"root\cimv2", "SELECT ChassisTypes FROM Win32_SystemEnclosure"))
                {
                    var types = Get(row, "ChassisTypes") as ushort[];
                    if (types != null) chassis.AddRange(types.Select(t => (int)t));
                }
                battery = Query(@"root\cimv2", "SELECT Name FROM Win32_Battery").Any();
                foreach (var row in Query(@"root\cimv2", "SELECT Name, NumberOfCores, NumberOfLogicalProcessors FROM Win32_Processor"))
                {
                    if (String.IsNullOrEmpty(hw.CpuName)) hw.CpuName = HardwareClassifier.Clean(Text(row, "Name"));
                    hw.Cores += Number(row, "NumberOfCores");
                    hw.Threads += Number(row, "NumberOfLogicalProcessors");
                }
                foreach (var row in Query(@"root\cimv2", "SELECT Name FROM Win32_VideoController"))
                {
                    string name = Text(row, "Name");
                    if (IsRealAdapter(name)) hw.Gpus.Add(HardwareClassifier.Gpu(name));
                }
            }
            catch (Exception e) when (Expected(e)) { /* lo que no se leyó queda vacío */ }
            hw.FormFactor = HardwareClassifier.FormFactorFrom(chassis, battery);
            ReadDisplay(hw);
            return hw;
        }

        /// <summary>Sin el adaptador básico de Microsoft ni los virtuales o remotos.</summary>
        public static bool IsRealAdapter(string name)
        {
            string n = (name ?? "").ToLowerInvariant();
            if (n.Length == 0) return false;
            string[] skip = { "microsoft", "remote", "virtual", "parsec", "meta ", "citrix", "vmware", "virtualbox", "displaylink" };
            return !skip.Any(s => n.Contains(s));
        }

        private static void ReadDisplay(HardwareInfo hw)
        {
            try
            {
                var monitors = DisplaySettings.Monitors();
                var primary = monitors.FirstOrDefault(m => m.Primary) ?? monitors.FirstOrDefault();
                if (primary == null) return;
                var mode = DisplaySettings.CurrentMode(primary.Device);
                if (!mode.HasValue) return;
                hw.Width = mode.Value.Width; hw.Height = mode.Value.Height; hw.RefreshHz = mode.Value.Hz;
                hw.MaxRefreshHz = DisplaySettings.MaxRefreshFor(mode.Value.Width, mode.Value.Height, DisplaySettings.Modes(primary.Device));
            }
            catch (Exception e) when (e is System.ComponentModel.Win32Exception || e is InvalidOperationException) { /* sin pantalla legible */ }
        }

        // ---------- Salud ----------

        public static StatusResult Defender()
        {
            try
            {
                DefenderInfo info = null;
                foreach (var row in Query(@"root\Microsoft\Windows\Defender", "SELECT AMServiceEnabled, RealTimeProtectionEnabled, AntivirusSignatureAge FROM MSFT_MpComputerStatus"))
                {
                    info = new DefenderInfo
                    {
                        ServiceEnabled = Flag(row, "AMServiceEnabled"),
                        RealTimeProtection = Flag(row, "RealTimeProtectionEnabled"),
                        SignatureAgeDays = Number(row, "AntivirusSignatureAge")
                    };
                    break;
                }
                string other = OtherAntivirus();
                if (info == null && !String.IsNullOrEmpty(other)) info = new DefenderInfo { ServiceEnabled = false, OtherAntivirus = other };
                if (info != null && info.ServiceEnabled && !info.RealTimeProtection && !String.IsNullOrEmpty(other)) info.OtherAntivirus = other;
                return HealthRules.Defender(info);
            }
            catch (Exception e) when (Expected(e)) { return HealthRules.Defender(null).WithReason(e.Message); }
        }

        private static string OtherAntivirus()
        {
            try
            {
                var names = Query(@"root\SecurityCenter2", "SELECT displayName FROM AntiVirusProduct").Select(r => Text(r, "displayName"))
                    .Where(n => n.Length > 0 && n.IndexOf("Defender", StringComparison.OrdinalIgnoreCase) < 0).ToList();
                return names.Count == 0 ? "" : String.Join(", ", names);
            }
            catch (Exception e) when (Expected(e)) { return ""; }
        }

        public static StatusResult WindowsUpdate()
        {
            try
            {
                using (var key = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)
                    .OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect"))
                {
                    if (key == null) return HealthRules.WindowsUpdate(null, DateTime.UtcNow, true);
                    string raw = key.GetValue("LastSuccessTime") as string;
                    DateTime parsed;
                    if (String.IsNullOrEmpty(raw)) return HealthRules.WindowsUpdate(null, DateTime.UtcNow, true);
                    if (!DateTime.TryParseExact(raw, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out parsed))
                        return HealthRules.WindowsUpdate(null, DateTime.UtcNow, false);
                    return HealthRules.WindowsUpdate(parsed, DateTime.UtcNow, true);
                }
            }
            catch (Exception e) when (Expected(e)) { return HealthRules.WindowsUpdate(null, DateTime.UtcNow, false).WithReason(e.Message); }
        }

        public static StatusResult Disk()
        {
            try
            {
                var drive = new DriveInfo(Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)));
                return HealthRules.Disk(drive.AvailableFreeSpace, drive.TotalSize);
            }
            catch (Exception e) when (Expected(e)) { return StatusResult.Unknown("No se pudo leer el disco del sistema", e.Message); }
        }

        public static StatusResult Startup()
        {
            try { return HealthRules.Startup(StartupEntries()); }
            catch (Exception e) when (Expected(e)) { return HealthRules.Startup(null).WithReason(e.Message); }
        }

        public static List<StartupEntry> StartupEntries()
        {
            var all = new List<StartupEntry>();
            AddRun(all, RegistryHive.CurrentUser, RegistryView.Registry64, RunKey, "Run", "Usuario");
            AddRun(all, RegistryHive.LocalMachine, RegistryView.Registry64, RunKey, "Run", "Equipo");
            AddRun(all, RegistryHive.LocalMachine, RegistryView.Registry32, RunKey, "Run32", "Equipo (32 bits)");
            AddFolder(all, Environment.GetFolderPath(Environment.SpecialFolder.Startup), RegistryHive.CurrentUser, "Carpeta de inicio");
            AddFolder(all, Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup), RegistryHive.LocalMachine, "Carpeta de inicio (todos)");
            return StartupRules.Distinct(all);
        }

        private static void AddRun(List<StartupEntry> all, RegistryHive hive, RegistryView view, string path, string approvedName, string source)
        {
            using (var baseKey = RegistryKey.OpenBaseKey(hive, view))
            using (var key = baseKey.OpenSubKey(path))
            using (var approved = baseKey.OpenSubKey(ApprovedKey + approvedName))
            {
                if (key == null) return;
                foreach (string name in key.GetValueNames())
                {
                    string command = Convert.ToString(key.GetValue(name));
                    all.Add(new StartupEntry
                    {
                        Name = StartupRules.FriendlyName(name, command),
                        Command = command,
                        Source = source,
                        Enabled = StartupRules.IsEnabled(approved == null ? null : approved.GetValue(name) as byte[])
                    });
                }
            }
        }

        private static void AddFolder(List<StartupEntry> all, string folder, RegistryHive hive, string source)
        {
            if (String.IsNullOrEmpty(folder) || !Directory.Exists(folder)) return;
            using (var baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Registry64))
            using (var approved = baseKey.OpenSubKey(ApprovedKey + "StartupFolder"))
            {
                foreach (string file in Directory.GetFiles(folder))
                {
                    string leaf = Path.GetFileName(file);
                    if (leaf.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase)) continue;
                    all.Add(new StartupEntry
                    {
                        Name = Path.GetFileNameWithoutExtension(file),
                        Command = file,
                        Source = source,
                        Enabled = StartupRules.IsEnabled(approved == null ? null : approved.GetValue(leaf) as byte[])
                    });
                }
            }
        }

        /// <summary>
        /// Zonas térmicas que Windows publica sin drivers extra: primero el contador de rendimiento (sin permisos especiales)
        /// y, si no hay, ACPI (casi siempre pide administrador). Muchos equipos no exponen ninguna.
        /// </summary>
        public static StatusResult Temperature()
        {
            var readings = new List<TemperatureReading>();
            try
            {
                int index = 0;
                foreach (var row in Query(@"root\cimv2", "SELECT Name, Temperature, HighPrecisionTemperature FROM Win32_PerfFormattedData_Counters_ThermalZoneInformation"))
                {
                    index++;
                    double c = HealthRules.CelsiusFromTenthsKelvin(Number(row, "HighPrecisionTemperature"));
                    if (c == 0) c = HealthRules.CelsiusFromKelvin(Number(row, "Temperature"));
                    if (c > 0) readings.Add(new TemperatureReading { Name = "Zona " + index, Celsius = c });
                }
            }
            catch (Exception e) when (Expected(e)) { /* la clase no existe en este equipo */ }
            if (readings.Count == 0)
            {
                try
                {
                    int index = 0;
                    foreach (var row in Query(@"root\WMI", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature"))
                    {
                        index++;
                        double c = HealthRules.CelsiusFromTenthsKelvin(Number(row, "CurrentTemperature"));
                        if (c > 0) readings.Add(new TemperatureReading { Name = "Zona " + index, Celsius = c });
                    }
                }
                catch (Exception e) when (Expected(e)) { /* sin permiso o sin sensor */ }
            }
            return HealthRules.Temperature(readings);
        }

        // ---------- WMI ----------

        private static List<Dictionary<string, object>> Query(string scope, string query)
        {
            var rows = new List<Dictionary<string, object>>();
            using (var searcher = new ManagementObjectSearcher(scope, query))
            using (var results = searcher.Get())
            {
                foreach (ManagementBaseObject row in results)
                {
                    using (row)
                    {
                        var copy = new Dictionary<string, object>();
                        foreach (PropertyData property in row.Properties) copy[property.Name] = property.Value;
                        rows.Add(copy);
                    }
                }
            }
            return rows;
        }

        private static object Get(Dictionary<string, object> row, string name)
        {
            object value;
            return row.TryGetValue(name, out value) ? value : null;
        }

        private static string Text(Dictionary<string, object> row, string name)
        {
            object value = Get(row, name);
            return value == null ? "" : Convert.ToString(value, CultureInfo.InvariantCulture).Trim();
        }

        private static int Number(Dictionary<string, object> row, string name)
        {
            object value = Get(row, name);
            if (value == null) return 0;
            try { return Convert.ToInt32(value, CultureInfo.InvariantCulture); }
            catch (Exception e) when (e is FormatException || e is OverflowException || e is InvalidCastException) { return 0; }
        }

        private static bool Flag(Dictionary<string, object> row, string name)
        {
            object value = Get(row, name);
            return value is bool && (bool)value;
        }
    }
}
