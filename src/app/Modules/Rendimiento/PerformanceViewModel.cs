using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using IWinInstaller.App.Core;
using IWinInstaller.App.Modules.Games;
using IWinInstaller.App.Shell;

namespace IWinInstaller.App.Modules.Rendimiento
{
    /// <summary>Una acción de rendimiento con su estado y sus botones Aplicar y Deshacer.</summary>
    public sealed class PerfActionRow : ObservableObject
    {
        private bool _applied, _available = true, _canUndo;
        private string _detail = "", _result = "";

        public PerfActionRow(PerfAction action) { Action = action; }
        public PerfAction Action { get; private set; }
        public string Title { get { return Action.Title; } }
        public string Description { get { return Action.Description; } }
        public bool IsApplied { get { return _applied; } private set { if (Set(ref _applied, value)) { OnPropertyChanged("StateLabel"); OnPropertyChanged("CanApply"); } } }
        public bool IsAvailable { get { return _available; } private set { if (Set(ref _available, value)) OnPropertyChanged("CanApply"); } }
        public bool CanUndo { get { return _canUndo; } private set { Set(ref _canUndo, value); } }
        public bool CanApply { get { return _available && !_applied; } }
        public string Detail { get { return _detail; } private set { Set(ref _detail, value ?? ""); OnPropertyChanged("HasDetail"); } }
        public bool HasDetail { get { return _detail.Length > 0; } }
        public string Result { get { return _result; } set { Set(ref _result, value ?? ""); OnPropertyChanged("HasResult"); } }
        public bool HasResult { get { return _result.Length > 0; } }
        public string StateLabel { get { return !_available ? "No disponible" : _applied ? "Activo" : "Sin aplicar"; } }

        public void Apply(PerfStatus status)
        {
            IsApplied = status.Applied; IsAvailable = status.Available; CanUndo = status.CanUndo; Detail = status.Detail;
        }
    }

    public sealed class HeavyAppRow
    {
        public HeavyAppRow(HeavyApp app) { App = app; }
        public HeavyApp App { get; private set; }
        public string Name { get { return App.Name + (App.Instances > 1 ? " (" + App.Instances + " procesos)" : ""); } }
        public string Memory { get { return App.Mb.ToString(CultureInfo.CurrentCulture) + " MB"; } }
    }

    /// <summary>Un juego del perfil con sus cuatro opciones.</summary>
    public sealed class ProfileRow : ObservableObject
    {
        private readonly ProfileOptions _options;
        private readonly Action _changed;

        public ProfileRow(ProfileTarget target, ProfileOptions options, Action changed) { Target = target; _options = options; _changed = changed; }
        public ProfileTarget Target { get; private set; }
        public string Title { get { return Target.Title; } }
        public bool IsCustom { get { return Target.Custom; } }
        public ProfileOptions Options { get { return _options; } }
        public bool Priority { get { return _options.Priority; } set { _options.Priority = value; OnPropertyChanged(); _changed(); } }
        public bool PowerPlan { get { return _options.PowerPlan; } set { _options.PowerPlan = value; OnPropertyChanged(); _changed(); } }
        public bool CloseOverlays { get { return _options.CloseOverlays; } set { _options.CloseOverlays = value; OnPropertyChanged(); _changed(); } }
        public bool CloseBrowsers { get { return _options.CloseBrowsers; } set { _options.CloseBrowsers = value; OnPropertyChanged(); _changed(); } }
    }

    /// <summary>
    /// Página Rendimiento: acciones reversibles que se aplican desde la app, apps pesadas que se pueden cerrar, mediciones antes y después,
    /// perfil de juego (cierra distracciones y sube la prioridad mientras juegas; todo se restaura al salir) y aviso de temperaturas.
    /// El perfil solo vigila si el usuario activa el interruptor; sin él no hay temporizadores en marcha.
    /// </summary>
    public sealed class PerformanceViewModel : ObservableObject
    {
        private readonly Dispatcher _dispatcher;
        private readonly IDialogService _dialogs;
        private readonly Action<string> _runAction;
        private readonly Action<string> _searchInstall;
        private readonly IPerfHost _host;
        private readonly PerfStore _store;
        private readonly PerfService _service;
        private readonly GameProfileEngine _engine;
        private readonly IThermalSource _thermalSource;
        private readonly ProfileSettings _settings;
        private DispatcherTimer _monitor, _thermalTimer;
        private ThermalTracker _tracker;
        private bool _ticking, _sampling, _loaded, _measureBusy;
        private bool _measureAround = true;
        private PerfSnapshot _baseline;
        private string _measureStatus = "", _sessionText = "Sin juego en marcha.", _thermalAlert = "", _customName = "", _heavyNote = "", _frameNote = "";
        private CancellationTokenSource _measureCts;

        public PerformanceViewModel(IGameEnvironment env, IPerfHost host, IThermalSource thermalSource, Dispatcher dispatcher, IDialogService dialogs,
            Action<string> runAction, Action<string> searchInstall)
        {
            _host = host; _thermalSource = thermalSource; _dispatcher = dispatcher; _dialogs = dialogs; _runAction = runAction; _searchInstall = searchInstall;
            _store = new PerfStore(PerfStore.DefaultRoot(env.LocalAppData));
            _service = new PerfService(env, host, _store);
            _engine = new GameProfileEngine(host, _store);
            _settings = _store.LoadSettings();
            _engine.Log += text => _dispatcher.BeginInvoke(new Action(() => AddLog(text)));
            _engine.Activated += session => _dispatcher.BeginInvoke(new Action(() => OnActivated(session)));
            _engine.Restored += session => _dispatcher.BeginInvoke(new Action(() => OnRestored(session)));

            Actions = new ObservableCollection<PerfActionRow>(PerfCatalog.All.Select(a => new PerfActionRow(a)));
            Heavy = new ObservableCollection<HeavyAppRow>();
            Profiles = new ObservableCollection<ProfileRow>();
            Compare = new ObservableCollection<CompareLine>();
            Log = new ObservableCollection<string>();
            Thermal = new ObservableCollection<string>();
            History = new ObservableCollection<string>();
            RebuildProfiles();

            ApplyCommand = new RelayCommand(p => { var row = p as PerfActionRow; if (row != null) RunAction(row, true); }, _ => !_measureBusy);
            UndoCommand = new RelayCommand(p => { var row = p as PerfActionRow; if (row != null) RunAction(row, false); }, _ => !_measureBusy);
            RefreshCommand = new RelayCommand(_ => Refresh());
            CloseAppCommand = new RelayCommand(p => CloseHeavy(p as HeavyAppRow));
            MeasureCommand = new RelayCommand(_ => { var ignored = MeasureNowAsync(); }, _ => !_measureBusy);
            CancelMeasureCommand = new RelayCommand(_ => { var cts = _measureCts; if (cts != null) cts.Cancel(); }, _ => _measureBusy);
            AddCustomCommand = new RelayCommand(_ => AddCustom());
            RemoveCustomCommand = new RelayCommand(p => RemoveCustom(p as ProfileRow));
            OpenCommand = new RelayCommand(p => { var id = p as string; if (!string.IsNullOrEmpty(id)) _runAction(id); });
            InstallFrameToolCommand = new RelayCommand(_ => { if (_searchInstall != null) _searchInstall("CapFrameX"); });
            ClearHistoryCommand = new RelayCommand(_ => { _store.ClearThermal(); LoadThermal(); });
        }

        public ObservableCollection<PerfActionRow> Actions { get; private set; }
        public ObservableCollection<HeavyAppRow> Heavy { get; private set; }
        public ObservableCollection<ProfileRow> Profiles { get; private set; }
        public ObservableCollection<CompareLine> Compare { get; private set; }
        public ObservableCollection<string> Log { get; private set; }
        public ObservableCollection<string> Thermal { get; private set; }
        public ObservableCollection<string> History { get; private set; }
        public RelayCommand ApplyCommand { get; private set; }
        public RelayCommand UndoCommand { get; private set; }
        public RelayCommand RefreshCommand { get; private set; }
        public RelayCommand CloseAppCommand { get; private set; }
        public RelayCommand MeasureCommand { get; private set; }
        public RelayCommand CancelMeasureCommand { get; private set; }
        public RelayCommand AddCustomCommand { get; private set; }
        public RelayCommand RemoveCustomCommand { get; private set; }
        public RelayCommand OpenCommand { get; private set; }
        public RelayCommand InstallFrameToolCommand { get; private set; }
        public RelayCommand ClearHistoryCommand { get; private set; }

        public bool MeasureAround { get { return _measureAround; } set { Set(ref _measureAround, value); } }
        public bool IsMeasuring { get { return _measureBusy; } }
        public string MeasureStatus { get { return _measureStatus; } private set { Set(ref _measureStatus, value ?? ""); } }
        public string SessionText { get { return _sessionText; } private set { Set(ref _sessionText, value); } }
        public string ThermalAlert { get { return _thermalAlert; } private set { Set(ref _thermalAlert, value ?? ""); OnPropertyChanged("HasThermalAlert"); } }
        public bool HasThermalAlert { get { return _thermalAlert.Length > 0; } }
        public string HeavyNote { get { return _heavyNote; } private set { Set(ref _heavyNote, value ?? ""); } }
        public string FrameNote { get { return _frameNote; } private set { Set(ref _frameNote, value ?? ""); } }
        public bool HasCompare { get { return Compare.Count > 0; } }
        public string CustomName { get { return _customName; } set { Set(ref _customName, value ?? ""); } }

        /// <summary>Interruptor general del perfil de juego y de los avisos térmicos. Apagado por defecto.</summary>
        public bool MonitorEnabled
        {
            get { return _settings.Enabled; }
            set
            {
                if (_settings.Enabled == value) return;
                _settings.Enabled = value;
                _store.SaveSettings(_settings);
                OnPropertyChanged();
                if (value) StartMonitor(); else StopMonitor(true);
            }
        }

        // ---------- Ciclo de vida ----------

        /// <summary>Al abrir la app: recupera una sesión que quedó a medias y, si el usuario lo activó, empieza a vigilar.</summary>
        public void Start()
        {
            Task.Run(() =>
            {
                try { _engine.RecoverStale(); }
                catch (Exception e) when (e is InvalidOperationException || e is System.ComponentModel.Win32Exception || e is System.IO.IOException) { }
            }).ContinueWith(_ => _dispatcher.BeginInvoke(new Action(() => { if (_settings.Enabled) StartMonitor(); })), TaskScheduler.Default);
        }

        /// <summary>Al cerrar la app: restaura el perfil si había uno activo y no deja temporizadores.</summary>
        public void Shutdown()
        {
            StopMonitor(false);
            if (_measureCts != null) _measureCts.Cancel();
            try { if (_engine.Active != null) _engine.Restore(); }
            catch (Exception e) when (e is InvalidOperationException || e is System.ComponentModel.Win32Exception || e is System.IO.IOException) { }
            var disposable = _thermalSource as IDisposable;
            if (disposable != null) disposable.Dispose();
        }

        /// <summary>Al entrar en la página: lee el estado de las acciones y las apps pesadas.</summary>
        public void EnsureLoaded()
        {
            if (!_loaded) { _loaded = true; LoadHistory(); }
            Refresh();
            LoadThermal();
            FrameNote = FrameStats.FindPresentMon() != null
                ? "PresentMon detectado: se capturan frametimes del juego en marcha al medir."
                : "Sin PresentMon: se mide la latencia del planificador y el ping. Para frametimes y 1 % low instala CapFrameX (incluye PresentMon).";
        }

        private void Refresh()
        {
            Task.Run(() =>
            {
                var statuses = PerfCatalog.All.ToDictionary(a => a.Id, a => SafeStatus(a));
                var heavy = HeavyApps.Find(_host.Processes(), 150, 8);
                return Tuple.Create(statuses, heavy);
            }).ContinueWith(t =>
            {
                if (t.IsFaulted) return;
                _dispatcher.BeginInvoke(new Action(() =>
                {
                    foreach (var row in Actions)
                    {
                        PerfStatus status;
                        if (t.Result.Item1.TryGetValue(row.Action.Id, out status)) row.Apply(status);
                    }
                    Heavy.Clear();
                    foreach (var app in t.Result.Item2) Heavy.Add(new HeavyAppRow(app));
                    HeavyNote = Heavy.Count == 0 ? "No hay programas grandes abiertos: nada que cerrar." : "Se pide cerrar su ventana con normalidad: si tienen algo sin guardar te lo preguntarán.";
                }));
            }, TaskScheduler.Default);
        }

        private PerfStatus SafeStatus(PerfAction action)
        {
            try { return _service.Status(action); }
            catch (Exception e) when (e is InvalidOperationException || e is System.IO.IOException || e is UnauthorizedAccessException || e is System.Security.SecurityException)
            { return new PerfStatus { Available = false, Detail = "No se pudo comprobar: " + e.Message }; }
        }

        // ---------- Acciones ----------

        private void RunAction(PerfActionRow row, bool apply)
        {
            if (apply && row.Action.Id == "power" && !_dialogs.Confirm("Plan Alto rendimiento",
                "Se activa el plan Alto rendimiento. En un portátil gasta más batería y hace más ruido. Puedes volver al plan anterior con Deshacer.", "Activar")) return;
            if (_measureAround) { var ignored = RunMeasuredAsync(row, apply); return; }
            Finish(row, apply ? _service.Apply(row.Action) : _service.Undo(row.Action));
        }

        private void Finish(PerfActionRow row, PerfResult result)
        {
            row.Result = result.Message;
            row.Apply(SafeStatus(row.Action));
        }

        private async Task RunMeasuredAsync(PerfActionRow row, bool apply)
        {
            SetBusy(true);
            _measureCts = new CancellationTokenSource();
            var token = _measureCts.Token;
            try
            {
                MeasureStatus = "Midiendo antes del cambio (≈ 14 s)…";
                var before = await Task.Run(() => Capture("Antes: " + row.Title, token), token);
                PerfResult result = await Task.Run(() => apply ? _service.Apply(row.Action) : _service.Undo(row.Action));
                Finish(row, result);
                if (!result.Ok || token.IsCancellationRequested) { MeasureStatus = result.Ok ? "Medición cancelada." : ""; return; }
                MeasureStatus = "Esperando 3 s a que Windows se asiente y midiendo de nuevo…";
                await Task.Delay(3000, token);
                var after = await Task.Run(() => Capture("Después: " + row.Title, token), token);
                ShowComparison(before, after, row.Title);
            }
            catch (OperationCanceledException) { MeasureStatus = "Medición cancelada."; }
            finally { SetBusy(false); _measureCts.Dispose(); _measureCts = null; }
        }

        private async Task MeasureNowAsync()
        {
            SetBusy(true);
            _measureCts = new CancellationTokenSource();
            var token = _measureCts.Token;
            try
            {
                MeasureStatus = "Midiendo (≈ 14 s)…";
                var snapshot = await Task.Run(() => Capture("Medición manual", token), token);
                if (_baseline == null)
                {
                    _baseline = snapshot; Compare.Clear(); OnPropertyChanged("HasCompare"); LoadHistory();
                    MeasureStatus = "Referencia guardada. Aplica un cambio (o vuelve a pulsar Medir) para compararlo con ella.";
                }
                else ShowComparison(_baseline, snapshot, "la referencia");
            }
            catch (OperationCanceledException) { MeasureStatus = "Medición cancelada."; }
            finally { SetBusy(false); _measureCts.Dispose(); _measureCts = null; }
        }

        private PerfSnapshot Capture(string label, CancellationToken token)
        {
            var snapshot = new PerfSnapshot { AtUtc = DateTime.UtcNow, Label = label };
            var samples = SchedulerProbe.Collect(4000, token);
            SchedulerProbe.Fill(snapshot, samples);
            PingProbe.Fill(snapshot, token);
            // Frametimes solo si PresentMon existe y hay un juego del perfil en marcha
            string presentMon = FrameStats.FindPresentMon();
            var session = _engine.Active;
            if (presentMon != null && session != null && !string.IsNullOrEmpty(session.ProcessName) && !token.IsCancellationRequested)
            {
                string error;
                string csv = FrameStats.Capture(presentMon, session.ProcessName, 10, out error);
                if (csv != null) FrameStats.Fill(snapshot, FrameStats.ParseCsv(csv));
                snapshot.Game = session.Title;
            }
            _store.AddMeasurement(snapshot);
            return snapshot;
        }

        private void ShowComparison(PerfSnapshot before, PerfSnapshot after, string name)
        {
            Compare.Clear();
            foreach (var line in PerfCompare.Compare(before, after)) Compare.Add(line);
            OnPropertyChanged("HasCompare");
            int better = Compare.Count(l => l.Verdict == "better"), worse = Compare.Count(l => l.Verdict == "worse");
            MeasureStatus = Compare.Count == 0 ? "No se pudo medir lo suficiente para comparar."
                : "Comparado con " + name + ": " + better + " métrica(s) mejor, " + worse + " peor. Las diferencias pequeñas son ruido normal.";
            LoadHistory();
        }

        private void SetBusy(bool busy)
        {
            _measureBusy = busy;
            OnPropertyChanged("IsMeasuring");
        }

        private void LoadHistory()
        {
            History.Clear();
            foreach (var s in _store.LoadMeasurements().OrderByDescending(x => x.AtUtc).Take(8))
                History.Add(s.AtUtc.ToLocalTime().ToString("d MMM HH:mm", CultureInfo.CurrentCulture) + " · " + s.Label + " · " + Describe(s));
        }

        private static string Describe(PerfSnapshot s)
        {
            var parts = new List<string>();
            if (s.SchedP99.HasValue) parts.Add("Sleep p99 " + s.SchedP99.Value.ToString("0.00", CultureInfo.CurrentCulture) + " ms");
            if (s.PingAvg.HasValue) parts.Add("ping " + s.PingAvg.Value.ToString("0", CultureInfo.CurrentCulture) + " ms");
            if (s.Fps.HasValue) parts.Add(s.Fps.Value.ToString("0", CultureInfo.CurrentCulture) + " FPS");
            return string.Join(" · ", parts);
        }

        // ---------- Apps pesadas ----------

        private void CloseHeavy(HeavyAppRow row)
        {
            if (row == null) return;
            if (!_dialogs.Confirm("Cerrar " + row.App.Name, "Se pide a " + row.App.Name + " que cierre su ventana (" + row.Memory + "). Si tiene algo sin guardar te lo preguntará. No se fuerza nada.", "Cerrar")) return;
            int asked = row.App.WindowPids.Count(pid => _host.CloseGracefully(pid));
            HeavyNote = asked > 0 ? "Pedido el cierre de " + row.App.Name + ". Actualiza la lista en unos segundos." : "No se pudo pedir el cierre de " + row.App.Name + " (puede ejecutarse como administrador).";
            Task.Delay(2500).ContinueWith(_ => _dispatcher.BeginInvoke(new Action(Refresh)), TaskScheduler.Default);
        }

        // ---------- Perfil de juego ----------

        private void RebuildProfiles()
        {
            Profiles.Clear();
            foreach (var target in ProfileLists.Targets(_settings))
            {
                ProfileOptions options;
                if (!_settings.Options.TryGetValue(target.Id, out options)) { options = new ProfileOptions(); _settings.Options[target.Id] = options; }
                Profiles.Add(new ProfileRow(target, options, () => _store.SaveSettings(_settings)));
            }
        }

        private void AddCustom()
        {
            string name = ProcessMatcher.CleanCustomName(CustomName);
            if (name == null) { _dialogs.Inform("Juego no válido", "Escribe el nombre del proceso o del ejecutable del juego (por ejemplo valorant-win64-shipping o cs2.exe)."); return; }
            if (_settings.Custom.Any(c => string.Equals(c.Process, name, StringComparison.OrdinalIgnoreCase))) { CustomName = ""; return; }
            _settings.Custom.Add(new CustomGame { Process = name, Title = name });
            _store.SaveSettings(_settings);
            CustomName = "";
            RebuildProfiles();
        }

        private void RemoveCustom(ProfileRow row)
        {
            if (row == null || !row.IsCustom) return;
            _settings.Custom.RemoveAll(c => ("custom:" + c.Process.ToLowerInvariant()) == row.Target.Id);
            _settings.Options.Remove(row.Target.Id);
            _store.SaveSettings(_settings);
            RebuildProfiles();
        }

        private void StartMonitor()
        {
            if (_monitor != null) return;
            _monitor = new DispatcherTimer(DispatcherPriority.Background, _dispatcher) { Interval = TimeSpan.FromSeconds(5) };
            _monitor.Tick += (s, e) => MonitorTick();
            _monitor.Start();
            SessionText = "Vigilando juegos (cada 5 s)…";
            MonitorTick();
        }

        private void StopMonitor(bool restore)
        {
            if (_monitor != null) { _monitor.Stop(); _monitor = null; }
            if (_thermalTimer != null) { _thermalTimer.Stop(); _thermalTimer = null; }
            if (restore && _engine.Active != null)
                Task.Run(() => _engine.Restore());
            if (_engine.Active == null) SessionText = "Vigilancia apagada.";
        }

        private void MonitorTick()
        {
            if (_ticking || !_settings.Enabled) return;
            _ticking = true;
            Task.Run(() => _engine.Tick(_settings)).ContinueWith(t =>
            {
                _ticking = false;
                if (t.IsFaulted) _dispatcher.BeginInvoke(new Action(() => AddLog("Perfil de juego: " + t.Exception.GetBaseException().Message)));
            }, TaskScheduler.Default);
        }

        private void AddLog(string text)
        {
            Log.Insert(0, DateTime.Now.ToString("HH:mm", CultureInfo.CurrentCulture) + " · " + text);
            while (Log.Count > 10) Log.RemoveAt(Log.Count - 1);
        }

        private void OnActivated(ProfileSession session)
        {
            SessionText = session.Title + " en marcha · perfil activo desde las " + DateTime.Now.ToString("HH:mm", CultureInfo.CurrentCulture) + ".";
            _tracker = new ThermalTracker(session.Title, RaiseThermal);
            if (_thermalTimer == null)
            {
                _thermalTimer = new DispatcherTimer(DispatcherPriority.Background, _dispatcher) { Interval = TimeSpan.FromSeconds(5) };
                _thermalTimer.Tick += (s, e) => SampleThermal();
                _thermalTimer.Start();
            }
        }

        private void OnRestored(ProfileSession session)
        {
            SessionText = _settings.Enabled ? "Vigilando juegos (cada 5 s)…" : "Vigilancia apagada.";
            if (_thermalTimer != null) { _thermalTimer.Stop(); _thermalTimer = null; }
            var tracker = _tracker; _tracker = null;
            var summary = tracker == null ? null : tracker.Finish(DateTime.UtcNow);
            if (summary != null) { _store.AddThermal(summary); LoadThermal(); }
        }

        private void SampleThermal()
        {
            if (_sampling || _tracker == null) return;
            _sampling = true;
            Task.Run(() => _thermalSource.Read()).ContinueWith(t =>
            {
                _dispatcher.BeginInvoke(new Action(() =>
                {
                    _sampling = false;
                    if (t.IsFaulted || _tracker == null) return;
                    _tracker.Add(t.Result);
                }));
            }, TaskScheduler.Default);
        }

        private void RaiseThermal(ThermalEvent evt)
        {
            _store.AddThermal(evt);
            ThermalAlert = (evt.Kind == "hot" ? "Temperatura alta" : "Throttling") + " en " + evt.Game + ": " + evt.Detail;
            ToastNotifier.Show(_dispatcher, evt.Kind == "hot" ? "iWinInstaller: temperatura alta" : "iWinInstaller: throttling", evt.Game + ": " + evt.Detail);
            LoadThermal();
        }

        private void LoadThermal()
        {
            Thermal.Clear();
            foreach (var e in _store.LoadThermal().OrderByDescending(x => x.AtUtc).Take(15))
            {
                string kind = e.Kind == "hot" ? "Calor" : e.Kind == "throttle" ? "Throttling" : "Resumen";
                Thermal.Add(e.AtUtc.ToLocalTime().ToString("d MMM HH:mm", CultureInfo.CurrentCulture) + " · " + kind + " · " + e.Game + " · " + e.Detail);
            }
            OnPropertyChanged("HasThermal");
        }

        public bool HasThermal { get { return Thermal.Count > 0; } }
    }
}
