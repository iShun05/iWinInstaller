using System.Collections.Generic;
using IWinInstaller.App.Modules.Gaming;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class GamingTests
    {
        [TestMethod]
        public void EstadisticasDePing()
        {
            var stats = new LatencyStats(60);
            foreach (long? ms in new long?[] { 20, 30, null, 20 }) stats.Add(ms);
            Assert.AreEqual(20L, stats.Last);
            Assert.AreEqual(70.0 / 3, stats.Average.Value, 1e-9);
            Assert.AreEqual(10.0, stats.Jitter.Value, 1e-9, "|30-20| y |20-30| entre respuestas consecutivas");
            Assert.AreEqual(25.0, stats.LossPercent, 1e-9);
            Assert.AreEqual(30L, stats.Max);
        }

        [TestMethod]
        public void LaVentanaSoloGuardaLasUltimasMuestras()
        {
            var stats = new LatencyStats(60);
            for (int i = 0; i < 100; i++) stats.Add(i);
            Assert.AreEqual(60, stats.Count);
            Assert.AreEqual(99L, stats.Last);
        }

        [TestMethod]
        public void ServidorQueNoRespondeAPing()
        {
            var stats = new LatencyStats(60);
            for (int i = 0; i < 9; i++) stats.Add(null);
            Assert.IsFalse(stats.NoAnswer());
            stats.Add(null);
            Assert.IsTrue(stats.NoAnswer());
            stats.Add(30);
            Assert.IsFalse(stats.NoAnswer());
        }

        [TestMethod]
        public void NotasDeBufferbloatConSusLimites()
        {
            Assert.AreEqual("A+", LatencyStats.BufferbloatGrade(4.9));
            Assert.AreEqual("A", LatencyStats.BufferbloatGrade(5));
            Assert.AreEqual("B", LatencyStats.BufferbloatGrade(30));
            Assert.AreEqual("C", LatencyStats.BufferbloatGrade(60));
            Assert.AreEqual("D", LatencyStats.BufferbloatGrade(200));
            Assert.AreEqual("F", LatencyStats.BufferbloatGrade(400));
        }

        [TestMethod]
        public void Percentiles()
        {
            var values = new List<double> { 10, 20, 30, 40, 50 };
            Assert.AreEqual(30, LatencyStats.Percentile(values, 50), 1e-9);
            Assert.AreEqual(46, LatencyStats.Percentile(values, 90), 1e-9);
            Assert.IsTrue(double.IsNaN(LatencyStats.Percentile(new List<double>(), 50)));
        }

        [TestMethod]
        public void ColoresDelPing()
        {
            Assert.AreEqual("ok", LatencyStats.Level(3, 0, true));
            Assert.AreEqual("bad", LatencyStats.Level(3, 1, true), "el router no debe perder paquetes");
            Assert.AreEqual("ok", LatencyStats.Level(25, 0, false));
            Assert.AreEqual("warn", LatencyStats.Level(50, 1, false));
            Assert.AreEqual("bad", LatencyStats.Level(85, 0, false));
            Assert.AreEqual("bad", LatencyStats.Level(null, 100, false));
        }

        [TestMethod]
        public void ServidorDelJuegoValido()
        {
            Assert.IsTrue(LatencyStats.IsValidHost("155.133.248.34"));
            Assert.IsTrue(LatencyStats.IsValidHost("euw1.riotgames.com"));
            Assert.IsTrue(LatencyStats.IsValidHost("2606:4700:4700::1111"));
            Assert.IsFalse(LatencyStats.IsValidHost(""));
            Assert.IsFalse(LatencyStats.IsValidHost("servidor con espacios"));
            Assert.IsFalse(LatencyStats.IsValidHost("-opcion"));
            Assert.IsFalse(LatencyStats.IsValidHost(new string('a', 254)));
        }

        [TestMethod]
        public void WifiEnEspanolSinSsid()
        {
            var info = WifiInfo.Parse("    Nombre                 : Wi-Fi\r\n    SSID                   : MiCasa\r\n    Tipo de radio          : 802.11ax\r\n    Banda                  : 5 GHz\r\n    Canal                  : 36\r\n    Señal                  : 82%\r\n");
            Assert.AreEqual(82, info.Signal);
            Assert.AreEqual(36, info.Channel);
            Assert.AreEqual("5 GHz", info.Band);
            Assert.AreEqual("802.11ax", info.RadioType);
        }

        [TestMethod]
        public void WifiEnInglesDeduceLaBandaDelCanal()
        {
            var info = WifiInfo.Parse("    Radio type             : 802.11n\n    Channel                : 6\n    Signal                 : 55%\n");
            Assert.AreEqual(55, info.Signal);
            Assert.AreEqual("2,4 GHz", info.Band);
        }

        [TestMethod]
        public void SinWifiNoHaySenal()
        {
            Assert.IsNull(WifiInfo.Parse("No hay ninguna interfaz inalámbrica en el sistema.").Signal);
            Assert.IsNull(WifiInfo.Parse(null).Signal);
        }
    }
}
