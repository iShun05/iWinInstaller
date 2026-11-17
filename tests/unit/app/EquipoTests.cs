using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using IWinInstaller.App.Core;
using IWinInstaller.App.Modules.Equipo;
using IWinInstaller.App.Modules.Games;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class EquipoTests
    {
        private static HardwareInfo Hw(FormFactor form, double ram, int threads, params string[] gpus)
        {
            var hw = new HardwareInfo { FormFactor = form, RamGb = ram, Threads = threads, Cores = Math.Max(1, threads / 2), CpuName = "CPU de prueba" };
            foreach (var g in gpus) hw.Gpus.Add(HardwareClassifier.Gpu(g));
            return hw;
        }

        // ---------- Clasificación ----------

        [TestMethod]
        public void FormFactor_UsaElChasisYLaBateriaComoRespaldo()
        {
            Assert.AreEqual(FormFactor.Laptop, HardwareClassifier.FormFactorFrom(new[] { 10 }, false));
            Assert.AreEqual(FormFactor.Laptop, HardwareClassifier.FormFactorFrom(new[] { 31 }, false));
            Assert.AreEqual(FormFactor.Desktop, HardwareClassifier.FormFactorFrom(new[] { 3 }, false));
            Assert.AreEqual(FormFactor.Desktop, HardwareClassifier.FormFactorFrom(new[] { 35 }, true), "un mini PC con SAI no es un portátil");
            Assert.AreEqual(FormFactor.Laptop, HardwareClassifier.FormFactorFrom(new[] { 1 }, true));
            Assert.AreEqual(FormFactor.Unknown, HardwareClassifier.FormFactorFrom(new[] { 2 }, false));
            Assert.AreEqual(FormFactor.Unknown, HardwareClassifier.FormFactorFrom(null, false));
        }

        [TestMethod]
        public void Gpu_DetectaMarcaYSiEsDedicada()
        {
            var cases = new[]
            {
                new { Name = "NVIDIA GeForce RTX 4060 Laptop GPU", Vendor = GpuVendor.Nvidia, Discrete = true },
                new { Name = "AMD Radeon RX 7800 XT", Vendor = GpuVendor.Amd, Discrete = true },
                new { Name = "AMD Radeon(TM) Graphics", Vendor = GpuVendor.Amd, Discrete = false },
                new { Name = "AMD Radeon 780M Graphics", Vendor = GpuVendor.Amd, Discrete = false },
                new { Name = "Intel(R) UHD Graphics 770", Vendor = GpuVendor.Intel, Discrete = false },
                new { Name = "Intel(R) Iris(R) Xe Graphics", Vendor = GpuVendor.Intel, Discrete = false },
                new { Name = "Intel(R) Arc(TM) A770 Graphics", Vendor = GpuVendor.Intel, Discrete = true },
                new { Name = "Intel(R) Arc(TM) Graphics", Vendor = GpuVendor.Intel, Discrete = false },
                new { Name = "Adaptador desconocido", Vendor = GpuVendor.Unknown, Discrete = false }
            };
            foreach (var c in cases)
            {
                var gpu = HardwareClassifier.Gpu(c.Name);
                Assert.AreEqual(c.Vendor, gpu.Vendor, c.Name);
                Assert.AreEqual(c.Discrete, gpu.Discrete, c.Name);
            }
        }

        [TestMethod]
        public void Clean_QuitaMarcasRegistradasYLaFrecuenciaDelNombre()
        {
            Assert.AreEqual("Intel Arc Graphics", HardwareClassifier.Clean("Intel(R) Arc(TM) Graphics"));
            Assert.AreEqual("Intel Core i7-9750H", HardwareClassifier.Clean("Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz"));
            Assert.AreEqual("AMD Ryzen 7 7840HS w/ Radeon 780M Graphics", HardwareClassifier.Clean("AMD Ryzen 7 7840HS  w/ Radeon 780M Graphics"));
            Assert.AreEqual("", HardwareClassifier.Clean(null));
        }

        [TestMethod]
        public void Gama_SeDecidePorMemoriaHilosYGraficaDedicada()
        {
            Assert.AreEqual(Tier.High, HardwareClassifier.TierOf(Hw(FormFactor.Desktop, 32, 24, "NVIDIA GeForce RTX 4070")));
            Assert.AreEqual(Tier.High, HardwareClassifier.TierOf(Hw(FormFactor.Laptop, 16, 12, "NVIDIA GeForce RTX 4060 Laptop GPU", "Intel(R) UHD Graphics")));
            Assert.AreEqual(Tier.Mid, HardwareClassifier.TierOf(Hw(FormFactor.Laptop, 16, 8, "NVIDIA GeForce GTX 1650")), "pocos hilos: no es gama alta");
            Assert.AreEqual(Tier.Mid, HardwareClassifier.TierOf(Hw(FormFactor.Laptop, 16, 16, "AMD Radeon(TM) Graphics")), "sin dedicada: no es gama alta");
            Assert.AreEqual(Tier.Basic, HardwareClassifier.TierOf(Hw(FormFactor.Laptop, 4, 4, "Intel(R) UHD Graphics")));
            Assert.AreEqual(Tier.Basic, HardwareClassifier.TierOf(Hw(FormFactor.Desktop, 4, 8, "NVIDIA GeForce RTX 3060")), "menos de 8 GB siempre es básica");
            Assert.AreEqual(Tier.Basic, HardwareClassifier.TierOf(Hw(FormFactor.Desktop, 16, 4, "Intel(R) UHD Graphics")));
            Assert.AreEqual(Tier.Mid, HardwareClassifier.TierOf(Hw(FormFactor.Desktop, 0, 0)), "sin datos no se castiga");
        }

        // ---------- Preset ----------

        [TestMethod]
        public void Preset_PortatilHibridoAsus_NoPoneAltoRendimientoYAnadeLoSuyo()
        {
            var hw = Hw(FormFactor.Laptop, 16, 16, "Intel(R) UHD Graphics", "NVIDIA GeForce RTX 4060 Laptop GPU");
            hw.Manufacturer = "ASUSTeK COMPUTER INC."; hw.RefreshHz = 60; hw.MaxRefreshHz = 144;
            var plan = PresetPlanner.Plan(hw);
            CollectionAssert.DoesNotContain(plan.Ids, "power");
            foreach (var id in new[] { "wifiperf", "ghelper", "nvidiaapp", "wsl", "git", "vscode", "mouseaccel", "gamemode", "nodvr", "gamedns" })
                CollectionAssert.Contains(plan.Ids, id);
            CollectionAssert.DoesNotContain(plan.Ids, "inteldsa", "la integrada no suma drivers si hay dedicada");
            Assert.IsTrue(plan.Notes.Any(n => n.ActionId == "nav.games"), "aviso de GPU híbrida");
            Assert.IsTrue(plan.Notes.Any(n => n.Text.Contains("144 Hz") && n.ActionId == "nav.system"), "aviso de Hz sin aprovechar");
        }

        [TestMethod]
        public void Preset_SobremesaConPocaRam_QuitaWslYAvisa()
        {
            var plan = PresetPlanner.Plan(Hw(FormFactor.Desktop, 8, 8, "NVIDIA GeForce RTX 3060"));
            CollectionAssert.Contains(plan.Ids, "power");
            CollectionAssert.DoesNotContain(plan.Ids, "wifiperf");
            CollectionAssert.DoesNotContain(plan.Ids, "wsl");
            Assert.IsTrue(plan.Notes.Any(n => n.Text.Contains("WSL")));
        }

        [TestMethod]
        public void Preset_SobremesaDeGamaAlta_NoTieneAvisosSobrantes()
        {
            var plan = PresetPlanner.Plan(Hw(FormFactor.Desktop, 32, 24, "AMD Radeon RX 7800 XT"));
            CollectionAssert.Contains(plan.Ids, "amdsoftware");
            CollectionAssert.Contains(plan.Ids, "wsl");
            Assert.AreEqual(Tier.High, plan.Tier);
            Assert.AreEqual(plan.Ids.Count, plan.Ids.Distinct().Count());
        }

        [TestMethod]
        public void Preset_ConPantallaYaAlMaximo_RecomiendaLimitarFps()
        {
            var hw = Hw(FormFactor.Desktop, 32, 24, "NVIDIA GeForce RTX 4070");
            hw.RefreshHz = 165; hw.MaxRefreshHz = 165;
            Assert.IsTrue(PresetPlanner.Plan(hw).Notes.Any(n => n.Text.Contains("162")));
        }

        [TestMethod]
        public void Preset_SinDatosDelEquipo_SigueDandoLaBase()
        {
            var plan = PresetPlanner.Plan(new HardwareInfo());
            foreach (var id in PresetPlanner.DevBase.Concat(PresetPlanner.GamingBase)) CollectionAssert.Contains(plan.Ids, id);
        }

        private static string RepoFile(string name)
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir != null && !File.Exists(Path.Combine(dir.FullName, name))) dir = dir.Parent;
            Assert.IsNotNull(dir, "No se encontró " + name);
            return Path.Combine(dir.FullName, name);
        }

        [TestMethod]
        public void Preset_TodosLosIdsExistenEnElCatalogo()
        {
            var catalog = (List<object>)MiniJson.Parse(File.ReadAllText(RepoFile("apps.json")));
            var ids = new HashSet<string>(catalog.OfType<Dictionary<string, object>>().Select(a => (string)a["id"]));
            var all = PresetPlanner.DevBase.Concat(PresetPlanner.GamingBase).Concat(PresetPlanner.Conditional).ToList();
            var missing = all.Where(id => !ids.Contains(id)).ToList();
            Assert.AreEqual(0, missing.Count, "Ids que no están en apps.json: " + String.Join(", ", missing));
        }

        [TestMethod]
        public void Preset_ElPerfilDeProfilesJsonCubreLaBase()
        {
            var profiles = (Dictionary<string, object>)MiniJson.Parse(File.ReadAllText(RepoFile("profiles.json")));
            Assert.IsTrue(profiles.ContainsKey(PresetPlanner.ProfileName), "falta el perfil " + PresetPlanner.ProfileName);
            var entries = ((List<object>)profiles[PresetPlanner.ProfileName]).Cast<string>().ToList();
            foreach (var id in PresetPlanner.DevBase.Concat(PresetPlanner.GamingBase).Concat(new[] { "power", "wsl" }))
                CollectionAssert.Contains(entries, id);
            CollectionAssert.Contains(entries, "@hardware");
        }

        // ---------- Salud ----------

        [TestMethod]
        public void Defender_DistingueTiempoRealFirmasYOtroAntivirus()
        {
            Assert.AreEqual(StatusState.Unknown, HealthRules.Defender(null).State);
            Assert.AreEqual(StatusState.Ok, HealthRules.Defender(new DefenderInfo { ServiceEnabled = true, RealTimeProtection = true, SignatureAgeDays = 1 }).State);
            Assert.AreEqual(StatusState.Attention, HealthRules.Defender(new DefenderInfo { ServiceEnabled = true, RealTimeProtection = false }).State);
            var old = HealthRules.Defender(new DefenderInfo { ServiceEnabled = true, RealTimeProtection = true, SignatureAgeDays = 9 });
            Assert.AreEqual(StatusState.Attention, old.State);
            StringAssert.Contains(old.Summary, "9 días");
            var other = HealthRules.Defender(new DefenderInfo { ServiceEnabled = false, OtherAntivirus = "ESET" });
            Assert.AreEqual(StatusState.Ok, other.State);
            StringAssert.Contains(other.Summary, "ESET");
            Assert.AreEqual(StatusState.Attention, HealthRules.Defender(new DefenderInfo { ServiceEnabled = false }).State);
        }

        [TestMethod]
        public void WindowsUpdate_AlDiaHastaSieteDias()
        {
            var now = new DateTime(2026, 11, 17, 12, 0, 0, DateTimeKind.Utc);
            Assert.AreEqual(StatusState.Ok, HealthRules.WindowsUpdate(now.AddDays(-3), now, true).State);
            Assert.AreEqual(StatusState.Ok, HealthRules.WindowsUpdate(now.AddDays(-7), now, true).State);
            var late = HealthRules.WindowsUpdate(now.AddDays(-20), now, true);
            Assert.AreEqual(StatusState.Attention, late.State);
            StringAssert.Contains(late.Summary, "20 días");
            Assert.AreEqual(StatusState.Attention, HealthRules.WindowsUpdate(null, now, true).State);
            Assert.AreEqual(StatusState.Unknown, HealthRules.WindowsUpdate(null, now, false).State, "un fallo de lectura nunca se presenta como correcto");
        }

        [TestMethod]
        public void Inicio_AvisaConMuchasAppsYIgnoraLasDesactivadas()
        {
            Func<int, bool, List<StartupEntry>> make = (n, enabled) => Enumerable.Range(1, n).Select(i => new StartupEntry { Name = "App" + i, Enabled = enabled }).ToList();
            Assert.AreEqual(StatusState.Ok, HealthRules.Startup(make(5, true)).State);
            Assert.AreEqual(StatusState.Ok, HealthRules.Startup(make(HealthRules.StartupAttention, true)).State);
            Assert.AreEqual(StatusState.Attention, HealthRules.Startup(make(HealthRules.StartupAttention + 1, true)).State);
            Assert.AreEqual(StatusState.Ok, HealthRules.Startup(make(30, false)).State, "las desactivadas no cuentan");
            Assert.AreEqual(StatusState.Unknown, HealthRules.Startup(null).State);
            StringAssert.Contains(HealthRules.Startup(make(1, true)).Summary, "1 app arranca");
        }

        [TestMethod]
        public void Temperatura_SinSensoresNoAplicaYLaAltaAvisa()
        {
            Assert.AreEqual(StatusState.NotApplicable, HealthRules.Temperature(new List<TemperatureReading>()).State);
            Assert.AreEqual(StatusState.NotApplicable, HealthRules.Temperature(null).State);
            Assert.AreEqual(StatusState.NotApplicable, HealthRules.Temperature(new List<TemperatureReading> { new TemperatureReading { Name = "Zona 1", Celsius = 0 } }).State, "0 °C es un sensor roto");
            var ok = HealthRules.Temperature(new List<TemperatureReading> { new TemperatureReading { Name = "Zona 1", Celsius = 47.6 }, new TemperatureReading { Name = "Zona 2", Celsius = 40 } });
            Assert.AreEqual(StatusState.Ok, ok.State);
            StringAssert.Contains(ok.Summary, "48");
            var hot = HealthRules.Temperature(new List<TemperatureReading> { new TemperatureReading { Name = "Zona 1", Celsius = 91 } });
            Assert.AreEqual(StatusState.Attention, hot.State);
        }

        [TestMethod]
        public void Temperatura_ConvierteKelvinYDecimasDeKelvin()
        {
            Assert.AreEqual(25.0, HealthRules.CelsiusFromTenthsKelvin(2981.5), 0.01);
            Assert.AreEqual(0, HealthRules.CelsiusFromTenthsKelvin(0));
            Assert.AreEqual(0, HealthRules.CelsiusFromTenthsKelvin(99999), "valor imposible");
            Assert.AreEqual(35.0, HealthRules.CelsiusFromKelvin(308.15), 0.01);
            Assert.AreEqual(0, HealthRules.CelsiusFromKelvin(0));
        }

        [TestMethod]
        public void Arranque_StartupApprovedYNombres()
        {
            Assert.IsTrue(StartupRules.IsEnabled(null));
            Assert.IsTrue(StartupRules.IsEnabled(new byte[] { 0x02, 0, 0, 0 }));
            Assert.IsTrue(StartupRules.IsEnabled(new byte[] { 0x06, 0, 0, 0 }));
            Assert.IsFalse(StartupRules.IsEnabled(new byte[] { 0x03, 0, 0, 0 }));
            Assert.IsFalse(StartupRules.IsEnabled(new byte[] { 0x07, 0, 0, 0 }));
            Assert.AreEqual("Discord", StartupRules.FriendlyName("Discord", "\"C:\\Users\\x\\Update.exe\" --processStart Discord.exe"));
            Assert.AreEqual("steam", StartupRules.FriendlyName("", "\"C:\\Program Files (x86)\\Steam\\steam.exe\" -silent"));
            Assert.AreEqual("OneDrive", StartupRules.FriendlyName("", "C:\\Users\\x\\OneDrive.exe /background"));
        }

        [TestMethod]
        public void Arranque_QuitaRepetidosYOrdena()
        {
            var list = StartupRules.Distinct(new[]
            {
                new StartupEntry { Name = "Steam", Enabled = true },
                new StartupEntry { Name = "steam", Enabled = false },
                new StartupEntry { Name = "Discord", Enabled = true },
                new StartupEntry { Name = " ", Enabled = true }
            });
            CollectionAssert.AreEqual(new[] { "Discord", "Steam" }, list.Select(e => e.Name).ToArray());
        }
    }
}
