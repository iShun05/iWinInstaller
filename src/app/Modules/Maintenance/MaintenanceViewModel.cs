using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;
using IWinInstaller.App.Probes;
using IWinInstaller.App.Shell;

namespace IWinInstaller.App.Modules.Maintenance
{
    /// <summary>Una categoría de limpieza: estimación antes de borrar y resultado después.</summary>
    public sealed class CleanupCategory : ObservableObject
    {
        private bool _isSelected = true;
        private long _estimated;
        private string _result = "";
        public string Id { get; set; }
        public string Label { get; set; }
        public bool Admin { get; set; }
        public bool IsSelected { get { return _isSelected; } set { Set(ref _isSelected, value); } }
        public long Estimated { get { return _estimated; } set { if (Set(ref _estimated, value)) OnPropertyChanged("EstimatedText"); } }
        public string EstimatedText { get { return MaintenanceViewModel.FormatBytes(_estimated) + (Admin ? " · pide permiso" : ""); } }
        public string Result { get { return _result; } set { Set(ref _result, value ?? ""); } }
    }

    /// <summary>Mantenimiento y salud: limpieza segura, reparación de Windows, salud del equipo e informe exportable.</summary>
    public sealed class MaintenanceViewModel : ObservableObject
    {
        private readonly EngineClient _engine;
        private readonly IDialogService _dialogs;
        private bool _isBusy, _loaded, _includeSensitive;
        private string _message = "", _health = "", _total = "";

        public MaintenanceViewModel(EngineClient engine, IDialogService dialogs)
        {
            _engine = engine; _dialogs = dialogs;
            Categories = new ObservableCollection<CleanupCategory>();
            EstimateCommand = new RelayCommand(_ => Run(EstimateAsync()), _ => !IsBusy);
            CleanCommand = new RelayCommand(_ => Run(CleanAsync()), _ => !IsBusy && Categories.Any(c => c.IsSelected && c.Estimated > 0));
            RepairCommand = new RelayCommand(_ => Run(RepairAsync()), _ => !IsBusy);
            ReportCommand = new RelayCommand(_ => Run(ReportAsync()), _ => !IsBusy);
            BatteryReportCommand = new RelayCommand(_ => Run(BatteryReportAsync()), _ => !IsBusy);
        }

        public ObservableCollection<CleanupCategory> Categories { get; private set; }
        public RelayCommand EstimateCommand { get; private set; }
        public RelayCommand CleanCommand { get; private set; }
        public RelayCommand RepairCommand { get; private set; }
        public RelayCommand ReportCommand { get; private set; }
        public RelayCommand BatteryReportCommand { get; private set; }
        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }
        public string Message { get { return _message; } private set { Set(ref _message, value ?? ""); } }
        public string Health { get { return _health; } private set { Set(ref _health, value ?? ""); } }
        public string Total { get { return _total; } private set { Set(ref _total, value ?? ""); } }
        public bool IncludeSensitive { get { return _includeSensitive; } set { Set(ref _includeSensitive, value); } }

        public static string FormatBytes(long bytes)
        {
            if (bytes < 1048576) return (bytes / 1024.0).ToString("0", CultureInfo.GetCultureInfo("es-ES")) + " KB";
            if (bytes < 1073741824) return (bytes / 1048576.0).ToString("0.#", CultureInfo.GetCultureInfo("es-ES")) + " MB";
            return (bytes / 1073741824.0).ToString("0.##", CultureInfo.GetCultureInfo("es-ES")) + " GB";
        }

        public void EnsureLoaded()
        {
            if (_loaded) return;
            _loaded = true;
            Run(LoadHealthAsync());
            Run(EstimateAsync());
        }

        private async Task LoadHealthAsync()
        {
            var results = await Task.Run(() => new[] { SystemProbes.DiskSpace(), SystemProbes.DiskHealth(), SystemProbes.Battery(), SystemProbes.Reboot() });
            string[] titles = { "Espacio", "Discos", "Batería", "Reinicio" };
            Health = String.Join(Environment.NewLine, results.Select((r, i) => r.State == StatusState.NotApplicable ? null
                : titles[i] + ": " + r.Summary + (String.IsNullOrEmpty(r.Reason) ? "" : " · " + r.Reason)).Where(l => l != null));
        }

        private async Task EstimateAsync()
        {
            IsBusy = true;
            Message = "Calculando cuánto se puede liberar…";
            try
            {
                var result = await _engine.RunAsync("maintenance.estimate", null, null, TimeSpan.FromMinutes(10), CancellationToken.None);
                if (!result.Ok) { Message = "No se pudo calcular: " + result.Error; return; }
                var selected = Categories.Where(c => !c.IsSelected).Select(c => c.Id).ToList();
                Categories.Clear();
                foreach (var row in Rows(result.Response, "categories"))
                {
                    Categories.Add(new CleanupCategory
                    {
                        Id = Text(row, "id"), Label = Text(row, "label"), Admin = Flag(row, "admin"),
                        Estimated = Convert.ToInt64(row["estimatedBytes"], CultureInfo.InvariantCulture),
                        IsSelected = !selected.Contains(Text(row, "id"))
                    });
                }
                Total = "Se pueden liberar unos " + FormatBytes(Categories.Sum(c => c.Estimated)) + ". Solo se borran archivos temporales y cachés de más de un día; nunca documentos.";
                Message = "";
            }
            finally { IsBusy = false; }
        }

        private async Task CleanAsync()
        {
            var chosen = Categories.Where(c => c.IsSelected && c.Estimated > 0).ToList();
            if (chosen.Count == 0) return;
            if (!_dialogs.Confirm("Liberar espacio", "Se borrarán unos " + FormatBytes(chosen.Sum(c => c.Estimated)) + " de:" + Environment.NewLine +
                String.Join(Environment.NewLine, chosen.Select(c => "• " + c.Label + " · " + FormatBytes(c.Estimated))) + Environment.NewLine + Environment.NewLine +
                "Los archivos en uso se omiten. La papelera, si la marcas, se vacía y no se puede recuperar.", "Liberar")) return;
            IsBusy = true;
            Message = "Liberando espacio…";
            try
            {
                var request = new Dictionary<string, object> { { "categories", chosen.Select(c => c.Id).ToArray() } };
                var result = await _engine.RunAsync("maintenance.clean", request, null, TimeSpan.FromMinutes(30), CancellationToken.None);
                if (!result.Ok) { Message = "No se pudo limpiar: " + result.Error; return; }
                long freed = 0;
                foreach (var row in Rows(result.Response, "categories"))
                {
                    var category = Categories.FirstOrDefault(c => c.Id == Text(row, "id"));
                    long bytes = Convert.ToInt64(row["freedBytes"], CultureInfo.InvariantCulture);
                    freed += bytes;
                    if (category != null)
                        category.Result = Flag(row, "denied") ? "No se aceptó el permiso" : FormatBytes(bytes) + " liberados" + (Convert.ToInt32(row["skippedFiles"], CultureInfo.InvariantCulture) > 0 ? " · " + row["skippedFiles"] + " en uso omitidos" : "");
                }
                Message = "Listo: " + FormatBytes(freed) + " liberados.";
            }
            finally { IsBusy = false; }
            await EstimateAsync();
        }

        private async Task RepairAsync()
        {
            if (!_dialogs.Confirm("Reparar Windows", "Se ejecutan DISM (repara la imagen de Windows, puede descargar archivos de Windows Update) y SFC (comprueba los archivos del sistema). Tarda entre 10 y 40 minutos y pide permiso de administrador. Puedes seguir usando el PC.", "Reparar")) return;
            IsBusy = true;
            Message = "Reparando Windows… (DISM y SFC, puede tardar)";
            try
            {
                var result = await _engine.RunAsync("maintenance.repair", null, null, TimeSpan.FromHours(2), CancellationToken.None);
                Message = result.Ok ? Text(result.Response, "text") : "No se pudo reparar: " + result.Error;
            }
            finally { IsBusy = false; }
        }

        private async Task ReportAsync()
        {
            string path = _dialogs.SaveFile("Informe del equipo (*.json)|*.json", "Informe del equipo " + DateTime.Now.ToString("yyyy-MM-dd") + ".json");
            if (path == null) return;
            IsBusy = true;
            try
            {
                var result = await _engine.RunAsync("report.machine", new Dictionary<string, object> { { "path", path }, { "includeSensitive", IncludeSensitive } }, null, TimeSpan.FromMinutes(3), CancellationToken.None);
                Message = result.Ok ? "Informe guardado" + (IncludeSensitive ? " con números de serie." : " sin números de serie, nombre del equipo ni usuario.") : "No se pudo crear: " + result.Error;
                if (result.Ok && File.Exists(path)) Process.Start("explorer.exe", "/select,\"" + path + "\"");
            }
            finally { IsBusy = false; }
        }

        /// <summary>Informe detallado de la batería que genera Windows (powercfg).</summary>
        private async Task BatteryReportAsync()
        {
            string path = Path.Combine(Path.GetTempPath(), "iwin-bateria-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".html");
            int code = await Task.Run(() =>
            {
                var start = new ProcessStartInfo("powercfg.exe", "/batteryreport /output \"" + path + "\"") { UseShellExecute = false, CreateNoWindow = true };
                using (var process = Process.Start(start)) { process.WaitForExit(60000); return process.HasExited ? process.ExitCode : -1; }
            });
            if (code == 0 && File.Exists(path)) { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); Message = "Informe de batería abierto en el navegador."; }
            else Message = "Este equipo no tiene batería o Windows no pudo generar el informe.";
        }

        private void Run(Task task)
        {
            task.ContinueWith(t => { IsBusy = false; Message = "Error inesperado: " + t.Exception.GetBaseException().Message; },
                CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.FromCurrentSynchronizationContext());
        }

        private static IEnumerable<Dictionary<string, object>> Rows(Dictionary<string, object> data, string key)
        {
            object value;
            return data != null && data.TryGetValue(key, out value) && value is object[] ? ((object[])value).OfType<Dictionary<string, object>>() : Enumerable.Empty<Dictionary<string, object>>();
        }
        private static string Text(Dictionary<string, object> data, string key) { object v; return data.TryGetValue(key, out v) && v != null ? Convert.ToString(v, CultureInfo.InvariantCulture) : ""; }
        private static bool Flag(Dictionary<string, object> data, string key) { object v; return data.TryGetValue(key, out v) && v is bool && (bool)v; }
    }
}
