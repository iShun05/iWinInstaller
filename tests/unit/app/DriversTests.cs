using System;
using System.Collections.Generic;
using System.Linq;
using IWinInstaller.App.Modules.Drivers;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class DriversTests
    {
        private static readonly DateTime Now = new DateTime(2026, 11, 17);
        private const string NvidiaId = @"PCI\VEN_10DE&DEV_28E0&SUBSYS_3E5717AA&REV_A1\4&1234";

        private static InstalledDriver Driver(string cls, string name, string deviceId, string version, string provider, DateTime? date = null, string hardwareId = null)
        {
            return new InstalledDriver
            {
                DeviceClass = cls, Name = name, DeviceId = deviceId, Version = version, Provider = provider, Date = date,
                HardwareId = hardwareId ?? deviceId.Split('\\').Take(2).Aggregate((a, b) => a + "\\" + b)
            };
        }

        private static DriverScan Scan(params InstalledDriver[] drivers)
        {
            var scan = new DriverScan { Identity = new SystemIdentity { Manufacturer = "LENOVO", Model = "82XV", BiosVersion = "LPCN47WW", BiosDate = new DateTime(2025, 2, 5), CpuVendor = "GenuineIntel", IsLaptop = true }, Offers = new List<WindowsUpdateOffer>() };
            scan.Drivers.AddRange(drivers);
            return scan;
        }

        private static InstalledDriver Gpu(string version = "32.0.15.6094")
        {
            return Driver("DISPLAY", "NVIDIA GeForce RTX 4060 Laptop GPU", NvidiaId, version, "NVIDIA", new DateTime(2024, 9, 1));
        }

        [TestMethod]
        public void TraduceLaVersionDeWindowsDeNvidia()
        {
            Assert.AreEqual("560.94", DriverRules.NvidiaVersion("32.0.15.6094"));
            Assert.AreEqual("552.22", DriverRules.NvidiaVersion("31.0.15.5222"));
            Assert.AreEqual("621.24", DriverRules.NvidiaVersion("32.0.16.2124"));
            Assert.AreEqual("509.99", DriverRules.NvidiaVersion("31.0.15.0999"));
            Assert.IsNull(DriverRules.NvidiaVersion("560.94"));
            Assert.IsNull(DriverRules.NvidiaVersion("32.0.15.abc"));
            Assert.IsNull(DriverRules.NvidiaVersion(null));
        }

        [TestMethod]
        public void ComparaVersionesPorPartesNumericas()
        {
            Assert.AreEqual(1, DriverRules.CompareVersions("1.10", "1.9"));
            Assert.AreEqual(0, DriverRules.CompareVersions("31.0.101.5590", "31.0.101.5590.0"));
            Assert.AreEqual(-1, DriverRules.CompareVersions("560.94", "621.24"));
            Assert.IsNull(DriverRules.CompareVersions("1.0a", "1.0"));
            Assert.IsNull(DriverRules.CompareVersions("", "1.0"));
        }

        [TestMethod]
        public void LeeVersionDelTituloYFechaCim()
        {
            Assert.AreEqual("32.0.15.6094", DriverRules.VersionFromTitle("NVIDIA - Display - 32.0.15.6094"));
            Assert.AreEqual("23.40.0.4", DriverRules.VersionFromTitle("Intel Corporation - Net - 23.40.0.4"));
            Assert.IsNull(DriverRules.VersionFromTitle("Lenovo - Firmware"));
            Assert.AreEqual(new DateTime(2024, 3, 12), DriverRules.ParseCimDate("20240312000000.000000-000"));
            Assert.IsNull(DriverRules.ParseCimDate("1980"));
            Assert.IsNull(DriverRules.ParseCimDate("19800101000000.000000-000"));
        }

        [TestMethod]
        public void EdadEnMesesYAnios()
        {
            Assert.AreEqual("este mes", DriverRules.Age(new DateTime(2026, 11, 2), Now));
            Assert.AreEqual("hace 1 mes", DriverRules.Age(new DateTime(2026, 10, 1), Now));
            Assert.AreEqual("hace 1 año y 2 meses", DriverRules.Age(new DateTime(2025, 9, 10), Now));
            Assert.AreEqual("hace 2 años", DriverRules.Age(new DateTime(2024, 11, 17), Now));
        }

        [TestMethod]
        public void FabricantePorIdYWebsOficiales()
        {
            Assert.AreEqual("NVIDIA", DriverRules.Vendor(NvidiaId, null));
            Assert.AreEqual("Intel", DriverRules.Vendor(@"PCI\VEN_8086&DEV_2725", null));
            Assert.AreEqual("Realtek", DriverRules.Vendor(@"USB\VID_0BDA&PID_8153", null));
            Assert.AreEqual("AMD", DriverRules.Vendor(@"ACPI\XYZ", "Advanced Micro Devices, Inc."));
            Assert.IsNull(DriverRules.Vendor(@"ACPI\XYZ", "Contoso"));
            Assert.AreEqual("28E0", DriverRules.PciDeviceId(NvidiaId));
            Assert.AreEqual("https://pcsupport.lenovo.com/", DriverRules.OemSupportUrl("LENOVO"));
            Assert.AreEqual("https://www.msi.com/support/download", DriverRules.OemSupportUrl("Micro-Star International Co., Ltd."));
            Assert.AreEqual("https://support.hp.com/es-es/drivers", DriverRules.OemSupportUrl("HP"));
            Assert.IsNull(DriverRules.OemSupportUrl("To Be Filled By O.E.M."));
            Assert.AreEqual("https://www.asrock.com/support/index.asp", DriverRules.OemUrl(new SystemIdentity { Manufacturer = "To Be Filled By O.E.M.", BoardManufacturer = "ASRock" }));
        }

        [TestMethod]
        public void UrlDeNvidiaCodificaElJson()
        {
            string url = NvidiaDriverSource.BuildUrl("28e0", 26100, true);
            StringAssert.StartsWith(url, "https://gfwsl.geforce.com/");
            StringAssert.Contains(url, "%7B%22dIDa%22:[%2228E0_10DE%22]");
            StringAssert.Contains(url, "%22osB%22:%2226100%22");
            Assert.IsFalse(url.Contains("\"") || url.Contains("{"));
            Assert.ThrowsException<ArgumentException>(() => NvidiaDriverSource.BuildUrl("12345", 1, true));
        }

        [TestMethod]
        public void LeeLaRespuestaDeNvidia()
        {
            const string body = "{\"criteria\":{\"overallState\":\"true\",\"IsSupported\":{\"state\":\"true\"},\"IsDispDriverNewer\":{\"latestDispDriverVersion\":\"621.24\"}},"
                + "\"DriverAttributes\":{\"ID\":285320,\"Name\":\"GeForce Game Ready Driver\",\"ReleaseDateTime\":\"2026-11-12T00:00:00+0000\",\"Version\":\"621.24\","
                + "\"DetailsURL\":\"https:\\/\\/www.nvidia.com\\/en-us\\/drivers\\/details\\/285320\\/\"}}";
            var release = NvidiaDriverSource.Parse(body);
            Assert.IsNotNull(release);
            Assert.AreEqual("621.24", release.Version);
            Assert.AreEqual(new DateTime(2026, 11, 12), release.Date);
            Assert.AreEqual("https://www.nvidia.com/en-us/drivers/details/285320/", release.DetailsUrl);

            Assert.IsNull(NvidiaDriverSource.Parse("{\"criteria\":{\"IsSupported\":{\"state\":\"false\"}},\"DriverAttributes\":{\"Version\":\"621.24\"}}"), "GPU no soportada");
            Assert.IsNull(NvidiaDriverSource.Parse("<html>error</html>"));
            Assert.IsNull(NvidiaDriverSource.Parse("{\"DriverAttributes\":{\"Version\":\"\"}}"));
            var foreign = NvidiaDriverSource.Parse("{\"DriverAttributes\":{\"Version\":\"621.24\",\"DetailsURL\":\"https://evil.example/\"}}");
            Assert.IsNull(foreign.DetailsUrl, "solo enlaces de nvidia.com");
        }

        [TestMethod]
        public void NvidiaAntiguaAvisaYNuevaQuedaAlDia()
        {
            var scan = Scan(Gpu());
            scan.Nvidia[NvidiaId] = new NvidiaRelease { Version = "621.24", Date = new DateTime(2026, 11, 12), DetailsUrl = "https://www.nvidia.com/en-us/drivers/details/285320/" };
            var row = DriverReport.Build(scan, Now).Single(r => r.Kind == DriverKind.Gpu);
            Assert.AreEqual(DriverState.UpdateAvailable, row.State);
            StringAssert.Contains(row.Status, "621.24");
            StringAssert.Contains(row.Installed, "560.94");
            Assert.AreEqual("https://www.nvidia.com/en-us/drivers/details/285320/", row.LinkUrl);

            var current = Scan(Gpu("32.0.16.2124"));
            current.Nvidia[NvidiaId] = new NvidiaRelease { Version = "621.24" };
            Assert.AreEqual(DriverState.UpToDate, DriverReport.Build(current, Now).Single(r => r.Kind == DriverKind.Gpu).State);

            var beta = Scan(Gpu("32.0.16.2210"));
            beta.Nvidia[NvidiaId] = new NvidiaRelease { Version = "621.24" };
            Assert.AreEqual(DriverState.UpToDate, DriverReport.Build(beta, Now).Single(r => r.Kind == DriverKind.Gpu).State, "una beta o hotfix más nueva no avisa");
        }

        [TestMethod]
        public void SinRespuestaDeNvidiaNoAvisa()
        {
            var scan = Scan(Gpu());
            scan.NvidiaErrors.Add(NvidiaId);
            var row = DriverReport.Build(scan, Now).Single(r => r.Kind == DriverKind.Gpu);
            Assert.AreEqual(DriverState.CheckManually, row.State);
            StringAssert.Contains(row.Note, "NVIDIA");
            Assert.AreEqual(DriverRules.NvidiaDriversUrl, row.LinkUrl);
        }

        [TestMethod]
        public void WindowsUpdateConVersionAnteriorSeIgnora()
        {
            var wifi = Driver("NET", "Intel(R) Wi-Fi 6E AX211 160MHz", @"PCI\VEN_8086&DEV_51F1&SUBSYS_00948086\3&11583659", "23.60.0.3", "Intel", new DateTime(2026, 6, 1));
            var scan = Scan(wifi);
            scan.Offers.Add(new WindowsUpdateOffer { Title = "Intel - Net - 23.40.0.4", DriverClass = "Net", HardwareId = @"PCI\VEN_8086&DEV_51F1&SUBSYS_00948086", Date = new DateTime(2026, 8, 1), Optional = true });
            var row = DriverReport.Build(scan, Now).Single(r => r.Kind == DriverKind.Network);
            Assert.AreEqual(DriverState.CheckManually, row.State, "fecha más nueva pero versión anterior: no es una actualización");
            StringAssert.Contains(row.Status, "igual o anterior");
            Assert.AreEqual(DriverRules.IntelAssistantUrl, row.LinkUrl);
            Assert.IsFalse(DriverReport.Build(scan, Now).Any(r => r.Kind == DriverKind.Other));
        }

        [TestMethod]
        public void WindowsUpdateConVersionNuevaAvisa()
        {
            var lan = Driver("NET", "Realtek PCIe GbE Family Controller", @"PCI\VEN_10EC&DEV_8168&SUBSYS_3E5717AA&REV_15\01000000", "10.50.511.2021", "Realtek", new DateTime(2021, 5, 11));
            var scan = Scan(lan);
            scan.Offers.Add(new WindowsUpdateOffer { Title = "Realtek - Net - 10.68.815.2023", DriverClass = "Net", HardwareId = @"PCI\VEN_10EC&DEV_8168", Optional = true });
            var row = DriverReport.Build(scan, Now).Single(r => r.Kind == DriverKind.Network);
            Assert.AreEqual(DriverState.UpdateAvailable, row.State);
            StringAssert.Contains(row.Status, "10.68.815.2023 (opcional)");
            Assert.AreEqual(DriverRules.OptionalUpdatesUri, row.LinkUrl);
        }

        [TestMethod]
        public void FirmwareDeWindowsUpdateVaALaBiosYElRestoAOtros()
        {
            var scan = Scan();
            scan.Offers.Add(new WindowsUpdateOffer { Title = "LENOVO - Firmware - 1.47.0.0", DriverClass = "Firmware", HardwareId = "UEFI\\RES_{abc}" });
            scan.Offers.Add(new WindowsUpdateOffer { Title = "Realtek - Audio - 6.0.9600.1", DriverClass = "MEDIA", HardwareId = @"HDAUDIO\FUNC_01&VEN_10EC" });
            var rows = DriverReport.Build(scan, Now);
            var bios = rows.Single(r => r.Kind == DriverKind.Firmware);
            Assert.AreEqual(DriverState.UpdateAvailable, bios.State);
            StringAssert.Contains(bios.Status, "1.47.0.0");
            StringAssert.Contains(bios.Note, "BIOS");
            var other = rows.Single(r => r.Kind == DriverKind.Other);
            Assert.AreEqual(DriverState.UpdateAvailable, other.State);
        }

        [TestMethod]
        public void BiosSinOfertaRemiteAlFabricanteSinAvisar()
        {
            var row = DriverReport.Build(Scan(), Now).Single(r => r.Kind == DriverKind.Firmware);
            Assert.AreEqual(DriverState.CheckManually, row.State);
            StringAssert.Contains(row.Installed, "LPCN47WW");
            StringAssert.Contains(row.Title, "LENOVO 82XV");
            Assert.AreEqual("https://pcsupport.lenovo.com/", row.LinkUrl);
        }

        [TestMethod]
        public void ChipsetAgrupaLosDriversDelFabricanteDelProcesador()
        {
            var scan = Scan(
                Driver("SYSTEM", "Intel(R) Serial IO I2C", @"PCI\VEN_8086&DEV_51E8\3&1", "30.100.2129.8", "Intel", new DateTime(2023, 1, 1)),
                Driver("SYSTEM", "Intel(R) Management Engine Interface", @"PCI\VEN_8086&DEV_51E0\3&2", "2306.4.3.0", "Intel", new DateTime(2025, 3, 1)),
                Driver("SYSTEM", "PCI Express Root Port", @"PCI\VEN_8086&DEV_51B8\3&3", "10.0.26100.1", "Microsoft", new DateTime(2006, 6, 21)));
            var rows = DriverReport.Build(scan, Now);
            var chipset = rows.Single(r => r.Kind == DriverKind.Chipset);
            StringAssert.Contains(chipset.Title, "Intel (2 componentes)");
            StringAssert.Contains(chipset.Installed, "2306.4.3.0");
            Assert.AreEqual("https://pcsupport.lenovo.com/", chipset.LinkUrl, "en portátiles, primero el fabricante del equipo");
        }

        [TestMethod]
        public void IgnoraAdaptadoresVirtualesYPantallaBasica()
        {
            var scan = Scan(
                Driver("NET", "WAN Miniport (IP)", @"SWD\MSRRAS\MS_NDISWANIP", "10.0.1", "Microsoft"),
                Driver("NET", "Hyper-V Virtual Ethernet Adapter", @"ROOT\VMS_MP\0000", "10.0.1", "Microsoft"),
                Driver("DISPLAY", "Microsoft Basic Display Adapter", @"ROOT\BasicDisplay\0000", "10.0.1", "Microsoft"));
            var rows = DriverReport.Build(scan, Now);
            Assert.AreEqual(1, rows.Count, "solo queda la fila de la BIOS");
            Assert.AreEqual(DriverKind.Firmware, rows[0].Kind);
        }

        [TestMethod]
        public void ResumenCuentaAvisosYFalloDeWindowsUpdate()
        {
            var scan = Scan(Gpu());
            scan.Nvidia[NvidiaId] = new NvidiaRelease { Version = "621.24" };
            scan.Offers = null;
            scan.WindowsUpdateError = "el servicio Windows Update está desactivado.";
            var rows = DriverReport.Build(scan, Now);
            string summary = DriverReport.Summary(rows, scan);
            StringAssert.Contains(summary, "1 driver o firmware con versión nueva.");
            StringAssert.Contains(summary, "1 se comprueba en la web del fabricante.");
            StringAssert.Contains(summary, "Windows Update no respondió: el servicio");
        }
    }
}
