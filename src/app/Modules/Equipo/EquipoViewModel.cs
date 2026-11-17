using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Threading;
using IWinInstaller.App.Core;

namespace IWinInstaller.App.Modules.Equipo
{
    /// <summary>
    /// Página Equipo: hardware detectado, preset «Dev + Gaming competitivo» ajustado a él y panel de salud
    /// (Defender, Windows Update, disco, apps de inicio y temperaturas). Lee solo al entrar o al pulsar Comprobar:
    /// no deja procesos ni temporizadores en marcha.
    /// </summary>
    public sealed class EquipoViewModel : ObservableObject
    {
        private readonly Dispatcher _dispatcher;
        private readonly Action<string> _runAction;
        private readonly Action<IEnumerable<string>, string> _applyPreset;
        private bool _loaded, _isBusy;
        private string _machine = "Leyendo el equipo…", _cpu = "", _ram = "", _gpu = "", _display = "", _tier = "", _planText = "", _checked = "";
        private PresetPlan _plan;

        public EquipoViewModel(Dispatcher dispatcher, Action<string> runAction, Action<IEnumerable<string>, string> applyPreset)
        {
            _dispatcher = dispatcher; _runAction = runAction; _applyPreset = applyPreset;
            Notes = new ObservableCollection<PresetNote>();
            Cards = new ObservableCollection<StatusCard>
            {
                new StatusCard("antivirus", "Microsoft Defender"),
                new StatusCard("windowsUpdate", "Windows Update"),
                new StatusCard("diskSpace", "Espacio en disco"),
                new StatusCard("startup", "Apps de inicio"),
                new StatusCard("thermal", "Temperaturas")
            };
            RefreshCommand = new RelayCommand(_ => Refresh(), _ => !IsBusy);
            ApplyPresetCommand = new RelayCommand(_ => { if (_plan != null) _applyPreset(_plan.Ids, _plan.ProfileName); }, _ => _plan != null && !IsBusy);
            OpenActionCommand = new RelayCommand(p => { var card = p as StatusCard; if (card != null) _runAction(card.ActionId); });
            OpenNoteCommand = new RelayCommand(p => { var note = p as PresetNote; if (note != null && note.ActionId.Length > 0) _runAction(note.ActionId); });
        }

        public ObservableCollection<PresetNote> Notes { get; private set; }
        public ObservableCollection<StatusCard> Cards { get; private set; }
        public RelayCommand RefreshCommand { get; private set; }
        public RelayCommand ApplyPresetCommand { get; private set; }
        public RelayCommand OpenActionCommand { get; private set; }
        public RelayCommand OpenNoteCommand { get; private set; }

        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }
        public string Machine { get { return _machine; } private set { Set(ref _machine, value); } }
        public string Cpu { get { return _cpu; } private set { Set(ref _cpu, value); } }
        public string Ram { get { return _ram; } private set { Set(ref _ram, value); } }
        public string Gpu { get { return _gpu; } private set { Set(ref _gpu, value); } }
        public string Display { get { return _display; } private set { Set(ref _display, value); } }
        public string Tier { get { return _tier; } private set { Set(ref _tier, value); } }
        public string PlanText { get { return _planText; } private set { Set(ref _planText, value); } }
        public string LastChecked { get { return _checked; } private set { Set(ref _checked, value); } }

        /// <summary>Al entrar en la página: la primera vez lee todo; después solo con Comprobar.</summary>
        public void EnsureLoaded()
        {
            if (_loaded) return;
            _loaded = true;
            Refresh();
        }

        private void Refresh()
        {
            if (IsBusy) return;
            IsBusy = true;
            var hardware = Task.Run(() => EquipoProbes.Hardware()).ContinueWith(t =>
            {
                if (t.IsFaulted) _dispatcher.BeginInvoke(new Action(() => Machine = "No se pudo leer el equipo: " + t.Exception.GetBaseException().Message));
                else _dispatcher.BeginInvoke(new Action(() => ShowHardware(t.Result)));
            }, TaskScheduler.Default);
            var health = new[]
            {
                RunCheck("antivirus", EquipoProbes.Defender),
                RunCheck("windowsUpdate", EquipoProbes.WindowsUpdate),
                RunCheck("diskSpace", EquipoProbes.Disk),
                RunCheck("startup", EquipoProbes.Startup),
                RunCheck("thermal", EquipoProbes.Temperature)
            };
            Task.WhenAll(health.Concat(new[] { hardware })).ContinueWith(_ => _dispatcher.BeginInvoke(new Action(() =>
            {
                LastChecked = "Comprobado a las " + DateTime.Now.ToString("HH:mm");
                IsBusy = false;
            })), TaskScheduler.Default);
        }

        private Task RunCheck(string area, Func<StatusResult> probe)
        {
            return Task.Run(probe).ContinueWith(t =>
            {
                var result = t.IsFaulted ? StatusResult.Unknown("No se pudo comprobar", t.Exception.GetBaseException().Message) : t.Result;
                _dispatcher.BeginInvoke(new Action(() =>
                {
                    var card = Cards.FirstOrDefault(c => c.Area == area);
                    if (card != null) card.Apply(result.State, result.Summary, result.Reason, result.ActionId);
                }));
            }, TaskScheduler.Default);
        }

        private void ShowHardware(HardwareInfo hw)
        {
            var plan = PresetPlanner.Plan(hw);
            _plan = plan;
            string maker = (hw.Manufacturer + " " + hw.Model).Trim();
            Machine = HardwareClassifier.FormFactorLabel(hw.FormFactor) + (maker.Length > 0 ? " · " + maker : "");
            Cpu = hw.CpuName.Length == 0 ? "Procesador: sin datos" : hw.CpuName + (hw.Cores > 0 ? " · " + hw.Cores + " núcleos, " + hw.Threads + " hilos" : "");
            Ram = hw.RamGb > 0 ? "Memoria: " + Math.Round(hw.RamGb) + " GB" : "Memoria: sin datos";
            Gpu = hw.Gpus.Count == 0 ? "Gráfica: sin datos" : "Gráfica: " + String.Join(" + ", hw.Gpus.Select(g => g.Name + (g.Discrete ? " (dedicada)" : " (integrada)")));
            Display = hw.RefreshHz > 0 ? "Pantalla: " + hw.Width + "×" + hw.Height + " a " + hw.RefreshHz + " Hz" + (hw.MaxRefreshHz > hw.RefreshHz ? " (admite " + hw.MaxRefreshHz + " Hz)" : "") : "Pantalla: sin datos";
            Tier = "Gama " + HardwareClassifier.TierLabel(plan.Tier).ToLowerInvariant();
            PlanText = plan.Ids.Count + " ajustes y apps para marcar en Instalar. Nada se instala hasta que pulses Instalar allí.";
            Notes.Clear();
            foreach (var note in plan.Notes) Notes.Add(note);
            OnPropertyChanged("HasNotes");
        }

        public bool HasNotes { get { return Notes.Count > 0; } }
    }
}
