using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;
using IWinInstaller.App.Probes;

namespace IWinInstaller.App.Modules.Home
{
    /// <summary>Inicio: tarjetas con el estado del PC. Se muestra al momento y se completa en segundo plano.</summary>
    public sealed class HomeViewModel : ObservableObject
    {
        // Áreas que comprueba el motor (status.collect); el resto las lee la interfaz directamente
        private static readonly string[] EngineAreas = { "appUpdates", "windowsUpdate", "antivirus", "pendingBatch" };
        private readonly EngineClient _engine;
        private readonly Dispatcher _dispatcher;
        private bool _isRefreshing;
        private string _lastChecked = "";

        public HomeViewModel(EngineClient engine, Dispatcher dispatcher)
        {
            _engine = engine;
            _dispatcher = dispatcher;
            Cards = new ObservableCollection<StatusCard>
            {
                new StatusCard("appUpdates", "Actualizaciones de apps"),
                new StatusCard("windowsUpdate", "Windows Update"),
                new StatusCard("antivirus", "Protección antivirus"),
                new StatusCard("diskSpace", "Espacio en disco"),
                new StatusCard("diskHealth", "Salud de los discos"),
                new StatusCard("battery", "Batería"),
                new StatusCard("reboot", "Reinicio"),
                new StatusCard("pendingBatch", "Lotes de instalación")
            };
            RefreshCommand = new RelayCommand(_ => { var ignored = RefreshAsync(EngineAreas, CancellationToken.None); }, _ => !IsRefreshing);
        }

        public ObservableCollection<StatusCard> Cards { get; private set; }
        public RelayCommand RefreshCommand { get; private set; }
        public bool IsRefreshing { get { return _isRefreshing; } private set { Set(ref _isRefreshing, value); } }
        public string LastChecked { get { return _lastChecked; } private set { Set(ref _lastChecked, value); } }

        /// <summary>Resumen de la cabecera: cuántos avisos hay o si todo está bien.</summary>
        public string Headline
        {
            get
            {
                var visible = Cards.Where(c => c.IsVisible).ToList();
                if (visible.Any(c => c.IsLoading)) return "Comprobando tu PC…";
                int attention = visible.Count(c => c.State == StatusState.Attention);
                int unknown = visible.Count(c => c.State == StatusState.Unknown);
                if (attention == 0 && unknown == 0) return "Todo en orden";
                string text = attention == 1 ? "1 aviso" : attention > 1 ? attention + " avisos" : "";
                if (unknown > 0) text += (text.Length > 0 ? " · " : "") + unknown + (unknown == 1 ? " sin comprobar" : " sin comprobar");
                return text;
            }
        }

        public StatusCard Find(string area) { return Cards.FirstOrDefault(c => c.Area == area); }

        /// <summary>Comprueba todo: lecturas locales en paralelo y, a la vez, el motor para el resto.</summary>
        public async Task RefreshAsync(IEnumerable<string> engineAreas, CancellationToken cancellation)
        {
            if (IsRefreshing) return;
            IsRefreshing = true;
            try
            {
                var local = new[]
                {
                    RunLocal("diskSpace", SystemProbes.DiskSpace),
                    RunLocal("diskHealth", SystemProbes.DiskHealth),
                    RunLocal("battery", SystemProbes.Battery),
                    RunLocal("reboot", SystemProbes.Reboot)
                };
                var areas = engineAreas.ToList();
                foreach (var card in Cards.Where(c => EngineAreas.Contains(c.Area) && !areas.Contains(c.Area)))
                    card.Apply(StatusState.Unknown, "Sin comprobar", "Esta comprobación se omite en este modo.", "");
                Task remote = areas.Count == 0 ? Task.FromResult(0) : RunEngine(areas, cancellation);
                await Task.WhenAll(local.Concat(new[] { remote }));
                LastChecked = "Comprobado a las " + DateTime.Now.ToString("HH:mm");
            }
            finally { IsRefreshing = false; }
        }

        private Task RunLocal(string area, Func<StatusResult> probe)
        {
            return Task.Run(probe).ContinueWith(t =>
            {
                var result = t.IsFaulted ? StatusResult.Unknown("No se pudo comprobar", t.Exception.GetBaseException().Message) : t.Result;
                Apply(area, result);
            }, TaskScheduler.Default);
        }

        private async Task RunEngine(List<string> areas, CancellationToken cancellation)
        {
            var request = new Dictionary<string, object> { { "areas", areas.ToArray() } };
            var result = await _engine.RunAsync("status.collect", request, null, TimeSpan.FromMinutes(4), cancellation);
            var seen = new HashSet<string>();
            if (result.Ok)
            {
                object cards;
                if (result.Response.TryGetValue("cards", out cards) && cards is object[])
                {
                    foreach (var item in ((object[])cards).OfType<Dictionary<string, object>>())
                    {
                        string area = Read(item, "area");
                        seen.Add(area);
                        Apply(area, new StatusResult(StatusCard.ParseState(Read(item, "state")), Read(item, "summary"), Read(item, "reason"), Read(item, "action")));
                    }
                }
            }
            // Lo que el motor no devolvió queda como «no se pudo comprobar», con el motivo real
            string why = result.Ok ? "El motor no devolvió esta comprobación." : (result.Error ?? "El motor no respondió.");
            foreach (string area in areas.Where(a => !seen.Contains(a)))
                Apply(area, StatusResult.Unknown("No se pudo comprobar", why));
        }

        private void Apply(string area, StatusResult result)
        {
            _dispatcher.BeginInvoke(new Action(() =>
            {
                var card = Find(area);
                if (card != null) card.Apply(result.State, result.Summary, result.Reason, result.ActionId);
                OnPropertyChanged("Headline");
            }));
        }

        private static string Read(Dictionary<string, object> data, string key)
        {
            object value;
            return data.TryGetValue(key, out value) && value != null ? Convert.ToString(value) : "";
        }
    }
}
