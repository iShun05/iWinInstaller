using System.Collections.Generic;
using IWinInstaller.App.Modules.Updates;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class UpdatesTests
    {
        private static Dictionary<string, object> Row(string id, string name, string available, bool excluded = false, bool interactive = false)
        {
            return new Dictionary<string, object>
            {
                { "id", id }, { "name", name }, { "installedVersion", "1.0" }, { "availableVersion", available },
                { "source", "winget" }, { "catalogId", null }, { "interactive", interactive }, { "excluded", excluded }
            };
        }

        [TestMethod]
        public void LeeLaListaYDesmarcaLasExcluidas()
        {
            var response = new Dictionary<string, object> { { "items", new object[] { Row("Git.Git", "Git", "2.0"), Row("VideoLAN.VLC", "VLC", "3.1", excluded: true) } } };
            var items = UpdateItem.FromResponse(response);
            Assert.AreEqual(2, items.Count);
            Assert.AreEqual("Git", items[0].Name, "las excluidas van al final");
            Assert.IsTrue(items[0].IsSelected);
            Assert.IsTrue(items[1].Excluded);
            Assert.IsFalse(items[1].IsSelected);
        }

        [TestMethod]
        public void IgnoraFilasSinIdOSinVersionNueva()
        {
            var response = new Dictionary<string, object> { { "items", new object[] { Row("", "Nada", "1.0"), Row("A.B", "A", "") } } };
            Assert.AreEqual(0, UpdateItem.FromResponse(response).Count);
        }

        [TestMethod]
        public void UnaExcluidaNoSePuedeMarcar()
        {
            var item = new UpdateItem { Id = "A.B", Name = "A", AvailableVersion = "2" };
            item.Excluded = true;
            item.IsSelected = true;
            Assert.IsFalse(item.IsSelected);
        }

        [TestMethod]
        public void ProgramacionConValoresInvalidosUsaLosPorDefecto()
        {
            var response = new Dictionary<string, object> { { "schedule", new Dictionary<string, object> { { "enabled", true }, { "frequency", "mensual" }, { "time", "25:99" } } } };
            var schedule = UpdateSchedule.FromResponse(response);
            Assert.IsTrue(schedule.Enabled);
            Assert.AreEqual("weekly", schedule.Frequency);
            Assert.AreEqual("12:00", schedule.Time);
        }

        [TestMethod]
        public void HorasValidas()
        {
            Assert.IsTrue(UpdateSchedule.IsValidTime("07:30"));
            Assert.IsFalse(UpdateSchedule.IsValidTime("7:30"));
            Assert.IsFalse(UpdateSchedule.IsValidTime("24:00"));
        }

        [TestMethod]
        public void ResultadosDeAplicar()
        {
            var response = new Dictionary<string, object> { { "results", new object[] { new Dictionary<string, object> { { "id", "Git.Git" }, { "outcome", "success" } } } } };
            var outcomes = UpdatesViewModel.ReadOutcomes(response);
            Assert.AreEqual("success", outcomes["git.git"]);
            Assert.AreEqual("Actualizada", UpdatesViewModel.Describe("success"));
            Assert.AreEqual("Sin resultado", UpdatesViewModel.Describe(null));
        }
    }
}
