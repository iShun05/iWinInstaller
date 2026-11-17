using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using IWinInstaller.App.Core;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>Un cambio de la lista de Optimizar, con su casilla.</summary>
    public sealed class TweakItem : ObservableObject
    {
        private bool _isChecked;
        private int _selectedIndex;

        public string Id { get; set; }
        public string Title { get; set; }
        /// <summary>«Ajuste del juego», «Ajuste de Windows» o «No oficial · riesgo bajo».</summary>
        public string Label { get; set; }
        public string Current { get; set; }
        public string New { get; set; }
        public string Note { get; set; }
        /// <summary>Ya tiene el valor nuevo: se muestra sin casilla y no se aplica.</summary>
        public bool AlreadyDone { get; set; }
        public bool IsUnofficial { get { return Label == GameTweaks.UnofficialLabel; } }
        public bool CanToggle { get { return !AlreadyDone; } }
        public string Change { get { return AlreadyDone ? "Ya está: " + Current : Current + "  →  " + New; } }
        public bool IsChecked { get { return _isChecked && !AlreadyDone; } set { Set(ref _isChecked, value); } }
        /// <summary>Opciones (solo el límite de FPS de Fortnite).</summary>
        public List<string> Options { get; set; }
        public bool HasOptions { get { return Options != null && Options.Count > 0; } }
        public int SelectedIndex { get { return _selectedIndex; } set { Set(ref _selectedIndex, value); } }
        /// <summary>Claves que toca (sección, clave, valor) o (clave JSON, valor).</summary>
        internal List<string[]> Changes = new List<string[]>();
    }

    /// <summary>Lista de cambios y advertencias de un juego, leída sin escribir nada.</summary>
    public sealed class TweakPlan
    {
        public TweakPlan() { Items = new List<TweakItem>(); Warnings = new List<string>(); }
        public List<TweakItem> Items { get; private set; }
        public List<string> Warnings { get; private set; }
        public string FortniteIni { get; set; }
        public bool StarRailReady { get; set; }
        public List<string> GpuExes { get; set; }
    }

    /// <summary>Qué se puede cambiar en cada juego y cómo se aplica (con copia previa).</summary>
    public static class GameTweaks
    {
        public const string GameLabel = "Ajuste del juego", WindowsLabel = "Ajuste de Windows", UnofficialLabel = "No oficial · riesgo bajo";
        public const string FortniteSection = "/Script/FortniteGame.FortGameUserSettings";

        public static string FortniteIniPath(IGameEnvironment env)
        {
            return Path.Combine(env.LocalAppData, @"FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini");
        }

        /// <summary>Ejecutables del juego a los que se aplica la GPU (el principal y los extra que existan).</summary>
        public static List<string> GpuExecutables(GameDefinition game, GameInstall install, IGameEnvironment env)
        {
            var list = new List<string>();
            if (install == null || !install.Found) return list;
            list.Add(install.ExePath);
            if (game.ExtraExecutables != null)
                foreach (string rel in game.ExtraExecutables)
                {
                    string path = Path.Combine(install.Folder, rel);
                    if (env.FileExists(path) && !list.Contains(path, StringComparer.OrdinalIgnoreCase)) list.Add(path);
                }
            return list;
        }

        public static TweakPlan Build(GameDefinition game, GameInstall install, IGameEnvironment env, int currentHz)
        {
            var plan = new TweakPlan();
            if (install == null || !install.Found) return plan;
            if (game.Id == GameDefinitions.Fortnite) BuildFortnite(plan, env, currentHz);
            else if (game.Id == GameDefinitions.StarRail) BuildStarRail(plan, install, env);
            BuildGpu(plan, game, install, env);
            return plan;
        }

        private static void BuildGpu(TweakPlan plan, GameDefinition game, GameInstall install, IGameEnvironment env)
        {
            plan.GpuExes = GpuExecutables(game, install, env);
            var current = plan.GpuExes.Select(exe => GpuPreference.GetPair(env.GetValue(GpuPreference.RegistryKey, exe) as string, GpuPreference.PairName)).ToList();
            int gpus = env.GpuCount();
            var item = new TweakItem
            {
                Id = "gpu", Title = "GPU de alto rendimiento", Label = WindowsLabel,
                Current = GpuPreference.Describe(current[0]), New = GpuPreference.Describe(GpuPreference.HighPerformance),
                AlreadyDone = current.All(v => v == GpuPreference.HighPerformance),
                Note = gpus == 1 ? "Sin efecto: este equipo tiene una sola GPU." : "Igual que Configuración › Pantalla › Gráficos. Útil en portátiles con dos GPU."
            };
            item.IsChecked = gpus != 1;
            plan.Items.Add(item);
        }

        private static string OnOff(string value)
        {
            if (value == null) return "—";
            return value.Equals("True", StringComparison.OrdinalIgnoreCase) || value == "1" ? "Activado" : "Desactivado";
        }

        private static string FortniteQuality(string value)
        {
            switch (value)
            {
                case null: return "—";
                case "0": return "Baja";
                case "1": return "Media";
                case "2": return "Alta";
                case "3": return "Épica";
                case "4": return "Cinemática";
                default: return value;
            }
        }

        public static string FortniteFps(string value)
        {
            double fps;
            if (string.IsNullOrEmpty(value) || !double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out fps) || fps <= 0) return "Sin límite";
            return Math.Round(fps).ToString(CultureInfo.InvariantCulture) + " FPS";
        }

        /// <summary>Valor de FrameRateLimit para la opción elegida: 0 = Hz actuales, 1 = Hz − 3, 2 = sin límite.</summary>
        public static string FortniteFpsValue(int option, int currentHz)
        {
            int fps = option == 2 || currentHz <= 0 ? 0 : option == 1 ? Math.Max(30, currentHz - 3) : currentHz;
            return fps.ToString(CultureInfo.InvariantCulture) + ".000000";
        }

        private static TweakItem Ini(IniDocument ini, string id, string title, string newLabel, Func<string, string> describe, params string[] triples)
        {
            var item = new TweakItem { Id = id, Title = title, Label = GameLabel, New = newLabel };
            bool done = true;
            for (int i = 0; i < triples.Length; i += 3)
            {
                item.Changes.Add(new[] { triples[i], triples[i + 1], triples[i + 2] });
                string current = ini.Get(triples[i], triples[i + 1]);
                if (!string.Equals(current, triples[i + 2], StringComparison.OrdinalIgnoreCase)) done = false;
                if (i == 0) item.Current = describe(current);
            }
            item.AlreadyDone = done;
            item.IsChecked = true;
            return item;
        }

        private static void BuildFortnite(TweakPlan plan, IGameEnvironment env, int currentHz)
        {
            string path = FortniteIniPath(env);
            plan.FortniteIni = path;
            if (!env.FileExists(path)) { plan.Warnings.Add("Abre Fortnite una vez y ciérralo: todavía no ha creado su archivo de ajustes."); return; }
            if (SafeFile.IsReparsePoint(path)) { plan.Warnings.Add("GameUserSettings.ini es un enlace: no se toca."); plan.FortniteIni = null; return; }
            if ((File.GetAttributes(path) & FileAttributes.ReadOnly) != 0)
            {
                plan.Warnings.Add("GameUserSettings.ini está en solo lectura (lo dejan así algunas guías). Quítale el atributo si quieres optimizar; iWinInstaller no lo cambia.");
                plan.FortniteIni = null;
                return;
            }
            IniDocument ini;
            try { ini = IniDocument.Parse(File.ReadAllBytes(path)); }
            catch (IOException ex) { plan.Warnings.Add("No se pudo leer GameUserSettings.ini: " + ex.Message); plan.FortniteIni = null; return; }

            string rhi = ini.Get("D3DRHIPreference", "PreferredRHI"), level = ini.Get("D3DRHIPreference", "PreferredFeatureLevel");
            var render = Ini(ini, "fn-render", "Modo de renderizado Rendimiento", "Rendimiento", v => v == null ? "—" : v, "D3DRHIPreference", "PreferredRHI", "dx11", "D3DRHIPreference", "PreferredFeatureLevel", "es31");
            render.Current = string.Equals(rhi, "dx11", StringComparison.OrdinalIgnoreCase) && string.Equals(level, "es31", StringComparison.OrdinalIgnoreCase)
                ? "Rendimiento" : rhi == null ? "Por defecto" : rhi.ToUpperInvariant();
            render.Note = "La clave más usada para el modo Rendimiento; compruébalo en el juego tras reiniciar.";
            plan.Items.Add(render);
            plan.Items.Add(Ini(ini, "fn-mesh", "Mallas bajas", "Baja", FortniteQuality, "PerformanceMode", "MeshQuality", "0"));
            plan.Items.Add(Ini(ini, "fn-textures", "Texturas bajas", "Baja", FortniteQuality, "ScalabilityGroups", "sg.TextureQuality", "0"));
            var view = Ini(ini, "fn-view", "Distancia de visión épica", "Épica", FortniteQuality, "ScalabilityGroups", "sg.ViewDistanceQuality", "3");
            view.Note = "Ver lejos importa en competitivo y en modo Rendimiento cuesta poco.";
            plan.Items.Add(view);
            plan.Items.Add(Ini(ini, "fn-res", "Resolución 3D al 100 %", "100 %", v => v == null ? "—" : v + " %", "ScalabilityGroups", "sg.ResolutionQuality", "100"));

            string hzText = currentHz > 0 ? currentHz.ToString(CultureInfo.InvariantCulture) : "?";
            var fps = new TweakItem
            {
                Id = "fn-fps", Title = "Límite de FPS", Label = GameLabel, Current = FortniteFps(ini.Get(FortniteSection, "FrameRateLimit")),
                Options = new List<string>
                {
                    hzText + " FPS (los Hz de tu pantalla)",
                    (currentHz > 0 ? Math.Max(30, currentHz - 3).ToString(CultureInfo.InvariantCulture) : "?") + " FPS (Hz − 3, con G‑Sync o FreeSync)",
                    "Sin límite (con Reflex + Boost; más calor)"
                },
                IsChecked = true
            };
            fps.New = fps.Options[0];
            fps.Changes.Add(new[] { FortniteSection, "FrameRateLimit", FortniteFpsValue(0, currentHz) });
            plan.Items.Add(fps);

            plan.Items.Add(Ini(ini, "fn-vsync", "VSync desactivado", "Desactivado", OnOff, FortniteSection, "bUseVSync", "False"));
            plan.Items.Add(Ini(ini, "fn-showfps", "Contador de FPS visible", "Activado", OnOff, FortniteSection, "bShowFPS", "True"));
            var full = Ini(ini, "fn-fullscreen", "Pantalla completa exclusiva", "Pantalla completa",
                v => v == "0" ? "Pantalla completa" : v == "1" ? "Sin bordes" : v == "2" ? "Ventana" : "—",
                FortniteSection, "FullscreenMode", "0", FortniteSection, "LastConfirmedFullscreenMode", "0", FortniteSection, "PreferredFullscreenMode", "0");
            full.IsChecked = false;
            full.Note = "Algo menos de latencia; cambiar de ventana con Alt+Tab es más lento.";
            plan.Items.Add(full);
        }

        private static readonly string[][] StarRailQuality =
        {
            new[] { "ShadowQuality", "2", "Sombras" }, new[] { "LightQuality", "1", "Luz" }, new[] { "CharacterQuality", "2", "Personajes" },
            new[] { "EnvDetailQuality", "1", "Detalle del entorno" }, new[] { "ReflectionQuality", "1", "Reflejos" },
            new[] { "BloomQuality", "1", "Resplandor" }, new[] { "SFXQuality", "2", "Efectos" }
        };

        private static void BuildStarRail(TweakPlan plan, GameInstall install, IGameEnvironment env)
        {
            if (install.IsChina) { plan.Warnings.Add("Versión china: solo se ajusta la GPU."); return; }
            string json; bool nul;
            if (!StarRailSettings.TryDecode(env.GetValue(StarRailSettings.RegistryKey, StarRailSettings.ModelValue) as byte[], out json, out nul))
            {
                plan.Warnings.Add("Abre el juego, cambia cualquier ajuste de gráficos y ciérralo: así guarda sus ajustes y se pueden optimizar.");
                return;
            }
            plan.StarRailReady = true;
            if (env.GetValue(StarRailSettings.RegistryKey, StarRailSettings.AbTestValue) != null)
                plan.Warnings.Add("El juego tiene activa una prueba de ajustes: puede ignorar estos cambios.");

            int? fps = StarRailSettings.GetInt(json, "FPS");
            if (fps.HasValue)
            {
                var item = new TweakItem
                {
                    Id = "sr-fps", Title = "120 FPS", Label = UnofficialLabel, Current = fps.Value + " FPS", New = "120 FPS", AlreadyDone = fps.Value == 120,
                    Note = "Escribe en tu registro el mismo valor que guarda el juego, con el juego cerrado; no toca la memoria ni los archivos. No es una opción oficial: HoYoverse no lo garantiza. No cambies la opción FPS dentro del juego."
                };
                item.Changes.Add(new[] { "FPS", "120" });
                plan.Items.Add(item);
            }
            string vsync = StarRailSettings.GetRaw(json, "EnableVSync");
            if (vsync != null)
            {
                var item = new TweakItem { Id = "sr-vsync", Title = "VSync desactivado", Label = GameLabel, Current = vsync == "true" ? "Activado" : "Desactivado", New = "Desactivado", AlreadyDone = vsync == "false", IsChecked = true };
                item.Changes.Add(new[] { "EnableVSync", "false" });
                plan.Items.Add(item);
            }
            var quality = new TweakItem { Id = "sr-quality", Title = "Gráficos para rendimiento", Label = GameLabel, New = "Bajo o muy bajo", IsChecked = true };
            var higher = new List<string>();
            foreach (var q in StarRailQuality)
            {
                int? value = StarRailSettings.GetInt(json, q[0]);
                int target = int.Parse(q[1], CultureInfo.InvariantCulture);
                if (!value.HasValue || value.Value <= target) continue; // solo baja, nunca sube
                quality.Changes.Add(new[] { q[0], q[1] });
                higher.Add(q[2] + " " + StarRailSettings.QualityName(value).ToLowerInvariant());
            }
            quality.AlreadyDone = higher.Count == 0;
            quality.Current = higher.Count == 0 ? "Ya en bajo" : string.Join(", ", higher);
            quality.Note = "Solo baja (nunca sube) sombras, luz, personajes, entorno, reflejos, resplandor y efectos. Resolución y antialiasing no cambian.";
            plan.Items.Add(quality);
        }

        /// <summary>Lista blanca de lo que una copia de este juego puede restaurar.</summary>
        public static Func<BackupItem, bool> Allowed(GameDefinition game, GameInstall install, IGameEnvironment env)
        {
            var exes = GpuExecutables(game, install, env);
            string ini = FortniteIniPath(env);
            return item =>
            {
                if (item.Kind == "file")
                    return game.Id == GameDefinitions.Fortnite && string.Equals(item.Target, ini, StringComparison.OrdinalIgnoreCase) && !SafeFile.IsReparsePoint(ini);
                if (string.Equals(item.Target, StarRailSettings.RegistryKey, StringComparison.OrdinalIgnoreCase))
                    return game.Id == GameDefinitions.StarRail && (item.Name == StarRailSettings.ModelValue || item.Name == StarRailSettings.QualityValue);
                if (string.Equals(item.Target, GpuPreference.RegistryKey, StringComparison.OrdinalIgnoreCase))
                    return exes.Contains(item.Name ?? "", StringComparer.OrdinalIgnoreCase);
                return false;
            };
        }

        /// <summary>Copia y aplica los cambios marcados. Si la copia falla no se cambia nada. Una línea por cambio.</summary>
        public static List<string> Apply(GameDefinition game, GameInstall install, IGameEnvironment env, TweakPlan plan, GameBackupStore store, int currentHz, DateTime nowUtc)
        {
            var lines = new List<string>();
            var chosen = plan.Items.Where(i => i.IsChecked).ToList();
            if (chosen.Count == 0) { lines.Add("No hay cambios marcados."); return lines; }

            var fortnite = chosen.Where(i => i.Id.StartsWith("fn-", StringComparison.Ordinal)).ToList();
            var starRail = chosen.Where(i => i.Id.StartsWith("sr-", StringComparison.Ordinal)).ToList();
            var gpu = chosen.FirstOrDefault(i => i.Id == "gpu");

            // 1. Copia de seguridad de todo lo que se va a tocar
            var items = new List<BackupItem>();
            var files = new Dictionary<string, string>();
            if (fortnite.Count > 0 && plan.FortniteIni != null)
            {
                items.Add(new BackupItem { Kind = "file", Target = plan.FortniteIni, Existed = true, File = "GameUserSettings.ini" });
                files["GameUserSettings.ini"] = plan.FortniteIni;
            }
            if (starRail.Count > 0)
            {
                items.Add(store.CaptureRegistry(StarRailSettings.RegistryKey, StarRailSettings.ModelValue));
                items.Add(store.CaptureRegistry(StarRailSettings.RegistryKey, StarRailSettings.QualityValue));
            }
            if (gpu != null) foreach (string exe in plan.GpuExes) items.Add(store.CaptureRegistry(GpuPreference.RegistryKey, exe));
            try { store.Create(game.Id, items, files, nowUtc); }
            catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
            {
                lines.Add("✗ No se pudo hacer la copia de seguridad (" + ex.Message + "): no se ha cambiado nada.");
                return lines;
            }

            // 2. Fortnite: un solo .ini, escritura atómica
            if (fortnite.Count > 0)
            {
                try
                {
                    var ini = IniDocument.Parse(File.ReadAllBytes(plan.FortniteIni));
                    foreach (var item in fortnite)
                    {
                        if (item.Id == "fn-fps") ini.Set(FortniteSection, "FrameRateLimit", FortniteFpsValue(item.SelectedIndex, currentHz));
                        else foreach (var c in item.Changes) ini.Set(c[0], c[1], c[2]);
                    }
                    SafeFile.WriteAtomic(plan.FortniteIni, ini.ToBytes());
                    foreach (var item in fortnite) lines.Add("✓ " + item.Title);
                }
                catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
                {
                    foreach (var item in fortnite) lines.Add("✗ " + item.Title + ": " + ex.Message);
                }
            }

            // 3. Star Rail: JSON en el sitio y calidad «Personalizado»
            if (starRail.Count > 0)
            {
                try
                {
                    string json; bool nul;
                    if (!StarRailSettings.TryDecode(env.GetValue(StarRailSettings.RegistryKey, StarRailSettings.ModelValue) as byte[], out json, out nul))
                        throw new IOException("los ajustes del juego ya no se pueden leer");
                    foreach (var item in starRail) foreach (var c in item.Changes) json = StarRailSettings.SetRaw(json, c[0], c[1]);
                    if (MiniJson.TryParseObject(json) == null) throw new IOException("el resultado no es JSON válido");
                    env.SetValue(StarRailSettings.RegistryKey, StarRailSettings.ModelValue, StarRailSettings.Encode(json, nul), RegKind.Binary);
                    env.SetValue(StarRailSettings.RegistryKey, StarRailSettings.QualityValue, StarRailSettings.CustomQuality, RegKind.DWord);
                    foreach (var item in starRail) lines.Add("✓ " + item.Title);
                }
                catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException || ex is System.Security.SecurityException)
                {
                    foreach (var item in starRail) lines.Add("✗ " + item.Title + ": " + ex.Message);
                }
            }

            // 4. GPU: solo el par GpuPreference de cada ejecutable
            if (gpu != null)
            {
                try
                {
                    foreach (string exe in plan.GpuExes)
                    {
                        string data = env.GetValue(GpuPreference.RegistryKey, exe) as string;
                        env.SetValue(GpuPreference.RegistryKey, exe, GpuPreference.SetPair(data, GpuPreference.PairName, GpuPreference.HighPerformance), RegKind.String);
                    }
                    lines.Add("✓ " + gpu.Title);
                }
                catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException || ex is System.Security.SecurityException)
                {
                    lines.Add("✗ " + gpu.Title + ": " + ex.Message);
                }
            }
            return lines;
        }
    }
}
