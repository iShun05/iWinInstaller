using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>Resultado de buscar un juego.</summary>
    public sealed class GameInstall
    {
        public bool Found { get { return !string.IsNullOrEmpty(ExePath); } }
        public string Folder { get; set; }
        public string ExePath { get; set; }
        public string Source { get; set; }
        public string Version { get; set; }
        public long? SizeBytes { get; set; }
        public bool IsChina { get; set; }
        public bool FromSteam { get; set; }
        public static readonly GameInstall None = new GameInstall();
    }

    /// <summary>Un manifiesto de Epic Games (%ProgramData%\Epic\EpicGamesLauncher\Data\Manifests\*.item).</summary>
    public sealed class EpicManifest
    {
        public string AppName { get; set; }
        public string DisplayName { get; set; }
        public string InstallLocation { get; set; }
        public string Version { get; set; }
        public long? InstallSize { get; set; }

        public static EpicManifest Parse(string json)
        {
            var data = MiniJson.TryParseObject(json);
            if (data == null) return null;
            double? size = MiniJson.GetNumber(data, "InstallSize");
            return new EpicManifest
            {
                AppName = MiniJson.GetString(data, "AppName"),
                DisplayName = MiniJson.GetString(data, "DisplayName"),
                InstallLocation = MiniJson.GetString(data, "InstallLocation"),
                Version = MiniJson.GetString(data, "AppVersionString"),
                InstallSize = size.HasValue && size.Value > 0 ? (long?)size.Value : null
            };
        }
    }

    /// <summary>Bibliotecas de Steam (libraryfolders.vdf) y manifiestos de juego (appmanifest_*.acf).</summary>
    public static class SteamLibrary
    {
        private static readonly Regex PathPattern = new Regex("\"path\"\\s+\"((?:[^\"\\\\]|\\\\.)*)\"", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        public static List<string> ParseFolders(string vdf)
        {
            var result = new List<string>();
            if (string.IsNullOrEmpty(vdf)) return result;
            foreach (Match m in PathPattern.Matches(vdf))
            {
                string path = m.Groups[1].Value.Replace("\\\\", "\\");
                if (path.Length > 0 && !result.Contains(path, StringComparer.OrdinalIgnoreCase)) result.Add(path);
            }
            return result;
        }

        /// <summary>Valor de una clave de primer nivel de un .acf (installdir, SizeOnDisk, buildid…).</summary>
        public static string ParseField(string acf, string key)
        {
            if (string.IsNullOrEmpty(acf)) return null;
            var m = Regex.Match(acf, "\"" + Regex.Escape(key) + "\"\\s+\"((?:[^\"\\\\]|\\\\.)*)\"", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            return m.Success ? m.Groups[1].Value.Replace("\\\\", "\\") : null;
        }
    }

    /// <summary>config.ini de la carpeta de un juego de HoYoverse.</summary>
    public static class HoyoConfig
    {
        public static string ParseVersion(string ini)
        {
            if (string.IsNullOrEmpty(ini)) return null;
            var doc = IniDocument.Parse(new System.Text.UTF8Encoding(false).GetBytes(ini));
            string version = doc.Get("general", "game_version");
            return string.IsNullOrEmpty(version) ? null : version;
        }
    }

    /// <summary>Busca cada juego en Epic, HoYoPlay, Steam, los desinstaladores de Windows o la carpeta elegida a mano.</summary>
    public static class GameLocator
    {
        public static readonly string[] UninstallRoots =
        {
            @"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            @"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
            @"HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall"
        };

        public static GameInstall Locate(GameDefinition game, IGameEnvironment env, string manualFolder)
        {
            GameInstall found;
            if (!string.IsNullOrEmpty(manualFolder) && TryFolder(game, env, manualFolder, "Elegido a mano", out found)) return found;
            if (game.HoyoBizGlobal != null && TryHoyoPlay(game, env, out found)) return found;
            if (TryEpic(game, env, out found)) return found;
            if (game.SteamAppId > 0 && TrySteam(game, env, out found)) return found;
            if (TryUninstall(game, env, out found)) return found;
            return GameInstall.None;
        }

        /// <summary>Busca el ejecutable del juego en la carpeta (y, sin recursión, en sus subcarpetas fijas o de un nivel).</summary>
        public static bool TryFolder(GameDefinition game, IGameEnvironment env, string folder, string source, out GameInstall found)
        {
            found = null;
            if (string.IsNullOrEmpty(folder) || !env.DirectoryExists(folder)) return false;
            bool china;
            string exe = FindExe(game, env, folder, out china);
            if (exe == null)
            {
                // Epic y algunos instaladores dejan el juego un nivel más abajo
                if (game.FindExeByCompany || game.Id == GameDefinitions.Fortnite) return false;
                foreach (string sub in env.GetDirectories(folder))
                {
                    exe = FindExe(game, env, sub, out china);
                    if (exe != null) { folder = sub; break; }
                }
                if (exe == null) return false;
            }
            found = new GameInstall { Folder = folder, ExePath = exe, Source = source, IsChina = china };
            return true;
        }

        private static string FindExe(GameDefinition game, IGameEnvironment env, string folder, out bool china)
        {
            china = false;
            if (game.FindExeByCompany)
            {
                foreach (string sub in game.SubFolders ?? new[] { "" })
                {
                    string dir = sub.Length == 0 ? folder : Path.Combine(folder, sub);
                    string exe = FindByCompany(game, env, dir);
                    if (exe != null) return exe;
                }
                return null;
            }
            foreach (string rel in game.Executables)
            {
                string path = Path.Combine(folder, rel);
                if (env.FileExists(path)) return path;
            }
            if (game.ChinaExecutables != null)
                foreach (string rel in game.ChinaExecutables)
                {
                    string path = Path.Combine(folder, rel);
                    if (env.FileExists(path)) { china = true; return path; }
                }
            return null;
        }

        private static string FindByCompany(GameDefinition game, IGameEnvironment env, string dir)
        {
            if (!env.DirectoryExists(dir)) return null;
            string byPrefix = null;
            foreach (string file in env.GetFiles(dir, "*.exe").OrderBy(f => f, StringComparer.OrdinalIgnoreCase))
            {
                string name = Path.GetFileNameWithoutExtension(file);
                if (IsHelperExe(name)) continue;
                if (name.StartsWith(game.ExePrefix, StringComparison.OrdinalIgnoreCase)) { if (byPrefix == null) byPrefix = file; continue; }
                string company = env.CompanyName(file) ?? "";
                if (game.Companies.Any(c => company.IndexOf(c, StringComparison.OrdinalIgnoreCase) >= 0)) return byPrefix ?? file;
            }
            return byPrefix;
        }

        private static bool IsHelperExe(string name)
        {
            string n = name.ToLowerInvariant();
            return n.Contains("unins") || n.Contains("crash") || n.Contains("launcher") || n.Contains("gryphlink") || n.Contains("update") || n.Contains("report");
        }

        private static bool TryHoyoPlay(GameDefinition game, IGameEnvironment env, out GameInstall found)
        {
            found = null;
            GameInstall china = null;
            foreach (string vendor in new[] { "Cognosphere", "miHoYo" })
            {
                string root = @"HKCU\Software\" + vendor + @"\HYP";
                foreach (string version in env.SubKeyNames(root))
                {
                    foreach (bool isChina in new[] { false, true })
                    {
                        foreach (string biz in isChina ? game.HoyoBizChina : game.HoyoBizGlobal)
                        {
                            string path = env.GetValue(root + "\\" + version + "\\" + biz, "GameInstallPath") as string;
                            GameInstall candidate;
                            if (!TryFolder(game, env, path, "HoYoPlay", out candidate)) continue;
                            if (!isChina && !candidate.IsChina) { found = candidate; return true; }
                            if (china == null) china = candidate;
                        }
                    }
                }
            }
            found = china;
            return found != null;
        }

        private static bool TryEpic(GameDefinition game, IGameEnvironment env, out GameInstall found)
        {
            found = null;
            string dir = Path.Combine(env.ProgramData, "Epic", "EpicGamesLauncher", "Data", "Manifests");
            if (!env.DirectoryExists(dir)) return false;
            foreach (string file in env.GetFiles(dir, "*.item"))
            {
                EpicManifest manifest;
                try { manifest = EpicManifest.Parse(env.ReadAllText(file)); }
                catch (IOException) { continue; }
                catch (UnauthorizedAccessException) { continue; }
                if (manifest == null || !MatchesEpic(game, manifest)) continue;
                if (!TryFolder(game, env, manifest.InstallLocation, "Epic Games", out found)) continue;
                found.Version = manifest.Version;
                found.SizeBytes = manifest.InstallSize;
                return true;
            }
            return false;
        }

        public static bool MatchesEpic(GameDefinition game, EpicManifest manifest)
        {
            if (!string.IsNullOrEmpty(game.EpicAppName))
                return string.Equals(manifest.AppName, game.EpicAppName, StringComparison.OrdinalIgnoreCase);
            return !string.IsNullOrEmpty(game.EpicDisplayName) && manifest.DisplayName != null
                && manifest.DisplayName.IndexOf(game.EpicDisplayName, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static bool TrySteam(GameDefinition game, IGameEnvironment env, out GameInstall found)
        {
            found = null;
            string steam = env.GetValue(@"HKCU\Software\Valve\Steam", "SteamPath") as string;
            if (string.IsNullOrEmpty(steam)) return false;
            var libraries = new List<string> { steam };
            string vdfPath = Path.Combine(steam, "steamapps", "libraryfolders.vdf");
            if (env.FileExists(vdfPath))
            {
                try { libraries.AddRange(SteamLibrary.ParseFolders(env.ReadAllText(vdfPath))); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            string acfName = "appmanifest_" + game.SteamAppId.ToString(CultureInfo.InvariantCulture) + ".acf";
            foreach (string library in libraries.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                string acfPath = Path.Combine(library, "steamapps", acfName);
                if (!env.FileExists(acfPath)) continue;
                string acf;
                try { acf = env.ReadAllText(acfPath); }
                catch (IOException) { continue; }
                catch (UnauthorizedAccessException) { continue; }
                string installDir = SteamLibrary.ParseField(acf, "installdir");
                if (string.IsNullOrEmpty(installDir) || installDir.IndexOfAny(new[] { '\\', '/', ':' }) >= 0 || installDir.Contains("..")) continue;
                if (!TryFolder(game, env, Path.Combine(library, "steamapps", "common", installDir), "Steam", out found)) continue;
                long size;
                if (long.TryParse(SteamLibrary.ParseField(acf, "SizeOnDisk"), NumberStyles.Integer, CultureInfo.InvariantCulture, out size) && size > 0) found.SizeBytes = size;
                string build = SteamLibrary.ParseField(acf, "buildid");
                if (!string.IsNullOrEmpty(build)) found.Version = "build " + build;
                found.FromSteam = true;
                return true;
            }
            return false;
        }

        private static bool TryUninstall(GameDefinition game, IGameEnvironment env, out GameInstall found)
        {
            found = null;
            foreach (string root in UninstallRoots)
            {
                foreach (string sub in env.SubKeyNames(root))
                {
                    string key = root + "\\" + sub;
                    string name = env.GetValue(key, "DisplayName") as string;
                    if (string.IsNullOrEmpty(name)) continue;
                    if (!game.UninstallNames.Any(n => name.IndexOf(n, StringComparison.OrdinalIgnoreCase) >= 0)) continue;
                    string location = env.GetValue(key, "InstallLocation") as string;
                    if (!string.IsNullOrEmpty(location) && TryFolder(game, env, location.Trim().Trim('"'), "Windows", out found)) return true;
                }
            }
            return false;
        }

        /// <summary>Completa versión (config.ini de HoYoverse) y tamaño (suma de pkg_version) si faltan.</summary>
        public static void FillDetails(GameDefinition game, IGameEnvironment env, GameInstall install)
        {
            if (install == null || !install.Found || game.HoyoBizGlobal == null) return;
            string config = Path.Combine(install.Folder, "config.ini");
            try
            {
                if (install.Version == null && env.FileExists(config)) install.Version = HoyoConfig.ParseVersion(env.ReadAllText(config));
                if (!install.SizeBytes.HasValue)
                {
                    long total = 0;
                    bool any = false;
                    foreach (string list in env.GetFiles(install.Folder, "*pkg_version"))
                        foreach (var entry in PkgVersion.Parse(env.ReadAllText(list))) { total += entry.Size; any = true; }
                    if (any) install.SizeBytes = total;
                }
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
}
