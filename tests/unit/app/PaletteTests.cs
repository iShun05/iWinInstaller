using System.Linq;
using IWinInstaller.App.Shell.Palette;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class PaletteTests
    {
        private static readonly System.Collections.Generic.List<PaletteAction> Actions = ActionRegistry.BuiltIn()
            .Concat(new[] { new PaletteAction("install.search:git", "Git", "Instalar · Lenguajes", "control de versiones"), new PaletteAction("install.search:sshfs", "SSHFS-Win", "Instalar · Utilidades", "montar carpetas por ssh") })
            .ToList();

        [TestMethod]
        public void SinTildesNiMayusculas()
        {
            Assert.AreEqual("resolucion energia", PaletteSearch.Normalize("Resolución ENERGÍA"));
        }

        [TestMethod]
        public void BusquedasDeReferenciaEnElPrimerResultado()
        {
            Assert.AreEqual("nav.system", PaletteSearch.Find(Actions, "frecuencia")[0].Id);
            Assert.AreEqual("nav.system", PaletteSearch.Find(Actions, "resolución")[0].Id);
            Assert.AreEqual("nav.security", PaletteSearch.Find(Actions, "defender")[0].Id);
            Assert.AreEqual("nav.remote", PaletteSearch.Find(Actions, "ssh")[0].Id, "las acciones de la app van antes que apps parecidas");
            Assert.AreEqual("install.search:git", PaletteSearch.Find(Actions, "git")[0].Id);
        }

        [TestMethod]
        public void TodasLasPalabrasDebenAparecer()
        {
            Assert.IsTrue(PaletteSearch.Find(Actions, "energia hibernar").All(a => a.Id == "nav.system"));
            Assert.AreEqual(0, PaletteSearch.Find(Actions, "zzzz").Count);
        }

        [TestMethod]
        public void SinTextoMuestraLasSecciones()
        {
            Assert.IsTrue(PaletteSearch.Find(Actions, "").All(a => a.Id.StartsWith("nav.")));
        }
    }
}
