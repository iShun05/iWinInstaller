using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Xml;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>Un juego encontrado en un lanzador (solo se lista; no se optimiza).</summary>
    public sealed class DetectedGame
    {
        public string Launcher { get; set; }
        public string Name { get; set; }
        public string Folder { get; set; }
        public string ExePath { get; set; }
        public string Version { get; set; }
        public long? SizeBytes { get; set; }
    }

    /// <summary>Datos de MicrosoftGame.Config (juegos de Xbox / Game Pass en PC).</summary>
    public sealed class XboxGameConfig
    {
        public string DisplayName { get; set; }
        public string Version { get; set; }
        public string Executable { get; set; }

        public static XboxGameConfig Parse(string xml)
        {
            if (string.IsNullOrWhiteSpace(xml)) return null;
            try
            {
                var doc = new XmlDocument { XmlResolver = null };
                var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null };
                using (var reader = XmlReader.Create(new StringReader(xml.TrimStart('﻿')), settings)) doc.Load(reader);
                var config = new XboxGameConfig();
                foreach (XmlElement e in doc.GetElementsByTagName("*"))
                {
                    switch (e.LocalName)
                    {
                        case "Identity": if (config.Version == null) config.Version = Clean(e.GetAttribute("Version")); break;
                        case "ShellVisuals": if (config.DisplayName == null) config.DisplayName = Clean(e.GetAttribute("DefaultDisplayName")); break;
                        case "Executable": if (config.Executable == null) config.Executable = Clean(e.GetAttribute("Name")); break;
                    }
                }
                // Los nombres «ms-resource:…» no se pueden resolver sin Windows: se usa el nombre de la carpeta
                if (config.DisplayName != null && config.DisplayName.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase)) config.DisplayName = null;
                return config;
            }
            catch (XmlException) { return null; }
        }

        private static string Clean(string value) { return string.IsNullOrWhiteSpace(value) ? null : value.Trim(); }
    }

    /// <summary>
    /// Lista los juegos de Xbox/Game Pass, Battle.net, EA App, Ubisoft Connect y GOG (y los demás de Epic y Steam) leyendo
    /// solo manifiestos y registro por IGameEnvironment. No ejecuta nada ni toca archivos.
    /// </summary>
    public static class LauncherScanner
    {
        public const string Xbox = "Xbox / Game Pass", BattleNet = "Battle.net", Ea = "EA App", Ubisoft = "Ubisoft Connect", Gog = "GOG", Epic = "Epic Games", Steam = "Steam";

        /// <summary>Todos los juegos encontrados, sin repetir carpeta, sin los de <paramref name="excludeFolders"/> (los cinco con tarjeta) y ordenados por lanzador y nombre.</summary>
        public static List<DetectedGame> Scan(IGameEnvironment env, IEnumerable<string> excludeFolders)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string folder in excludeFolders ?? new string[0]) { string n = Norm(folder); if (n.Length > 0) seen.Add(n); }
            var result = new List<DetectedGame>();
            var sources = new Func<IGameEnvironment, List<DetectedGame>>[] { ScanXbox, ScanBattleNet, ScanEa, ScanUbisoft, ScanGog, ScanEpic, ScanSteam };
            foreach (var source in sources)
            {
                List<DetectedGame> games;
                try { games = source(env); }
                catch (Exception ex) when (GamesViewModel.IsDetectionError(ex)) { continue; }
                foreach (var game in games)
                {
                    string key = Norm(game.Folder);
                    if (key.Length == 0 || string.IsNullOrWhiteSpace(game.Name) || !seen.Add(key)) continue;
                    result.Add(game);
                }
            }
            return result.OrderBy(g => g.Launcher, StringComparer.OrdinalIgnoreCase).ThenBy(g => g.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        }

        public static string Norm(string path)
        {
            return string.IsNullOrWhiteSpace(path) ? "" : path.Trim().Trim('"').Replace('/', '\\').TrimEnd('\\');
        }

        private static string Str(IGameEnvironment env, string key, string name)
        {
            string v = env.GetValue(key, name) as string;
            return string.IsNullOrWhiteSpace(v) ? null : v.Trim();
        }

        // ---------- Xbox / Game Pass: <unidad>:\XboxGames\<Título>\Content\MicrosoftGame.Config ----------

        public static List<DetectedGame> ScanXbox(IGameEnvironment env)
        {
            var list = new List<DetectedGame>();
            for (char drive = 'C'; drive <= 'Z'; drive++)
            {
                string root = drive + @":\XboxGames";
                if (!env.DirectoryExists(root)) continue;
                foreach (string dir in env.GetDirectories(root))
                {
                    string content = Path.Combine(dir, "Content");
                    string configPath = Path.Combine(content, "MicrosoftGame.Config");
                    if (!env.FileExists(configPath)) continue;
                    XboxGameConfig config = null;
                    try { config = XboxGameConfig.Parse(env.ReadAllText(configPath)); }
                    catch (IOException) { }
                    catch (UnauthorizedAccessException) { }
                    string exe = config != null && config.Executable != null ? Path.Combine(content, config.Executable) : null;
                    list.Add(new DetectedGame
                    {
                        Launcher = Xbox,
                        Name = config != null && config.DisplayName != null ? config.DisplayName : Path.GetFileName(dir.TrimEnd('\\')),
                        Folder = dir,
                        ExePath = exe != null && env.FileExists(exe) ? exe : null,
                        Version = config == null ? null : config.Version
                    });
                }
            }
            return list;
        }

        // ---------- Battle.net: sus juegos se registran en Desinstalar con Publisher «Blizzard Entertainment» ----------

        public static List<DetectedGame> ScanBattleNet(IGameEnvironment env)
        {
            var list = new List<DetectedGame>();
            foreach (string root in GameLocator.UninstallRoots)
                foreach (string sub in env.SubKeyNames(root))
                {
                    string key = root + "\\" + sub;
                    string publisher = Str(env, key, "Publisher");
                    string name = Str(env, key, "DisplayName");
                    string location = Norm(Str(env, key, "InstallLocation"));
                    if (publisher == null || name == null || location.Length == 0) continue;
                    if (publisher.IndexOf("Blizzard", StringComparison.OrdinalIgnoreCase) < 0) continue;
                    if (name.IndexOf("Battle.net", StringComparison.OrdinalIgnoreCase) >= 0 || !env.DirectoryExists(location)) continue;
                    list.Add(new DetectedGame { Launcher = BattleNet, Name = name, Folder = location, Version = Str(env, key, "DisplayVersion") });
                }
            return list;
        }

        // ---------- EA App: HKLM\SOFTWARE\WOW6432Node\EA Games\<juego>\«Install Dir» y la carpeta por defecto ----------

        public static List<DetectedGame> ScanEa(IGameEnvironment env)
        {
            var list = new List<DetectedGame>();
            const string root = @"HKLM\SOFTWARE\WOW6432Node\EA Games";
            foreach (string sub in env.SubKeyNames(root))
            {
                string key = root + "\\" + sub;
                string dir = Norm(Str(env, key, "Install Dir"));
                if (dir.Length == 0 || !env.DirectoryExists(dir)) continue;
                list.Add(new DetectedGame { Launcher = Ea, Name = Str(env, key, "DisplayName") ?? sub, Folder = dir, Version = Str(env, key, "Version") });
            }
            string programFiles = Path.GetPathRoot(env.ProgramData ?? "") ?? "";
            if (programFiles.Length > 0)
                foreach (string parent in new[] { Path.Combine(programFiles, "Program Files", "EA Games"), Path.Combine(programFiles, "Program Files", "Electronic Arts") })
                {
                    if (!env.DirectoryExists(parent)) continue;
                    foreach (string dir in env.GetDirectories(parent))
                        if (env.GetFiles(dir, "*.exe").Length > 0 || env.GetDirectories(dir).Length > 0)
                            list.Add(new DetectedGame { Launcher = Ea, Name = Path.GetFileName(dir.TrimEnd('\\')), Folder = dir });
                }
            return list;
        }

        // ---------- Ubisoft Connect: HKLM\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs\<id>\InstallDir ----------

        public static List<DetectedGame> ScanUbisoft(IGameEnvironment env)
        {
            var list = new List<DetectedGame>();
            const string root = @"HKLM\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs";
            foreach (string id in env.SubKeyNames(root))
            {
                string dir = Norm(Str(env, root + "\\" + id, "InstallDir"));
                if (dir.Length == 0 || !env.DirectoryExists(dir)) continue;
                string name = null;
                foreach (string uninstall in GameLocator.UninstallRoots)
                {
                    name = Str(env, uninstall + "\\Uplay Install " + id, "DisplayName");
                    if (name != null) break;
                }
                list.Add(new DetectedGame { Launcher = Ubisoft, Name = name ?? Path.GetFileName(dir), Folder = dir });
            }
            return list;
        }

        // ---------- GOG: HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\<id> (gameName, path, exe, ver) ----------

        public static List<DetectedGame> ScanGog(IGameEnvironment env)
        {
            var list = new List<DetectedGame>();
            const string root = @"HKLM\SOFTWARE\WOW6432Node\GOG.com\Games";
            foreach (string id in env.SubKeyNames(root))
            {
                string key = root + "\\" + id;
                if (Str(env, key, "dependsOn") != null) continue; // contenido adicional (DLC), no un juego
                string dir = Norm(Str(env, key, "path"));
                string name = Str(env, key, "gameName");
                if (dir.Length == 0 || name == null || !env.DirectoryExists(dir)) continue;
                string exe = Str(env, key, "exe");
                list.Add(new DetectedGame
                {
                    Launcher = Gog, Name = name, Folder = dir, Version = Str(env, key, "ver"),
                    ExePath = exe != null && env.FileExists(exe) ? exe : null
                });
            }
            return list;
        }

        // ---------- Epic: manifiestos *.item (los 2 juegos con tarjeta se excluyen por carpeta) ----------

        public static List<DetectedGame> ScanEpic(IGameEnvironment env)
        {
            var list = new List<DetectedGame>();
            string dir = Path.Combine(env.ProgramData, "Epic", "EpicGamesLauncher", "Data", "Manifests");
            if (!env.DirectoryExists(dir)) return list;
            foreach (string file in env.GetFiles(dir, "*.item"))
            {
                EpicManifest manifest;
                try { manifest = EpicManifest.Parse(env.ReadAllText(file)); }
                catch (IOException) { continue; }
                catch (UnauthorizedAccessException) { continue; }
                if (manifest == null || string.IsNullOrWhiteSpace(manifest.DisplayName) || string.IsNullOrWhiteSpace(manifest.InstallLocation)) continue;
                if (manifest.AppName != null && manifest.AppName.StartsWith("UE_", StringComparison.OrdinalIgnoreCase)) continue; // Unreal Engine
                string folder = Norm(manifest.InstallLocation);
                if (!env.DirectoryExists(folder)) continue;
                list.Add(new DetectedGame { Launcher = Epic, Name = manifest.DisplayName, Folder = folder, Version = manifest.Version, SizeBytes = manifest.InstallSize });
            }
            return list;
        }

        // ---------- Steam: appmanifest_*.acf de cada biblioteca ----------

        public static List<DetectedGame> ScanSteam(IGameEnvironment env)
        {
            var list = new List<DetectedGame>();
            string steam = Str(env, @"HKCU\Software\Valve\Steam", "SteamPath");
            if (steam == null) return list;
            var libraries = new List<string> { steam };
            string vdfPath = Path.Combine(steam, "steamapps", "libraryfolders.vdf");
            if (env.FileExists(vdfPath))
            {
                try { libraries.AddRange(SteamLibrary.ParseFolders(env.ReadAllText(vdfPath))); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            foreach (string library in libraries.Select(Norm).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                string apps = Path.Combine(library, "steamapps");
                if (!env.DirectoryExists(apps)) continue;
                foreach (string acfPath in env.GetFiles(apps, "*.acf"))
                {
                    if (!Path.GetFileName(acfPath).StartsWith("appmanifest_", StringComparison.OrdinalIgnoreCase)) continue;
                    string acf;
                    try { acf = env.ReadAllText(acfPath); }
                    catch (IOException) { continue; }
                    catch (UnauthorizedAccessException) { continue; }
                    string installDir = SteamLibrary.ParseField(acf, "installdir");
                    string name = SteamLibrary.ParseField(acf, "name");
                    if (string.IsNullOrEmpty(installDir) || installDir.IndexOfAny(new[] { '\\', '/', ':' }) >= 0 || installDir.Contains("..")) continue;
                    if (string.IsNullOrEmpty(name) || IsSteamTool(name)) continue;
                    string folder = Path.Combine(apps, "common", installDir);
                    if (!env.DirectoryExists(folder)) continue;
                    long size;
                    long? sizeOnDisk = long.TryParse(SteamLibrary.ParseField(acf, "SizeOnDisk"), NumberStyles.Integer, CultureInfo.InvariantCulture, out size) && size > 0 ? (long?)size : null;
                    string build = SteamLibrary.ParseField(acf, "buildid");
                    list.Add(new DetectedGame { Launcher = Steam, Name = name, Folder = folder, SizeBytes = sizeOnDisk, Version = string.IsNullOrEmpty(build) ? null : "build " + build });
                }
            }
            return list;
        }

        /// <summary>Componentes que Steam guarda como «apps» pero que no son juegos.</summary>
        public static bool IsSteamTool(string name)
        {
            return name.StartsWith("Steamworks Common Redistributables", StringComparison.OrdinalIgnoreCase)
                || name.StartsWith("Steam Linux Runtime", StringComparison.OrdinalIgnoreCase)
                || name.StartsWith("Proton ", StringComparison.OrdinalIgnoreCase)
                || name.StartsWith("Steamworks Shared", StringComparison.OrdinalIgnoreCase);
        }
    }
}
