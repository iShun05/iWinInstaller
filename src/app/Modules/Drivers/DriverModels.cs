using System;
using System.Collections.Generic;

namespace IWinInstaller.App.Modules.Drivers
{
    public enum DriverKind { Gpu, Chipset, Network, Firmware, Other }

    /// <summary>
    /// UpToDate solo cuando una fuente fiable lo confirma (NVIDIA). CheckManually: no hay fuente fiable
    /// o Windows Update no ofrece nada; se muestra la versión y la web oficial, sin avisar.
    /// </summary>
    public enum DriverState { UpToDate, UpdateAvailable, CheckManually }

    /// <summary>Un driver instalado tal como lo da Win32_PnPSignedDriver.</summary>
    public sealed class InstalledDriver
    {
        public string Name { get; set; }
        public string DeviceClass { get; set; }
        public string DeviceId { get; set; }
        public string HardwareId { get; set; }
        public string Version { get; set; }
        public DateTime? Date { get; set; }
        public string Provider { get; set; }
        public string Manufacturer { get; set; }
    }

    /// <summary>Un driver que Windows Update ofrece y no está instalado (solo búsqueda, nunca se descarga).</summary>
    public sealed class WindowsUpdateOffer
    {
        public string Title { get; set; }
        public string DriverClass { get; set; }
        public string HardwareId { get; set; }
        public string Provider { get; set; }
        public DateTime? Date { get; set; }
        /// <summary>Opcional en Windows Update (BrowseOnly): Windows no lo instala solo.</summary>
        public bool Optional { get; set; }
        public string Version { get { return DriverRules.VersionFromTitle(Title); } }
    }

    /// <summary>Fabricante, modelo, BIOS y placa del equipo.</summary>
    public sealed class SystemIdentity
    {
        public string Manufacturer { get; set; }
        public string Model { get; set; }
        public string BoardManufacturer { get; set; }
        public string BoardProduct { get; set; }
        public string BiosVersion { get; set; }
        public DateTime? BiosDate { get; set; }
        public string CpuVendor { get; set; }
        public bool IsLaptop { get; set; }
    }

    /// <summary>Última versión publicada por NVIDIA para una GPU concreta.</summary>
    public sealed class NvidiaRelease
    {
        public string Version { get; set; }
        public DateTime? Date { get; set; }
        public string DetailsUrl { get; set; }
        public string Name { get; set; }
    }

    /// <summary>Todo lo que hace falta para montar el informe; lo rellena DriverProbe y las pruebas.</summary>
    public sealed class DriverScan
    {
        public DriverScan()
        {
            Drivers = new List<InstalledDriver>();
            Nvidia = new Dictionary<string, NvidiaRelease>(StringComparer.OrdinalIgnoreCase);
            NvidiaErrors = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }

        public List<InstalledDriver> Drivers { get; private set; }
        public SystemIdentity Identity { get; set; }
        /// <summary>null si la búsqueda en Windows Update falló.</summary>
        public List<WindowsUpdateOffer> Offers { get; set; }
        public string WindowsUpdateError { get; set; }
        /// <summary>Por DeviceId de la GPU.</summary>
        public Dictionary<string, NvidiaRelease> Nvidia { get; private set; }
        /// <summary>GPUs de NVIDIA cuya consulta falló o que NVIDIA no reconoce.</summary>
        public HashSet<string> NvidiaErrors { get; private set; }
    }
}
