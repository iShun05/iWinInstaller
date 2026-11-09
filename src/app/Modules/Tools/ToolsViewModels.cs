using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;
using IWinInstaller.App.Shell;

namespace IWinInstaller.App.Modules.Tools
{
    internal static class Json
    {
        public static string Text(Dictionary<string, object> data, string key)
        {
            object value;
            return data != null && data.TryGetValue(key, out value) && value != null ? Convert.ToString(value, CultureInfo.InvariantCulture) : "";
        }
        public static bool Flag(Dictionary<string, object> data, string key)
        {
            object value;
            return data != null && data.TryGetValue(key, out value) && value is bool && (bool)value;
        }
        public static int Number(Dictionary<string, object> data, string key)
        {
            object value;
            return data != null && data.TryGetValue(key, out value) && value != null ? Convert.ToInt32(value, CultureInfo.InvariantCulture) : 0;
        }
        public static DateTime? Date(Dictionary<string, object> data, string key)
        {
            DateTime parsed;
            return DateTime.TryParse(Text(data, key), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out parsed) ? parsed.ToLocalTime() : (DateTime?)null;
        }
    }

    /// <summary>Seguridad: estado de Microsoft Defender, análisis y firmas.</summary>
    public sealed class SecurityViewModel : ObservableObject
    {
        private readonly EngineClient _engine;
        private string _summary = "Leyendo el estado de la protección…", _details = "", _threats = "", _message = "";
        private bool _isBusy, _available, _loaded;

        public SecurityViewModel(EngineClient engine)
        {
            _engine = engine;
            QuickCommand = new RelayCommand(_ => Run("quick", "Análisis rápido", null), _ => !IsBusy && _available);
            FullCommand = new RelayCommand(_ => Run("full", "Análisis completo", null), _ => !IsBusy && _available);
            UpdateCommand = new RelayCommand(_ => Run("update", "Actualización de firmas", null), _ => !IsBusy && _available);
            FolderCommand = new RelayCommand(_ => { string path = PickFolder(); if (path != null) Run("folder", "Análisis de " + Path.GetFileName(path.TrimEnd('\\')), path); }, _ => !IsBusy && _available);
            OpenCommand = new RelayCommand(_ => { try { Process.Start(new ProcessStartInfo("windowsdefender://threat") { UseShellExecute = true }); } catch (System.ComponentModel.Win32Exception) { Message = "No se pudo abrir Seguridad de Windows."; } });
            RefreshCommand = new RelayCommand(_ => { var ignored = LoadAsync(); }, _ => !IsBusy);
        }

        public RelayCommand QuickCommand { get; private set; }
        public RelayCommand FullCommand { get; private set; }
        public RelayCommand UpdateCommand { get; private set; }
        public RelayCommand FolderCommand { get; private set; }
        public RelayCommand OpenCommand { get; private set; }
        public RelayCommand RefreshCommand { get; private set; }
        public string Summary { get { return _summary; } private set { Set(ref _summary, value); } }
        public string Details { get { return _details; } private set { Set(ref _details, value); } }
        public string Threats { get { return _threats; } private set { Set(ref _threats, value); } }
        public string Message { get { return _message; } private set { Set(ref _message, value ?? ""); } }
        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }

        public void EnsureLoaded() { if (!_loaded) { _loaded = true; var ignored = LoadAsync(); } }

        internal static string Ago(DateTime? date)
        {
            if (!date.HasValue) return "nunca";
            int days = (int)(DateTime.Now - date.Value).TotalDays;
            return days <= 0 ? "hoy" : days == 1 ? "ayer" : "hace " + days + " días";
        }

        private async Task LoadAsync()
        {
            var result = await _engine.RunAsync("security.status", null, null, TimeSpan.FromMinutes(2), CancellationToken.None);
            if (!result.Ok) { Summary = "No se pudo leer la protección: " + result.Error; return; }
            var r = result.Response;
            var others = InstallLists(r, "others");
            _available = Json.Flag(r, "available");
            if (!_available)
            {
                Summary = others.Count > 0 ? "Protección a cargo de " + String.Join(", ", others) + ". Defender no está disponible en este equipo." : "No se pudo leer Microsoft Defender en este equipo.";
                Details = "Abre Seguridad de Windows para revisar la protección."; Threats = "—";
                return;
            }
            bool passive = Json.Flag(r, "passive"), ok = Json.Flag(r, "realtime") && Json.Flag(r, "antivirus") && !passive;
            int age = Json.Number(r, "signatureAge");
            Summary = passive && others.Count > 0 ? "Protección en tiempo real a cargo de " + String.Join(", ", others) + ". Defender sigue disponible para análisis manuales."
                : ok && age <= 3 ? "Protegido: tiempo real activado y firmas al día."
                : ok ? "Protegido, pero las firmas tienen " + age + " días: actualízalas."
                : "Atención: la protección en tiempo real está desactivada.";
            Details = String.Join(Environment.NewLine, new[]
            {
                "Tiempo real: " + (Json.Flag(r, "realtime") ? "activado" : "desactivado") + "  ·  Modo: " + Json.Text(r, "mode"),
                "Protección contra alteraciones: " + (Json.Flag(r, "tamper") ? "activada" : "desactivada"),
                "Firmas: " + Json.Text(r, "signatureVersion") + " · " + Ago(Json.Date(r, "signatureUpdated")),
                "Último análisis rápido: " + Ago(Json.Date(r, "quickScan")) + "  ·  completo: " + Ago(Json.Date(r, "fullScan"))
            });
            object threats;
            var list = r.TryGetValue("threats", out threats) && threats is object[] ? ((object[])threats).OfType<Dictionary<string, object>>().ToList() : new List<Dictionary<string, object>>();
            Threats = !Json.Flag(r, "threatsVisible") ? "Solo visible con permiso de administrador o en Seguridad de Windows."
                : list.Count == 0 ? "Ninguna detectada."
                : String.Join(Environment.NewLine, list.Select(t => (Json.Date(t, "when") ?? DateTime.MinValue).ToString("dd/MM HH:mm") + " · " + Json.Text(t, "name") + " · " + (Json.Flag(t, "resolved") ? "resuelta" : "pendiente")));
        }

        private static List<string> InstallLists(Dictionary<string, object> data, string key)
        {
            object value;
            return data.TryGetValue(key, out value) && value is object[] ? ((object[])value).Select(v => Convert.ToString(v)).ToList() : new List<string>();
        }

        private string PickFolder()
        {
            using (var picker = new System.Windows.Forms.FolderBrowserDialog { Description = "Carpeta que quieres analizar" })
                return picker.ShowDialog() == System.Windows.Forms.DialogResult.OK && Directory.Exists(picker.SelectedPath) ? picker.SelectedPath : null;
        }

        private async void Run(string action, string label, string path)
        {
            IsBusy = true;
            Message = label + " en curso… Puedes seguir usando la app.";
            try
            {
                var request = new Dictionary<string, object> { { "action", action } };
                if (path != null) request["path"] = path;
                var result = await _engine.RunAsync("security.run", request, null, TimeSpan.FromHours(12), CancellationToken.None);
                Message = result.Ok ? label + " terminado." : label + " no se completó: " + (result.Error ?? "puede necesitar permiso de administrador.");
                await LoadAsync();
            }
            catch (Exception e) { Message = label + " no se completó: " + e.Message; }
            finally { IsBusy = false; }
        }
    }

    /// <summary>Vincular equipos: SSH con clave desde un Mac u otro Windows.</summary>
    public sealed class LinkViewModel : ObservableObject
    {
        private readonly EngineClient _engine;
        private readonly IDialogService _dialogs;
        private string _status = "Leyendo el estado…", _macCommand = "", _windowsCommand = "", _guide = "", _key = "", _message = "", _alias = "";
        private bool _isBusy, _ready, _lanAllowed, _loaded;

        public LinkViewModel(EngineClient engine, IDialogService dialogs)
        {
            _engine = engine; _dialogs = dialogs;
            PrepareCommand = new RelayCommand(_ => Do("link.prepare", null, "Servidor SSH listo: ahora ejecuta el comando en el otro equipo."), _ => !IsBusy);
            CopyMacCommand = new RelayCommand(_ => { _dialogs.CopyText(MacCommand); Message = "Comando para Mac copiado: pégalo en la Terminal del Mac."; });
            CopyWindowsCommand = new RelayCommand(_ => { _dialogs.CopyText(WindowsCommand); Message = "Comando para Windows copiado: pégalo en PowerShell del otro PC."; });
            AuthorizeCommand = new RelayCommand(_ => Do("link.authorize", new Dictionary<string, object> { { "key", Key } }, null), _ => !IsBusy && !String.IsNullOrWhiteSpace(Key));
            KeysCommand = new RelayCommand(_ => { var ignored = ShowKeysAsync(); }, _ => !IsBusy);
            TailscaleCommand = new RelayCommand(_ =>
            {
                string exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Tailscale", "tailscale-ipn.exe");
                if (File.Exists(exe)) Process.Start(exe); else Message = "Tailscale no está instalado: búscalo en Instalar (Acceso remoto).";
            });
        }

        public RelayCommand PrepareCommand { get; private set; }
        public RelayCommand CopyMacCommand { get; private set; }
        public RelayCommand CopyWindowsCommand { get; private set; }
        public RelayCommand AuthorizeCommand { get; private set; }
        public RelayCommand KeysCommand { get; private set; }
        public RelayCommand TailscaleCommand { get; private set; }
        public string Status { get { return _status; } private set { Set(ref _status, value); } }
        public string MacCommand { get { return _macCommand; } private set { Set(ref _macCommand, value); } }
        public string WindowsCommand { get { return _windowsCommand; } private set { Set(ref _windowsCommand, value); } }
        public string Guide { get { return _guide; } private set { Set(ref _guide, value); } }
        public string Key { get { return _key; } set { Set(ref _key, value ?? ""); } }
        public string Message { get { return _message; } private set { Set(ref _message, value ?? ""); } }
        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }
        public string PrepareLabel { get { return _ready ? "Volver a aplicar" : "Preparar este PC"; } }

        /// <summary>Permitir SSH en la red local privada (además de Tailscale).</summary>
        public bool LanAllowed
        {
            get { return _lanAllowed; }
            set
            {
                if (_lanAllowed == value || IsBusy) return;
                Do("link.lan", new Dictionary<string, object> { { "enabled", value } }, value ? "SSH permitido en la red local privada." : "SSH cerrado en la red local.");
            }
        }

        public void EnsureLoaded() { if (!_loaded) { _loaded = true; var ignored = LoadAsync(); } }

        private async Task LoadAsync()
        {
            var result = await _engine.RunAsync("link.status", null, null, TimeSpan.FromMinutes(2), CancellationToken.None);
            if (!result.Ok) { Status = "No se pudo leer el estado: " + result.Error; return; }
            var r = result.Response;
            _ready = Json.Flag(r, "ready"); _lanAllowed = Json.Flag(r, "lanAllowed"); _alias = Json.Text(r, "alias");
            OnPropertyChanged("LanAllowed"); OnPropertyChanged("PrepareLabel");
            string tailscale = Json.Text(r, "tailscale"), lan = Json.Text(r, "lan");
            Status = String.Join(Environment.NewLine, new[]
            {
                "Servidor SSH: " + (_ready ? "listo (solo claves)" : "sin preparar — pulsa «Preparar este PC»"),
                "Tailscale: " + (tailscale.Length > 0 ? tailscale + " (funciona desde cualquier red)" : "sin conexión — instálalo e inicia sesión para conectar fuera de casa"),
                "Red local: " + (lan.Length > 0 ? lan : "—") + (_lanAllowed ? " · permitida" : ""),
                "Usuario: " + Json.Text(r, "user") + "  ·  Equipos autorizados: " + Json.Number(r, "authorized")
            });
            MacCommand = Json.Text(r, "macCommand"); WindowsCommand = Json.Text(r, "windowsCommand");
            Guide = String.Join(Environment.NewLine, new[]
            {
                "Terminal: ssh " + _alias + "   (abre PowerShell de este PC)",
                "Copiar archivos: scp archivo.txt " + _alias + ":Desktop/",
                "Claude (app de escritorio o Claude Code): añade una conexión SSH con el host " + _alias + ".",
                "VS Code: extensión Remote - SSH › " + _alias + ".",
                "Portapapeles y archivos al vuelo: KDE Connect en ambos equipos (Instalar › Acceso remoto).",
                "Escritorio completo: Sunshine + Moonlight (perfil «Escritorio remoto»)."
            });
        }

        private async void Do(string command, Dictionary<string, object> request, string success)
        {
            IsBusy = true;
            try
            {
                var result = await _engine.RunAsync(command, request, null, TimeSpan.FromMinutes(20), CancellationToken.None);
                if (!result.Ok) Message = result.Error ?? "No se pudo completar.";
                else
                {
                    Message = success ?? Json.Text(result.Response, "message");
                    if (command == "link.authorize" && Json.Flag(result.Response, "added")) Key = "";
                }
                await LoadAsync();
            }
            catch (Exception e) { Message = e.Message; }
            finally { IsBusy = false; }
        }

        private async Task ShowKeysAsync()
        {
            var result = await _engine.RunAsync("link.keys", null, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (!result.Ok) { Message = result.Error; return; }
            object keys;
            var list = result.Response.TryGetValue("keys", out keys) && keys is object[] ? ((object[])keys).Select(k => Convert.ToString(k)).ToList() : new List<string>();
            _dialogs.Inform("Equipos autorizados", list.Count == 0 ? "Ninguno." : String.Join(Environment.NewLine, list) + Environment.NewLine + Environment.NewLine + "Para quitar uno, borra su línea en:" + Environment.NewLine + Json.Text(result.Response, "path") + " (necesita administrador).");
        }
    }

    /// <summary>Ajustes de la app: actualización automática, buscar versión nueva, diagnóstico y actividad.</summary>
    public sealed class SettingsViewModel : ObservableObject
    {
        private readonly EngineClient _engine;
        private string _message = "", _version = "", _logDir = "";
        private bool _autoUpdate, _isBusy, _loaded;

        public SettingsViewModel(EngineClient engine)
        {
            _engine = engine;
            SelfUpdateCommand = new RelayCommand(_ => Do("app.selfupdate", null), _ => !IsBusy);
            DiagnosticCommand = new RelayCommand(_ => Do("app.diagnostic", null), _ => !IsBusy);
            ActivityCommand = new RelayCommand(_ => { if (Directory.Exists(_logDir)) Process.Start("explorer.exe", "\"" + _logDir + "\""); });
        }

        public RelayCommand SelfUpdateCommand { get; private set; }
        public RelayCommand DiagnosticCommand { get; private set; }
        public RelayCommand ActivityCommand { get; private set; }
        public string Message { get { return _message; } private set { Set(ref _message, value ?? ""); } }
        public string Version { get { return _version; } private set { Set(ref _version, value); } }
        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }

        public bool AutoUpdate
        {
            get { return _autoUpdate; }
            set { if (_autoUpdate != value && !IsBusy) Do("app.autoupdate", new Dictionary<string, object> { { "enabled", value } }); }
        }

        public void EnsureLoaded() { if (!_loaded) { _loaded = true; var ignored = LoadAsync(); } }

        private async Task LoadAsync()
        {
            var result = await _engine.RunAsync("app.info", null, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (!result.Ok) { Message = result.Error; return; }
            _autoUpdate = Json.Flag(result.Response, "autoUpdate"); OnPropertyChanged("AutoUpdate");
            _logDir = Json.Text(result.Response, "logDir");
            Version = "iWinInstaller " + Json.Text(result.Response, "version") + " · instalada en " + Json.Text(result.Response, "installDir");
        }

        private async void Do(string command, Dictionary<string, object> request)
        {
            IsBusy = true;
            try
            {
                var result = await _engine.RunAsync(command, request, null, TimeSpan.FromMinutes(30), CancellationToken.None);
                if (!result.Ok) { Message = result.Error ?? "No se pudo completar."; }
                else if (command == "app.diagnostic")
                {
                    string path = Json.Text(result.Response, "path");
                    Message = "Diagnóstico guardado en Descargas: " + Path.GetFileName(path) + ". Revísalo antes de compartirlo.";
                    if (File.Exists(path)) Process.Start("explorer.exe", "/select,\"" + path + "\"");
                }
                else if (command == "app.selfupdate") Message = Json.Flag(result.Response, "ok") ? "iWinInstaller está al día o la versión nueva se aplicará al cerrar la app." : "No se pudo actualizar iWinInstaller: revisa la conexión y reintenta.";
                else if (command == "app.autoupdate") Message = Json.Flag(result.Response, "autoUpdate") ? "Actualización automática activada: comprueba al iniciar sesión y cada día." : "Actualización automática desactivada.";
                await LoadAsync();
            }
            catch (Exception e) { Message = e.Message; }
            finally { IsBusy = false; }
        }
    }
}
