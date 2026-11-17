using System;
using System.Collections.Generic;
using System.Linq;

namespace IWinInstaller.App.Modules.Drivers
{
    /// <summary>Una fila de la sección Drivers y firmware.</summary>
    public sealed class DriverRow
    {
        public DriverKind Kind { get; set; }
        public string Title { get; set; }
        public string Installed { get; set; }
        public DriverState State { get; set; }
        public string Status { get; set; }
        public string Note { get; set; }
        public string LinkUrl { get; set; }
        public string LinkLabel { get; set; }

        public bool HasNote { get { return !String.IsNullOrEmpty(Note); } }
        public bool HasLink { get { return !String.IsNullOrEmpty(LinkUrl); } }
        public bool IsUpdate { get { return State == DriverState.UpdateAvailable; } }
        public bool IsUpToDate { get { return State == DriverState.UpToDate; } }
    }

    /// <summary>Convierte el inventario y las consultas en filas. Puro: lo prueban las pruebas unitarias.</summary>
    public static class DriverReport
    {
        private const string BiosWarning = "La BIOS se actualiza solo con la herramienta del fabricante, enchufado y sin cortar la corriente.";

        public static List<DriverRow> Build(DriverScan scan, DateTime now)
        {
            var rows = new List<DriverRow>();
            var identity = scan.Identity ?? new SystemIdentity();
            var offers = scan.Offers ?? new List<WindowsUpdateOffer>();
            var used = new HashSet<WindowsUpdateOffer>();

            foreach (var gpu in scan.Drivers.Where(IsGpu).OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase))
                rows.Add(GpuRow(gpu, scan, identity, offers, used, now));

            var chipset = Chipset(scan.Drivers, identity);
            if (chipset.Count > 0) rows.Add(ChipsetRow(chipset, scan, identity, offers, used, now));

            foreach (var adapter in scan.Drivers.Where(IsNetwork).OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase))
                rows.Add(NetworkRow(adapter, scan, identity, offers, used, now));

            rows.Add(FirmwareRow(scan, identity, offers, used, now));

            foreach (var offer in offers.Where(o => !used.Contains(o)))
            {
                rows.Add(new DriverRow
                {
                    Kind = DriverKind.Other,
                    Title = "Otro · " + (String.IsNullOrEmpty(offer.DriverClass) ? "dispositivo" : offer.DriverClass),
                    Installed = offer.Title,
                    State = DriverState.UpdateAvailable,
                    Status = OfferStatus(offer),
                    LinkUrl = offer.Optional ? DriverRules.OptionalUpdatesUri : DriverRules.WindowsUpdateUri,
                    LinkLabel = "Abrir Windows Update"
                });
            }
            return rows;
        }

        public static string Summary(IList<DriverRow> rows, DriverScan scan)
        {
            int updates = rows.Count(r => r.State == DriverState.UpdateAvailable);
            int manual = rows.Count(r => r.State == DriverState.CheckManually);
            string text = updates == 0 ? "Ningún driver con versión nueva confirmada."
                : updates + (updates == 1 ? " driver o firmware con versión nueva." : " drivers o firmware con versión nueva.");
            if (manual > 0) text += " " + manual + (manual == 1 ? " se comprueba" : " se comprueban") + " en la web del fabricante.";
            if (scan.Offers == null) text += " Windows Update no respondió" + (String.IsNullOrEmpty(scan.WindowsUpdateError) ? "." : ": " + scan.WindowsUpdateError);
            return text;
        }

        internal static bool IsGpu(InstalledDriver d)
        {
            return Is(d, "DISPLAY") && StartsWithAny(d.DeviceId, "PCI\\", "ACPI\\");
        }

        internal static bool IsNetwork(InstalledDriver d)
        {
            return Is(d, "NET") && StartsWithAny(d.DeviceId, "PCI\\", "USB\\");
        }

        /// <summary>Drivers de sistema del fabricante del procesador (Intel, AMD o Qualcomm) que no son de Microsoft.</summary>
        internal static List<InstalledDriver> Chipset(IEnumerable<InstalledDriver> drivers, SystemIdentity identity)
        {
            string cpu = DriverRules.VendorFromText(identity.CpuVendor);
            if (cpu == null) return new List<InstalledDriver>();
            return drivers.Where(d => Is(d, "SYSTEM") && StartsWithAny(d.DeviceId, "PCI\\", "ACPI\\")
                                      && !IsMicrosoft(d.Provider)
                                      && DriverRules.VendorFromText(d.Provider) == cpu).ToList();
        }

        private static DriverRow GpuRow(InstalledDriver gpu, DriverScan scan, SystemIdentity identity, List<WindowsUpdateOffer> offers, HashSet<WindowsUpdateOffer> used, DateTime now)
        {
            string vendor = DriverRules.Vendor(gpu.DeviceId, gpu.Provider + " " + gpu.Name);
            var row = new DriverRow { Kind = DriverKind.Gpu, Title = "Gráfica · " + gpu.Name };
            var related = Related(new[] { gpu }, offers, used);

            if (vendor == "NVIDIA")
            {
                string friendly = DriverRules.NvidiaVersion(gpu.Version);
                row.Installed = Installed(friendly != null ? friendly + " (" + gpu.Version + ")" : gpu.Version, gpu.Date, now);
                NvidiaRelease latest;
                if (friendly != null && scan.Nvidia.TryGetValue(gpu.DeviceId ?? "", out latest))
                {
                    int? cmp = DriverRules.CompareVersions(latest.Version, friendly);
                    if (cmp.HasValue)
                    {
                        string published = latest.Version + (latest.Date.HasValue ? " (" + DriverRules.FormatDate(latest.Date) + ")" : "");
                        row.State = cmp.Value > 0 ? DriverState.UpdateAvailable : DriverState.UpToDate;
                        row.Status = cmp.Value > 0 ? "Versión nueva de NVIDIA: " + published : "Al día · la última de NVIDIA es " + published;
                        row.LinkUrl = cmp.Value > 0 ? (latest.DetailsUrl ?? DriverRules.NvidiaDriversUrl) : DriverRules.NvidiaDriversUrl;
                        row.LinkLabel = cmp.Value > 0 ? "Ver en NVIDIA" : "Web de NVIDIA";
                        if (cmp.Value > 0) row.Note = "Instálala con la app de NVIDIA o desde su web. En portátiles con gráfica integrada y NVIDIA, la integrada se actualiza aparte.";
                        return row;
                    }
                }
                ApplyOffersOrManual(row, gpu, related, DriverRules.NvidiaDriversUrl, "Web de NVIDIA",
                    scan.NvidiaErrors.Contains(gpu.DeviceId ?? "") || friendly == null ? "No se pudo consultar la última versión a NVIDIA." : null);
                return row;
            }

            row.Installed = Installed(gpu.Version, gpu.Date, now);
            string url = DriverRules.ChipVendorUrl(DriverKind.Gpu, vendor) ?? DriverRules.OemUrl(identity);
            string note = identity.IsLaptop && (vendor == "AMD" || vendor == "Intel")
                ? "En portátiles, si la versión del fabricante del chip no se instala, usa la del fabricante del portátil."
                : null;
            ApplyOffersOrManual(row, gpu, related, url, LinkLabel(url, vendor, identity), note);
            return row;
        }

        private static DriverRow ChipsetRow(List<InstalledDriver> parts, DriverScan scan, SystemIdentity identity, List<WindowsUpdateOffer> offers, HashSet<WindowsUpdateOffer> used, DateTime now)
        {
            string vendor = DriverRules.VendorFromText(identity.CpuVendor);
            var newest = parts.OrderByDescending(d => d.Date ?? DateTime.MinValue).First();
            var row = new DriverRow
            {
                Kind = DriverKind.Chipset,
                Title = "Chipset · " + vendor + " (" + parts.Count + (parts.Count == 1 ? " componente)" : " componentes)"),
                Installed = Installed(newest.Version, newest.Date, now, "componente más reciente")
            };
            var related = Related(parts, offers, used);
            // Portátil: primero el fabricante del equipo, que adapta el chipset; sobremesa: el del chip
            string url = identity.IsLaptop ? (DriverRules.OemUrl(identity) ?? DriverRules.ChipVendorUrl(DriverKind.Chipset, vendor))
                                           : (DriverRules.ChipVendorUrl(DriverKind.Chipset, vendor) ?? DriverRules.OemUrl(identity));
            ApplyOffersOrManual(row, newest, related, url, LinkLabel(url, vendor, identity), null, parts);
            return row;
        }

        private static DriverRow NetworkRow(InstalledDriver adapter, DriverScan scan, SystemIdentity identity, List<WindowsUpdateOffer> offers, HashSet<WindowsUpdateOffer> used, DateTime now)
        {
            string vendor = DriverRules.Vendor(adapter.DeviceId, adapter.Provider + " " + adapter.Name);
            var row = new DriverRow
            {
                Kind = DriverKind.Network,
                Title = "Red · " + adapter.Name,
                Installed = Installed(adapter.Version, adapter.Date, now, IsMicrosoft(adapter.Provider) ? "driver genérico de Windows" : null)
            };
            var related = Related(new[] { adapter }, offers, used);
            string url = DriverRules.ChipVendorUrl(DriverKind.Network, vendor) ?? DriverRules.OemUrl(identity);
            ApplyOffersOrManual(row, adapter, related, url, LinkLabel(url, vendor, identity), null);
            return row;
        }

        private static DriverRow FirmwareRow(DriverScan scan, SystemIdentity identity, List<WindowsUpdateOffer> offers, HashSet<WindowsUpdateOffer> used, DateTime now)
        {
            string model = String.Join(" ", new[] { identity.Manufacturer, identity.Model }.Where(s => !String.IsNullOrWhiteSpace(s) && !IsPlaceholder(s)));
            if (String.IsNullOrEmpty(model)) model = String.Join(" ", new[] { identity.BoardManufacturer, identity.BoardProduct }.Where(s => !String.IsNullOrWhiteSpace(s)));
            var row = new DriverRow
            {
                Kind = DriverKind.Firmware,
                Title = "BIOS / UEFI" + (String.IsNullOrEmpty(model) ? "" : " · " + model),
                Installed = Installed(identity.BiosVersion, identity.BiosDate, now)
            };
            var firmware = offers.Where(o => !used.Contains(o) && String.Equals(o.DriverClass, "Firmware", StringComparison.OrdinalIgnoreCase)).ToList();
            foreach (var offer in firmware) used.Add(offer);
            string url = DriverRules.OemUrl(identity);
            if (firmware.Count > 0)
            {
                row.State = DriverState.UpdateAvailable;
                row.Status = firmware.Count == 1 ? OfferStatus(firmware[0]) : "Windows Update ofrece " + firmware.Count + " actualizaciones de firmware";
                row.LinkUrl = firmware.Any(o => o.Optional) ? DriverRules.OptionalUpdatesUri : DriverRules.WindowsUpdateUri;
                row.LinkLabel = "Abrir Windows Update";
                row.Note = BiosWarning;
                return row;
            }
            row.State = DriverState.CheckManually;
            row.Status = url != null ? "Compara la versión en la web de " + DriverRules.OemName(identity) : "Compara la versión en la web del fabricante del equipo o de la placa";
            row.LinkUrl = url;
            row.LinkLabel = url != null ? "Soporte de " + DriverRules.OemName(identity) : null;
            row.Note = "Ningún fabricante publica una consulta fiable de la última BIOS. " + BiosWarning;
            return row;
        }

        /// <summary>Si Windows Update ofrece algo más nuevo, avisa; si no, deja la fila para comprobar a mano.</summary>
        private static void ApplyOffersOrManual(DriverRow row, InstalledDriver installed, List<WindowsUpdateOffer> related, string url, string label, string note, List<InstalledDriver> parts = null)
        {
            var newer = related.Where(o => (parts ?? new List<InstalledDriver> { installed })
                .Any(d => DriverRules.SameHardware(d.HardwareId, o.HardwareId) && DriverRules.IsNewer(d, o))).ToList();
            if (newer.Count > 0)
            {
                row.State = DriverState.UpdateAvailable;
                row.Status = newer.Count == 1 ? OfferStatus(newer[0]) : "Windows Update ofrece " + newer.Count + " drivers más nuevos";
                row.LinkUrl = newer.Any(o => o.Optional) ? DriverRules.OptionalUpdatesUri : DriverRules.WindowsUpdateUri;
                row.LinkLabel = "Abrir Windows Update";
                row.Note = note;
                return;
            }
            row.State = DriverState.CheckManually;
            row.Status = related.Count > 0
                ? "Windows Update ofrece una versión igual o anterior: no hace falta"
                : "Sin novedades en Windows Update · el fabricante puede tener una versión posterior";
            row.LinkUrl = url;
            row.LinkLabel = url != null ? label : null;
            row.Note = note;
        }

        private static List<WindowsUpdateOffer> Related(IEnumerable<InstalledDriver> drivers, List<WindowsUpdateOffer> offers, HashSet<WindowsUpdateOffer> used)
        {
            var related = DriverRules.Matching(drivers, offers.Where(o => !used.Contains(o))).ToList();
            foreach (var offer in related) used.Add(offer);
            return related;
        }

        private static string OfferStatus(WindowsUpdateOffer offer)
        {
            string version = offer.Version ?? DriverRules.FormatDate(offer.Date);
            return "Windows Update ofrece " + (version ?? "una versión nueva") + (offer.Optional ? " (opcional)" : "");
        }

        private static string LinkLabel(string url, string vendor, SystemIdentity identity)
        {
            if (url == null) return null;
            if (url == DriverRules.IntelAssistantUrl) return "Asistente de Intel";
            if (url == DriverRules.AmdDriversUrl) return "Web de AMD";
            if (url == DriverRules.NvidiaDriversUrl) return "Web de NVIDIA";
            return "Soporte de " + (DriverRules.OemName(identity) ?? vendor ?? "fabricante");
        }

        private static string Installed(string version, DateTime? date, DateTime now, string extra = null)
        {
            var parts = new List<string>();
            if (!String.IsNullOrWhiteSpace(version)) parts.Add(version.Trim());
            if (date.HasValue) parts.Add(DriverRules.FormatDate(date) + " (" + DriverRules.Age(date.Value, now) + ")");
            if (!String.IsNullOrEmpty(extra)) parts.Add(extra);
            return parts.Count == 0 ? "Versión desconocida" : "Instalado: " + String.Join(" · ", parts);
        }

        private static bool Is(InstalledDriver d, string deviceClass)
        {
            return String.Equals(d.DeviceClass, deviceClass, StringComparison.OrdinalIgnoreCase);
        }

        private static bool StartsWithAny(string value, params string[] prefixes)
        {
            return value != null && prefixes.Any(p => value.StartsWith(p, StringComparison.OrdinalIgnoreCase));
        }

        private static bool IsMicrosoft(string provider)
        {
            return provider != null && provider.IndexOf("Microsoft", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static bool IsPlaceholder(string text)
        {
            string t = text.ToLowerInvariant();
            return t.Contains("to be filled") || t.Contains("system manufacturer") || t.Contains("system product") || t == "default string" || t == "o.e.m.";
        }
    }
}
