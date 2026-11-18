using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using IWinInstaller.App.Modules.Games;

namespace IWinInstaller.App.Modules.Rendimiento
{
    /// <summary>Un valor DWORD de HKCU que cambia una acción, con el valor que Windows usa cuando no existe.</summary>
    public sealed class RegChange
    {
        public RegChange(string key, string name, int value, int missing) { Key = key; Name = name; Value = value; WhenMissing = missing; }
        public string Key { get; private set; }
        public string Name { get; private set; }
        public int Value { get; private set; }
        public int WhenMissing { get; private set; }
    }

    public sealed class PerfAction
    {
        public string Id { get; set; }
        public string Title { get; set; }
        public string Description { get; set; }
        public bool IsPower { get; set; }
        public RegChange[] Changes { get; set; }
    }

    public sealed class PerfStatus
    {
        public bool Applied { get; set; }
        public bool Available { get; set; }
        /// <summary>Hay un estado anterior guardado: se puede deshacer.</summary>
        public bool CanUndo { get; set; }
        public string Detail { get; set; }
    }

    public sealed class PerfResult
    {
        public PerfResult(bool ok, string message) { Ok = ok; Message = message; }
        public bool Ok { get; private set; }
        public string Message { get; private set; }
    }

    /// <summary>Acciones de rendimiento que se aplican desde la app: solo HKCU (sin administrador) y el plan de energía; todas se deshacen.</summary>
    public static class PerfCatalog
    {
        public const string HighPerformance = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";

        public static readonly IList<PerfAction> All = new List<PerfAction>
        {
            new PerfAction
            {
                Id = "gamemode", Title = "Modo Juego de Windows activado",
                Description = "Windows da prioridad al juego en primer plano y evita que Windows Update reinstale controladores o reinicie mientras juegas.",
                Changes = new[]
                {
                    new RegChange(@"HKCU\Software\Microsoft\GameBar", "AutoGameModeEnabled", 1, 1),
                    new RegChange(@"HKCU\Software\Microsoft\GameBar", "AllowAutoGameMode", 1, 1)
                }
            },
            new PerfAction
            {
                Id = "capture", Title = "Sin grabación de partidas en segundo plano",
                Description = "Desactiva Xbox Game DVR y las capturas automáticas: libera CPU, GPU y disco, y quita el aviso de captura en pantalla.",
                Changes = new[]
                {
                    new RegChange(@"HKCU\System\GameConfigStore", "GameDVR_Enabled", 0, 1),
                    new RegChange(@"HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR", "AppCaptureEnabled", 0, 1)
                }
            },
            new PerfAction
            {
                Id = "transparency", Title = "Sin transparencias en Windows",
                Description = "Quita el desenfoque de ventanas, Inicio y barra de tareas: menos trabajo para la gráfica integrada y para DWM.",
                Changes = new[] { new RegChange(@"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "EnableTransparency", 0, 1) }
            },
            new PerfAction
            {
                Id = "background", Title = "Apps de la Tienda sin segundo plano",
                Description = "Impide que las apps de la Tienda (UWP) se ejecuten en segundo plano: menos procesos y menos consumo. Las apps de escritorio no se tocan.",
                Changes = new[] { new RegChange(@"HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications", "GlobalUserDisabled", 1, 0) }
            },
            new PerfAction
            {
                Id = "power", Title = "Plan de energía Alto rendimiento", IsPower = true,
                Description = "Mantiene la CPU sin bajar frecuencia al jugar o compilar. En portátil gasta más batería: úsalo con el cargador y deshaz al terminar."
            }
        };

        public static PerfAction Find(string id) { return All.FirstOrDefault(a => a.Id == id); }
    }

    /// <summary>Lee, aplica y deshace las acciones. Antes de escribir guarda el valor original; si la comprobación posterior falla, lo devuelve.</summary>
    public sealed class PerfService
    {
        private readonly IGameEnvironment _env;
        private readonly IPerfHost _host;
        private readonly PerfStore _store;

        public PerfService(IGameEnvironment env, IPerfHost host, PerfStore store) { _env = env; _host = host; _store = store; }

        private int Current(RegChange change)
        {
            object value = _env.GetValue(change.Key, change.Name);
            return value is int ? (int)value : change.WhenMissing;
        }

        public PerfStatus Status(PerfAction action)
        {
            if (action.IsPower)
            {
                string active = _host.ActivePowerScheme();
                bool exists = active == PerfCatalog.HighPerformance || _host.PowerSchemeExists(PerfCatalog.HighPerformance);
                return new PerfStatus
                {
                    Applied = active == PerfCatalog.HighPerformance, Available = exists,
                    CanUndo = _store.LoadPowerPrevious() != null && active == PerfCatalog.HighPerformance,
                    Detail = !exists ? "Este equipo no tiene el plan Alto rendimiento (Windows lo oculta en algunos portátiles)." : ""
                };
            }
            bool all = action.Changes.All(c => Current(c) == c.Value);
            return new PerfStatus { Applied = all, Available = true, CanUndo = _store.LoadOriginals().ContainsKey(action.Id) };
        }

        public PerfResult Apply(PerfAction action)
        {
            try { return action.IsPower ? ApplyPower() : ApplyRegistry(action); }
            catch (Exception e) when (e is IOException || e is UnauthorizedAccessException || e is System.Security.SecurityException)
            { return new PerfResult(false, "No se pudo aplicar: " + e.Message); }
        }

        public PerfResult Undo(PerfAction action)
        {
            try { return action.IsPower ? UndoPower() : UndoRegistry(action); }
            catch (Exception e) when (e is IOException || e is UnauthorizedAccessException || e is System.Security.SecurityException)
            { return new PerfResult(false, "No se pudo deshacer: " + e.Message); }
        }

        private PerfResult ApplyRegistry(PerfAction action)
        {
            if (action.Changes.All(c => Current(c) == c.Value)) return new PerfResult(true, "Ya estaba así: no se cambia nada.");
            var originals = _store.LoadOriginals();
            if (!originals.ContainsKey(action.Id))
            {
                originals[action.Id] = action.Changes.Select(Capture).ToList();
                _store.SaveOriginals(originals);
            }
            foreach (var c in action.Changes) _env.SetValue(c.Key, c.Name, c.Value, RegKind.DWord);
            if (!action.Changes.All(c => Current(c) == c.Value))
            {
                RestoreOriginals(originals[action.Id]);
                originals.Remove(action.Id);
                _store.SaveOriginals(originals);
                return new PerfResult(false, "Windows no aceptó el cambio; se ha dejado como estaba.");
            }
            return new PerfResult(true, "Aplicado. Si algo no te gusta, pulsa Deshacer.");
        }

        private RegOriginal Capture(RegChange change)
        {
            object value = _env.GetValue(change.Key, change.Name);
            var original = new RegOriginal { Key = change.Key, Name = change.Name, Existed = value != null };
            if (value is int) { original.Kind = "dword"; original.Data = (int)value; }
            else { original.Kind = "string"; original.Data = value as string; original.Existed = value is string; }
            return original;
        }

        private void RestoreOriginals(IEnumerable<RegOriginal> items)
        {
            foreach (var o in items)
            {
                if (!o.Existed) _env.DeleteValue(o.Key, o.Name);
                else if (o.Kind == "dword" && o.Data is int) _env.SetValue(o.Key, o.Name, (int)o.Data, RegKind.DWord);
                else if (o.Kind == "string" && o.Data is string) _env.SetValue(o.Key, o.Name, (string)o.Data, RegKind.String);
            }
        }

        private PerfResult UndoRegistry(PerfAction action)
        {
            var originals = _store.LoadOriginals();
            List<RegOriginal> saved;
            if (!originals.TryGetValue(action.Id, out saved))
                return new PerfResult(false, "No hay estado anterior guardado: este ajuste ya estaba así antes de usar la app o se aplicó desde otro sitio.");
            RestoreOriginals(saved);
            originals.Remove(action.Id);
            _store.SaveOriginals(originals);
            return new PerfResult(true, "Deshecho: vuelve a estar como antes.");
        }

        private PerfResult ApplyPower()
        {
            string current = _host.ActivePowerScheme();
            if (current == PerfCatalog.HighPerformance) return new PerfResult(true, "Ya estaba activo.");
            if (!_host.PowerSchemeExists(PerfCatalog.HighPerformance))
                return new PerfResult(false, "Este equipo no tiene el plan Alto rendimiento; no se cambia nada.");
            if (current != null && _store.LoadPowerPrevious() == null) _store.SavePowerPrevious(current);
            if (!_host.SetPowerScheme(PerfCatalog.HighPerformance) || _host.ActivePowerScheme() != PerfCatalog.HighPerformance)
            {
                if (current != null) _host.SetPowerScheme(current);
                _store.SavePowerPrevious(null);
                return new PerfResult(false, "Windows no cambió el plan de energía; se ha dejado como estaba.");
            }
            return new PerfResult(true, "Plan Alto rendimiento activo. Deshaz al terminar para ahorrar batería y ruido.");
        }

        private PerfResult UndoPower()
        {
            string previous = _store.LoadPowerPrevious();
            if (previous == null) return new PerfResult(false, "No hay plan anterior guardado: elige tú el plan en Sistema › Energía.");
            if (!_host.PowerSchemeExists(previous)) { _store.SavePowerPrevious(null); return new PerfResult(false, "El plan anterior ya no existe en este equipo."); }
            if (!_host.SetPowerScheme(previous)) return new PerfResult(false, "Windows no pudo volver al plan anterior.");
            _store.SavePowerPrevious(null);
            return new PerfResult(true, "Vuelve el plan de energía anterior.");
        }
    }

    /// <summary>Un programa abierto que gasta memoria y se puede cerrar con calma desde la app.</summary>
    public sealed class HeavyApp
    {
        public string Name { get; set; }
        public long Mb { get; set; }
        public int Instances { get; set; }
        public List<int> WindowPids { get; set; }
    }

    public static class HeavyApps
    {
        /// <summary>Procesos que nunca se ofrecen: sistema, escritorio, antivirus, esta app y herramientas de arranque.</summary>
        public static readonly string[] Protected =
        {
            "explorer", "dwm", "winlogon", "csrss", "svchost", "system", "idle", "services", "lsass", "wininit", "smss", "fontdrvhost",
            "searchhost", "searchapp", "startmenuexperiencehost", "shellexperiencehost", "textinputhost", "applicationframehost", "sihost", "ctfmon",
            "taskmgr", "msmpeng", "securityhealthsystray", "nissrv", "iwininstaller*", "iwininstaller.app", "claude*", "powershell*", "pwsh", "windowsterminal", "conhost"
        };

        public static List<HeavyApp> Find(IEnumerable<ProcInfo> processes, int minimumMb = 150, int top = 8)
        {
            return processes
                .Where(p => !string.IsNullOrEmpty(p.Name) && !ProcessMatcher.MatchesAny(p.Name, Protected))
                .GroupBy(p => p.Name, StringComparer.OrdinalIgnoreCase)
                .Where(g => g.Any(p => p.HasWindow))
                .Select(g => new HeavyApp
                {
                    Name = g.Key, Mb = g.Sum(p => p.WorkingSetMb), Instances = g.Count(),
                    WindowPids = g.Where(p => p.HasWindow).Select(p => p.Id).ToList()
                })
                .Where(a => a.Mb >= minimumMb)
                .OrderByDescending(a => a.Mb)
                .Take(top)
                .ToList();
        }
    }
}
