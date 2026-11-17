using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>Resumen guardado de la última comprobación de archivos de un juego.</summary>
    public sealed class CheckSummary
    {
        public DateTime At { get; set; }
        public string Mode { get; set; }
        public int Total { get; set; }
        public int Bad { get; set; }
        public bool Ok { get; set; }

        public string Describe()
        {
            string when = At.ToLocalTime().ToString("d MMM HH:mm", CultureInfo.CurrentCulture);
            if (Ok) return "Correcta (" + Mode + ", " + when + "): " + Total + " archivos.";
            return "Con fallos (" + Mode + ", " + when + "): " + Bad + " de " + Total + ".";
        }
    }

    /// <summary>rutas.json (ejecutables elegidos a mano) y estado.json (última comprobación) en %LOCALAPPDATA%\iWinInstaller\Juegos.</summary>
    public sealed class GameStateStore
    {
        private readonly string _root;
        public GameStateStore(string root) { _root = root; }

        private string PathsFile { get { return Path.Combine(_root, "rutas.json"); } }
        private string StateFile { get { return Path.Combine(_root, "estado.json"); } }

        private static Dictionary<string, object> Read(string path, string format)
        {
            try
            {
                if (!File.Exists(path) || SafeFile.IsReparsePoint(path)) return null;
                var data = MiniJson.TryParseObject(File.ReadAllText(path, Encoding.UTF8));
                return data != null && MiniJson.GetString(data, "format") == format ? data : null;
            }
            catch (IOException) { return null; }
            catch (UnauthorizedAccessException) { return null; }
        }

        private void Write(string path, Dictionary<string, object> data)
        {
            try
            {
                Directory.CreateDirectory(_root);
                SafeFile.WriteAtomic(path, new UTF8Encoding(false).GetBytes(MiniJson.Serialize(data)));
            }
            catch (IOException) { /* no poder guardar el estado no impide usar la página */ }
            catch (UnauthorizedAccessException) { }
        }

        public Dictionary<string, string> LoadPaths()
        {
            var result = new Dictionary<string, string>(StringComparer.Ordinal);
            var data = Read(PathsFile, "iWinInstaller-juegos-rutas");
            object raw;
            if (data != null && data.TryGetValue("paths", out raw) && raw is Dictionary<string, object>)
                foreach (var pair in (Dictionary<string, object>)raw)
                    if (pair.Value is string && GameDefinitions.Get(pair.Key) != null) result[pair.Key] = (string)pair.Value;
            return result;
        }

        public void SavePaths(Dictionary<string, string> paths)
        {
            var map = new Dictionary<string, object>();
            foreach (var pair in paths) map[pair.Key] = pair.Value;
            Write(PathsFile, new Dictionary<string, object> { { "format", "iWinInstaller-juegos-rutas" }, { "version", 1 }, { "paths", map } });
        }

        public Dictionary<string, CheckSummary> LoadChecks()
        {
            var result = new Dictionary<string, CheckSummary>(StringComparer.Ordinal);
            var data = Read(StateFile, "iWinInstaller-juegos-estado");
            object raw;
            if (data == null || !data.TryGetValue("games", out raw) || !(raw is Dictionary<string, object>)) return result;
            foreach (var pair in (Dictionary<string, object>)raw)
            {
                var g = pair.Value as Dictionary<string, object>;
                DateTime at;
                if (g == null || !DateTime.TryParseExact(MiniJson.GetString(g, "at"), "yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture,
                    DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out at)) continue;
                object ok;
                g.TryGetValue("ok", out ok);
                result[pair.Key] = new CheckSummary
                {
                    At = at, Mode = MiniJson.GetString(g, "mode") ?? "", Ok = ok is bool && (bool)ok,
                    Total = (int)(MiniJson.GetNumber(g, "total") ?? 0), Bad = (int)(MiniJson.GetNumber(g, "bad") ?? 0)
                };
            }
            return result;
        }

        public void SaveChecks(Dictionary<string, CheckSummary> checks)
        {
            var games = new Dictionary<string, object>();
            foreach (var pair in checks)
                games[pair.Key] = new Dictionary<string, object>
                {
                    { "at", pair.Value.At.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture) },
                    { "mode", pair.Value.Mode }, { "total", pair.Value.Total }, { "bad", pair.Value.Bad }, { "ok", pair.Value.Ok }
                };
            Write(StateFile, new Dictionary<string, object> { { "format", "iWinInstaller-juegos-estado" }, { "version", 1 }, { "games", games } });
        }
    }
}
