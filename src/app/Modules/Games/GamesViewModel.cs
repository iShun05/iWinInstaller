using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Threading;
using IWinInstaller.App.Core;
using IWinInstaller.App.Modules.Tools;
using IWinInstaller.App.Shell;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>
    /// Página Juegos: detecta los cinco juegos al entrar, mira cada 3 s si alguno está en marcha (solo con la página
    /// seleccionada) y muestra la frecuencia de la pantalla. No lanza PowerShell ni procesos auxiliares.
    /// </summary>
    public sealed class GamesViewModel : ObservableObject
    {
        private readonly IGameEnvironment _env;
        private readonly Dispatcher _dispatcher;
        private readonly GameStateStore _state;
        private readonly Dictionary<string, string> _paths;
        private readonly Dictionary<string, CheckSummary> _checks;
        private DispatcherTimer _timer;
        private bool _detecting;
        private string _display = "", _raiseLabel = "";
        private bool _canRaise;

        public GamesViewModel(Dispatcher dispatcher, IDialogService dialogs, Action openSystem, Action openLatency)
            : this(new WindowsGameEnvironment(), dispatcher, dialogs, openSystem, openLatency) { }

        public GamesViewModel(IGameEnvironment env, Dispatcher dispatcher, IDialogService dialogs, Action openSystem, Action openLatency)
        {
            _env = env;
            _dispatcher = dispatcher;
            string root = GameBackupStore.DefaultRoot(env);
            _state = new GameStateStore(root);
            _paths = _state.LoadPaths();
            _checks = _state.LoadChecks();
            var backups = new GameBackupStore(root, env);
            Cards = new ObservableCollection<GameCardViewModel>(GameDefinitions.All.Select(d =>
                new GameCardViewModel(d, env, backups, dialogs, CurrentHz, OnManualPath, OnCheckFinished)));
            RefreshCommand = new RelayCommand(_ => Detect(), _ => !_detecting);
            OpenSystemCommand = new RelayCommand(_ => openSystem());
            OpenLatencyCommand = new RelayCommand(_ => openLatency());
        }

        public ObservableCollection<GameCardViewModel> Cards { get; private set; }
        public RelayCommand RefreshCommand { get; private set; }
        public RelayCommand OpenSystemCommand { get; private set; }
        public RelayCommand OpenLatencyCommand { get; private set; }
        public string Display { get { return _display; } private set { Set(ref _display, value); } }
        public bool CanRaiseHz { get { return _canRaise; } private set { Set(ref _canRaise, value); } }
        public string RaiseHzLabel { get { return _raiseLabel; } private set { Set(ref _raiseLabel, value); } }

        /// <summary>Al entrar en la página: detecta, lee la pantalla y empieza a mirar los procesos.</summary>
        public void Start()
        {
            RefreshDisplay();
            Detect();
            if (_timer == null)
            {
                _timer = new DispatcherTimer(TimeSpan.FromSeconds(3), DispatcherPriority.Background, (s, e) => PollProcesses(), _dispatcher);
                _timer.Start();
            }
        }

        /// <summary>Al salir de la página o cerrar la app: deja de mirar los procesos.</summary>
        public void Stop()
        {
            if (_timer != null) { _timer.Stop(); _timer = null; }
        }

        private static MonitorInfo PrimaryMonitor()
        {
            try { return DisplaySettings.Monitors().FirstOrDefault(m => m.Primary); }
            catch (Exception ex) when (ex is DllNotFoundException || ex is EntryPointNotFoundException) { return null; }
        }

        /// <summary>Hz actuales de la pantalla principal (0 si no se saben).</summary>
        public static int CurrentHz()
        {
            var monitor = PrimaryMonitor();
            var mode = monitor == null ? null : DisplaySettings.CurrentMode(monitor.Device);
            return mode.HasValue ? mode.Value.Hz : 0;
        }

        /// <summary>Hz máximos que admite la pantalla principal a su resolución actual (0 si no se saben).</summary>
        public static int MaxHz()
        {
            var monitor = PrimaryMonitor();
            var mode = monitor == null ? null : DisplaySettings.CurrentMode(monitor.Device);
            return mode.HasValue ? DisplaySettings.MaxRefreshFor(mode.Value.Width, mode.Value.Height, DisplaySettings.Modes(monitor.Device)) : 0;
        }

        private void RefreshDisplay()
        {
            var monitor = PrimaryMonitor();
            var mode = monitor == null ? null : DisplaySettings.CurrentMode(monitor.Device);
            if (!mode.HasValue) { Display = "No se pudo leer la pantalla principal."; CanRaiseHz = false; return; }
            int max = DisplaySettings.MaxRefreshFor(mode.Value.Width, mode.Value.Height, DisplaySettings.Modes(monitor.Device));
            if (max > mode.Value.Hz)
            {
                Display = "Pantalla principal: " + mode.Value.Hz + " Hz · admite hasta " + max + " Hz a " + mode.Value.Width + " × " + mode.Value.Height + ".";
                RaiseHzLabel = "Subir a " + max + " Hz en Sistema";
                CanRaiseHz = true;
            }
            else
            {
                Display = "Pantalla principal: " + mode.Value.Hz + " Hz, al máximo a " + mode.Value.Width + " × " + mode.Value.Height + ".";
                CanRaiseHz = false;
            }
        }

        private void Detect()
        {
            if (_detecting) return;
            _detecting = true;
            foreach (var card in Cards) card.SetDetecting();
            var paths = new Dictionary<string, string>(_paths);
            Task.Run(() =>
            {
                var found = new Dictionary<string, GameInstall>();
                foreach (var definition in GameDefinitions.All)
                {
                    string manual;
                    paths.TryGetValue(definition.Id, out manual);
                    GameInstall install;
                    try
                    {
                        install = GameLocator.Locate(definition, _env, manual);
                        bool running = _env.AnyProcessRunning(definition.GameProcesses);
                        if (install.Found && !running) GameLocator.FillDetails(definition, _env, install);
                    }
                    catch (Exception ex) when (ex is System.IO.IOException || ex is UnauthorizedAccessException || ex is System.Security.SecurityException)
                    {
                        install = GameInstall.None;
                    }
                    found[definition.Id] = install;
                }
                return found;
            }).ContinueWith(t =>
            {
                _detecting = false;
                if (t.Status != TaskStatus.RanToCompletion) { foreach (var card in Cards) card.SetInstall(GameInstall.None, null); return; }
                bool pathsChanged = false;
                foreach (var card in Cards)
                {
                    var install = t.Result[card.Definition.Id];
                    // Una ruta elegida a mano que ya no tiene el ejecutable se descarta
                    if (_paths.ContainsKey(card.Definition.Id) && (!install.Found || install.Source != "Elegido a mano")) { _paths.Remove(card.Definition.Id); pathsChanged = true; }
                    CheckSummary check;
                    _checks.TryGetValue(card.Definition.Id, out check);
                    card.SetInstall(install, check);
                }
                if (pathsChanged) _state.SavePaths(_paths);
                PollProcesses();
            }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        private void PollProcesses()
        {
            foreach (var card in Cards)
            {
                if (!card.IsInstalled) continue;
                bool game = _env.AnyProcessRunning(card.Definition.GameProcesses);
                bool launcher = !game && _env.AnyProcessRunning(card.Definition.LauncherProcesses);
                card.SetRunning(game, launcher);
            }
        }

        private void OnManualPath(GameCardViewModel card, string folder)
        {
            _paths[card.Definition.Id] = folder;
            _state.SavePaths(_paths);
            Detect();
        }

        private void OnCheckFinished(GameCardViewModel card, CheckSummary summary)
        {
            _checks[card.Definition.Id] = summary;
            _state.SaveChecks(_checks);
        }
    }
}
