using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace IWinInstaller.App.Modules.Equipo
{
    public enum FormFactor { Unknown, Laptop, Desktop }
    public enum GpuVendor { Unknown, Nvidia, Amd, Intel }
    public enum Tier { Basic, Mid, High }

    public sealed class GpuInfo
    {
        public string Name { get; set; }
        public GpuVendor Vendor { get; set; }
        public bool Discrete { get; set; }
    }

    /// <summary>Lo que se sabe del equipo. Cualquier dato que Windows no dé queda en 0 o vacío, nunca inventado.</summary>
    public sealed class HardwareInfo
    {
        public FormFactor FormFactor { get; set; }
        public string Manufacturer { get; set; }
        public string Model { get; set; }
        public string CpuName { get; set; }
        public int Cores { get; set; }
        public int Threads { get; set; }
        public double RamGb { get; set; }
        public List<GpuInfo> Gpus { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int RefreshHz { get; set; }
        public int MaxRefreshHz { get; set; }

        public HardwareInfo() { Gpus = new List<GpuInfo>(); Manufacturer = ""; Model = ""; CpuName = ""; }

        public bool HasDiscreteGpu { get { return Gpus.Any(g => g.Discrete); } }
        /// <summary>Portátil con gráfica integrada y dedicada (Windows reparte cada juego con la preferencia de GPU).</summary>
        public bool IsHybridGraphics { get { return Gpus.Any(g => g.Discrete) && Gpus.Any(g => !g.Discrete); } }
    }

    /// <summary>Clasificación pura del hardware: sin acceso al sistema.</summary>
    public static class HardwareClassifier
    {
        private static readonly int[] LaptopChassis = { 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 };
        private static readonly int[] DesktopChassis = { 3, 4, 5, 6, 7, 13, 15, 16, 23, 24, 35, 36 };

        /// <summary>Tipo de equipo a partir del chasis SMBIOS; sin dato útil, la batería decide.</summary>
        public static FormFactor FormFactorFrom(IEnumerable<int> chassisTypes, bool hasBattery)
        {
            var types = chassisTypes == null ? new int[0] : chassisTypes.ToArray();
            if (types.Any(t => LaptopChassis.Contains(t))) return FormFactor.Laptop;
            if (types.Any(t => DesktopChassis.Contains(t))) return FormFactor.Desktop;
            return hasBattery ? FormFactor.Laptop : FormFactor.Unknown;
        }

        public static GpuVendor VendorOf(string name)
        {
            string n = (name ?? "").ToLowerInvariant();
            if (n.Contains("nvidia") || n.Contains("geforce") || n.Contains("quadro")) return GpuVendor.Nvidia;
            if (n.Contains("amd") || n.Contains("radeon") || n.Contains("ati ")) return GpuVendor.Amd;
            if (n.Contains("intel") || n.Contains("iris") || n.Contains("uhd graphics")) return GpuVendor.Intel;
            return GpuVendor.Unknown;
        }

        /// <summary>
        /// Dedicada o integrada por el nombre del adaptador (AdapterRAM no sirve: se queda en 4 GB). NVIDIA siempre es dedicada;
        /// AMD solo con «RX», «Pro» o «VII»; Intel solo la serie Arc con modelo (A770, B580…).
        /// </summary>
        public static bool IsDiscrete(string name, GpuVendor vendor)
        {
            string n = name ?? "";
            switch (vendor)
            {
                case GpuVendor.Nvidia: return true;
                case GpuVendor.Amd: return Regex.IsMatch(n, @"\bRX\b|Radeon\s+Pro|Radeon\s+VII\b", RegexOptions.IgnoreCase);
                case GpuVendor.Intel: return Regex.IsMatch(n, @"\bArc\b.*\b[AB]\d{3}\b", RegexOptions.IgnoreCase);
                default: return false;
            }
        }

        public static GpuInfo Gpu(string name)
        {
            string clean = Clean(name);
            var vendor = VendorOf(clean);
            return new GpuInfo { Name = clean, Vendor = vendor, Discrete = IsDiscrete(clean, vendor) };
        }

        /// <summary>Quita «(R)», «(TM)» y los espacios dobles de los nombres que da Windows.</summary>
        public static string Clean(string name)
        {
            string n = (name ?? "").Replace("(R)", "").Replace("(TM)", "").Replace("(tm)", "").Replace("®", "").Replace("™", "");
            n = Regex.Replace(n, @"\s+", " ").Trim();
            n = Regex.Replace(n, @"\s+CPU\s+@\s+[\d.]+\s?GHz$", "", RegexOptions.IgnoreCase);
            return n;
        }

        /// <summary>Gama para el preset: Alta (dedicada, 16 GB y 12 hilos), Básica (menos de 8 GB, o sin dedicada y 4 hilos o menos) o Media.</summary>
        public static Tier TierOf(HardwareInfo hw)
        {
            if (hw.RamGb > 0 && hw.RamGb < 7.5) return Tier.Basic;
            if (!hw.HasDiscreteGpu && hw.Threads > 0 && hw.Threads <= 4) return Tier.Basic;
            if (hw.HasDiscreteGpu && hw.RamGb >= 15.5 && hw.Threads >= 12) return Tier.High;
            return Tier.Mid;
        }

        public static string TierLabel(Tier tier)
        {
            switch (tier)
            {
                case Tier.High: return "Alta";
                case Tier.Basic: return "Básica";
                default: return "Media";
            }
        }

        public static string FormFactorLabel(FormFactor form)
        {
            switch (form)
            {
                case FormFactor.Laptop: return "Portátil";
                case FormFactor.Desktop: return "Sobremesa";
                default: return "Equipo";
            }
        }
    }

    public sealed class PresetNote
    {
        public PresetNote(string text, string actionId = "") { Text = text; ActionId = actionId ?? ""; }
        public string Text { get; private set; }
        public string ActionId { get; private set; }
    }

    /// <summary>Qué se propone marcar en Instalar y por qué.</summary>
    public sealed class PresetPlan
    {
        public string ProfileName { get; set; }
        public Tier Tier { get; set; }
        public List<string> Ids { get; set; }
        public List<PresetNote> Notes { get; set; }
        public PresetPlan() { Ids = new List<string>(); Notes = new List<PresetNote>(); }
    }

    /// <summary>
    /// Preset «Dev + Gaming competitivo»: la base de desarrollo y de baja latencia, ajustada al equipo detectado.
    /// Todos los ids existen en apps.json y un perfil con el mismo nombre en profiles.json permite elegirlo a mano.
    /// </summary>
    public static class PresetPlanner
    {
        public const string ProfileName = "Dev + Gaming competitivo";

        /// <summary>Desarrollo: punto de restauración, modo desarrollador, rutas largas, extensiones visibles, Git, editor y terminal.</summary>
        public static readonly string[] DevBase = { "restorepoint", "devmode", "longpaths", "showext", "endtask", "git", "vscode", "terminal", "pwsh" };

        /// <summary>Juego competitivo: sin aceleración, Modo Juego, sin grabación en segundo plano, DNS rápido, librerías y medición.</summary>
        public static readonly string[] GamingBase = { "mouseaccel", "gamemode", "nodvr", "gamedns", "directx", "vcredist", "latencymon", "speedtest" };

        /// <summary>Todo lo que el plan puede proponer según el equipo (para comprobar el catálogo y el perfil).</summary>
        public static readonly string[] Conditional = { "power", "wifiperf", "wsl", "nvidiaapp", "amdsoftware", "inteldsa", "ghelper" };

        public static PresetPlan Plan(HardwareInfo hw)
        {
            var ids = new List<string>(DevBase);
            ids.AddRange(GamingBase);
            var plan = new PresetPlan { ProfileName = ProfileName, Tier = HardwareClassifier.TierOf(hw) };
            bool laptop = hw.FormFactor == FormFactor.Laptop;

            if (laptop)
            {
                ids.Add("wifiperf");
                plan.Notes.Add(new PresetNote("Portátil: no se pone el plan de energía de alto rendimiento (gasta batería). Enchufado, usa «Mejor rendimiento» en Sistema › Energía.", "nav.system"));
            }
            else ids.Add("power");

            if (hw.RamGb > 0 && hw.RamGb < 12)
                plan.Notes.Add(new PresetNote("Con " + Gb(hw.RamGb) + " de RAM no se propone WSL: compite con el juego por memoria. Con 16 GB o más cabe sin problema."));
            else ids.Add("wsl");

            foreach (var gpu in hw.Gpus)
            {
                string id = gpu.Vendor == GpuVendor.Nvidia ? "nvidiaapp" : gpu.Vendor == GpuVendor.Amd ? "amdsoftware" : gpu.Vendor == GpuVendor.Intel ? "inteldsa" : null;
                if (id != null && (gpu.Discrete || !hw.HasDiscreteGpu) && !ids.Contains(id)) ids.Add(id);
            }

            if (laptop && hw.Manufacturer.IndexOf("ASUS", StringComparison.OrdinalIgnoreCase) >= 0) ids.Add("ghelper");
            if (hw.IsHybridGraphics)
                plan.Notes.Add(new PresetNote("Gráfica integrada y dedicada: en Juegos y en Latencia puedes mandar cada juego a la dedicada.", "nav.games"));

            if (hw.RefreshHz > 0 && hw.MaxRefreshHz > hw.RefreshHz)
                plan.Notes.Add(new PresetNote("La pantalla va a " + hw.RefreshHz + " Hz y admite " + hw.MaxRefreshHz + " Hz: súbela en Sistema.", "nav.system"));
            else if (hw.RefreshHz >= 100)
                plan.Notes.Add(new PresetNote("Pantalla a " + hw.RefreshHz + " Hz: en los juegos limita los FPS unos 3 por debajo (" + (hw.RefreshHz - 3) + ") para menos input lag."));

            if (plan.Tier == Tier.Basic)
                plan.Notes.Add(new PresetNote("Gama básica: en los juegos prioriza calidad baja y resolución nativa; los ajustes de baja latencia siguen siendo útiles."));
            else if (plan.Tier == Tier.High)
                plan.Notes.Add(new PresetNote("Gama alta: sobra potencia para desarrollar y jugar a la vez; el límite suele ser la red, mídela en Latencia.", "nav.gaming"));

            plan.Ids = ids.Distinct().ToList();
            return plan;
        }

        private static string Gb(double gb) { return Math.Round(gb) + " GB"; }
    }
}
