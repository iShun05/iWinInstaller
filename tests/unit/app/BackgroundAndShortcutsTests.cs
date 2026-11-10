using System;
using System.IO;
using System.Linq;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;
using IWinInstaller.App.Modules.Shortcuts;
using IWinInstaller.App.Shell;
using IWinInstaller.App.Shell.Palette;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    /// <summary>v5.2: segundo plano, monitor, atajos de Windows y resiliencia.</summary>
    [TestClass]
    public class BackgroundAndShortcutsTests
    {
        private string _dir;

        [TestInitialize]
        public void Setup()
        {
            _dir = Path.Combine(Path.GetTempPath(), "iwin-v52-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_dir);
        }

        [TestCleanup]
        public void Cleanup() { try { Directory.Delete(_dir, true); } catch (IOException) { } }

        [TestMethod]
        public void AtajosConIdUnicoYDestinoSeguro()
        {
            Assert.IsTrue(QuickLinks.All.Count >= 60, "catálogo de atajos completo");
            Assert.AreEqual(QuickLinks.All.Count, QuickLinks.All.Select(l => l.Id).Distinct().Count(), "ids únicos");
            foreach (var link in QuickLinks.All)
            {
                Assert.IsTrue(QuickLinks.IsSafeTarget(link.Target), link.Id + ": destino no permitido");
                Assert.IsFalse(String.IsNullOrWhiteSpace(link.Title) || String.IsNullOrWhiteSpace(link.Description) || String.IsNullOrWhiteSpace(link.Group), link.Id);
            }
            foreach (string id in QuickLinks.TrayIds) Assert.IsNotNull(QuickLinks.Find(id), id);
        }

        [TestMethod]
        public void SoloDestinosDeWindows()
        {
            Assert.IsTrue(QuickLinks.IsSafeTarget("ms-settings:display"));
            Assert.IsTrue(QuickLinks.IsSafeTarget("devmgmt.msc"));
            Assert.IsTrue(QuickLinks.IsSafeTarget("taskmgr.exe"));
            Assert.IsFalse(QuickLinks.IsSafeTarget("ms-settings:"));
            Assert.IsFalse(QuickLinks.IsSafeTarget("C:\\Temp\\algo.exe"), "sin rutas");
            Assert.IsFalse(QuickLinks.IsSafeTarget("https://example.com"));
            Assert.IsFalse(QuickLinks.IsSafeTarget("cmd.exe /c del"));
            Assert.IsFalse(QuickLinks.IsSafeTarget("script.ps1"));
            Assert.IsFalse(QuickLinks.IsSafeTarget(""));
            Assert.AreEqual("Atajo no válido.", QuickLinks.Open(null));
        }

        [TestMethod]
        public void BusquedaDeAtajosSinTildes()
        {
            var groups = QuickLinks.Groups("raton");
            Assert.IsTrue(groups.SelectMany(g => g.Links).Any(l => l.Id == "mouse"));
            Assert.AreEqual(0, QuickLinks.Groups("zzzz").Count);
            Assert.IsTrue(QuickLinks.Groups("").Count >= 8, "sin búsqueda se ven todos los grupos");
            var model = new QuickLinksViewModel { Search = "wifi" };
            Assert.IsFalse(model.IsEmpty);
            model.Search = "zzzz";
            Assert.IsTrue(model.IsEmpty);
        }

        [TestMethod]
        public void LaPaletaPriorizaAccionesDeLaApp()
        {
            var actions = ActionRegistry.BuiltIn();
            foreach (var link in QuickLinks.All) actions.Add(new PaletteAction(ShellViewModel.QuickPrefix + link.Id, link.Title, "Windows · " + link.Group, link.Description + " " + link.Keywords));
            Assert.AreEqual("nav.security", PaletteSearch.Find(actions, "defender")[0].Id);
            Assert.AreEqual("quick:bluetooth", PaletteSearch.Find(actions, "bluetooth")[0].Id);
            Assert.AreEqual("nav.shortcuts", PaletteSearch.Find(actions, "atajos")[0].Id);
        }

        [TestMethod]
        public void UsoDelProcesadorEntreDosLecturas()
        {
            Assert.AreEqual(25, LiveMonitor.CpuPercent(0, 0, 750, 1000));
            Assert.AreEqual(100, LiveMonitor.CpuPercent(100, 1000, 100, 2000));
            Assert.AreEqual(0, LiveMonitor.CpuPercent(0, 1000, 1000, 2000));
            Assert.AreEqual(0, LiveMonitor.CpuPercent(0, 1000, 0, 1000), "sin tiempo transcurrido no hay dato");
            Assert.AreEqual("16", LiveMonitor.FormatGigabytes(16.0 * 1024 * 1024 * 1024));
            Assert.AreEqual("6,9", LiveMonitor.FormatGigabytes(6.9 * 1024 * 1024 * 1024));
        }

        [TestMethod]
        public void AvisoSoloTrasUsoAltoSostenido()
        {
            var threshold = new SustainedThreshold(90, 75, 3);
            Assert.IsFalse(threshold.Push(95));
            Assert.IsFalse(threshold.Push(95));
            Assert.IsTrue(threshold.Push(95), "tercera lectura seguida");
            Assert.IsFalse(threshold.Push(99), "no repite el aviso");
            Assert.IsFalse(threshold.Push(80), "entre 75 y 90 sigue armado sin avisar");
            Assert.IsFalse(threshold.Push(95));
            Assert.IsFalse(threshold.Push(50), "al bajar del 75 % se rearma");
            Assert.IsFalse(threshold.Push(95));
            Assert.IsFalse(threshold.Push(95));
            Assert.IsTrue(threshold.Push(95));
            var interrupted = new SustainedThreshold(90, 75, 3);
            interrupted.Push(95); interrupted.Push(95); interrupted.Push(85);
            Assert.IsFalse(interrupted.Push(95), "una bajada reinicia la cuenta");
        }

        [TestMethod]
        public void SoloAvisaDeLoQuePasaARequerirAtencion()
        {
            var disk = new StatusCard("diskSpace", "Espacio en disco");
            var antivirus = new StatusCard("antivirus", "Protección antivirus");
            var cards = new[] { disk, antivirus };
            var tracker = new AttentionTracker();
            disk.Apply(StatusState.Attention, "Poco espacio", "", "");
            antivirus.Apply(StatusState.Ok, "Protegido", "", "");
            Assert.AreEqual(0, tracker.NewAlerts(cards).Count, "la primera comprobación es la referencia");
            Assert.AreEqual(0, tracker.NewAlerts(cards).Count, "sin cambios no hay aviso");
            antivirus.Apply(StatusState.Attention, "Protección desactivada", "", "");
            var fresh = tracker.NewAlerts(cards);
            Assert.AreEqual(1, fresh.Count);
            Assert.AreEqual("antivirus", fresh[0].Area);
            antivirus.Apply(StatusState.Ok, "Protegido", "", "");
            Assert.AreEqual(0, tracker.NewAlerts(cards).Count);
            antivirus.Apply(StatusState.Attention, "Protección desactivada", "", "");
            Assert.AreEqual(1, tracker.NewAlerts(cards).Count, "si se resuelve y vuelve, avisa otra vez");
        }

        [TestMethod]
        public void TextoDeLaBandejaYArranque()
        {
            Assert.AreEqual("iWinInstaller · CPU 5 % · RAM 40 %", TrayService.TooltipText("CPU 5 % · RAM 40 %"));
            Assert.AreEqual(63, TrayService.TooltipText(new string('x', 200)).Length, "límite de Windows");
            Assert.AreEqual("\"C:\\Program Files\\iWinInstaller\\iWinInstaller.App.exe\" --tray", Autostart.CommandFor("C:\\Program Files\\iWinInstaller\\iWinInstaller.App.exe"));
        }

        [TestMethod]
        public void PreferenciasDeSegundoPlano()
        {
            string path = Path.Combine(_dir, "interfaz.json");
            var preferences = Preferences.Load(path);
            Assert.IsFalse(preferences.Background, "desactivado al principio");
            Assert.IsTrue(preferences.Notifications);
            Assert.IsTrue(preferences.Animations);
            preferences.Background = true; preferences.Animations = false; preferences.Zoom = 1.2;
            preferences.Save();
            var loaded = Preferences.Load(path);
            Assert.IsTrue(loaded.Background);
            Assert.IsFalse(loaded.Animations);
            Assert.IsTrue(loaded.Notifications);
            Assert.AreEqual(1.2, loaded.Zoom, 1e-9);
            // Un archivo de una versión anterior (solo zoom) conserva los valores por defecto
            File.WriteAllText(path, "{\"zoom\":1.5}");
            var old = Preferences.Load(path);
            Assert.IsFalse(old.Background);
            Assert.IsTrue(old.Notifications);
        }

        [TestMethod]
        public void ElRegistroDeLaInterfazSeArchiva()
        {
            string log = Path.Combine(_dir, "interfaz.log");
            File.WriteAllText(log, new string('x', 100));
            Assert.IsFalse(App.RotateLog(log, 1000), "por debajo del límite no se toca");
            File.WriteAllText(log, new string('x', 2000));
            Assert.IsTrue(App.RotateLog(log, 1000));
            Assert.IsFalse(File.Exists(log));
            Assert.AreEqual(2000, new FileInfo(Path.Combine(_dir, "interfaz.anterior.log")).Length);
            Assert.IsFalse(App.RotateLog(Path.Combine(_dir, "no-existe.log"), 1000));
        }

        [TestMethod]
        public void MotivoLegibleCuandoElMotorNoArranca()
        {
            StringAssert.Contains(EngineClient.DescribeFailure(EngineResult.EnvironmentBlocked, false, null), "modo restringido");
            Assert.AreEqual("detalle", EngineClient.DescribeFailure(EngineResult.InternalError, false, "detalle"));
            StringAssert.Contains(EngineClient.DescribeFailure(1, false, null), "directiva de ejecución");
            Assert.AreEqual("El motor terminó con el código 10.", EngineClient.DescribeFailure(10, false, null));
        }
    }
}
