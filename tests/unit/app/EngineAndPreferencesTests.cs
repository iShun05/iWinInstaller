using System;
using System.IO;
using System.Text;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class EngineAndPreferencesTests
    {
        private string _dir;

        [TestInitialize]
        public void Setup()
        {
            _dir = Path.Combine(Path.GetTempPath(), "iwin-app-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_dir);
        }

        [TestCleanup]
        public void Cleanup() { try { Directory.Delete(_dir, true); } catch (IOException) { } }

        [TestMethod]
        public void LeeUnEventoDone()
        {
            var e = EngineEvent.Parse("{\"t\":\"2026-11-08T10:00:00Z\",\"type\":\"done\",\"outcome\":\"success\",\"exitCode\":0}");
            Assert.IsNotNull(e);
            Assert.AreEqual("done", e.Type);
            Assert.AreEqual(0, e.ExitCode);
        }

        [TestMethod]
        public void IgnoraLineasMalFormadas()
        {
            Assert.IsNull(EngineEvent.Parse("{roto"));
            Assert.IsNull(EngineEvent.Parse(""));
            Assert.IsNull(EngineEvent.Parse("{\"sin\":\"tipo\"}"));
        }

        [TestMethod]
        public void LectorConservaLaLineaAMedias()
        {
            string path = Path.Combine(_dir, "events.jsonl");
            var reader = new EventFileReader(path);
            File.WriteAllText(path, "{\"type\":\"progress\",\"id\":\"a\"}\n{\"type\":\"pro", new UTF8Encoding(false));
            var first = reader.ReadNew();
            Assert.AreEqual(1, first.Count);
            File.AppendAllText(path, "gress\",\"id\":\"b\"}\n", new UTF8Encoding(false));
            var second = reader.ReadNew();
            Assert.AreEqual(1, second.Count);
            Assert.AreEqual("b", second[0].Id);
        }

        [TestMethod]
        public void ZoomLimitadoEntre70y200()
        {
            Assert.AreEqual(0.7, Preferences.ClampZoom(0.2), 1e-9);
            Assert.AreEqual(2.0, Preferences.ClampZoom(5), 1e-9);
            Assert.AreEqual(1.3, Preferences.ClampZoom(1.27), 1e-9);
            Assert.AreEqual(1.0, Preferences.ClampZoom(double.NaN), 1e-9);
        }

        [TestMethod]
        public void PreferenciasSeGuardanYSeRecuperan()
        {
            string path = Path.Combine(_dir, "interfaz.json");
            var preferences = Preferences.Load(path);
            Assert.AreEqual(1.0, preferences.Zoom, 1e-9);
            preferences.Zoom = 1.5;
            preferences.Save();
            Assert.AreEqual(1.5, Preferences.Load(path).Zoom, 1e-9);
        }

        [TestMethod]
        public void ArchivoDanadoUsaValoresPorDefecto()
        {
            string path = Path.Combine(_dir, "interfaz.json");
            File.WriteAllText(path, "{no es json");
            Assert.AreEqual(1.0, Preferences.Load(path).Zoom, 1e-9);
        }
    }
}
