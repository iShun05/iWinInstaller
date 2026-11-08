using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;

namespace IWinInstaller.App.Modules.Updates
{
    /// <summary>Actualizaciones: ver qué apps tienen versión nueva, elegir, excluir y programar.</summary>
    public sealed class UpdatesViewModel : ObservableObject
    {
        private readonly EngineClient _engine;
        private readonly Dispatcher _dispatcher;
        private bool _isBusy;
        private bool _loaded;
        private string _message = "Pulsa «Comprobar» para buscar versiones nuevas.";
        private bool _scheduleEnabled;
        private string _scheduleFrequency = "weekly";
        private string _scheduleTime = "12:00";
        private CancellationTokenSource _cancellation;

        public UpdatesViewModel(EngineClient engine, Dispatcher dispatcher)
        {
            _engine = engine;
            _dispatcher = dispatcher;
            Items = new ObservableCollection<UpdateItem>();
            Frequencies = new[] { new KeyValuePair<string, string>("daily", "Cada día"), new KeyValuePair<string, string>("weekly", "Cada semana (domingo)") };
            RefreshCommand = new RelayCommand(_ => { var ignored = LoadAsync(); }, _ => !IsBusy);
            ApplyCommand = new RelayCommand(_ => { var ignored = ApplyAsync(); }, _ => !IsBusy && Items.Any(i => i.IsSelected));
            SelectAllCommand = new RelayCommand(_ => { foreach (var item in Items) item.IsSelected = !item.Excluded; }, _ => !IsBusy);
            ToggleExcludedCommand = new RelayCommand(p => { var ignored = ToggleExcludedAsync(p as UpdateItem); }, _ => !IsBusy);
            SaveScheduleCommand = new RelayCommand(_ => { var ignored = SaveScheduleAsync(); }, _ => !IsBusy && UpdateSchedule.IsValidTime(ScheduleTime));
            CancelCommand = new RelayCommand(_ => { if (_cancellation != null) _cancellation.Cancel(); }, _ => IsBusy);
        }

        public ObservableCollection<UpdateItem> Items { get; private set; }
        public KeyValuePair<string, string>[] Frequencies { get; private set; }
        public RelayCommand RefreshCommand { get; private set; }
        public RelayCommand ApplyCommand { get; private set; }
        public RelayCommand SelectAllCommand { get; private set; }
        public RelayCommand ToggleExcludedCommand { get; private set; }
        public RelayCommand SaveScheduleCommand { get; private set; }
        public RelayCommand CancelCommand { get; private set; }

        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }
        public string Message { get { return _message; } private set { Set(ref _message, value); } }
        public bool HasItems { get { return Items.Count > 0; } }
        public bool ScheduleEnabled { get { return _scheduleEnabled; } set { Set(ref _scheduleEnabled, value); } }
        public string ScheduleFrequency { get { return _scheduleFrequency; } set { Set(ref _scheduleFrequency, value); } }
        public string ScheduleTime { get { return _scheduleTime; } set { Set(ref _scheduleTime, (value ?? "").Trim()); } }

        /// <summary>Se llama al entrar en la sección: la primera vez busca automáticamente.</summary>
        public void EnsureLoaded() { if (!_loaded) { _loaded = true; var ignored = LoadAsync(); } }

        public async Task LoadAsync()
        {
            if (IsBusy) return;
            IsBusy = true;
            Message = "Buscando versiones nuevas con WinGet…";
            try
            {
                var result = await _engine.RunAsync("updates.list", null, null, TimeSpan.FromMinutes(4), CancellationToken.None);
                if (!result.Ok) { Message = "No se pudieron comprobar las actualizaciones: " + (result.Error ?? "el motor no respondió."); return; }
                var items = UpdateItem.FromResponse(result.Response);
                Items.Clear();
                foreach (var item in items) Items.Add(item);
                OnPropertyChanged("HasItems");
                var schedule = UpdateSchedule.FromResponse(result.Response);
                ScheduleEnabled = schedule.Enabled; ScheduleFrequency = schedule.Frequency; ScheduleTime = schedule.Time;
                int pending = items.Count(i => !i.Excluded);
                Message = items.Count == 0 ? "Todo al día: ninguna aplicación tiene versión nueva."
                    : pending + (pending == 1 ? " aplicación con versión nueva" : " aplicaciones con versión nueva") + (items.Count > pending ? " · " + (items.Count - pending) + " se mantienen en su versión" : "");
            }
            finally { IsBusy = false; }
        }

        private async Task ApplyAsync()
        {
            var selected = Items.Where(i => i.IsSelected && !i.Excluded).ToList();
            if (selected.Count == 0 || IsBusy) return;
            IsBusy = true;
            _cancellation = new CancellationTokenSource();
            foreach (var item in selected) item.Status = "En cola";
            Message = "Actualizando " + selected.Count + (selected.Count == 1 ? " aplicación…" : " aplicaciones…");
            try
            {
                var request = new Dictionary<string, object> { { "ids", selected.Select(i => i.Id).ToArray() } };
                var result = await _engine.RunAsync("updates.apply", request, OnEvent, TimeSpan.FromHours(2), _cancellation.Token);
                var outcomes = ReadOutcomes(result.Response);
                foreach (var item in selected)
                {
                    string outcome;
                    item.Status = outcomes.TryGetValue(item.Id, out outcome) ? Describe(outcome) : (result.ExitCode == EngineResult.Cancelled ? "Cancelada" : "Sin resultado");
                }
                int ok = selected.Count(i => i.Status == Describe("success"));
                Message = result.Ok ? ok + " de " + selected.Count + " actualizadas. Las que fallaron tienen el motivo en el informe de la ventana clásica."
                    : "La actualización no terminó: " + (result.Error ?? "error del motor.");
            }
            finally { IsBusy = false; _cancellation.Dispose(); _cancellation = null; }
        }

        private void OnEvent(EngineEvent engineEvent)
        {
            if (engineEvent.Id == null) return;
            _dispatcher.BeginInvoke(new Action(() =>
            {
                var item = Items.FirstOrDefault(i => String.Equals(i.Id, engineEvent.Id, StringComparison.OrdinalIgnoreCase));
                if (item == null) return;
                if (engineEvent.Type == "progress") item.Status = "Actualizando…";
                else if (engineEvent.Type == "item") item.Status = Describe(engineEvent.Outcome);
            }));
        }

        private async Task ToggleExcludedAsync(UpdateItem item)
        {
            if (item == null || IsBusy) return;
            bool target = !item.Excluded;
            var request = new Dictionary<string, object> { { "id", item.Id }, { "excluded", target } };
            var result = await _engine.RunAsync("updates.exclude", request, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (result.Ok) item.Excluded = target;
            else Message = "No se pudo guardar el cambio: " + (result.Error ?? "error del motor.");
        }

        private async Task SaveScheduleAsync()
        {
            IsBusy = true;
            try
            {
                var request = new Dictionary<string, object> { { "enabled", ScheduleEnabled }, { "frequency", ScheduleFrequency }, { "time", ScheduleTime } };
                var result = await _engine.RunAsync("updates.schedule", request, null, TimeSpan.FromMinutes(1), CancellationToken.None);
                if (!result.Ok) { Message = "No se pudo programar: " + (result.Error ?? "error del motor."); return; }
                var schedule = UpdateSchedule.FromResponse(result.Response);
                ScheduleEnabled = schedule.Enabled;
                Message = schedule.Enabled
                    ? "Programado " + (schedule.Frequency == "daily" ? "cada día" : "cada domingo") + " a las " + schedule.Time + ". No reinicia Windows ni abre asistentes."
                    : "Actualización programada desactivada.";
            }
            finally { IsBusy = false; }
        }

        internal static Dictionary<string, string> ReadOutcomes(Dictionary<string, object> response)
        {
            var outcomes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            object results;
            if (response == null || !response.TryGetValue("results", out results) || !(results is object[])) return outcomes;
            foreach (var row in ((object[])results).OfType<Dictionary<string, object>>())
            {
                string id = UpdateItem.Read(row, "id");
                if (!String.IsNullOrEmpty(id)) outcomes[id] = UpdateItem.Read(row, "outcome");
            }
            return outcomes;
        }

        internal static string Describe(string outcome)
        {
            switch (outcome)
            {
                case "success": return "Actualizada";
                case "skipped": return "Omitida";
                case "failed": return "Falló";
                default: return "Sin resultado";
            }
        }
    }
}
