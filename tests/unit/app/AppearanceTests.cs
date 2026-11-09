using IWinInstaller.App.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class AppearanceTests
    {
        [TestMethod]
        public void ColumnasSegunElAncho()
        {
            Assert.AreEqual(1, WidthToColumns.Columns(0));
            Assert.AreEqual(1, WidthToColumns.Columns(560));
            Assert.AreEqual(2, WidthToColumns.Columns(700));
            Assert.AreEqual(3, WidthToColumns.Columns(950));
            Assert.AreEqual(4, WidthToColumns.Columns(2400), "nunca más de cuatro columnas");
        }

        [TestMethod]
        public void EtiquetasCortasDeEstado()
        {
            var card = new StatusCard("diskSpace", "Espacio en disco");
            Assert.AreEqual("Comprobando", card.StateLabel);
            card.Apply(StatusState.Attention, "Poco espacio", "x", "");
            Assert.AreEqual("Atención", card.StateLabel);
            card.Apply(StatusState.Unknown, "?", "motivo", "");
            Assert.AreEqual("Sin comprobar", card.StateLabel);
            Assert.AreNotEqual("", card.Glyph);
        }
    }
}
