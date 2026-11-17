using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32;

namespace IWinInstaller.App.Modules.Drivers
{
    /// <summary>
    /// Lecturas del equipo para la sección Drivers y firmware. Solo lee: no descarga ni instala nada,
    /// y la búsqueda de Windows Update es la misma que hace Configuración al pulsar «Buscar actualizaciones».
    /// </summary>
    public static class DriverProbe
    {
        public static DriverScan Scan(CancellationToken token)
        {
            var scan = new DriverScan { Identity = ReadIdentity() };
            scan.Drivers.AddRange(ReadDrivers());
            token.ThrowIfCancellationRequested();

            try { scan.Offers = WindowsUpdateDrivers.Search(TimeSpan.FromMinutes(3)); }
            catch (Exception e) when (e is COMException || e is TimeoutException || e is InvalidOperationException || e is UnauthorizedAccessException || e is TargetInvocationException)
            {
                scan.Offers = null;
                scan.WindowsUpdateError = Describe(e);
            }
            token.ThrowIfCancellationRequested();

            int build = OsBuild();
            foreach (var gpu in scan.Drivers.Where(DriverReport.IsGpu).Where(d => DriverRules.Vendor(d.DeviceId, d.Provider) == "NVIDIA"))
            {
                string pci = DriverRules.PciDeviceId(gpu.DeviceId);
                try
                {
                    var release = pci == null ? null : NvidiaDriverSource.Fetch(pci, build, Environment.Is64BitOperatingSystem, token);
                    if (release != null) scan.Nvidia[gpu.DeviceId] = release; else scan.NvidiaErrors.Add(gpu.DeviceId);
                }
                catch (Exception e) when (e is System.Net.WebException || e is System.IO.IOException || e is NotSupportedException || e is ArgumentException)
                {
                    scan.NvidiaErrors.Add(gpu.DeviceId);
                }
            }
            return scan;
        }

        private static IEnumerable<InstalledDriver> ReadDrivers()
        {
            var drivers = new List<InstalledDriver>();
            const string query = "SELECT DeviceName, DeviceClass, DeviceID, HardWareID, DriverVersion, DriverDate, DriverProviderName, Manufacturer FROM Win32_PnPSignedDriver "
                               + "WHERE DeviceClass = 'DISPLAY' OR DeviceClass = 'NET' OR DeviceClass = 'SYSTEM'";
            try
            {
                using (var searcher = new ManagementObjectSearcher(@"root\cimv2", query))
                using (var results = searcher.Get())
                {
                    foreach (ManagementObject item in results)
                    {
                        using (item)
                        {
                            string name = Text(item, "DeviceName");
                            if (String.IsNullOrEmpty(name)) continue;
                            drivers.Add(new InstalledDriver
                            {
                                Name = name,
                                DeviceClass = Text(item, "DeviceClass"),
                                DeviceId = Text(item, "DeviceID"),
                                HardwareId = Text(item, "HardWareID"),
                                Version = Text(item, "DriverVersion"),
                                Date = DriverRules.ParseCimDate(Text(item, "DriverDate")),
                                Provider = Text(item, "DriverProviderName"),
                                Manufacturer = Text(item, "Manufacturer")
                            });
                        }
                    }
                }
            }
            catch (ManagementException) { }
            catch (UnauthorizedAccessException) { }
            return drivers;
        }

        private static SystemIdentity ReadIdentity()
        {
            var identity = new SystemIdentity();
            Read(@"SELECT Manufacturer, Model, PCSystemType FROM Win32_ComputerSystem", item =>
            {
                identity.Manufacturer = Text(item, "Manufacturer");
                identity.Model = Text(item, "Model");
                identity.IsLaptop = item["PCSystemType"] != null && Convert.ToInt32(item["PCSystemType"]) == 2; // 2 = Mobile
            });
            Read(@"SELECT SMBIOSBIOSVersion, ReleaseDate FROM Win32_BIOS", item =>
            {
                identity.BiosVersion = Text(item, "SMBIOSBIOSVersion");
                identity.BiosDate = DriverRules.ParseCimDate(Text(item, "ReleaseDate"));
            });
            Read(@"SELECT Manufacturer, Product FROM Win32_BaseBoard", item =>
            {
                identity.BoardManufacturer = Text(item, "Manufacturer");
                identity.BoardProduct = Text(item, "Product");
            });
            Read(@"SELECT Manufacturer FROM Win32_Processor", item => { if (identity.CpuVendor == null) identity.CpuVendor = Text(item, "Manufacturer"); });
            return identity;
        }

        private static void Read(string query, Action<ManagementBaseObject> read)
        {
            try
            {
                using (var searcher = new ManagementObjectSearcher(@"root\cimv2", query))
                using (var results = searcher.Get())
                    foreach (ManagementObject item in results) using (item) read(item);
            }
            catch (ManagementException) { }
            catch (UnauthorizedAccessException) { }
        }

        private static string Text(ManagementBaseObject item, string property)
        {
            object value = item[property];
            string text = value == null ? null : Convert.ToString(value).Trim();
            return String.IsNullOrEmpty(text) ? null : text;
        }

        /// <summary>Número de compilación real (Environment.OSVersion miente sin manifiesto de compatibilidad).</summary>
        private static int OsBuild()
        {
            try
            {
                using (var key = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64).OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
                {
                    int build;
                    if (key != null && int.TryParse(Convert.ToString(key.GetValue("CurrentBuildNumber")), out build)) return build;
                }
            }
            catch (System.Security.SecurityException) { }
            return Environment.OSVersion.Version.Build;
        }

        private static string Describe(Exception e)
        {
            var com = (e as TargetInvocationException)?.InnerException as COMException ?? e as COMException;
            if (com != null)
            {
                switch ((uint)com.HResult)
                {
                    case 0x8024402C: case 0x80072EE7: case 0x80072EFD: return "sin conexión con el servidor de actualizaciones.";
                    case 0x80070422: return "el servicio Windows Update está desactivado.";
                    case 0x8024001E: return "el servicio Windows Update se está cerrando; vuelve a probar.";
                }
                return "error 0x" + ((uint)com.HResult).ToString("X8") + ".";
            }
            if (e is TimeoutException) return "tardó más de 3 minutos.";
            return e.Message;
        }
    }
}
