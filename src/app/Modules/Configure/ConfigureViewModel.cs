using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;
using IWinInstaller.App.Modules.Install;

namespace IWinInstaller.App.Modules.Configure
{
    /// <summary>Por configurar: apps instaladas que hay que configurar por dentro, con un check que se quita solo al actualizarse la app.</summary>
    public sealed class ConfigureViewModel : ObservableObject
    {
        private readonly EngineClient _engine;
        private readonly Func<IEnumerable<CatalogEntry>> _entries;
        private readonly Action _changed;
        private bool _isBusy;
        private string _message = "Pulsa «Comprobar» para ver qué apps instaladas necesitan configuración.";

        public ConfigureViewModel(EngineClient engine, Func<IEnumerable<CatalogEntry>> entries, Action changed)
        {
            _engine = engine; _entries = entries; _changed = changed;
            Items = new ObservableCollection<ConfigureItem>();
            RefreshCommand = new RelayCommand(_ => Reload(), _ => !IsBusy);
            ToggleCommand = new RelayCommand(p => { var ignored = ToggleAsync(p as ConfigureItem); }, _ => !IsBusy);
            OpenCommand = new RelayCommand(p => { var ignored = OpenAsync(p as ConfigureItem); }, _ => !IsBusy);
        }

        public ObservableCollection<ConfigureItem> Items { get; private set; }
        public RelayCommand RefreshCommand { get; private set; }
        public RelayCommand ToggleCommand { get; private set; }
        public RelayCommand OpenCommand { get; private set; }

        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }
        public string Message { get { return _message; } private set { Set(ref _message, value); } }
        public bool HasItems { get { return Items.Count > 0; } }

        /// <summary>Se llama al entrar en la página: relee qué está instalado y las versiones.</summary>
        public async void Reload()
        {
            if (IsBusy) return;
            IsBusy = true;
            Message = "Comprobando qué apps tienes instaladas y en qué versión…";
            try
            {
                var result = await _engine.RunAsync("configure.list", null, null, TimeSpan.FromMinutes(8), CancellationToken.None);
                if (!result.Ok) { Message = "No se pudo comprobar: " + (result.Error ?? "el motor no respondió."); return; }
                var byId = _entries().Where(e => e.ListedToConfigure).ToDictionary(e => e.Id);
                var items = new List<ConfigureItem>();
                object rows;
                if (result.Response.TryGetValue("items", out rows) && rows is object[])
                {
                    foreach (var row in ((object[])rows).OfType<Dictionary<string, object>>())
                    {
                        CatalogEntry entry;
                        if (!byId.TryGetValue(Read(row, "id"), out entry) || !ReadBool(row, "installed")) continue;
                        int steps;
                        Int32.TryParse(Read(row, "stepCount"), out steps);
                        items.Add(new ConfigureItem(entry) { Version = Read(row, "version"), StepCount = steps, Configured = ReadBool(row, "configured"), ReopenedFrom = Read(row, "reopenedFrom") });
                    }
                }
                Items.Clear();
                foreach (var item in items.OrderBy(i => i.Configured).ThenBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase)) Items.Add(item);
                OnPropertyChanged("HasItems");
                UpdateMessage();
            }
            finally { IsBusy = false; }
        }

        private void UpdateMessage()
        {
            int pending = Items.Count(i => !i.Configured);
            if (Items.Count == 0) Message = "Ninguna app instalada del catálogo necesita configuración.";
            else if (pending == 0) Message = "Todo configurado: " + Items.Count + (Items.Count == 1 ? " app." : " apps.") + " Si una se actualiza, volverá a salir aquí.";
            else Message = pending + (pending == 1 ? " app pendiente de configurar" : " apps pendientes de configurar") + " de " + Items.Count + " instaladas.";
        }

        private async Task ToggleAsync(ConfigureItem item)
        {
            if (item == null || IsBusy) return;
            IsBusy = true;
            try
            {
                bool target = !item.Configured;
                var steps = target ? Enumerable.Range(0, item.StepCount).ToArray() : new int[0];
                var request = new Dictionary<string, object> { { "id", item.Id }, { "steps", steps } };
                var result = await _engine.RunAsync("postinstall.set", request, null, TimeSpan.FromMinutes(1), CancellationToken.None);
                if (!result.Ok) { Message = "No se pudo guardar " + item.Name + ": " + (result.Error ?? "error del motor."); return; }
                item.Configured = ReadBool(result.Response, "configured");
                item.ReopenedFrom = "";
                UpdateMessage();
                if (_changed != null) _changed();
            }
            finally { IsBusy = false; }
        }

        private async Task OpenAsync(ConfigureItem item)
        {
            if (item == null) return;
            var result = await _engine.RunAsync("app.open", new Dictionary<string, object> { { "id", item.Id } }, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            Message = result.Ok ? Convert.ToString(result.Response["message"]) : "No se pudo abrir " + item.Name + ": " + (result.Error ?? "error del motor.");
        }

        private static string Read(Dictionary<string, object> row, string key)
        {
            object value;
            return row.TryGetValue(key, out value) && value != null ? Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) : "";
        }

        private static bool ReadBool(Dictionary<string, object> row, string key)
        {
            object value;
            return row.TryGetValue(key, out value) && value is bool && (bool)value;
        }
    }
}
