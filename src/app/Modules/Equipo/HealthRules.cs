using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using IWinInstaller.App.Core;

namespace IWinInstaller.App.Modules.Equipo
{
    /// <summary>Microsoft Defender tal como lo expone Windows (MSFT_MpComputerStatus).</summary>
    public sealed class DefenderInfo
    {
        public bool ServiceEnabled { get; set; }
        public bool RealTimeProtection { get; set; }
        public int SignatureAgeDays { get; set; }
        /// <summary>Otro antivirus registrado en el Centro de seguridad (no Defender).</summary>
        public string OtherAntivirus { get; set; }
    }

    public sealed class StartupEntry
    {
        public string Name { get; set; }
        public string Command { get; set; }
        public string Source { get; set; }
        public bool Enabled { get; set; }
    }

    public sealed class TemperatureReading
    {
        public string Name { get; set; }
        public double Celsius { get; set; }
    }

    /// <summary>Reglas puras del panel de salud: de los datos en bruto al estado, el resumen y el motivo.</summary>
    public static class HealthRules
    {
        public const int StartupAttention = 12;
        public const double TemperatureAttention = 85;

        private static readonly CultureInfo Es = new CultureInfo("es-ES");

        public static StatusResult Defender(DefenderInfo info)
        {
            if (info == null) return StatusResult.Unknown("No se pudo leer Microsoft Defender", "Defender no responde en este equipo.");
            if (!info.ServiceEnabled && !String.IsNullOrEmpty(info.OtherAntivirus))
                return new StatusResult(StatusState.Ok, "Protección a cargo de " + info.OtherAntivirus, "", "nav.security");
            if (!info.ServiceEnabled || !info.RealTimeProtection)
                return new StatusResult(StatusState.Attention, "Protección en tiempo real desactivada", "Actívala en Seguridad de Windows.", "nav.security");
            if (info.SignatureAgeDays > 3)
                return new StatusResult(StatusState.Attention, "Firmas de hace " + info.SignatureAgeDays + " días", "Actualiza las firmas desde Seguridad.", "nav.security");
            return new StatusResult(StatusState.Ok, "Defender activo y al día", info.SignatureAgeDays <= 0 ? "Firmas de hoy." : "Firmas de hace " + info.SignatureAgeDays + (info.SignatureAgeDays == 1 ? " día." : " días."), "nav.security");
        }

        /// <summary>Windows Update: al día si buscó con éxito en la última semana.</summary>
        public static StatusResult WindowsUpdate(DateTime? lastSuccessUtc, DateTime nowUtc, bool readable)
        {
            if (!readable) return StatusResult.Unknown("No se pudo leer Windows Update", "Windows no guarda la fecha de la última búsqueda en este equipo.");
            if (!lastSuccessUtc.HasValue || lastSuccessUtc.Value.Year < 2000)
                return new StatusResult(StatusState.Attention, "Windows Update no ha buscado todavía", "Abre Windows Update y pulsa «Buscar actualizaciones».", "windowsupdate.open");
            int days = (int)(nowUtc - lastSuccessUtc.Value).TotalDays;
            if (days <= 7) return new StatusResult(StatusState.Ok, "Windows Update al día", "Última búsqueda: " + When(days) + ".", "windowsupdate.open");
            return new StatusResult(StatusState.Attention, "Windows Update lleva " + days + " días sin buscar", "Abre Windows Update y busca actualizaciones.", "windowsupdate.open");
        }

        public static string When(int days)
        {
            if (days <= 0) return "hoy";
            if (days == 1) return "ayer";
            return "hace " + days + " días";
        }

        /// <summary>Espacio libre del disco del sistema, con las mismas reglas que el Inicio.</summary>
        public static StatusResult Disk(long freeBytes, long totalBytes)
        {
            return StatusRules.DiskSpace(freeBytes, totalBytes);
        }

        public static StatusResult Startup(IList<StartupEntry> entries)
        {
            if (entries == null) return StatusResult.Unknown("No se pudo leer el inicio", "No se pudieron leer las claves de arranque.");
            var active = entries.Where(e => e.Enabled).ToList();
            if (active.Count == 0) return new StatusResult(StatusState.Ok, "Nada se inicia con Windows", "", "");
            string names = String.Join(", ", active.Select(e => e.Name).Take(6)) + (active.Count > 6 ? "…" : "");
            string summary = active.Count + (active.Count == 1 ? " app arranca con Windows" : " apps arrancan con Windows");
            if (active.Count > StartupAttention)
                return new StatusResult(StatusState.Attention, summary, "Son muchas: retrasan el arranque y gastan RAM. Desactiva las que no uses en Administrador de tareas › Inicio. " + names, "");
            return new StatusResult(StatusState.Ok, summary, names, "");
        }

        /// <summary>Temperaturas de las zonas térmicas de Windows; sin lecturas no se inventa nada.</summary>
        public static StatusResult Temperature(IList<TemperatureReading> readings)
        {
            var valid = (readings ?? new List<TemperatureReading>()).Where(r => r.Celsius > 0 && r.Celsius < 130).ToList();
            if (valid.Count == 0)
                return new StatusResult(StatusState.NotApplicable, "Sin sensores de temperatura", "Este equipo no expone temperaturas a Windows sin un driver extra (HWiNFO, Core Temp…).", "");
            var hottest = valid.OrderByDescending(r => r.Celsius).First();
            string text = Math.Round(hottest.Celsius).ToString(Es) + " °C";
            string detail = String.Join(" · ", valid.Select(r => r.Name + " " + Math.Round(r.Celsius).ToString(Es) + " °C").Take(4)) + ". Lectura puntual de las zonas de Windows, no de cada núcleo.";
            if (hottest.Celsius >= TemperatureAttention)
                return new StatusResult(StatusState.Attention, "Temperatura alta: " + text, detail + " Revisa ventilación y polvo.", "");
            return new StatusResult(StatusState.Ok, "Temperatura normal: " + text, detail, "");
        }

        /// <summary>De décimas de kelvin (ACPI) a °C; 0 si el valor no es creíble.</summary>
        public static double CelsiusFromTenthsKelvin(double tenths)
        {
            if (tenths <= 0) return 0;
            double c = tenths / 10.0 - 273.15;
            return c > -50 && c < 200 ? c : 0;
        }

        /// <summary>De kelvin enteros (contador térmico de Windows) a °C; 0 si el valor no es creíble.</summary>
        public static double CelsiusFromKelvin(double kelvin)
        {
            if (kelvin <= 0) return 0;
            double c = kelvin - 273.15;
            return c > -50 && c < 200 ? c : 0;
        }
    }

    /// <summary>Lectura de las entradas de arranque (Run, carpetas de inicio y StartupApproved), sin tocar el sistema.</summary>
    public static class StartupRules
    {
        /// <summary>StartupApproved: el primer byte impar (03, 07…) significa desactivado desde el Administrador de tareas.</summary>
        public static bool IsEnabled(byte[] approved)
        {
            if (approved == null || approved.Length == 0) return true;
            return (approved[0] & 1) == 0;
        }

        /// <summary>Nombre legible de una línea de comandos: el ejecutable sin ruta ni extensión.</summary>
        public static string FriendlyName(string valueName, string command)
        {
            string cmd = (command ?? "").Trim();
            string exe = "";
            if (cmd.StartsWith("\"", StringComparison.Ordinal))
            {
                int end = cmd.IndexOf('"', 1);
                exe = end > 1 ? cmd.Substring(1, end - 1) : cmd.Trim('"');
            }
            else
            {
                int lower = cmd.ToLowerInvariant().IndexOf(".exe", StringComparison.Ordinal);
                exe = lower >= 0 ? cmd.Substring(0, lower + 4) : (cmd.Split(' ').FirstOrDefault() ?? "");
            }
            string file = exe.Replace('/', '\\');
            int slash = file.LastIndexOf('\\');
            if (slash >= 0) file = file.Substring(slash + 1);
            if (file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) file = file.Substring(0, file.Length - 4);
            if (!String.IsNullOrWhiteSpace(valueName) && valueName.Length >= 3 && valueName.Length <= 40) return valueName.Trim();
            return String.IsNullOrWhiteSpace(file) ? (valueName ?? "").Trim() : file;
        }

        /// <summary>Sin repetidos entre HKCU, HKLM y las carpetas de inicio, por nombre sin mayúsculas.</summary>
        public static List<StartupEntry> Distinct(IEnumerable<StartupEntry> entries)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var list = new List<StartupEntry>();
            foreach (var entry in entries.Where(e => !String.IsNullOrWhiteSpace(e.Name)))
                if (seen.Add(entry.Name)) list.Add(entry);
            return list.OrderBy(e => e.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        }
    }
}
