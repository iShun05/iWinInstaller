using System;
using System.Collections.Generic;
using System.IO;
using System.Management;
using IWinInstaller.App.Core;
using Microsoft.Win32;

namespace IWinInstaller.App.Probes
{
    /// <summary>Lecturas rápidas y sin permisos especiales que la interfaz hace sin pasar por el motor.</summary>
    public static class SystemProbes
    {
        public static StatusResult DiskSpace()
        {
            try
            {
                string systemRoot = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
                var drive = new DriveInfo(systemRoot);
                return StatusRules.DiskSpace(drive.AvailableFreeSpace, drive.TotalSize);
            }
            catch (Exception e) { return StatusResult.Unknown("No se pudo leer el disco del sistema", e.Message); }
        }

        public static StatusResult DiskHealth()
        {
            try
            {
                var disks = new List<DiskHealthInfo>();
                using (var searcher = new ManagementObjectSearcher(@"root\Microsoft\Windows\Storage", "SELECT FriendlyName, HealthStatus FROM MSFT_PhysicalDisk"))
                using (var results = searcher.Get())
                {
                    foreach (ManagementObject disk in results)
                    {
                        using (disk)
                        {
                            disks.Add(new DiskHealthInfo
                            {
                                Name = Convert.ToString(disk["FriendlyName"]) ?? "Disco",
                                HealthStatus = disk["HealthStatus"] == null ? 5 : Convert.ToInt32(disk["HealthStatus"])
                            });
                        }
                    }
                }
                return StatusRules.DiskHealth(disks);
            }
            catch (ManagementException e) { return StatusRules.DiskHealth(null).WithReason(e.Message); }
            catch (UnauthorizedAccessException e) { return StatusRules.DiskHealth(null).WithReason(e.Message); }
        }

        public static StatusResult Battery()
        {
            try
            {
                long designed = ReadMax(@"root\WMI", "SELECT DesignedCapacity FROM BatteryStaticData", "DesignedCapacity");
                long full = ReadMax(@"root\WMI", "SELECT FullChargedCapacity FROM BatteryFullChargedCapacity", "FullChargedCapacity");
                return StatusRules.Battery(designed, full);
            }
            catch (ManagementException)
            {
                // Sin batería estas clases no existen o no devuelven filas: la tarjeta no aplica
                return StatusRules.Battery(0, 0);
            }
        }

        /// <summary>Claves que usa Windows para marcar un reinicio pendiente.</summary>
        public static StatusResult Reboot()
        {
            try
            {
                bool pending =
                    KeyExists(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") ||
                    KeyExists(@"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") ||
                    ValueExists(@"SYSTEM\CurrentControlSet\Control\Session Manager", "PendingFileRenameOperations");
                return StatusRules.Reboot(pending);
            }
            catch (System.Security.SecurityException) { return StatusRules.Reboot(null); }
            catch (UnauthorizedAccessException) { return StatusRules.Reboot(null); }
        }

        private static long ReadMax(string scope, string query, string property)
        {
            long max = 0;
            using (var searcher = new ManagementObjectSearcher(scope, query))
            using (var results = searcher.Get())
            {
                foreach (ManagementObject item in results)
                    using (item) if (item[property] != null) max = Math.Max(max, Convert.ToInt64(item[property]));
            }
            return max;
        }

        private static bool KeyExists(string path)
        {
            using (var key = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64).OpenSubKey(path))
                return key != null;
        }

        private static bool ValueExists(string path, string name)
        {
            using (var key = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64).OpenSubKey(path))
            {
                if (key == null) return false;
                var value = key.GetValue(name) as string[];
                return value != null && value.Length > 0;
            }
        }
    }
}
