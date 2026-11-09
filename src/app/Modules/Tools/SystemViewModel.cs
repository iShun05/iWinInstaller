using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;

namespace IWinInstaller.App.Modules.Tools
{
    public sealed class ModeChoice
    {
        public ModeChoice(int width, int height, int hz, string label) { Width = width; Height = height; Hz = hz; Label = label; }
        public int Width { get; private set; }
        public int Height { get; private set; }
        public int Hz { get; private set; }
        public string Label { get; private set; }
        public override string ToString() { return Label; }
    }

    public sealed class MinutesChoice
    {
        public MinutesChoice(int minutes, string label) { Minutes = minutes; Label = label; }
        public int Minutes { get; private set; }
        public string Label { get; private set; }
        public override string ToString() { return Label; }
    }

    /// <summary>Sistema: resolución y Hz de cada monitor (vuelve solo al anterior si no confirmas) y energía del plan activo.</summary>
    public sealed class SystemViewModel : ObservableObject
    {
        public static readonly int[] PowerSteps = { 0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 120, 180, 300 };
        private readonly EngineClient _engine;
        private readonly Dispatcher _dispatcher;
        private MonitorInfo _monitor;
        private ModeChoice _resolution, _rate;
        private string _current = "", _message = "", _plan = "";
        private bool _confirming, _isBusy, _loaded;
        private int _secondsLeft;
        private DispatcherTimer _timer;
        private DisplayMode? _previous;
        private MinutesChoice _monitorOff, _sleep, _hibernateAfter;
        private bool _hibernate;

        public SystemViewModel(EngineClient engine, Dispatcher dispatcher)
        {
            _engine = engine; _dispatcher = dispatcher;
            Monitors = new ObservableCollection<MonitorInfo>();
            Resolutions = new ObservableCollection<ModeChoice>();
            Rates = new ObservableCollection<ModeChoice>();
            MonitorOffChoices = new ObservableCollection<MinutesChoice>();
            SleepChoices = new ObservableCollection<MinutesChoice>();
            HibernateAfterChoices = new ObservableCollection<MinutesChoice>();
            ApplyDisplayCommand = new RelayCommand(_ => ApplyDisplay(), _ => !Confirming && _monitor != null && _rate != null);
            KeepCommand = new RelayCommand(_ => EndConfirm(true), _ => Confirming);
            RevertCommand = new RelayCommand(_ => EndConfirm(false), _ => Confirming);
            ApplyPowerCommand = new RelayCommand(_ => { var ignored = ApplyPowerAsync(); }, _ => !IsBusy && _monitorOff != null && _sleep != null && _hibernateAfter != null);
            RefreshCommand = new RelayCommand(_ => Load(), _ => !IsBusy);
        }

        public ObservableCollection<MonitorInfo> Monitors { get; private set; }
        public ObservableCollection<ModeChoice> Resolutions { get; private set; }
        public ObservableCollection<ModeChoice> Rates { get; private set; }
        public ObservableCollection<MinutesChoice> MonitorOffChoices { get; private set; }
        public ObservableCollection<MinutesChoice> SleepChoices { get; private set; }
        public ObservableCollection<MinutesChoice> HibernateAfterChoices { get; private set; }
        public RelayCommand ApplyDisplayCommand { get; private set; }
        public RelayCommand KeepCommand { get; private set; }
        public RelayCommand RevertCommand { get; private set; }
        public RelayCommand ApplyPowerCommand { get; private set; }
        public RelayCommand RefreshCommand { get; private set; }

        public string Current { get { return _current; } private set { Set(ref _current, value); } }
        public string Message { get { return _message; } private set { Set(ref _message, value ?? ""); } }
        public string Plan { get { return _plan; } private set { Set(ref _plan, value ?? ""); } }
        public bool Confirming { get { return _confirming; } private set { Set(ref _confirming, value); } }
        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }
        public string ConfirmText { get { return "¿Mantener este modo? Vuelve al anterior en " + _secondsLeft + " s."; } }
        public bool Hibernate { get { return _hibernate; } set { Set(ref _hibernate, value); } }
        public MinutesChoice MonitorOff { get { return _monitorOff; } set { Set(ref _monitorOff, value); } }
        public MinutesChoice Sleep { get { return _sleep; } set { Set(ref _sleep, value); } }
        public MinutesChoice HibernateAfter { get { return _hibernateAfter; } set { Set(ref _hibernateAfter, value); } }

        public MonitorInfo Monitor { get { return _monitor; } set { if (Set(ref _monitor, value)) FillResolutions(); } }
        public ModeChoice Resolution { get { return _resolution; } set { if (Set(ref _resolution, value)) FillRates(); } }
        public ModeChoice Rate { get { return _rate; } set { Set(ref _rate, value); } }

        public void EnsureLoaded() { if (!_loaded) { _loaded = true; Load(); } }

        private void Load()
        {
            Monitors.Clear();
            try { foreach (var monitor in DisplaySettings.Monitors()) Monitors.Add(monitor); }
            catch (Exception e) { Message = "No se pudieron leer los monitores: " + e.Message; }
            Monitor = Monitors.FirstOrDefault(m => m.Primary) ?? Monitors.FirstOrDefault();
            if (Monitor == null) Message = "No se encontró ningún monitor activo.";
            var ignored = LoadPowerAsync();
        }

        private void FillResolutions()
        {
            Resolutions.Clear(); Rates.Clear();
            if (_monitor == null) return;
            var current = DisplaySettings.CurrentMode(_monitor.Device);
            Current = current.HasValue ? "Ahora: " + current.Value.Width + " × " + current.Value.Height + " a " + current.Value.Hz + " Hz" : "No se pudo leer el modo actual de este monitor.";
            var sizes = DisplaySettings.Modes(_monitor.Device).GroupBy(m => new { m.Width, m.Height })
                .OrderByDescending(g => (long)g.Key.Width * g.Key.Height).ThenByDescending(g => g.Key.Width).ToList();
            ModeChoice select = null;
            for (int i = 0; i < sizes.Count; i++)
            {
                var size = sizes[i].Key;
                bool isCurrent = current.HasValue && current.Value.Width == size.Width && current.Value.Height == size.Height;
                var choice = new ModeChoice(size.Width, size.Height, 0, size.Width + " × " + size.Height + (i == 0 ? " (máxima)" : "") + (isCurrent ? " · actual" : ""));
                Resolutions.Add(choice);
                if (isCurrent) select = choice;
            }
            Resolution = select ?? Resolutions.FirstOrDefault();
        }

        private void FillRates()
        {
            Rates.Clear();
            if (_monitor == null || _resolution == null) return;
            var current = DisplaySettings.CurrentMode(_monitor.Device);
            foreach (int hz in DisplaySettings.Modes(_monitor.Device).Where(m => m.Width == _resolution.Width && m.Height == _resolution.Height).Select(m => m.Hz).Distinct().OrderByDescending(h => h))
                Rates.Add(new ModeChoice(_resolution.Width, _resolution.Height, hz, hz + " Hz"));
            Rate = Rates.FirstOrDefault(r => current.HasValue && r.Hz == current.Value.Hz) ?? Rates.FirstOrDefault();
        }

        private void ApplyDisplay()
        {
            var before = DisplaySettings.CurrentMode(_monitor.Device);
            if (before.HasValue && before.Value.Width == _rate.Width && before.Value.Height == _rate.Height && before.Value.Hz == _rate.Hz) { Message = "Ese ya es el modo actual."; return; }
            int code = DisplaySettings.Apply(_monitor.Device, new DisplayMode(_rate.Width, _rate.Height, _rate.Hz));
            if (code == 1) { Message = "Windows aplicará ese modo después de reiniciar."; return; }
            if (code != 0) { Message = "Windows no admite " + _rate.Width + " × " + _rate.Height + " a " + _rate.Hz + " Hz en este monitor (código " + code + ")."; return; }
            // Como Windows: si no se confirma en 15 s (p. ej. la pantalla se queda en negro) vuelve al modo anterior
            _previous = before;
            _secondsLeft = 15;
            Confirming = true;
            OnPropertyChanged("ConfirmText");
            _timer = new DispatcherTimer(TimeSpan.FromSeconds(1), DispatcherPriority.Normal, (s, e) =>
            {
                _secondsLeft--;
                OnPropertyChanged("ConfirmText");
                if (_secondsLeft <= 0) EndConfirm(false);
            }, _dispatcher);
            _timer.Start();
        }

        private void EndConfirm(bool keep)
        {
            if (_timer != null) { _timer.Stop(); _timer = null; }
            Confirming = false;
            if (keep) Message = "Pantalla: " + _rate.Width + " × " + _rate.Height + " a " + _rate.Hz + " Hz.";
            else if (_previous.HasValue)
            {
                DisplaySettings.Apply(_monitor.Device, _previous.Value);
                Message = "Se restauró " + _previous.Value.Width + " × " + _previous.Value.Height + " a " + _previous.Value.Hz + " Hz.";
            }
            FillResolutions();
        }

        public static string FormatMinutes(int minutes)
        {
            if (minutes == 0) return "Nunca";
            return minutes < 60 ? minutes + " min" : (minutes % 60 == 0 ? (minutes / 60) + " h" : minutes + " min");
        }

        /// <summary>Opciones del desplegable con el valor actual incluido aunque no sea uno de los pasos.</summary>
        public static List<MinutesChoice> BuildChoices(int? current)
        {
            var list = PowerSteps.Select(m => new MinutesChoice(m, FormatMinutes(m))).ToList();
            if (current.HasValue && current.Value > 0 && !PowerSteps.Contains(current.Value))
                list.Add(new MinutesChoice(current.Value, FormatMinutes(current.Value) + " (actual)"));
            return list;
        }

        private static void Fill(ObservableCollection<MinutesChoice> target, int? current)
        {
            target.Clear();
            foreach (var choice in BuildChoices(current)) target.Add(choice);
        }

        private async Task LoadPowerAsync()
        {
            var result = await _engine.RunAsync("power.get", null, null, TimeSpan.FromMinutes(1), CancellationToken.None);
            if (!result.Ok) { Message = "No se pudo leer el plan de energía: " + result.Error; return; }
            int? monitor = ReadInt(result.Response, "monitor"), sleep = ReadInt(result.Response, "sleep"), hibernate = ReadInt(result.Response, "hibernateAfter");
            Fill(MonitorOffChoices, monitor); Fill(SleepChoices, sleep); Fill(HibernateAfterChoices, hibernate);
            MonitorOff = MonitorOffChoices.FirstOrDefault(c => c.Minutes == (monitor ?? 0)) ?? MonitorOffChoices[0];
            Sleep = SleepChoices.FirstOrDefault(c => c.Minutes == (sleep ?? 0)) ?? SleepChoices[0];
            HibernateAfter = HibernateAfterChoices.FirstOrDefault(c => c.Minutes == (hibernate ?? 0)) ?? HibernateAfterChoices[0];
            object flag;
            Hibernate = result.Response.TryGetValue("hibernate", out flag) && flag is bool && (bool)flag;
            object plan;
            Plan = result.Response.TryGetValue("plan", out plan) && plan != null && Convert.ToString(plan).Length > 0 ? "Plan activo: " + plan : "";
        }

        private async Task ApplyPowerAsync()
        {
            IsBusy = true;
            try
            {
                var request = new Dictionary<string, object> { { "monitor", MonitorOff.Minutes }, { "sleep", Sleep.Minutes }, { "hibernateAfter", HibernateAfter.Minutes }, { "hibernate", Hibernate } };
                var result = await _engine.RunAsync("power.set", request, null, TimeSpan.FromMinutes(3), CancellationToken.None);
                if (!result.Ok) { Message = "No se pudo cambiar la energía: " + result.Error; return; }
                object failed;
                bool hibernateFailed = result.Response.TryGetValue("hibernateFailed", out failed) && failed is bool && (bool)failed;
                Message = hibernateFailed ? "Tiempos guardados. La hibernación no cambió (hace falta permiso de administrador)."
                    : "Energía: pantalla " + FormatMinutes(MonitorOff.Minutes) + ", suspensión " + FormatMinutes(Sleep.Minutes) + ", hibernación " + (Hibernate ? "activada" : "desactivada") + ".";
                await LoadPowerAsync();
            }
            finally { IsBusy = false; }
        }

        private static int? ReadInt(Dictionary<string, object> data, string key)
        {
            object value;
            if (!data.TryGetValue(key, out value) || value == null) return null;
            return Convert.ToInt32(value, System.Globalization.CultureInfo.InvariantCulture);
        }
    }
}
