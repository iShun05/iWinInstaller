using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace IWinInstaller.App.Modules.Drivers
{
    /// <summary>Reglas puras (sin WMI ni red): versiones, fabricantes y webs oficiales.</summary>
    public static class DriverRules
    {
        public const string NvidiaDriversUrl = "https://www.nvidia.com/es-es/drivers/";
        public const string AmdDriversUrl = "https://www.amd.com/es/support/download/drivers.html";
        public const string IntelAssistantUrl = "https://www.intel.com/content/www/us/en/support/detect.html";
        public const string WindowsUpdateUri = "ms-settings:windowsupdate";
        public const string OptionalUpdatesUri = "ms-settings:windowsupdate-optionalupdates";

        private static readonly Regex PciVendor = new Regex(@"(?:VEN|VID)_([0-9A-F]{4})", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        private static readonly Regex PciDevice = new Regex(@"(?:DEV|PID)_([0-9A-F]{4})", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        private static readonly Regex TrailingVersion = new Regex(@"(\d+(?:\.\d+){1,4})\s*\)?\s*$", RegexOptions.CultureInvariant);

        /// <summary>Fabricante a partir del id de PCI/USB (VEN_/VID_) y, si no, del texto.</summary>
        public static string Vendor(string deviceId, string text)
        {
            var match = PciVendor.Match(deviceId ?? "");
            if (match.Success)
            {
                switch (match.Groups[1].Value.ToUpperInvariant())
                {
                    case "10DE": return "NVIDIA";
                    case "1002": case "1022": return "AMD";
                    case "8086": case "8087": return "Intel";
                    case "10EC": case "0BDA": return "Realtek";
                    case "14C3": case "0E8D": return "MediaTek";
                    case "17CB": case "168C": case "1969": return "Qualcomm";
                    case "14E4": return "Broadcom";
                }
            }
            return VendorFromText(text);
        }

        public static string VendorFromText(string text)
        {
            string t = (text ?? "").ToLowerInvariant();
            if (t.Contains("nvidia")) return "NVIDIA";
            if (t.Contains("advanced micro devices") || t.Contains("authenticamd") || Regex.IsMatch(t, @"\bamd\b")) return "AMD";
            if (t.Contains("intel")) return "Intel";
            if (t.Contains("realtek")) return "Realtek";
            if (t.Contains("mediatek")) return "MediaTek";
            if (t.Contains("qualcomm")) return "Qualcomm";
            if (t.Contains("killer")) return "Killer";
            if (t.Contains("broadcom")) return "Broadcom";
            return null;
        }

        /// <summary>Id de dispositivo PCI (DEV_xxxx) en mayúsculas, o null.</summary>
        public static string PciDeviceId(string deviceId)
        {
            var match = PciDevice.Match(deviceId ?? "");
            return match.Success ? match.Groups[1].Value.ToUpperInvariant() : null;
        }

        /// <summary>
        /// Versión de Windows de NVIDIA (32.0.15.6094) a la que publica NVIDIA (560.94): las cinco últimas cifras
        /// de las dos últimas partes. Devuelve null si el formato no es el esperado.
        /// </summary>
        public static string NvidiaVersion(string windowsVersion)
        {
            var parts = (windowsVersion ?? "").Trim().Split('.');
            if (parts.Length != 4 || parts.Any(p => p.Length == 0 || !p.All(char.IsDigit)) || parts[3].Length > 4) return null;
            string digits = parts[2] + parts[3].PadLeft(4, '0');
            if (digits.Length < 5) return null;
            string last = digits.Substring(digits.Length - 5);
            return int.Parse(last.Substring(0, 3), CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture) + "." + last.Substring(3);
        }

        /// <summary>Compara versiones numéricas por partes (1.10 &gt; 1.9). null si alguna no es numérica.</summary>
        public static int? CompareVersions(string a, string b)
        {
            var left = ParseParts(a);
            var right = ParseParts(b);
            if (left == null || right == null) return null;
            int length = Math.Max(left.Length, right.Length);
            for (int i = 0; i < length; i++)
            {
                long x = i < left.Length ? left[i] : 0, y = i < right.Length ? right[i] : 0;
                if (x != y) return x < y ? -1 : 1;
            }
            return 0;
        }

        private static long[] ParseParts(string version)
        {
            if (String.IsNullOrWhiteSpace(version)) return null;
            var parts = version.Trim().Split('.');
            var result = new long[parts.Length];
            for (int i = 0; i < parts.Length; i++)
                if (!long.TryParse(parts[i], NumberStyles.None, CultureInfo.InvariantCulture, out result[i])) return null;
            return result;
        }

        /// <summary>Versión al final del título de Windows Update («NVIDIA - Display - 32.0.15.6094»).</summary>
        public static string VersionFromTitle(string title)
        {
            var match = TrailingVersion.Match(title ?? "");
            return match.Success ? match.Groups[1].Value : null;
        }

        /// <summary>Fecha CIM de WMI (20240312000000.000000-000): solo el día.</summary>
        public static DateTime? ParseCimDate(string value)
        {
            DateTime date;
            if (value == null || value.Length < 8) return null;
            return DateTime.TryParseExact(value.Substring(0, 8), "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out date) && date.Year > 1990 ? date : (DateTime?)null;
        }

        public static string FormatDate(DateTime? date)
        {
            return date.HasValue ? date.Value.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture) : null;
        }

        /// <summary>«hace 3 meses», «hace 1 año y 2 meses». Informativo: la edad sola no es motivo de aviso.</summary>
        public static string Age(DateTime date, DateTime now)
        {
            int months = (now.Year - date.Year) * 12 + now.Month - date.Month - (now.Day < date.Day ? 1 : 0);
            if (months < 1) return "este mes";
            if (months < 12) return "hace " + months + (months == 1 ? " mes" : " meses");
            int years = months / 12, rest = months % 12;
            string text = "hace " + years + (years == 1 ? " año" : " años");
            return rest == 0 ? text : text + " y " + rest + (rest == 1 ? " mes" : " meses");
        }

        /// <summary>El id de hardware de la oferta corresponde al dispositivo (uno contiene al otro como prefijo).</summary>
        public static bool SameHardware(string installedId, string offerId)
        {
            if (String.IsNullOrWhiteSpace(installedId) || String.IsNullOrWhiteSpace(offerId)) return false;
            return installedId.StartsWith(offerId, StringComparison.OrdinalIgnoreCase) || offerId.StartsWith(installedId, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// La oferta es más nueva que lo instalado. Windows Update a veces ofrece versiones anteriores a las del fabricante
        /// (con fecha más reciente): si las dos versiones se pueden comparar, manda la versión.
        /// </summary>
        public static bool IsNewer(InstalledDriver installed, WindowsUpdateOffer offer)
        {
            var byVersion = CompareVersions(offer.Version, installed.Version);
            if (byVersion.HasValue) return byVersion.Value > 0;
            if (offer.Date.HasValue && installed.Date.HasValue) return offer.Date.Value > installed.Date.Value;
            return true; // Windows Update solo ofrece drivers mejor clasificados que el instalado
        }

        /// <summary>Página oficial de soporte del fabricante del equipo o de la placa; null si no se conoce.</summary>
        public static string OemSupportUrl(string manufacturer)
        {
            string m = (manufacturer ?? "").ToLowerInvariant();
            if (m.Contains("lenovo")) return "https://pcsupport.lenovo.com/";
            if (m.Contains("hewlett") || m == "hp" || m.StartsWith("hp ", StringComparison.Ordinal)) return "https://support.hp.com/es-es/drivers";
            if (m.Contains("dell") || m.Contains("alienware")) return "https://www.dell.com/support/home/";
            if (m.Contains("asus")) return "https://www.asus.com/support/download-center/";
            if (m.Contains("micro-star") || Regex.IsMatch(m, @"\bmsi\b")) return "https://www.msi.com/support/download";
            if (m.Contains("acer")) return "https://www.acer.com/es-es/support/drivers-and-manuals";
            if (m.Contains("gigabyte")) return "https://www.gigabyte.com/Support";
            if (m.Contains("asrock")) return "https://www.asrock.com/support/index.asp";
            if (m.Contains("razer")) return "https://mysupport.razer.com/";
            return null;
        }

        /// <summary>Web del fabricante del equipo; en sobremesas montados a mano, la de la placa base.</summary>
        public static string OemUrl(SystemIdentity identity)
        {
            if (identity == null) return null;
            return OemSupportUrl(identity.Manufacturer) ?? OemSupportUrl(identity.BoardManufacturer);
        }

        public static string OemName(SystemIdentity identity)
        {
            if (identity == null) return null;
            return OemSupportUrl(identity.Manufacturer) != null ? identity.Manufacturer : OemSupportUrl(identity.BoardManufacturer) != null ? identity.BoardManufacturer : null;
        }

        /// <summary>Web del fabricante del chip (gráfica, chipset o red); null si solo vale la del equipo.</summary>
        public static string ChipVendorUrl(DriverKind kind, string vendor)
        {
            switch (vendor)
            {
                case "NVIDIA": return kind == DriverKind.Gpu ? NvidiaDriversUrl : null;
                case "AMD": return kind == DriverKind.Gpu || kind == DriverKind.Chipset ? AmdDriversUrl : null;
                case "Intel": case "Killer": return IntelAssistantUrl;
                default: return null;
            }
        }

        internal static IEnumerable<WindowsUpdateOffer> Matching(IEnumerable<InstalledDriver> drivers, IEnumerable<WindowsUpdateOffer> offers)
        {
            if (offers == null) return Enumerable.Empty<WindowsUpdateOffer>();
            var list = drivers.ToList();
            return offers.Where(o => list.Any(d => SameHardware(d.HardwareId, o.HardwareId)));
        }
    }
}
