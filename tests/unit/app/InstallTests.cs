using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using IWinInstaller.App.Modules.Install;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class InstallTests
    {
        private static List<CatalogEntry> _catalog;

        // apps.json real del repositorio: se busca subiendo desde la carpeta de las pruebas
        private static string CatalogPath()
        {
            var dir = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            while (dir != null && !File.Exists(Path.Combine(dir.FullName, "apps.json"))) dir = dir.Parent;
            Assert.IsNotNull(dir, "No se encontró apps.json");
            return Path.Combine(dir.FullName, "apps.json");
        }

        [ClassInitialize]
        public static void Load(TestContext context) { _catalog = CatalogEntry.Load(CatalogPath()); }

        [TestMethod]
        public void CargaTodoElCatalogoSinIdsRepetidos()
        {
            Assert.IsTrue(_catalog.Count >= 400, "entradas: " + _catalog.Count);
            Assert.AreEqual(_catalog.Count, _catalog.Select(e => e.Id).Distinct().Count());
            Assert.IsTrue(_catalog.All(e => !String.IsNullOrEmpty(e.Name) && !String.IsNullOrEmpty(e.Section)));
        }

        [TestMethod]
        public void LaNotaCualElegirValeParaTodaLaSubseccion()
        {
            foreach (var group in _catalog.Where(e => !String.IsNullOrEmpty(e.Subgroup)).GroupBy(e => e.Group + "/" + e.Subgroup))
            {
                var notes = group.Select(e => e.SubgroupNote).Distinct().ToList();
                Assert.AreEqual(1, notes.Count, "subsección con notas distintas: " + group.Key);
            }
        }

        [TestMethod]
        public void ReglasDeDesinstalarComoEnLaVentanaClasica()
        {
            Assert.IsFalse(new CatalogEntry { Id = "wsl", Type = "tweak" }.CanUninstall);
            Assert.IsTrue(new CatalogEntry { Id = "darkmode", Type = "tweak" }.CanUninstall);
            Assert.IsFalse(new CatalogEntry { Id = "vc", Type = "winget", Keep = true }.CanUninstall);
            Assert.IsFalse(new CatalogEntry { Id = "x", Type = "wingetall" }.CanUninstall);
            Assert.IsTrue(new CatalogEntry { Id = "x", Type = "download" }.CanUninstall);
        }

        [TestMethod]
        public void IconosYLetras()
        {
            Assert.AreEqual("", new CatalogEntry { Icon = "glyph:E756" }.Glyph);
            Assert.AreEqual("", new CatalogEntry { Icon = "git-scm.com" }.Glyph);
            Assert.AreEqual("VS", new CatalogEntry { Name = "Visual Studio Code" }.Initials);
            Assert.AreEqual("Gi", new CatalogEntry { Name = "Git" }.Initials);
        }

        [TestMethod]
        public void EstadoTrasUnLote()
        {
            var item = new CatalogItem(new CatalogEntry { Id = "git", Name = "Git", Type = "winget" }) { IsChecked = true };
            item.ApplyOutcome("success", true, false, false);
            Assert.AreEqual("Instalada", item.Status);
            Assert.IsFalse(item.IsChecked);
            item.ApplyOutcome("failed", false, false, false);
            Assert.AreEqual("bad", item.StatusKind);
            Assert.IsTrue(item.IsChecked, "lo que falla queda marcado para reintentar");
        }

        [TestMethod]
        public void InformeDesdeElMotor()
        {
            var response = new Dictionary<string, object>
            {
                { "summary", "1 correctas · 1 fallaron (de 2)" }, { "text", "=== INFORME ===" },
                { "report", new Dictionary<string, object> { { "items", new object[] {
                    new Dictionary<string, object> { { "id", "pwsh" }, { "name", "PowerShell 7" }, { "kind", "fallo" }, { "code", -1978334957L }, { "codeText", "0x8A150113" }, { "reason", "No admite" }, { "hint", "Reintenta" }, { "details", new object[] { "linea" } } },
                    new Dictionary<string, object> { { "id", "nortonvpn" }, { "name", "Norton VPN" }, { "kind", "manual" } } } } } }
            };
            var report = ReportViewModel.FromResponse(response);
            Assert.AreEqual(2, report.Items.Count);
            Assert.AreEqual("Falló", report.Items[0].KindText);
            StringAssert.Contains(report.Items[0].Code, "0x8A150113");
            CollectionAssert.AreEqual(new[] { "pwsh" }, report.RetryIds, "las manuales no se reintentan");
            Assert.IsNull(ReportViewModel.FromResponse(new Dictionary<string, object> { { "report", null } }));
        }

        [TestMethod]
        public void PasosConfirmados()
        {
            var guide = new GuideViewModel("x", "X", new[] { "a", "b" }, new[] { 1 }, "", "", "", "");
            Assert.AreEqual("1 paso pendiente", guide.Summary);
            guide.Steps[0].IsDone = true;
            Assert.IsTrue(guide.AllDone);
            CollectionAssert.AreEqual(new[] { 0, 1 }, guide.DoneIndexes);
        }
    }
}
