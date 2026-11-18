using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using IWinInstaller.App.Modules.Games;
using IWinInstaller.App.Modules.Rendimiento;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    internal sealed class FakePerfHost : IPerfHost
    {
        public const string Balanced = "381b4222-f694-41f0-9685-ff5bb260df2e";
        public string Power = Balanced;
        public readonly HashSet<string> Schemes = new HashSet<string> { Balanced, PerfCatalog.HighPerformance };
        public readonly List<ProcInfo> Procs = new List<ProcInfo>();
        public readonly Dictionary<int, string> Paths = new Dictionary<int, string>();
        public readonly Dictionary<int, ProcessPriorityClass> Priority = new Dictionary<int, ProcessPriorityClass>();
        public readonly List<string> Launched = new List<string>();

        public string ActivePowerScheme() { return Power; }
        public bool PowerSchemeExists(string guid) { return Schemes.Contains(guid); }
        public bool SetPowerScheme(string guid) { if (!Schemes.Contains(guid)) return false; Power = guid; return true; }
        public List<ProcInfo> Processes() { return Procs.ToList(); }
        public string PathOf(int pid) { string p; return Paths.TryGetValue(pid, out p) ? p : null; }
        public bool CloseGracefully(int pid)
        {
            var proc = Procs.FirstOrDefault(p => p.Id == pid);
            if (proc == null || !proc.HasWindow) return false;
            Procs.Remove(proc);
            return true;
        }
        public bool IsRunning(int pid) { return Procs.Any(p => p.Id == pid); }
        public ProcessPriorityClass? PriorityOf(int pid) { ProcessPriorityClass c; return Priority.TryGetValue(pid, out c) ? c : (ProcessPriorityClass?)null; }
        public bool SetPriority(int pid, ProcessPriorityClass priority) { if (!Procs.Any(p => p.Id == pid)) return false; Priority[pid] = priority; return true; }
        public bool Launch(string path) { Launched.Add(path); return true; }

        public ProcInfo Add(int id, string name, bool window = true, long mb = 100, string path = null)
        {
            var info = new ProcInfo { Id = id, Name = name, HasWindow = window, WorkingSetMb = mb };
            Procs.Add(info);
            if (path != null) Paths[id] = path;
            Priority[id] = ProcessPriorityClass.Normal;
            return info;
        }
    }

    [TestClass]
    public class PerformanceTests
    {
        private string _dir;

        [TestInitialize] public void Init() { _dir = Path.Combine(Path.GetTempPath(), "iwin-perf-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(_dir); }
        [TestCleanup] public void Clean() { try { Directory.Delete(_dir, true); } catch (IOException) { } }

        private PerfStore Store() { return new PerfStore(Path.Combine(_dir, "Rendimiento")); }

        // ---------- Acciones ----------

        [TestMethod]
        public void AplicarGuardaElOriginalYDeshacerLoDevuelve()
        {
            var env = new FakeGameEnvironment(_dir); var host = new FakePerfHost();
            var service = new PerfService(env, host, Store());
            var action = PerfCatalog.Find("capture");
            env.SetValue(@"HKCU\System\GameConfigStore", "GameDVR_Enabled", 1, RegKind.DWord);
            Assert.IsFalse(service.Status(action).Applied);

            Assert.IsTrue(service.Apply(action).Ok);
            Assert.AreEqual(0, env.GetValue(@"HKCU\System\GameConfigStore", "GameDVR_Enabled"));
            Assert.AreEqual(0, env.GetValue(@"HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR", "AppCaptureEnabled"));
            Assert.IsTrue(service.Status(action).Applied);
            Assert.IsTrue(service.Status(action).CanUndo);

            Assert.IsTrue(service.Undo(action).Ok);
            Assert.AreEqual(1, env.GetValue(@"HKCU\System\GameConfigStore", "GameDVR_Enabled"), "valor que existía");
            Assert.IsNull(env.GetValue(@"HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR", "AppCaptureEnabled"), "valor que no existía se borra");
            Assert.IsFalse(service.Status(action).CanUndo);
        }

        [TestMethod]
        public void LaCopiaOriginalSobreviveAUnSegundoAplicar()
        {
            var env = new FakeGameEnvironment(_dir); var service = new PerfService(env, new FakePerfHost(), Store());
            var action = PerfCatalog.Find("transparency");
            env.SetValue(@"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "EnableTransparency", 1, RegKind.DWord);
            service.Apply(action);
            var again = service.Apply(action);
            Assert.IsTrue(again.Ok);
            service.Undo(action);
            Assert.AreEqual(1, env.GetValue(@"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "EnableTransparency"));
        }

        [TestMethod]
        public void DeshacerSinCopiaNoInventaValores()
        {
            var env = new FakeGameEnvironment(_dir); var service = new PerfService(env, new FakePerfHost(), Store());
            var result = service.Undo(PerfCatalog.Find("gamemode"));
            Assert.IsFalse(result.Ok);
            Assert.IsNull(env.GetValue(@"HKCU\Software\Microsoft\GameBar", "AutoGameModeEnabled"));
        }

        [TestMethod]
        public void ValorAusenteSeTrataComoElPredeterminadoDeWindows()
        {
            var env = new FakeGameEnvironment(_dir); var service = new PerfService(env, new FakePerfHost(), Store());
            Assert.IsTrue(service.Status(PerfCatalog.Find("gamemode")).Applied, "Windows 11 trae el Modo Juego activado");
            Assert.IsFalse(service.Status(PerfCatalog.Find("capture")).Applied);
        }

        [TestMethod]
        public void PlanDeEnergiaSeGuardaYSeRestaura()
        {
            var env = new FakeGameEnvironment(_dir); var host = new FakePerfHost();
            var service = new PerfService(env, host, Store());
            var action = PerfCatalog.Find("power");
            Assert.IsTrue(service.Apply(action).Ok);
            Assert.AreEqual(PerfCatalog.HighPerformance, host.Power);
            Assert.IsTrue(service.Status(action).CanUndo);
            Assert.IsTrue(service.Undo(action).Ok);
            Assert.AreEqual(FakePerfHost.Balanced, host.Power);
        }

        [TestMethod]
        public void SinPlanAltoRendimientoNoCambiaNada()
        {
            var host = new FakePerfHost(); host.Schemes.Remove(PerfCatalog.HighPerformance);
            var service = new PerfService(new FakeGameEnvironment(_dir), host, Store());
            var result = service.Apply(PerfCatalog.Find("power"));
            Assert.IsFalse(result.Ok);
            Assert.AreEqual(FakePerfHost.Balanced, host.Power);
            Assert.IsFalse(service.Status(PerfCatalog.Find("power")).Available);
        }

        [TestMethod]
        public void ProgramasPesadosSinProcesosProtegidosNiRepetidos()
        {
            var host = new FakePerfHost();
            host.Add(1, "chrome", true, 900); host.Add(2, "chrome", false, 400); host.Add(3, "explorer", true, 500);
            host.Add(4, "iWinInstaller.App", true, 300); host.Add(5, "notepad", true, 30); host.Add(6, "svchost", false, 800); host.Add(7, "code", true, 600);
            var list = HeavyApps.Find(host.Processes());
            CollectionAssert.AreEqual(new[] { "chrome", "code" }, list.Select(a => a.Name).ToArray());
            Assert.AreEqual(1300, list[0].Mb);
            Assert.AreEqual(2, list[0].Instances);
            CollectionAssert.AreEqual(new[] { 1 }, list[0].WindowPids);
        }

        [TestMethod]
        public void NombreDeProcesoPersonalizado()
        {
            Assert.AreEqual("cs2", ProcessMatcher.CleanCustomName(@" C:\Juegos\cs2.exe "));
            Assert.AreEqual("valorant-win64-shipping", ProcessMatcher.CleanCustomName("valorant-win64-shipping"));
            Assert.IsNull(ProcessMatcher.CleanCustomName("a"));
            Assert.IsNull(ProcessMatcher.CleanCustomName("mal;nombre"));
            Assert.IsTrue(ProcessMatcher.Matches("FortniteClient-Win64-Shipping", "FortniteClient-Win64-Shipping*"));
            Assert.IsFalse(ProcessMatcher.Matches("Fortnite", "StarRail"));
        }

        // ---------- Perfil de juego ----------

        private static ProfileSettings Enabled()
        {
            var s = new ProfileSettings { Enabled = true };
            return s;
        }

        [TestMethod]
        public void ElPerfilSeActivaAlLanzarElJuegoYSeRestauraAlSalir()
        {
            var host = new FakePerfHost(); var store = Store();
            host.Add(10, "StarRail", true, 4000); host.Add(11, "chrome", true, 800, @"C:\chrome.exe"); host.Add(12, "GameBar", true, 50, @"C:\gb.exe");
            var engine = new GameProfileEngine(host, store);
            var log = new List<string>(); engine.Log += log.Add;

            engine.Tick(Enabled());
            Assert.IsNotNull(engine.Active);
            Assert.AreEqual(ProcessPriorityClass.High, host.Priority[10]);
            Assert.AreEqual(PerfCatalog.HighPerformance, host.Power);
            Assert.IsFalse(host.Procs.Any(p => p.Name == "chrome"), "el navegador se cerró con cortesía");
            Assert.IsFalse(host.Procs.Any(p => p.Name == "GameBar"));
            Assert.IsNotNull(store.LoadSession(), "la sesión queda guardada por si la app se cierra");

            engine.Tick(Enabled());
            Assert.AreEqual(1, log.Count, "no se reactiva mientras el juego sigue");

            host.Procs.RemoveAll(p => p.Id == 10);
            engine.Tick(Enabled());
            Assert.IsNull(engine.Active);
            Assert.IsNull(store.LoadSession());
            Assert.AreEqual(FakePerfHost.Balanced, host.Power);
            CollectionAssert.AreEquivalent(new[] { @"C:\chrome.exe", @"C:\gb.exe" }, host.Launched);
        }

        [TestMethod]
        public void SinInterruptorNoSeVigilaNada()
        {
            var host = new FakePerfHost(); host.Add(10, "StarRail", true, 4000);
            var engine = new GameProfileEngine(host, Store());
            engine.Tick(new ProfileSettings { Enabled = false });
            Assert.IsNull(engine.Active);
            Assert.AreEqual(FakePerfHost.Balanced, host.Power);
            Assert.AreEqual(ProcessPriorityClass.Normal, host.Priority[10]);
        }

        [TestMethod]
        public void LasOpcionesDesmarcadasNoSeAplican()
        {
            var host = new FakePerfHost(); host.Add(10, "StarRail", true, 4000); host.Add(11, "chrome", true, 800, @"C:\chrome.exe");
            var settings = Enabled();
            settings.Options["starrail"] = new ProfileOptions { Priority = false, PowerPlan = false, CloseBrowsers = false, CloseOverlays = false };
            var engine = new GameProfileEngine(host, Store());
            engine.Tick(settings);
            Assert.IsNotNull(engine.Active, "sigue vigilando temperaturas");
            Assert.IsTrue(host.Procs.Any(p => p.Name == "chrome"));
            Assert.AreEqual(ProcessPriorityClass.Normal, host.Priority[10]);
            Assert.AreEqual(FakePerfHost.Balanced, host.Power);
        }

        [TestMethod]
        public void SiElPlanDeEnergiaCambioDuranteLaPartidaNoSePisa()
        {
            var host = new FakePerfHost(); host.Add(10, "StarRail", true, 4000);
            var engine = new GameProfileEngine(host, Store());
            engine.Tick(Enabled());
            host.Schemes.Add("aaaaaaaa-0000-0000-0000-000000000000"); host.Power = "aaaaaaaa-0000-0000-0000-000000000000";
            host.Procs.Clear();
            engine.Tick(Enabled());
            Assert.AreEqual("aaaaaaaa-0000-0000-0000-000000000000", host.Power, "el usuario eligió otro plan: se respeta");
        }

        [TestMethod]
        public void RecuperaUnaSesionQueQuedoAMedias()
        {
            var host = new FakePerfHost(); var store = Store();
            host.Add(10, "StarRail", true, 4000); host.Add(11, "msedge", true, 500, @"C:\edge.exe");
            new GameProfileEngine(host, store).Tick(Enabled());
            host.Procs.RemoveAll(p => p.Id == 10);   // el juego terminó y la app se cerró antes de restaurar
            var next = new GameProfileEngine(host, store);
            next.RecoverStale();
            Assert.IsNull(store.LoadSession());
            Assert.AreEqual(FakePerfHost.Balanced, host.Power);
            CollectionAssert.Contains(host.Launched, @"C:\edge.exe");
        }

        [TestMethod]
        public void ElAjustesSeGuardanYSeLeenDeNuevo()
        {
            var store = Store();
            var settings = new ProfileSettings { Enabled = true };
            settings.Options["zzz"] = new ProfileOptions { CloseBrowsers = false };
            settings.Custom.Add(new CustomGame { Process = "cs2", Title = "CS2" });
            store.SaveSettings(settings);
            var loaded = Store().LoadSettings();
            Assert.IsTrue(loaded.Enabled);
            Assert.IsFalse(loaded.For("zzz").CloseBrowsers);
            Assert.IsTrue(loaded.For("otro").CloseBrowsers, "por defecto todo activado");
            Assert.AreEqual("cs2", loaded.Custom.Single().Process);
        }

        // ---------- Mediciones ----------

        [TestMethod]
        public void PercentilesInterpolados()
        {
            var v = new List<double> { 1, 2, 3, 4, 5 };
            Assert.AreEqual(3.0, PerfStats.Percentile(v, 50), 1e-9);
            Assert.AreEqual(4.96, PerfStats.Percentile(v, 99), 1e-9);
            Assert.AreEqual(1.0, PerfStats.Percentile(v, 0), 1e-9);
        }

        [TestMethod]
        public void ComparacionDistingueMejorPeorYRuido()
        {
            var before = new PerfSnapshot { SchedP99 = 2.0, PingAvg = 20, PingJitter = 2, Fps = 100 };
            var after = new PerfSnapshot { SchedP99 = 1.0, PingAvg = 20.5, PingJitter = 5, Fps = 112 };
            var lines = PerfCompare.Compare(before, after).ToDictionary(l => l.Metric, l => l.Verdict);
            Assert.AreEqual("better", lines["Sobrecarga de Sleep(1), p99 (tirones)"]);
            Assert.AreEqual("same", lines["Ping a Internet, media"]);
            Assert.AreEqual("worse", lines["Jitter del ping"]);
            Assert.AreEqual("better", lines["FPS medios"]);
            Assert.IsFalse(lines.ContainsKey("Frametime p99"), "sin datos no se compara");
        }

        [TestMethod]
        public void FrametimesDeUnCsvDePresentMon()
        {
            var csv = "Application,ProcessID,MsBetweenPresents,Dropped\r\n" + string.Join("\r\n", Enumerable.Range(0, 200).Select(i => "game.exe,1," + (i == 100 ? "50" : "10") + ",0")) + "\r\n";
            var values = FrameStats.ParseCsv(csv);
            Assert.AreEqual(200, values.Count);
            var snapshot = new PerfSnapshot();
            FrameStats.Fill(snapshot, values);
            Assert.AreEqual(1000.0 / ((199 * 10 + 50) / 200.0), snapshot.Fps.Value, 1e-9);
            Assert.AreEqual(1000.0 / 30.0, snapshot.Low1Fps.Value, 1e-9, "el 1 % de 200 fotogramas son 2: 50 y 10 ms, de media 30 ms");
        }

        [TestMethod]
        public void CsvSinCabeceraOSinDatosSuficientes()
        {
            Assert.AreEqual(0, FrameStats.ParseCsv("a,b\n1,2\n").Count);
            var snapshot = new PerfSnapshot();
            FrameStats.Fill(snapshot, new List<double> { 10, 10 });
            Assert.IsNull(snapshot.Fps);
        }

        [TestMethod]
        public void LasMedicionesSeConservanHastaUnLimite()
        {
            var store = Store();
            for (int i = 0; i < PerfStore.KeepMeasurements + 5; i++)
                store.AddMeasurement(new PerfSnapshot { AtUtc = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMinutes(i), Label = "m" + i, SchedP50 = i });
            var list = store.LoadMeasurements();
            Assert.AreEqual(PerfStore.KeepMeasurements, list.Count);
            Assert.AreEqual("m" + (PerfStore.KeepMeasurements + 4), list.Last().Label);
            Assert.AreEqual(5.0, list.First().SchedP50.Value, 1e-9);
        }

        // ---------- Temperaturas ----------

        private static ThermalSample Sample(int seconds, double? cpu = null, double? freq = null, double? load = null, double? gpu = null, bool gpuThrottle = false)
        {
            return new ThermalSample { AtUtc = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc).AddSeconds(seconds), CpuC = cpu, CpuFreqPercent = freq, CpuLoad = load, GpuC = gpu, GpuThermalThrottle = gpuThrottle };
        }

        [TestMethod]
        public void AvisoDeCalorSoloTrasDosMuestrasSeguidasYConEsperaEntreAvisos()
        {
            var events = new List<ThermalEvent>();
            var tracker = new ThermalTracker("Fortnite", events.Add);
            tracker.Add(Sample(0, 92)); Assert.AreEqual(0, events.Count, "una muestra aislada no avisa");
            tracker.Add(Sample(5, 93)); Assert.AreEqual(1, events.Count);
            Assert.AreEqual("hot", events[0].Kind);
            tracker.Add(Sample(10, 95)); tracker.Add(Sample(15, 95));
            Assert.AreEqual(1, events.Count, "espera de dos minutos");
            tracker.Add(Sample(130, 95)); tracker.Add(Sample(135, 95));
            Assert.AreEqual(2, events.Count);
        }

        [TestMethod]
        public void UnPicoAislado_NoAvisa()
        {
            var events = new List<ThermalEvent>();
            var tracker = new ThermalTracker("Fortnite", events.Add);
            tracker.Add(Sample(0, 95)); tracker.Add(Sample(5, 70)); tracker.Add(Sample(10, 95));
            Assert.AreEqual(0, events.Count);
        }

        [TestMethod]
        public void ThrottlingDeCpuConCargaAlta()
        {
            var events = new List<ThermalEvent>();
            var tracker = new ThermalTracker("ZZZ", events.Add);
            for (int i = 0; i < 3; i++) tracker.Add(Sample(i * 5, 88, 55, 95));
            Assert.AreEqual(1, events.Count);
            Assert.AreEqual("throttle", events[0].Kind);
            var calm = new List<ThermalEvent>();
            var idle = new ThermalTracker("ZZZ", calm.Add);
            for (int i = 0; i < 5; i++) idle.Add(Sample(i * 5, 60, 40, 10));
            Assert.AreEqual(0, calm.Count, "frecuencia baja sin carga es ahorro de energía, no throttling");
        }

        [TestMethod]
        public void ThrottlingDeLaGraficaYResumenFinal()
        {
            var events = new List<ThermalEvent>();
            var tracker = new ThermalTracker("Fortnite", events.Add);
            tracker.Add(Sample(0, 70, gpu: 80, gpuThrottle: true)); tracker.Add(Sample(5, 72, gpu: 84, gpuThrottle: true));
            Assert.AreEqual("throttle", events.Single().Kind);
            var summary = tracker.Finish(new DateTime(2026, 1, 1, 13, 0, 0, DateTimeKind.Utc));
            Assert.AreEqual("summary", summary.Kind);
            Assert.AreEqual(84.0, summary.PeakC.Value, 1e-9);
            StringAssert.Contains(summary.Detail, "GPU máx. 84");
            Assert.IsNull(new ThermalTracker("x", events.Add).Finish(DateTime.UtcNow));
        }

        [TestMethod]
        public void SalidaDeNvidiaSmi()
        {
            double t; bool throttle;
            Assert.IsTrue(NvidiaSmi.TryParse("65, Not Active, Active", out t, out throttle));
            Assert.AreEqual(65.0, t, 1e-9); Assert.IsTrue(throttle);
            Assert.IsTrue(NvidiaSmi.TryParse("70", out t, out throttle)); Assert.IsFalse(throttle);
            Assert.IsFalse(NvidiaSmi.TryParse("No devices were found", out t, out throttle));
            Assert.IsFalse(NvidiaSmi.TryParse("", out t, out throttle));
        }

        [TestMethod]
        public void HistorialTermicoSePuedeBorrar()
        {
            var store = Store();
            store.AddThermal(new ThermalEvent { AtUtc = DateTime.UtcNow, Kind = "hot", Game = "Fortnite", Detail = "CPU a 92 °C", PeakC = 92 });
            Assert.AreEqual(1, store.LoadThermal().Count);
            store.ClearThermal();
            Assert.AreEqual(0, store.LoadThermal().Count);
        }
    }
}
