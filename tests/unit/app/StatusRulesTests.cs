using System.Collections.Generic;
using IWinInstaller.App.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class StatusRulesTests
    {
        private const long Gb = 1073741824L;

        [TestMethod]
        public void PocoEspacioPideAtencion()
        {
            Assert.AreEqual(StatusState.Attention, StatusRules.DiskSpace(9 * Gb, 100 * Gb).State);
            Assert.AreEqual(StatusState.Attention, StatusRules.DiskSpace(14 * Gb, 120 * Gb).State);
        }

        [TestMethod]
        public void EspacioSuficienteEsCorrecto()
        {
            var result = StatusRules.DiskSpace(200 * Gb, 500 * Gb);
            Assert.AreEqual(StatusState.Ok, result.State);
            StringAssert.Contains(result.Summary, "GB libres");
        }

        [TestMethod]
        public void DiscoSinTamanoNoSePresentaComoCorrecto()
        {
            var result = StatusRules.DiskSpace(0, 0);
            Assert.AreEqual(StatusState.Unknown, result.State);
            Assert.IsFalse(string.IsNullOrWhiteSpace(result.Reason));
        }

        [TestMethod]
        public void SinBateriaLaTarjetaNoAplica()
        {
            Assert.AreEqual(StatusState.NotApplicable, StatusRules.Battery(0, 0).State);
        }

        [TestMethod]
        public void BateriaDesgastadaPideAtencion()
        {
            Assert.AreEqual(StatusState.Attention, StatusRules.Battery(50000, 29000).State);
            Assert.AreEqual(StatusState.Ok, StatusRules.Battery(50000, 45000).State);
        }

        [TestMethod]
        public void BateriaConDatosIncompletosEsDesconocida()
        {
            Assert.AreEqual(StatusState.Unknown, StatusRules.Battery(50000, 0).State);
        }

        [TestMethod]
        public void DiscoConAvisoPideAtencionYNombraElDisco()
        {
            var result = StatusRules.DiskHealth(new List<DiskHealthInfo>
            {
                new DiskHealthInfo { Name = "Samsung SSD", HealthStatus = 0 },
                new DiskHealthInfo { Name = "WD HDD", HealthStatus = 1 }
            });
            Assert.AreEqual(StatusState.Attention, result.State);
            StringAssert.Contains(result.Summary, "WD HDD");
        }

        [TestMethod]
        public void SaludIlegibleEsDesconocida()
        {
            Assert.AreEqual(StatusState.Unknown, StatusRules.DiskHealth(null).State);
            Assert.AreEqual(StatusState.Unknown, StatusRules.DiskHealth(new List<DiskHealthInfo> { new DiskHealthInfo { Name = "x", HealthStatus = 5 } }).State);
        }

        [TestMethod]
        public void ReinicioPendiente()
        {
            Assert.AreEqual(StatusState.Attention, StatusRules.Reboot(true).State);
            Assert.AreEqual(StatusState.Ok, StatusRules.Reboot(false).State);
            Assert.AreEqual(StatusState.Unknown, StatusRules.Reboot(null).State);
        }

        [TestMethod]
        public void TarjetaDesconocidaSinMotivoRecibeUno()
        {
            var card = new StatusCard("x", "X");
            card.Apply(StatusState.Unknown, "No se pudo comprobar", "", "");
            Assert.IsTrue(card.HasReason);
            Assert.AreEqual("No se pudo comprobar", card.StateText);
        }

        [TestMethod]
        public void EstadosDelMotor()
        {
            Assert.AreEqual(StatusState.Ok, StatusCard.ParseState("ok"));
            Assert.AreEqual(StatusState.Attention, StatusCard.ParseState("attention"));
            Assert.AreEqual(StatusState.NotApplicable, StatusCard.ParseState("notApplicable"));
            Assert.AreEqual(StatusState.Unknown, StatusCard.ParseState("loquesea"));
        }
    }
}
