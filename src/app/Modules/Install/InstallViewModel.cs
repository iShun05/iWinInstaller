using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Data;
using System.Windows.Threading;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;
using IWinInstaller.App.Shell;

namespace IWinInstaller.App.Modules.Install
{
    /// <summary>Opción de un desplegable (clave interna y texto visible).</summary>
    public sealed class Choice
    {
        public Choice(string key, string label) { Key = key; Label = label; }
        public string Key { get; private set; }
        public string Label { get; private set; }
        public override string ToString() { return Label; }
    }

    /// <summary>Instalar: catálogo agrupado con búsqueda, filtros, perfiles, lotes reanudables y pasos de después de instalar.</summary>
    public sealed class InstallViewModel : ObservableObject
    {
        public const string CustomMark = "★ ";
        private readonly EngineClient _engine;
        private readonly Dispatcher _dispatcher;
        private readonly IDialogService _dialogs;
        private readonly Dictionary<string, CatalogItem> _byId;
        private bool _loaded, _isBusy, _hasPending;
        private string _search = "", _message = "Leyendo qué está instalado…", _progressText = "";
        private Choice _scope, _filter, _profile;
        private EngineOperation _operation;
        private GuideViewModel _guide;
        private ReportViewModel _report;
        private string _pendingPath;
        private bool _suspendProfile;

        public InstallViewModel(string root, EngineClient engine, Dispatcher dispatcher, IDialogService dialogs)
        {
            _engine = engine; _dispatcher = dispatcher; _dialogs = dialogs;
            var entries = CatalogEntry.Load(Path.Combine(root, "apps.json"));
            Items = new ObservableCollection<CatalogItem>(entries.Select(e => new CatalogItem(e) { IsChecked = false }));
            _byId = Items.ToDictionary(i => i.Id);
            View = CollectionViewSource.GetDefaultView(Items);
            View.GroupDescriptions.Add(new PropertyGroupDescription("GroupLabel"));
            View.Filter = o => Matches((CatalogItem)o);

            Scopes = new ObservableCollection<Choice> { new Choice("*", "Todo el catálogo") };
            foreach (var section in entries.Select(e => e.Section).Distinct())
            {
                Scopes.Add(new Choice("@" + section, section));
                foreach (var group in entries.Where(e => e.Section == section).Select(e => e.Group).Distinct()) Scopes.Add(new Choice(group, "   " + group));
            }
            Filters = new ObservableCollection<Choice> { new Choice("all", "Todas"), new Choice("checked", "Marcadas"), new Choice("missing", "Faltan"), new Choice("installed", "Instaladas"), new Choice("configure", "Por configurar") };
            Profiles = new ObservableCollection<Choice> { new Choice("Manual", "Manual") };
            _scope = Scopes[0]; _filter = Filters[0]; _profile = Profiles[0];

            InstallCommand = new RelayCommand(_ => Run(InstallSelectedAsync()), _ => !IsBusy && CheckedCount > 0);
            PauseCommand = new RelayCommand(_ => { if (_operation != null) { _operation.RequestPause(); Message = "Se pausará cuando termine esta aplicación. El resto quedará guardado."; } }, _ => IsBusy && _operation != null);
            ResumeCommand = new RelayCommand(_ => Run(ResumeAsync()), _ => !IsBusy && HasPending);
            UninstallCommand = new RelayCommand(p => Run(UninstallAsync(p as CatalogItem)), _ => !IsBusy);
            OpenCommand = new RelayCommand(p => Run(OpenAsync(p as CatalogItem)), _ => !IsBusy);
            GuideCommand = new RelayCommand(p => Run(OpenGuideAsync(p as CatalogItem)), _ => !IsBusy);
            CloseGuideCommand = new RelayCommand(_ => Run(CloseGuideAsync()));
            CheckGuideCommand = new RelayCommand(_ => Run(CheckGuideAsync()), _ => Guide != null);
            OpenGuideLinkCommand = new RelayCommand(_ => { if (Guide != null && Guide.HasLink) _dialogs.OpenUri(Guide.Link); });
            SaveProfileCommand = new RelayCommand(_ => Run(SaveProfileAsync()), _ => !IsBusy && CheckedCount > 0);
            ImportProfileCommand = new RelayCommand(_ => Run(ImportProfileAsync()), _ => !IsBusy);
            ExportProfileCommand = new RelayCommand(_ => Run(ExportProfileAsync()), _ => !IsBusy && CheckedCount > 0);
            ClearCommand = new RelayCommand(_ => { foreach (var item in Items) item.IsChecked = false; RefreshCounts(); }, _ => !IsBusy);
            CloseReportCommand = new RelayCommand(_ => Report = null);
            CopyReportCommand = new RelayCommand(_ => { if (Report != null) _dialogs.CopyText(Report.Text); Message = "Informe copiado: listo para pegar en un chat o un correo."; });
            RetryReportCommand = new RelayCommand(_ => Run(RetryAsync()), _ => !IsBusy && Report != null && Report.CanRetry);
            ShowLastReportCommand = new RelayCommand(_ => Run(ShowReportAsync(false)), _ => !IsBusy);
            VerifyCommand = new RelayCommand(_ => Run(LoadAsync()), _ => !IsBusy);
            UninstallSelectedCommand = new RelayCommand(_ => Run(UninstallSelectedAsync()), _ => !IsBusy && Items.Any(i => i.IsChecked && i.ShowUninstall));
            DeleteProfileCommand = new RelayCommand(_ => Run(DeleteProfileAsync()), _ => !IsBusy && _profile != null && _profile.Key.StartsWith(CustomMark, StringComparison.Ordinal));
            foreach (var item in Items) item.PropertyChanged += (s, e) => { if (e.PropertyName == "IsChecked") RefreshCounts(); };
        }

        public ObservableCollection<CatalogItem> Items { get; private set; }
        public ICollectionView View { get; private set; }
        public ObservableCollection<Choice> Scopes { get; private set; }
        public ObservableCollection<Choice> Filters { get; private set; }
        public ObservableCollection<Choice> Profiles { get; private set; }

        public RelayCommand InstallCommand { get; private set; }
        public RelayCommand PauseCommand { get; private set; }
        public RelayCommand ResumeCommand { get; private set; }
        public RelayCommand UninstallCommand { get; private set; }
        public RelayCommand OpenCommand { get; private set; }
        public RelayCommand GuideCommand { get; private set; }
        public RelayCommand CloseGuideCommand { get; private set; }
        public RelayCommand CheckGuideCommand { get; private set; }
        public RelayCommand OpenGuideLinkCommand { get; private set; }
        public RelayCommand SaveProfileCommand { get; private set; }
        public RelayCommand ImportProfileCommand { get; private set; }
        public RelayCommand ExportProfileCommand { get; private set; }
        public RelayCommand ClearCommand { get; private set; }
        public RelayCommand CloseReportCommand { get; private set; }
        public RelayCommand CopyReportCommand { get; private set; }
        public RelayCommand RetryReportCommand { get; private set; }
        public RelayCommand ShowLastReportCommand { get; private set; }
        public RelayCommand VerifyCommand { get; private set; }
        public RelayCommand UninstallSelectedCommand { get; private set; }
        public RelayCommand DeleteProfileCommand { get; private set; }

        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }
        public bool HasPending { get { return _hasPending; } private set { Set(ref _hasPending, value); } }
        public string Message { get { return _message; } set { Set(ref _message, value ?? ""); } }
        public string ProgressText { get { return _progressText; } private set { Set(ref _progressText, value ?? ""); } }
        public int CheckedCount { get { return Items.Count(i => i.IsChecked && !i.Installed); } }
        public string CountText { get { int n = CheckedCount; return n == 0 ? "Nada marcado" : n + (n == 1 ? " marcada para instalar" : " marcadas para instalar"); } }
        public GuideViewModel Guide { get { return _guide; } private set { if (Set(ref _guide, value)) OnPropertyChanged("HasGuide"); } }
        public bool HasGuide { get { return _guide != null; } }
        public ReportViewModel Report { get { return _report; } private set { if (Set(ref _report, value)) OnPropertyChanged("HasReport"); } }
        public bool HasReport { get { return _report != null; } }

        public string Search { get { return _search; } set { if (Set(ref _search, value ?? "")) View.Refresh(); } }
        public Choice Scope { get { return _scope; } set { if (value != null && Set(ref _scope, value)) View.Refresh(); } }
        public Choice Filter { get { return _filter; } set { if (value != null && Set(ref _filter, value)) View.Refresh(); } }
        public Choice Profile
        {
            get { return _profile; }
            set { if (value != null && Set(ref _profile, value) && !_suspendProfile) Run(ApplyProfileAsync(value)); }
        }

        /// <summary>Búsqueda por palabras: todas deben aparecer en nombre, descripción, grupo, comparativa o id.</summary>
        internal bool Matches(CatalogItem item)
        {
            var entry = item.Entry;
            if (_scope != null && _scope.Key != "*")
            {
                if (_scope.Key.StartsWith("@", StringComparison.Ordinal)) { if (entry.Section != _scope.Key.Substring(1)) return false; }
                else if (entry.Group != _scope.Key) return false;
            }
            switch (_filter == null ? "all" : _filter.Key)
            {
                case "checked": if (!item.IsChecked) return false; break;
                case "missing": if (!item.InventoryKnown || item.Installed) return false; break;
                case "installed": if (!item.Installed) return false; break;
                case "configure": if (!(item.Installed && item.NeedsConfiguration && !item.Configured)) return false; break;
            }
            if (String.IsNullOrWhiteSpace(_search)) return true;
            string text = entry.SearchText;
            return _search.ToLowerInvariant().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries).All(word => text.Contains(word));
        }

        public void EnsureLoaded()
        {
            if (_loaded) return;
            _loaded = true;
            IconLoader.Start(Items, _dispatcher);
            Run(LoadAsync());
        }

        private async Task LoadAsync()
        {
            IsBusy = true;
            try
            {
                var profiles = await _engine.RunAsync("profiles.list", null, null, TimeSpan.FromMinutes(1), CancellationToken.None);
                if (profiles.Ok) FillProfiles(profiles.Response);
                await RefreshPendingAsync();
                await RefreshConfiguredAsync();
                Message = "Leyendo qué está instalado…";
                var inventory = await _engine.RunAsync("catalog.inventory", null, null, TimeSpan.FromMinutes(8), CancellationToken.None);
                if (!inventory.Ok) { Message = "No se pudo leer qué está instalado: " + (inventory.Error ?? "el motor no respondió.") + " Puedes instalar igualmente."; return; }
                object rows;
                if (inventory.Response.TryGetValue("items", out rows) && rows is object[])
                {
                    foreach (var row in ((object[])rows).OfType<Dictionary<string, object>>())
                    {
                        CatalogItem item;
                        if (!_byId.TryGetValue(Convert.ToString(row["id"]), out item)) continue;
                        object installed;
                        item.Installed = row.TryGetValue("installed", out installed) && installed is bool && (bool)installed;
                        item.InventoryKnown = true;
                    }
                }
                int count = Items.Count(i => i.Installed);
                Message = count + " de " + Items.Count + " instaladas. Elige un perfil o marca lo que necesites.";
                View.Refresh();
            }
            finally { IsBusy = false; RefreshCounts(); }
        }

        private void FillProfiles(Dictionary<string, object> response)
        {
            _suspendProfile = true;
            try
            {
                Profiles.Clear();
                foreach (var name in ReadList(response, "builtIn")) Profiles.Add(new Choice(name, name));
                foreach (var name in ReadList(response, "custom")) Profiles.Add(new Choice(CustomMark + name, CustomMark + name));
                if (Profiles.Count == 0) Profiles.Add(new Choice("Manual", "Manual"));
                _profile = Profiles.FirstOrDefault(p => p.Key == "Manual") ?? Profiles[0];
                OnPropertyChanged("Profile");
            }
            finally { _suspendProfile = false; }
        }

        private async Task ApplyProfileAsync(Choice profile)
        {
            bool custom = profile.Key.StartsWith(CustomMark, StringComparison.Ordinal);
            string name = custom ? profile.Key.Substring(CustomMark.Length) : profile.Key;
            var result = await _engine.RunAsync("profiles.resolve", new Dictionary<string, object> { { "name", name }, { "custom", custom } }, null, TimeSpan.FromMinutes(2), CancellationToken.None);
            if (!result.Ok) { Message = "No se pudo aplicar el perfil: " + result.Error; return; }
            var ids = new HashSet<string>(ReadList(result.Response, "ids"));
            foreach (var item in Items) item.IsChecked = ids.Contains(item.Id) && !item.Installed;
            Message = ids.Count == 0 ? "Perfil Manual: marca lo que quieras instalar." : "Perfil «" + name + "»: " + CheckedCount + " por instalar (las ya instaladas no se marcan).";
            View.Refresh();
        }

        private async Task InstallSelectedAsync()
        {
            var selection = Items.Where(i => i.IsChecked && !i.Installed).Select(i => i.Id).ToArray();
            if (selection.Length == 0) return;
            await RunBatchAsync("install", selection, null);
        }

        private async Task RunBatchAsync(string operation, string[] ids, string resumePath)
        {
            IsBusy = true;
            try
            {
                if (resumePath == null && !await ConfirmPlanAsync(operation, ids)) return;
                _operation = new EngineOperation();
                int total = Math.Max(1, ids.Length), done = 0;
                ProgressText = "0/" + total;
                bool removing = operation == "uninstall";
                var request = new Dictionary<string, object> { { "operation", operation }, { "ids", ids } };
                if (resumePath != null) request["resume"] = resumePath;
                Message = removing ? "Desinstalando…" : "Instalando… Puedes pausar al terminar la aplicación actual.";
                var result = await _engine.RunAsync("batch.run", request, e => _dispatcher.BeginInvoke(new Action(() =>
                {
                    CatalogItem item;
                    if (e.Id == null || !_byId.TryGetValue(e.Id, out item)) return;
                    if (e.Type == "item")
                    {
                        done++;
                        if (done > total) total = done;
                        item.ApplyOutcome(e.Outcome, e.Installed ?? item.Installed, e.PreviousState ?? item.HasPreviousState, removing);
                        ProgressText = done + "/" + total;
                        Message = item.Name + " · " + item.Status + " · " + done + "/" + total;
                    }
                })), TimeSpan.FromHours(4), CancellationToken.None, _operation);
                await _dispatcher.InvokeAsync(() => { });
                if (!result.Ok) { Message = "El lote no terminó: " + (result.Error ?? "error del motor.") + " Lo pendiente queda guardado para reanudar."; }
                else
                {
                    var failed = ReadList(result.Response, "failed").ToList();
                    bool paused = ReadBool(result.Response, "paused");
                    Message = paused ? "Lote pausado. Reanuda cuando quieras; no se interrumpió la aplicación en curso."
                        : failed.Count > 0 ? "Quedan " + failed.Count + " pendientes: el informe explica cada una."
                        : removing ? "Desinstalación terminada." : "Instalación terminada.";
                    if (ReadList(result.Response, "rebootPending").Any()) Message += " Hay cambios que requieren reiniciar Windows.";
                    if (ReadBool(result.Response, "hasReport")) await ShowReportAsync(true);
                }
                await RefreshPendingAsync();
                await RefreshConfiguredAsync();
                View.Refresh();
            }
            finally { _operation = null; ProgressText = ""; IsBusy = false; RefreshCounts(); }
        }

        private async Task<bool> ConfirmPlanAsync(string operation, string[] ids)
        {
            var result = await _engine.RunAsync("install.preflight", new Dictionary<string, object> { { "operation", operation }, { "ids", ids } }, null, TimeSpan.FromMinutes(2), CancellationToken.None);
            if (!result.Ok) { Message = "No se pudo preparar el lote: " + result.Error; return false; }
            var lines = new List<string>();
            object plan;
            if (result.Response.TryGetValue("plan", out plan) && plan is object[])
            {
                foreach (var row in ((object[])plan).OfType<Dictionary<string, object>>())
                {
                    string line = "• " + Convert.ToString(row["name"]) + " · " + (Convert.ToString(row["context"]) == "machine" ? "administrador" : "tu usuario");
                    if (ReadBool(row, "tweak")) line += " · ajuste de Windows";
                    if (ReadBool(row, "restart")) line += " · reinicio o nueva sesión";
                    if (ReadBool(row, "interactive")) line += " · abre su asistente";
                    lines.Add(line);
                }
            }
            string text = Convert.ToString(result.Response["text"]) + Environment.NewLine + Environment.NewLine + String.Join(Environment.NewLine, lines) +
                          Environment.NewLine + Environment.NewLine + "Puedes pausar entre aplicaciones. No se reinicia Windows automáticamente.";
            if (!ReadBool(result.Response, "ok")) { _dialogs.Inform("Revisa el equipo antes de continuar", text); return false; }
            return _dialogs.Confirm(operation == "uninstall" ? "Antes de desinstalar" : "Antes de instalar", text, operation == "uninstall" ? "Desinstalar" : "Continuar");
        }

        private async Task ResumeAsync()
        {
            await RefreshPendingAsync();
            if (_pendingPath == null) return;
            await RunBatchAsync("install", new string[0], _pendingPath);
        }

        private async Task UninstallAsync(CatalogItem item)
        {
            if (item == null) return;
            await RunBatchAsync("uninstall", new[] { item.Id }, null);
        }

        /// <summary>Desinstala (o deshace) las marcadas que están instaladas, en un solo lote con confirmación.</summary>
        private async Task UninstallSelectedAsync()
        {
            var ids = Items.Where(i => i.IsChecked && i.ShowUninstall).Select(i => i.Id).ToArray();
            if (ids.Length > 0) await RunBatchAsync("uninstall", ids, null);
        }

        private async Task DeleteProfileAsync()
        {
            if (_profile == null || !_profile.Key.StartsWith(CustomMark, StringComparison.Ordinal)) return;
            string name = _profile.Key.Substring(CustomMark.Length);
            if (!_dialogs.Confirm("Eliminar perfil", "Se borra el perfil «" + name + "». Las apps instaladas no cambian.", "Eliminar")) return;
            var result = await _engine.RunAsync("profiles.delete", new Dictionary<string, object> { { "name", name } }, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (!result.Ok) { Message = "No se pudo eliminar: " + result.Error; return; }
            var profiles = await _engine.RunAsync("profiles.list", null, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (profiles.Ok) FillProfiles(profiles.Response);
            Message = "Perfil «" + name + "» eliminado.";
        }

        private async Task OpenAsync(CatalogItem item)
        {
            if (item == null) return;
            var result = await _engine.RunAsync("app.open", new Dictionary<string, object> { { "id", item.Id } }, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            Message = result.Ok ? Convert.ToString(result.Response["message"]) : "No se pudo abrir " + item.Name + ": " + result.Error;
        }

        private async Task RefreshPendingAsync()
        {
            var result = await _engine.RunAsync("batch.pending", null, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            _pendingPath = null;
            object batches;
            if (result.Ok && result.Response.TryGetValue("batches", out batches) && batches is object[])
            {
                var first = ((object[])batches).OfType<Dictionary<string, object>>().FirstOrDefault();
                if (first != null) _pendingPath = Convert.ToString(first["path"]);
            }
            HasPending = _pendingPath != null;
        }

        private async Task RefreshConfiguredAsync()
        {
            var result = await _engine.RunAsync("postinstall.get", null, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (!result.Ok) return;
            object guides;
            if (!result.Response.TryGetValue("guides", out guides) || !(guides is object[])) return;
            foreach (var row in ((object[])guides).OfType<Dictionary<string, object>>())
            {
                CatalogItem item;
                if (_byId.TryGetValue(Convert.ToString(row["id"]), out item)) item.Configured = ReadBool(row, "configured");
            }
        }

        private async Task OpenGuideAsync(CatalogItem item)
        {
            if (item == null) return;
            await CloseGuideAsync();
            var result = await _engine.RunAsync("postinstall.get", new Dictionary<string, object> { { "ids", new[] { item.Id } } }, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (!result.Ok) { Message = "No se pudieron leer los pasos: " + result.Error; return; }
            object guides;
            var row = result.Response.TryGetValue("guides", out guides) && guides is object[] ? ((object[])guides).OfType<Dictionary<string, object>>().FirstOrDefault() : null;
            if (row == null) { Message = item.Name + " no tiene pasos de después de instalar."; return; }
            var guide = new GuideViewModel(item.Id, item.Name, ReadList(row, "steps"), ReadList(row, "done").Select(d => Int32.Parse(d, System.Globalization.CultureInfo.InvariantCulture)),
                Convert.ToString(row["note"]), Convert.ToString(row["link"]), Convert.ToString(row["linkLabel"]), Convert.ToString(row["userNote"]));
            foreach (var step in guide.Steps) step.PropertyChanged += (s, e) => guide.Refresh();
            Guide = guide;
        }

        /// <summary>Al cerrar «Pasos y notas» se guardan los pasos marcados y la nota.</summary>
        private async Task CloseGuideAsync()
        {
            var guide = Guide;
            if (guide == null) return;
            Guide = null;
            var request = new Dictionary<string, object> { { "id", guide.Id }, { "steps", guide.DoneIndexes }, { "note", guide.UserNote } };
            var result = await _engine.RunAsync("postinstall.set", request, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (!result.Ok) { Message = "No se pudieron guardar los pasos de " + guide.Name + ": " + result.Error; return; }
            CatalogItem item;
            if (_byId.TryGetValue(guide.Id, out item)) item.Configured = ReadBool(result.Response, "configured");
            View.Refresh();
        }

        private async Task CheckGuideAsync()
        {
            var guide = Guide;
            if (guide == null) return;
            guide.Technical = "Comprobando…";
            var result = await _engine.RunAsync("postinstall.check", new Dictionary<string, object> { { "id", guide.Id } }, null, TimeSpan.FromMinutes(2), CancellationToken.None);
            guide.TechnicalOk = result.Ok && ReadBool(result.Response, "ok");
            guide.Technical = result.Ok ? Convert.ToString(result.Response["text"]) : "No se pudo comprobar: " + result.Error;
        }

        private async Task SaveProfileAsync()
        {
            string suggestion = _profile != null && _profile.Key.StartsWith(CustomMark, StringComparison.Ordinal) ? _profile.Key.Substring(CustomMark.Length) : "Mi PC " + DateTime.Now.ToString("yyyy-MM-dd");
            string name = _dialogs.Ask("Guardar perfil", "Nombre del perfil (se guardan las apps marcadas):", suggestion);
            if (String.IsNullOrWhiteSpace(name)) return;
            var ids = Items.Where(i => i.IsChecked).Select(i => i.Id).ToArray();
            var result = await _engine.RunAsync("profiles.save", new Dictionary<string, object> { { "name", name }, { "ids", ids } }, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (!result.Ok) { Message = "No se pudo guardar: " + result.Error; return; }
            Message = "Perfil «" + Convert.ToString(result.Response["name"]) + "» guardado con " + ids.Length + " apps.";
            var profiles = await _engine.RunAsync("profiles.list", null, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (profiles.Ok) FillProfiles(profiles.Response);
        }

        private async Task ImportProfileAsync()
        {
            string path = _dialogs.OpenFile("Perfil de iWinInstaller (*.iwin.json)|*.iwin.json|JSON (*.json)|*.json");
            if (path == null) return;
            var result = await _engine.RunAsync("profiles.import", new Dictionary<string, object> { { "path", path } }, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (!result.Ok) { Message = "No se pudo importar: " + result.Error; return; }
            var ids = new HashSet<string>(ReadList(result.Response, "ids"));
            foreach (var item in Items) item.IsChecked = ids.Contains(item.Id) && !item.Installed;
            Message = "Perfil importado: " + CheckedCount + " por instalar.";
            View.Refresh();
        }

        private async Task ExportProfileAsync()
        {
            string path = _dialogs.SaveFile("Perfil de iWinInstaller (*.iwin.json)|*.iwin.json", "Mi PC.iwin.json");
            if (path == null) return;
            var ids = Items.Where(i => i.IsChecked).Select(i => i.Id).ToArray();
            string name = Path.GetFileNameWithoutExtension(Path.GetFileNameWithoutExtension(path));
            var result = await _engine.RunAsync("profiles.export", new Dictionary<string, object> { { "path", path }, { "name", name }, { "ids", ids } }, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            Message = result.Ok ? "Perfil exportado: llévalo a otro PC y pulsa Importar." : "No se pudo exportar: " + result.Error;
        }

        private async Task ShowReportAsync(bool afterBatch)
        {
            var result = await _engine.RunAsync("report.last", null, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            var report = result.Ok ? ReportViewModel.FromResponse(result.Response) : null;
            if (report == null) { if (!afterBatch) Message = "Todavía no hay informe de instalación."; return; }
            Report = report;
        }

        private async Task RetryAsync()
        {
            var report = Report;
            if (report == null) return;
            Report = null;
            await RunBatchAsync("install", report.RetryIds, null);
        }

        private void RefreshCounts() { OnPropertyChanged("CheckedCount"); OnPropertyChanged("CountText"); }

        private void Run(Task task)
        {
            task.ContinueWith(t => _dispatcher.BeginInvoke(new Action(() => { IsBusy = false; Message = "Error inesperado: " + t.Exception.GetBaseException().Message; App.Log("Instalar: " + t.Exception); })),
                CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.Default);
        }

        internal static IEnumerable<string> ReadList(Dictionary<string, object> data, string key)
        {
            object value;
            if (data == null || !data.TryGetValue(key, out value) || value == null) return Enumerable.Empty<string>();
            var list = value as object[];
            if (list != null) return list.Where(v => v != null).Select(v => Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture));
            return new[] { Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) };
        }

        internal static bool ReadBool(Dictionary<string, object> data, string key)
        {
            object value;
            return data != null && data.TryGetValue(key, out value) && value is bool && (bool)value;
        }
    }
}
