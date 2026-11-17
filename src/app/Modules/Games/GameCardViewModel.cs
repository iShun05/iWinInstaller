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
using IWinInstaller.App.Shell;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>Una tarjeta de la página Juegos: estado, detalles, comprobación de archivos y Optimizar.</summary>
    public sealed class GameCardViewModel : ObservableObject
    {
        private readonly IGameEnvironment _env;
        private readonly GameBackupStore _backups;
        private readonly IDialogService _dialogs;
        private readonly Func<int> _currentHz;
        private readonly Action<GameCardViewModel, string> _manualPathChosen;
        private readonly Action<GameCardViewModel, CheckSummary> _checkFinished;
        private GameInstall _install = GameInstall.None;
        private TweakPlan _plan;
        private CancellationTokenSource _check;
        private bool _detecting = true, _running, _launcherRunning, _showDetails, _showOptimize, _fullCheck, _checking, _hasBackup;
        private string _result = "", _checkMessage = "", _backupText = "", _configSummary = "";
        private double _progress;
        private CheckSummary _lastCheck;

        public GameCardViewModel(GameDefinition definition, IGameEnvironment env, GameBackupStore backups, IDialogService dialogs,
            Func<int> currentHz, Action<GameCardViewModel, string> manualPathChosen, Action<GameCardViewModel, CheckSummary> checkFinished)
        {
            Definition = definition; _env = env; _backups = backups; _dialogs = dialogs;
            _currentHz = currentHz; _manualPathChosen = manualPathChosen; _checkFinished = checkFinished;
            Items = new ObservableCollection<TweakItem>();
            Warnings = new ObservableCollection<string>();
            Details = new ObservableCollection<string>();
            Problems = new ObservableCollection<string>();
            DetailsCommand = new RelayCommand(_ => ShowDetails = !ShowDetails);
            OptimizeCommand = new RelayCommand(_ => ToggleOptimize(), _ => CanModify);
            ApplyCommand = new RelayCommand(_ => Apply(), _ => CanModify && Items.Any(i => i.IsChecked));
            RestoreCommand = new RelayCommand(_ => Restore(), _ => CanModify && HasBackup);
            CheckCommand = new RelayCommand(_ => StartCheck(), _ => Install.Found && !Busy && !_checking);
            CancelCheckCommand = new RelayCommand(_ => { if (_check != null) _check.Cancel(); }, _ => _checking);
            OpenFolderCommand = new RelayCommand(_ => OpenFolder(), _ => Install.Found);
            BrowseCommand = new RelayCommand(_ => Browse());
            WebsiteCommand = new RelayCommand(_ => _dialogs.OpenUri(Definition.Website));
            SteamVerifyCommand = new RelayCommand(_ => StartUri("steam://validate/" + Definition.SteamAppId.ToString(CultureInfo.InvariantCulture)), _ => Install.FromSteam);
        }

        public GameDefinition Definition { get; private set; }
        public string Name { get { return Definition.Name; } }
        public GameInstall Install { get { return _install; } }
        public ObservableCollection<TweakItem> Items { get; private set; }
        public ObservableCollection<string> Warnings { get; private set; }
        public ObservableCollection<string> Details { get; private set; }
        public ObservableCollection<string> Problems { get; private set; }
        public string[] InGameTips { get { return Definition.InGameTips; } }
        public string Note { get { return Definition.Note; } }
        public string FilesHelp { get { return Definition.FilesHelp; } }
        public bool IsSteam { get { return Install.FromSteam; } }

        public RelayCommand DetailsCommand { get; private set; }
        public RelayCommand OptimizeCommand { get; private set; }
        public RelayCommand ApplyCommand { get; private set; }
        public RelayCommand RestoreCommand { get; private set; }
        public RelayCommand CheckCommand { get; private set; }
        public RelayCommand CancelCheckCommand { get; private set; }
        public RelayCommand OpenFolderCommand { get; private set; }
        public RelayCommand BrowseCommand { get; private set; }
        public RelayCommand WebsiteCommand { get; private set; }
        public RelayCommand SteamVerifyCommand { get; private set; }

        public bool IsInstalled { get { return Install.Found; } }
        public bool IsMissing { get { return !_detecting && !Install.Found; } }
        /// <summary>Juego en marcha: bloquea Optimizar, Restaurar y Comprobar.</summary>
        public bool Busy { get { return _running || _launcherRunning; } }
        public bool CanModify { get { return Install.Found && !_running && !_checking; } }
        public string BusyText
        {
            get
            {
                if (_running) return "Cierra el juego (y su lanzador) para optimizar, restaurar o comprobar archivos.";
                if (_launcherRunning) return "Cierra el lanzador para comprobar archivos: puede estar actualizando.";
                return "";
            }
        }

        /// <summary>«Detecting», «Missing», «Installed», «Attention» o «Running» (para los colores de la pastilla).</summary>
        public string State
        {
            get
            {
                if (_detecting) return "Detecting";
                if (!Install.Found) return "Missing";
                if (_running) return "Running";
                if (_lastCheck != null && !_lastCheck.Ok) return "Attention";
                return "Installed";
            }
        }

        public string StateLabel
        {
            get
            {
                switch (State)
                {
                    case "Detecting": return "Detectando…";
                    case "Missing": return "No instalado";
                    case "Running": return "En marcha";
                    case "Attention": return "Revisar archivos";
                    default: return "Instalado";
                }
            }
        }

        public string Summary
        {
            get
            {
                if (_detecting) return "Buscando en Epic, HoYoPlay, Steam y Windows…";
                if (!Install.Found) return "No se encuentra en este PC.";
                var parts = new List<string> { Install.Source };
                if (!string.IsNullOrEmpty(Install.Version)) parts.Add(Install.Version);
                parts.Add(FormatSize(Install.SizeBytes));
                if (_configSummary.Length > 0) parts.Add(_configSummary);
                return string.Join("  ·  ", parts);
            }
        }

        public bool ShowDetails { get { return _showDetails; } set { if (Set(ref _showDetails, value) && value) FillDetails(); } }
        public bool ShowOptimize { get { return _showOptimize; } set { Set(ref _showOptimize, value); } }
        public bool FullCheck { get { return _fullCheck; } set { Set(ref _fullCheck, value); } }
        public bool IsChecking { get { return _checking; } }
        public double CheckProgress { get { return _progress; } private set { Set(ref _progress, value); } }
        public string CheckMessage { get { return _checkMessage; } private set { Set(ref _checkMessage, value); } }
        public string Result { get { return _result; } private set { Set(ref _result, value); } }
        public bool HasBackup { get { return _hasBackup; } private set { Set(ref _hasBackup, value); } }
        public string BackupText { get { return _backupText; } private set { Set(ref _backupText, value); } }

        public static string FormatSize(long? bytes)
        {
            if (!bytes.HasValue || bytes.Value <= 0) return "tamaño —";
            double gb = bytes.Value / 1024.0 / 1024 / 1024;
            return gb >= 1 ? gb.ToString("0.#", CultureInfo.CurrentCulture) + " GB" : (bytes.Value / 1024.0 / 1024).ToString("0", CultureInfo.CurrentCulture) + " MB";
        }

        /// <summary>Resultado de la detección (llamar en el hilo de la interfaz).</summary>
        public void SetInstall(GameInstall install, CheckSummary lastCheck)
        {
            _install = install ?? GameInstall.None;
            _lastCheck = install != null && install.Found ? lastCheck : null;
            _detecting = false;
            _configSummary = ReadConfigSummary();
            RefreshBackup();
            if (ShowDetails) FillDetails();
            if (ShowOptimize) BuildPlan();
            RaiseAll();
        }

        public void SetDetecting()
        {
            _detecting = true;
            RaiseAll();
        }

        /// <summary>Estado de los procesos; cancela una comprobación si el juego se abre.</summary>
        public void SetRunning(bool game, bool launcher)
        {
            if (game == _running && launcher == _launcherRunning) return;
            bool closed = _running && !game;
            _running = game; _launcherRunning = launcher;
            if ((game || launcher) && _check != null) _check.Cancel();
            if (closed) { _configSummary = ReadConfigSummary(); if (ShowOptimize) BuildPlan(); }
            RaiseAll();
        }

        private void RaiseAll()
        {
            foreach (string p in new[] { "Install", "IsInstalled", "IsMissing", "Busy", "BusyText", "CanModify", "State", "StateLabel", "Summary", "IsSteam", "IsChecking" })
                OnPropertyChanged(p);
            System.Windows.Input.CommandManager.InvalidateRequerySuggested();
        }

        private string ReadConfigSummary()
        {
            if (!Install.Found) return "";
            try
            {
                if (Definition.Id == GameDefinitions.Fortnite)
                {
                    string ini = GameTweaks.FortniteIniPath(_env);
                    if (!File.Exists(ini)) return "";
                    var doc = IniDocument.Parse(File.ReadAllBytes(ini));
                    return "límite " + GameTweaks.FortniteFps(doc.Get(GameTweaks.FortniteSection, "FrameRateLimit"));
                }
                if (Definition.Id == GameDefinitions.StarRail && !Install.IsChina)
                {
                    string json; bool nul;
                    if (StarRailSettings.TryDecode(_env.GetValue(StarRailSettings.RegistryKey, StarRailSettings.ModelValue) as byte[], out json, out nul))
                    {
                        int? fps = StarRailSettings.GetInt(json, "FPS");
                        return fps.HasValue ? fps.Value + " FPS" : "";
                    }
                }
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            return "";
        }

        private void RefreshBackup()
        {
            BackupSet latest = null;
            try { latest = Install.Found ? _backups.Latest(Definition.Id) : null; }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            HasBackup = latest != null;
            BackupText = latest == null ? "Sin copias." : "Última copia: " + latest.At.ToLocalTime().ToString("d MMM yyyy HH:mm", CultureInfo.CurrentCulture) + ".";
        }

        private void FillDetails()
        {
            Details.Clear();
            if (!Install.Found) { Details.Add("No instalado. Si está en otra carpeta, usa «Buscar el ejecutable…»."); return; }
            Details.Add("Carpeta: " + Install.Folder);
            Details.Add("Ejecutable: " + Path.GetFileName(Install.ExePath) + (Install.IsChina ? " (versión china)" : ""));
            Details.Add("Lanzador: " + Install.Source + (string.IsNullOrEmpty(Install.Version) ? "" : " · versión " + Install.Version));
            Details.Add("Tamaño: " + FormatSize(Install.SizeBytes) + " · libre en la unidad: " + FreeSpace(Install.Folder));
            string gpu = GpuPreference.GetPair(_env.GetValue(GpuPreference.RegistryKey, Install.ExePath) as string, GpuPreference.PairName);
            Details.Add("GPU para este juego: " + GpuPreference.Describe(gpu));
            foreach (string line in ConfigLines()) Details.Add(line);
            Details.Add("Anticheat: " + Definition.AntiCheat + ". iWinInstaller no toca nada mientras el juego está abierto.");
            Details.Add("Archivos: " + (_lastCheck == null ? "sin comprobar." : _lastCheck.Describe()));
            Details.Add("Copias de seguridad: " + BackupText);
        }

        private IEnumerable<string> ConfigLines()
        {
            var lines = new List<string>();
            try
            {
                if (Definition.Id == GameDefinitions.Fortnite)
                {
                    string ini = GameTweaks.FortniteIniPath(_env);
                    if (!File.Exists(ini)) { lines.Add("Ajustes: aún no existen (abre el juego una vez)."); return lines; }
                    var doc = IniDocument.Parse(File.ReadAllBytes(ini));
                    string rhi = doc.Get("D3DRHIPreference", "PreferredRHI"), level = doc.Get("D3DRHIPreference", "PreferredFeatureLevel");
                    string mode = doc.Get(GameTweaks.FortniteSection, "FullscreenMode");
                    lines.Add("Ajustes: renderizado " + (rhi == "dx11" && level == "es31" ? "Rendimiento" : rhi ?? "por defecto")
                        + " · límite " + GameTweaks.FortniteFps(doc.Get(GameTweaks.FortniteSection, "FrameRateLimit"))
                        + " · VSync " + (string.Equals(doc.Get(GameTweaks.FortniteSection, "bUseVSync"), "True", StringComparison.OrdinalIgnoreCase) ? "sí" : "no")
                        + " · " + (mode == "0" ? "pantalla completa" : mode == "1" ? "sin bordes" : mode == "2" ? "ventana" : "modo de pantalla —"));
                }
                else if (Definition.Id == GameDefinitions.StarRail && !Install.IsChina)
                {
                    string json; bool nul;
                    if (StarRailSettings.TryDecode(_env.GetValue(StarRailSettings.RegistryKey, StarRailSettings.ModelValue) as byte[], out json, out nul))
                        lines.Add("Ajustes: " + StarRailSettings.GetInt(json, "FPS") + " FPS · VSync " + (StarRailSettings.GetRaw(json, "EnableVSync") == "true" ? "sí" : "no"));
                    else lines.Add("Ajustes: aún no guardados (cambia un ajuste de gráficos en el juego y ciérralo).");
                }
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            return lines;
        }

        private static string FreeSpace(string folder)
        {
            try
            {
                var drive = new DriveInfo(Path.GetPathRoot(folder));
                return FormatSize(drive.AvailableFreeSpace);
            }
            catch (ArgumentException) { return "—"; }
            catch (IOException) { return "—"; }
            catch (UnauthorizedAccessException) { return "—"; }
        }

        private void ToggleOptimize()
        {
            ShowOptimize = !ShowOptimize;
            Result = "";
            if (ShowOptimize) BuildPlan();
        }

        private void BuildPlan()
        {
            Items.Clear(); Warnings.Clear();
            try { _plan = GameTweaks.Build(Definition, Install, _env, _currentHz()); }
            catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
            {
                _plan = null;
                Warnings.Add("No se pudieron leer los ajustes: " + ex.Message);
                return;
            }
            foreach (var item in _plan.Items) Items.Add(item);
            foreach (string w in _plan.Warnings) Warnings.Add(w);
        }

        private void Apply()
        {
            if (_plan == null || !CanModify) return;
            if (_env.AnyProcessRunning(Definition.GameProcesses)) { SetRunning(true, _launcherRunning); return; }
            List<string> lines;
            try { lines = GameTweaks.Apply(Definition, Install, _env, _plan, _backups, _currentHz(), DateTime.UtcNow); }
            catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException || ex is System.Security.SecurityException)
            {
                lines = new List<string> { "✗ " + ex.Message };
            }
            Result = string.Join(Environment.NewLine, lines);
            RefreshBackup();
            _configSummary = ReadConfigSummary();
            BuildPlan();
            RaiseAll();
        }

        private void Restore()
        {
            if (!CanModify) return;
            var latest = _backups.Latest(Definition.Id);
            if (latest == null) return;
            if (!_dialogs.Confirm("Restaurar " + Name, "Se vuelve a la copia del " + latest.At.ToLocalTime().ToString("d MMM yyyy HH:mm", CultureInfo.CurrentCulture)
                + ". Se perderán los cambios que hicieras en el juego después de optimizar.", "Restaurar")) return;
            if (_env.AnyProcessRunning(Definition.GameProcesses)) { SetRunning(true, _launcherRunning); return; }
            var lines = _backups.Restore(latest, GameTweaks.Allowed(Definition, Install, _env));
            Result = "Restaurado:" + Environment.NewLine + string.Join(Environment.NewLine, lines);
            _configSummary = ReadConfigSummary();
            if (ShowOptimize) BuildPlan();
            RaiseAll();
        }

        private void StartCheck()
        {
            if (!Install.Found || Busy || _checking) return;
            if (_env.AnyProcessRunning(Definition.GameProcesses.Concat(Definition.LauncherProcesses)))
            {
                CheckMessage = "Cierra el juego y su lanzador para comprobar los archivos.";
                return;
            }
            _check = new CancellationTokenSource();
            var token = _check.Token;
            _checking = true;
            CheckProgress = 0;
            Problems.Clear();
            CheckMessage = FullCheck ? "Comprobando tamaño y MD5 de cada archivo (puede tardar varios minutos)…" : "Comprobando archivos…";
            RaiseAll();
            var install = Install;
            var definition = Definition;
            bool md5 = FullCheck;
            var progress = new Progress<double>(p => CheckProgress = p);
            Task.Run(() => RunCheck(definition, install, md5, progress, token)).ContinueWith(t =>
            {
                _checking = false;
                FileCheckResult result = t.Status == TaskStatus.RanToCompletion ? t.Result : null;
                ShowCheck(result, t.Exception);
                RaiseAll();
            }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        private static FileCheckResult RunCheck(GameDefinition definition, GameInstall install, bool md5, IProgress<double> progress, CancellationToken token)
        {
            if (definition.Id == GameDefinitions.Fortnite) return BasicFileCheck.Fortnite(install.Folder);
            if (definition.HoyoBizGlobal != null)
            {
                var entries = PkgVersion.LoadAll(install.Folder);
                if (entries.Count == 0) { var none = BasicFileCheck.Executable(install.ExePath); none.NoList = true; return none; }
                return PkgVersion.Check(install.Folder, entries, md5, progress, token);
            }
            return BasicFileCheck.Executable(install.ExePath);
        }

        private void ShowCheck(FileCheckResult result, AggregateException error)
        {
            if (result == null)
            {
                CheckMessage = "No se pudo comprobar: " + (error == null ? "error desconocido" : error.GetBaseException().Message);
                return;
            }
            if (result.Cancelled) { CheckMessage = "Comprobación cancelada."; return; }
            if (result.NoList && result.Bad == 0)
            {
                CheckMessage = "Este juego no trae lista de archivos: el ejecutable está, pero para una comprobación completa usa «Reparar» en el lanzador.";
                return;
            }
            foreach (var p in result.Problems.Take(20)) Problems.Add(p.Kind + ": " + p.Path);
            if (result.Problems.Count > 20) Problems.Add("y " + (result.Problems.Count - 20) + " más");
            if (result.Ok) CheckMessage = "Correcto: " + result.Total + " archivos (" + result.Mode + ")." + (Definition.Id == GameDefinitions.Fortnite ? " " + FilesHelp : "");
            else if (result.ListLooksStale) CheckMessage = "Hay " + result.Bad + " diferencias de " + result.Total + ": la lista del juego parece desactualizada. " + FilesHelp;
            else CheckMessage = result.Bad + " de " + result.Total + " archivos con fallos (" + result.Mode + "). " + FilesHelp;
            _lastCheck = new CheckSummary { At = DateTime.UtcNow, Mode = result.Mode, Total = result.Total, Bad = result.Bad, Ok = result.Ok };
            _checkFinished(this, _lastCheck);
            if (ShowDetails) FillDetails();
        }

        private void OpenFolder()
        {
            if (!Install.Found || !Directory.Exists(Install.Folder)) return;
            try { Process.Start(new ProcessStartInfo("explorer.exe", "\"" + Install.Folder + "\"") { UseShellExecute = false }); }
            catch (System.ComponentModel.Win32Exception) { }
        }

        private static void StartUri(string uri)
        {
            try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); }
            catch (System.ComponentModel.Win32Exception) { }
        }

        private void Browse()
        {
            var names = Definition.FindExeByCompany ? new[] { "*.exe" } : Definition.Executables.Concat(Definition.ChinaExecutables ?? new string[0]).Select(Path.GetFileName).Distinct().ToArray();
            string file = _dialogs.OpenFile(Name + "|" + string.Join(";", names));
            if (string.IsNullOrEmpty(file)) return;
            string folder = Path.GetDirectoryName(file);
            if (Definition.Id == GameDefinitions.Fortnite)
            {
                // FortniteGame\Binaries\Win64\…exe → carpeta raíz del juego
                var dir = new DirectoryInfo(folder);
                for (int i = 0; i < 3 && dir != null; i++) dir = dir.Parent;
                folder = dir == null ? folder : dir.FullName;
            }
            GameInstall found;
            if (!GameLocator.TryFolder(Definition, _env, folder, "Elegido a mano", out found))
            {
                _dialogs.Inform(Name, "Ese archivo no es el ejecutable de " + Name + ".");
                return;
            }
            _manualPathChosen(this, found.Folder);
        }
    }
}
