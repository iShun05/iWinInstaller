using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using IWinInstaller.App.Modules.Games;

namespace IWinInstaller.App.Modules.Rendimiento
{
    /// <summary>Opciones del perfil de un juego: qué se hace al lanzarlo (todo se deshace al salir).</summary>
    public sealed class ProfileOptions
    {
        public bool Priority = true;
        public bool PowerPlan = true;
        public bool CloseOverlays = true;
        public bool CloseBrowsers = true;

        public ProfileOptions Clone() { return new ProfileOptions { Priority = Priority, PowerPlan = PowerPlan, CloseOverlays = CloseOverlays, CloseBrowsers = CloseBrowsers }; }
    }

    /// <summary>Un juego añadido a mano: nombre del proceso sin «.exe».</summary>
    public sealed class CustomGame
    {
        public string Process { get; set; }
        public string Title { get; set; }
    }

    public sealed class ProfileSettings
    {
        public ProfileSettings() { Options = new Dictionary<string, ProfileOptions>(StringComparer.OrdinalIgnoreCase); Custom = new List<CustomGame>(); }
        /// <summary>Interruptor general: apagado por defecto. Con él apagado la app no vigila nada.</summary>
        public bool Enabled { get; set; }
        public Dictionary<string, ProfileOptions> Options { get; private set; }
        public List<CustomGame> Custom { get; private set; }

        public ProfileOptions For(string id)
        {
            ProfileOptions options;
            return Options.TryGetValue(id, out options) ? options : new ProfileOptions();
        }
    }

    /// <summary>Lo que el perfil cambió al lanzar el juego, guardado para deshacerlo aunque la app se cierre antes.</summary>
    public sealed class ProfileSession
    {
        public ProfileSession() { Closed = new List<ClosedApp>(); }
        public string GameId { get; set; }
        public string Title { get; set; }
        public int Pid { get; set; }
        public string ProcessName { get; set; }
        public string PreviousPriority { get; set; }
        public string PreviousPower { get; set; }
        public string AppliedPower { get; set; }
        public bool PriorityChanged { get; set; }
        public DateTime StartedUtc { get; set; }
        public List<ClosedApp> Closed { get; private set; }
    }

    public sealed class ClosedApp
    {
        public string Name { get; set; }
        public string Path { get; set; }
    }

    /// <summary>Un valor del registro tal y como estaba antes de cambiarlo.</summary>
    public sealed class RegOriginal
    {
        public string Key { get; set; }
        public string Name { get; set; }
        public bool Existed { get; set; }
        /// <summary>«dword» o «string».</summary>
        public string Kind { get; set; }
        public object Data { get; set; }
    }

    /// <summary>Una medición del equipo en un momento dado (antes o después de un ajuste).</summary>
    public sealed class PerfSnapshot
    {
        public DateTime AtUtc { get; set; }
        public string Label { get; set; }
        /// <summary>Sobrecarga de Sleep(1) en ms: mediana, p95 y p99 (planificador y temporizador de Windows).</summary>
        public double? SchedP50 { get; set; }
        public double? SchedP95 { get; set; }
        public double? SchedP99 { get; set; }
        public double? PingAvg { get; set; }
        public double? PingJitter { get; set; }
        public double? PingLoss { get; set; }
        /// <summary>Solo si PresentMon capturó un juego.</summary>
        public double? Fps { get; set; }
        public double? FrameP99 { get; set; }
        public double? Low1Fps { get; set; }
        public string Game { get; set; }
    }

    /// <summary>Un aviso térmico guardado en el historial.</summary>
    public sealed class ThermalEvent
    {
        public DateTime AtUtc { get; set; }
        /// <summary>«hot» (temperatura alta), «throttle» (frecuencia recortada) o «summary» (resumen de la partida).</summary>
        public string Kind { get; set; }
        public string Game { get; set; }
        public string Detail { get; set; }
        public double? PeakC { get; set; }
    }

    /// <summary>
    /// Estado de la sección Rendimiento en %LOCALAPPDATA%\iWinInstaller\Rendimiento: estado.json (valores originales, ajustes
    /// del perfil y sesión activa), mediciones.json y termico.json. Escritura atómica; un archivo dañado se ignora.
    /// </summary>
    public sealed class PerfStore
    {
        public const int KeepMeasurements = 30, KeepThermal = 100;
        private readonly string _root;

        public PerfStore(string root) { _root = root; }

        public static string DefaultRoot(string localAppData) { return Path.Combine(localAppData, "iWinInstaller", "Rendimiento"); }

        private string StateFile { get { return Path.Combine(_root, "estado.json"); } }
        private string MeasureFile { get { return Path.Combine(_root, "mediciones.json"); } }
        private string ThermalFile { get { return Path.Combine(_root, "termico.json"); } }

        private static Dictionary<string, object> Read(string path, string format)
        {
            try
            {
                if (!File.Exists(path) || SafeFile.IsReparsePoint(path)) return new Dictionary<string, object>();
                var data = MiniJson.TryParseObject(File.ReadAllText(path, Encoding.UTF8));
                return data != null && MiniJson.GetString(data, "format") == format ? data : new Dictionary<string, object>();
            }
            catch (IOException) { return new Dictionary<string, object>(); }
            catch (UnauthorizedAccessException) { return new Dictionary<string, object>(); }
        }

        private void Write(string path, string format, Dictionary<string, object> data)
        {
            try
            {
                data["format"] = format; data["version"] = 1;
                Directory.CreateDirectory(_root);
                SafeFile.WriteAtomic(path, new UTF8Encoding(false).GetBytes(MiniJson.Serialize(data)));
            }
            catch (IOException) { /* no poder guardar no impide usar la página */ }
            catch (UnauthorizedAccessException) { }
        }

        private Dictionary<string, object> State() { return Read(StateFile, "iWinInstaller-rendimiento"); }
        private void SaveState(Dictionary<string, object> state) { Write(StateFile, "iWinInstaller-rendimiento", state); }

        private static Dictionary<string, object> Obj(Dictionary<string, object> parent, string key)
        {
            object value;
            return parent.TryGetValue(key, out value) ? value as Dictionary<string, object> : null;
        }

        private static List<object> Arr(Dictionary<string, object> parent, string key)
        {
            object value;
            return parent.TryGetValue(key, out value) ? value as List<object> : null;
        }

        private static bool Bool(Dictionary<string, object> data, string key, bool fallback)
        {
            object value;
            return data != null && data.TryGetValue(key, out value) && value is bool ? (bool)value : fallback;
        }

        // ---------- Valores originales (para Deshacer) ----------

        public Dictionary<string, List<RegOriginal>> LoadOriginals()
        {
            var result = new Dictionary<string, List<RegOriginal>>(StringComparer.Ordinal);
            var originals = Obj(State(), "originals");
            if (originals == null) return result;
            foreach (var pair in originals)
            {
                var list = pair.Value as List<object>;
                if (list == null) continue;
                var items = new List<RegOriginal>();
                foreach (var raw in list)
                {
                    var d = raw as Dictionary<string, object>;
                    if (d == null) continue;
                    object data; d.TryGetValue("data", out data);
                    string kind = MiniJson.GetString(d, "kind") ?? "dword";
                    if (kind == "dword" && data is double) data = Convert.ToInt32((double)data, CultureInfo.InvariantCulture);
                    items.Add(new RegOriginal { Key = MiniJson.GetString(d, "key"), Name = MiniJson.GetString(d, "name"), Existed = Bool(d, "existed", false), Kind = kind, Data = data });
                }
                result[pair.Key] = items;
            }
            return result;
        }

        public void SaveOriginals(Dictionary<string, List<RegOriginal>> originals)
        {
            var state = State();
            var dict = new Dictionary<string, object>();
            foreach (var pair in originals)
                dict[pair.Key] = pair.Value.Select(o => (object)new Dictionary<string, object>
                    { { "key", o.Key }, { "name", o.Name }, { "existed", o.Existed }, { "kind", o.Kind }, { "data", o.Data } }).ToList();
            state["originals"] = dict;
            SaveState(state);
        }

        /// <summary>Plan de energía que había antes de aplicar «Alto rendimiento» desde la página (GUID) o null.</summary>
        public string LoadPowerPrevious() { return MiniJson.GetString(State(), "powerPrevious"); }

        public void SavePowerPrevious(string guid)
        {
            var state = State();
            if (guid == null) state.Remove("powerPrevious"); else state["powerPrevious"] = guid;
            SaveState(state);
        }

        // ---------- Perfil de juego ----------

        public ProfileSettings LoadSettings()
        {
            var settings = new ProfileSettings();
            var d = Obj(State(), "settings");
            if (d == null) return settings;
            settings.Enabled = Bool(d, "enabled", false);
            var options = Obj(d, "options");
            if (options != null)
                foreach (var pair in options)
                {
                    var o = pair.Value as Dictionary<string, object>;
                    if (o == null) continue;
                    settings.Options[pair.Key] = new ProfileOptions
                    {
                        Priority = Bool(o, "priority", true), PowerPlan = Bool(o, "power", true),
                        CloseOverlays = Bool(o, "overlays", true), CloseBrowsers = Bool(o, "browsers", true)
                    };
                }
            var custom = Arr(d, "custom");
            if (custom != null)
                foreach (var raw in custom)
                {
                    var c = raw as Dictionary<string, object>;
                    string process = MiniJson.GetString(c, "process");
                    if (!string.IsNullOrWhiteSpace(process)) settings.Custom.Add(new CustomGame { Process = process, Title = MiniJson.GetString(c, "title") ?? process });
                }
            return settings;
        }

        public void SaveSettings(ProfileSettings settings)
        {
            var state = State();
            state["settings"] = new Dictionary<string, object>
            {
                { "enabled", settings.Enabled },
                { "options", settings.Options.ToDictionary(p => p.Key, p => (object)new Dictionary<string, object>
                    { { "priority", p.Value.Priority }, { "power", p.Value.PowerPlan }, { "overlays", p.Value.CloseOverlays }, { "browsers", p.Value.CloseBrowsers } }) },
                { "custom", settings.Custom.Select(c => (object)new Dictionary<string, object> { { "process", c.Process }, { "title", c.Title } }).ToList() }
            };
            SaveState(state);
        }

        public ProfileSession LoadSession()
        {
            var d = Obj(State(), "session");
            if (d == null) return null;
            double? pid = MiniJson.GetNumber(d, "pid");
            var session = new ProfileSession
            {
                GameId = MiniJson.GetString(d, "gameId"), Title = MiniJson.GetString(d, "title"), Pid = pid.HasValue ? (int)pid.Value : 0, ProcessName = MiniJson.GetString(d, "process"),
                PreviousPriority = MiniJson.GetString(d, "previousPriority"), PreviousPower = MiniJson.GetString(d, "previousPower"),
                AppliedPower = MiniJson.GetString(d, "appliedPower"), PriorityChanged = Bool(d, "priorityChanged", false)
            };
            DateTime started;
            if (DateTime.TryParseExact(MiniJson.GetString(d, "startedUtc") ?? "", "yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture,
                DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out started)) session.StartedUtc = started;
            var closed = Arr(d, "closed");
            if (closed != null)
                foreach (var raw in closed)
                {
                    var c = raw as Dictionary<string, object>;
                    if (c != null) session.Closed.Add(new ClosedApp { Name = MiniJson.GetString(c, "name"), Path = MiniJson.GetString(c, "path") });
                }
            return session;
        }

        public void SaveSession(ProfileSession session)
        {
            var state = State();
            if (session == null) state.Remove("session");
            else state["session"] = new Dictionary<string, object>
            {
                { "gameId", session.GameId }, { "title", session.Title }, { "pid", session.Pid }, { "process", session.ProcessName },
                { "previousPriority", session.PreviousPriority }, { "previousPower", session.PreviousPower }, { "appliedPower", session.AppliedPower },
                { "priorityChanged", session.PriorityChanged },
                { "startedUtc", session.StartedUtc.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture) },
                { "closed", session.Closed.Select(c => (object)new Dictionary<string, object> { { "name", c.Name }, { "path", c.Path ?? "" } }).ToList() }
            };
            SaveState(state);
        }

        // ---------- Mediciones ----------

        private static double? Num(Dictionary<string, object> d, string key) { return MiniJson.GetNumber(d, key); }

        public List<PerfSnapshot> LoadMeasurements()
        {
            var list = new List<PerfSnapshot>();
            var items = Arr(Read(MeasureFile, "iWinInstaller-mediciones"), "items");
            if (items == null) return list;
            foreach (var raw in items)
            {
                var d = raw as Dictionary<string, object>;
                DateTime at;
                if (d == null || !DateTime.TryParseExact(MiniJson.GetString(d, "at") ?? "", "yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture,
                    DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out at)) continue;
                list.Add(new PerfSnapshot
                {
                    AtUtc = at, Label = MiniJson.GetString(d, "label") ?? "", Game = MiniJson.GetString(d, "game"),
                    SchedP50 = Num(d, "p50"), SchedP95 = Num(d, "p95"), SchedP99 = Num(d, "p99"),
                    PingAvg = Num(d, "pingAvg"), PingJitter = Num(d, "pingJitter"), PingLoss = Num(d, "pingLoss"),
                    Fps = Num(d, "fps"), FrameP99 = Num(d, "frameP99"), Low1Fps = Num(d, "low1")
                });
            }
            return list;
        }

        public void AddMeasurement(PerfSnapshot snapshot)
        {
            var list = LoadMeasurements();
            list.Add(snapshot);
            list = list.OrderBy(s => s.AtUtc).Skip(Math.Max(0, list.Count - KeepMeasurements)).ToList();
            var items = list.Select(s => (object)new Dictionary<string, object>
            {
                { "at", s.AtUtc.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture) }, { "label", s.Label ?? "" }, { "game", s.Game },
                { "p50", s.SchedP50 }, { "p95", s.SchedP95 }, { "p99", s.SchedP99 }, { "pingAvg", s.PingAvg }, { "pingJitter", s.PingJitter },
                { "pingLoss", s.PingLoss }, { "fps", s.Fps }, { "frameP99", s.FrameP99 }, { "low1", s.Low1Fps }
            }).ToList();
            Write(MeasureFile, "iWinInstaller-mediciones", new Dictionary<string, object> { { "items", items } });
        }

        // ---------- Historial térmico ----------

        public List<ThermalEvent> LoadThermal()
        {
            var list = new List<ThermalEvent>();
            var items = Arr(Read(ThermalFile, "iWinInstaller-termico"), "items");
            if (items == null) return list;
            foreach (var raw in items)
            {
                var d = raw as Dictionary<string, object>;
                DateTime at;
                if (d == null || !DateTime.TryParseExact(MiniJson.GetString(d, "at") ?? "", "yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture,
                    DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out at)) continue;
                list.Add(new ThermalEvent { AtUtc = at, Kind = MiniJson.GetString(d, "kind") ?? "", Game = MiniJson.GetString(d, "game") ?? "", Detail = MiniJson.GetString(d, "detail") ?? "", PeakC = Num(d, "peak") });
            }
            return list;
        }

        public void ClearThermal()
        {
            Write(ThermalFile, "iWinInstaller-termico", new Dictionary<string, object> { { "items", new List<object>() } });
        }

        public void AddThermal(ThermalEvent item)
        {
            var list = LoadThermal();
            list.Add(item);
            list = list.OrderBy(s => s.AtUtc).Skip(Math.Max(0, list.Count - KeepThermal)).ToList();
            var items = list.Select(s => (object)new Dictionary<string, object>
            {
                { "at", s.AtUtc.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture) }, { "kind", s.Kind }, { "game", s.Game ?? "" }, { "detail", s.Detail ?? "" }, { "peak", s.PeakC }
            }).ToList();
            Write(ThermalFile, "iWinInstaller-termico", new Dictionary<string, object> { { "items", items } });
        }
    }
}
