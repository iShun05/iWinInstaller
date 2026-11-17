using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>Escritura atómica: temporal en la misma carpeta (WriteThrough) y después Replace o Move.</summary>
    public static class SafeFile
    {
        public static bool IsReparsePoint(string path)
        {
            try { return (File.Exists(path) || Directory.Exists(path)) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0; }
            catch (IOException) { return true; }
            catch (UnauthorizedAccessException) { return true; }
        }

        public static void WriteAtomic(string path, byte[] bytes)
        {
            if (IsReparsePoint(path)) throw new IOException("El destino es un enlace: no se escribe.");
            string temporary = path + ".iwin.tmp";
            using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                stream.Write(bytes, 0, bytes.Length);
            if (File.Exists(path)) File.Replace(temporary, path, null);
            else File.Move(temporary, path);
        }
    }

    /// <summary>Un valor o archivo guardado antes de optimizar.</summary>
    public sealed class BackupItem
    {
        /// <summary>«file», «reg-binary», «reg-dword» o «reg-string».</summary>
        public string Kind { get; set; }
        /// <summary>Ruta del archivo o clave del registro.</summary>
        public string Target { get; set; }
        /// <summary>Nombre del valor del registro (vacío para archivos).</summary>
        public string Name { get; set; }
        public bool Existed { get; set; }
        /// <summary>base64 (binario), número (DWORD) o texto.</summary>
        public object Data { get; set; }
        /// <summary>Archivo copiado dentro de la carpeta de la copia.</summary>
        public string File { get; set; }
    }

    public sealed class BackupSet
    {
        public string Game { get; set; }
        public DateTime At { get; set; }
        public string Folder { get; set; }
        public List<BackupItem> Items { get; set; }
    }

    /// <summary>
    /// Copias en %LOCALAPPDATA%\iWinInstaller\Juegos\copias\&lt;juego&gt;\&lt;aaaaMMdd-HHmmss&gt;\manifest.json.
    /// Restaurar valida cada destino con una lista blanca y que el archivo copiado siga dentro de su carpeta.
    /// </summary>
    public sealed class GameBackupStore
    {
        public const int Keep = 10;
        private readonly string _root;
        private readonly IGameEnvironment _env;

        public GameBackupStore(string root, IGameEnvironment env) { _root = root; _env = env; }

        public static string DefaultRoot(IGameEnvironment env) { return Path.Combine(env.LocalAppData, "iWinInstaller", "Juegos"); }

        private string GameFolder(string game) { return Path.Combine(_root, "copias", game); }

        public BackupItem CaptureRegistry(string key, string name)
        {
            object value = _env.GetValue(key, name);
            var item = new BackupItem { Target = key, Name = name, Existed = value != null };
            var bytes = value as byte[];
            if (bytes != null) { item.Kind = "reg-binary"; item.Data = Convert.ToBase64String(bytes); }
            else if (value is int) { item.Kind = "reg-dword"; item.Data = (int)value; }
            else { item.Kind = "reg-string"; item.Data = value as string; }
            return item;
        }

        /// <summary>Crea la copia; si algo falla lanza excepción y no se debe aplicar nada.</summary>
        public BackupSet Create(string game, IList<BackupItem> items, IDictionary<string, string> filesToCopy, DateTime nowUtc)
        {
            string baseName = nowUtc.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
            string folder = Path.Combine(GameFolder(game), baseName);
            for (int n = 2; Directory.Exists(folder); n++) folder = Path.Combine(GameFolder(game), baseName + "-" + n.ToString(CultureInfo.InvariantCulture));
            Directory.CreateDirectory(folder);
            if (filesToCopy != null)
                foreach (var pair in filesToCopy)
                {
                    // pair.Key = nombre dentro de la copia, pair.Value = archivo original
                    if (SafeFile.IsReparsePoint(pair.Value)) throw new IOException("El archivo de ajustes es un enlace: no se toca.");
                    System.IO.File.Copy(pair.Value, Path.Combine(folder, pair.Key), false);
                }
            var manifest = new Dictionary<string, object>
            {
                { "format", "iWinInstaller-juegos-copia" }, { "version", 1 }, { "game", game },
                { "at", nowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture) },
                { "items", items.Select(i => (object)new Dictionary<string, object>
                    {
                        { "kind", i.Kind }, { "target", i.Target }, { "name", i.Name ?? "" }, { "existed", i.Existed },
                        { "data", i.Data }, { "file", i.File ?? "" }
                    }).ToList() }
            };
            SafeFile.WriteAtomic(Path.Combine(folder, "manifest.json"), new UTF8Encoding(false).GetBytes(MiniJson.Serialize(manifest)));
            Prune(game);
            return new BackupSet { Game = game, At = nowUtc, Folder = folder, Items = items.ToList() };
        }

        private void Prune(string game)
        {
            var all = List(game);
            foreach (var old in all.Skip(Keep))
            {
                try { Directory.Delete(old.Folder, true); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
        }

        /// <summary>Copias del juego, de la más reciente a la más antigua.</summary>
        public List<BackupSet> List(string game)
        {
            var result = new List<BackupSet>();
            string dir = GameFolder(game);
            if (!Directory.Exists(dir)) return result;
            foreach (string folder in Directory.GetDirectories(dir))
            {
                var set = Load(game, folder);
                if (set != null) result.Add(set);
            }
            return result.OrderByDescending(s => s.At).ThenByDescending(s => s.Folder, StringComparer.Ordinal).ToList();
        }

        public BackupSet Latest(string game) { return List(game).FirstOrDefault(); }

        private static BackupSet Load(string game, string folder)
        {
            try
            {
                if (SafeFile.IsReparsePoint(folder)) return null;
                var data = MiniJson.TryParseObject(System.IO.File.ReadAllText(Path.Combine(folder, "manifest.json"), Encoding.UTF8));
                if (data == null || MiniJson.GetString(data, "format") != "iWinInstaller-juegos-copia" || MiniJson.GetString(data, "game") != game) return null;
                DateTime at;
                if (!DateTime.TryParseExact(MiniJson.GetString(data, "at"), "yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture,
                    DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out at)) return null;
                object rawItems;
                var items = new List<BackupItem>();
                if (data.TryGetValue("items", out rawItems) && rawItems is List<object>)
                    foreach (var raw in (List<object>)rawItems)
                    {
                        var d = raw as Dictionary<string, object>;
                        if (d == null) continue;
                        object existed, value;
                        d.TryGetValue("existed", out existed);
                        d.TryGetValue("data", out value);
                        items.Add(new BackupItem
                        {
                            Kind = MiniJson.GetString(d, "kind"), Target = MiniJson.GetString(d, "target"), Name = MiniJson.GetString(d, "name"),
                            Existed = existed is bool && (bool)existed, Data = value, File = MiniJson.GetString(d, "file")
                        });
                    }
                return new BackupSet { Game = game, At = at, Folder = folder, Items = items };
            }
            catch (IOException) { return null; }
            catch (UnauthorizedAccessException) { return null; }
        }

        /// <summary>
        /// Devuelve la copia entera. allowed decide qué destinos se aceptan (lista blanca); lo demás se ignora.
        /// Sigue aunque un elemento falle y devuelve una línea por elemento.
        /// </summary>
        public List<string> Restore(BackupSet set, Func<BackupItem, bool> allowed)
        {
            var lines = new List<string>();
            foreach (var item in set.Items)
            {
                string label = item.Kind == "file" ? Path.GetFileName(item.Target ?? "") : item.Name;
                if (item.Target == null || !allowed(item)) { lines.Add("✗ " + label + ": destino no permitido, se ignora"); continue; }
                try
                {
                    if (item.Kind == "file")
                    {
                        string source = SafeSource(set.Folder, item.File);
                        if (source == null) { lines.Add("✗ " + label + ": la copia no es válida"); continue; }
                        if (!item.Existed) { if (System.IO.File.Exists(item.Target)) System.IO.File.Delete(item.Target); }
                        else SafeFile.WriteAtomic(item.Target, System.IO.File.ReadAllBytes(source));
                    }
                    else if (!item.Existed || item.Data == null) _env.DeleteValue(item.Target, item.Name);
                    else if (item.Kind == "reg-binary") _env.SetValue(item.Target, item.Name, Convert.FromBase64String((string)item.Data), RegKind.Binary);
                    else if (item.Kind == "reg-dword") _env.SetValue(item.Target, item.Name, Convert.ToInt32(item.Data, CultureInfo.InvariantCulture), RegKind.DWord);
                    else if (item.Kind == "reg-string") _env.SetValue(item.Target, item.Name, Convert.ToString(item.Data, CultureInfo.InvariantCulture), RegKind.String);
                    else { lines.Add("✗ " + label + ": tipo desconocido"); continue; }
                    lines.Add("✓ " + label);
                }
                catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException || ex is FormatException || ex is InvalidCastException || ex is System.Security.SecurityException)
                {
                    lines.Add("✗ " + label + ": " + ex.Message);
                }
            }
            return lines;
        }

        /// <summary>El archivo de la copia debe estar dentro de su carpeta y no ser un enlace.</summary>
        public static string SafeSource(string folder, string file)
        {
            if (string.IsNullOrEmpty(file)) return null;
            string root = Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full;
            try { full = Path.GetFullPath(Path.Combine(root, file)); }
            catch (ArgumentException) { return null; }
            catch (NotSupportedException) { return null; }
            if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return null;
            if (!System.IO.File.Exists(full) || SafeFile.IsReparsePoint(full)) return null;
            return full;
        }
    }
}
