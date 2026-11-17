using System.Collections.Generic;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>Datos fijos de un juego: dónde buscarlo, qué ejecutables y procesos tiene y qué textos se muestran.</summary>
    public sealed class GameDefinition
    {
        public string Id { get; set; }
        public string Name { get; set; }
        /// <summary>Ejecutable principal relativo a la carpeta del juego (versión global).</summary>
        public string[] Executables { get; set; }
        /// <summary>Ejecutables de la versión china (solo HoYoverse).</summary>
        public string[] ChinaExecutables { get; set; }
        /// <summary>Otros ejecutables a los que también se aplica la GPU (si existen).</summary>
        public string[] ExtraExecutables { get; set; }
        public string[] HoyoBizGlobal { get; set; }
        public string[] HoyoBizChina { get; set; }
        public string EpicAppName { get; set; }
        public string EpicDisplayName { get; set; }
        public int SteamAppId { get; set; }
        public string[] UninstallNames { get; set; }
        /// <summary>Endfield: el ejecutable se busca por empresa o prefijo (nombre por verificar en el PC).</summary>
        public bool FindExeByCompany { get; set; }
        public string[] Companies { get; set; }
        public string ExePrefix { get; set; }
        public string[] SubFolders { get; set; }
        /// <summary>Procesos del juego (bloquean Optimizar, Restaurar y Comprobar).</summary>
        public string[] GameProcesses { get; set; }
        /// <summary>Procesos del lanzador (bloquean Comprobar: puede estar actualizando).</summary>
        public string[] LauncherProcesses { get; set; }
        public string AntiCheat { get; set; }
        public string Website { get; set; }
        public string FilesHelp { get; set; }
        public string[] InGameTips { get; set; }
        /// <summary>Texto fijo bajo la lista de cambios (lo que no se toca y por qué).</summary>
        public string Note { get; set; }
    }

    public static class GameDefinitions
    {
        public const string Fortnite = "fortnite", StarRail = "starrail", Zzz = "zzz", Endfield = "endfield", Genshin = "genshin";
        public const string FortniteExe = @"FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe";

        private static readonly string[] HoyoLauncher = { "HYP", "HoYoPlay" };

        public static readonly IList<GameDefinition> All = new List<GameDefinition>
        {
            new GameDefinition
            {
                Id = Fortnite, Name = "Fortnite",
                Executables = new[] { FortniteExe },
                ExtraExecutables = new[] { @"FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping_EAC_EOS.exe", @"FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping_BE.exe" },
                EpicAppName = "Fortnite", UninstallNames = new[] { "Fortnite" },
                GameProcesses = new[] { "FortniteClient-Win64-Shipping*", "FortniteLauncher" },
                LauncherProcesses = new[] { "EpicGamesLauncher" },
                AntiCheat = "Easy Anti-Cheat o BattlEye",
                Website = "https://www.fortnite.com/",
                FilesHelp = "Comprobación básica. Para una verificación real: Epic Games › Biblioteca › ⋯ en Fortnite › Administrar › Verificar.",
                InGameTips = new[]
                {
                    "Vídeo › NVIDIA Reflex: Activado + Boost (con NVIDIA). La clave del archivo no está documentada y no se adivina.",
                    "Tras reiniciar el juego, comprueba que «Modo de renderizado» dice Rendimiento.",
                    "Para comparar antes y después, mira el contador de FPS (lo activa Optimizar) o usa CapFrameX."
                },
                Note = "Se edita GameUserSettings.ini, el mismo archivo que guarda el menú del juego. No se toca nada de la carpeta del juego."
            },
            new GameDefinition
            {
                Id = StarRail, Name = "Honkai: Star Rail",
                Executables = new[] { "StarRail.exe" }, ChinaExecutables = new[] { "StarRail.exe" },
                HoyoBizGlobal = new[] { "hkrpg_global" }, HoyoBizChina = new[] { "hkrpg_cn" },
                EpicDisplayName = "Honkai: Star Rail", UninstallNames = new[] { "Honkai: Star Rail", "Star Rail" },
                GameProcesses = new[] { "StarRail" }, LauncherProcesses = HoyoLauncher,
                AntiCheat = "HoYoKProtect (HoYoverse)",
                Website = "https://hsr.hoyoverse.com/",
                FilesHelp = "Si hay fallos: HoYoPlay › ⚙ junto a Jugar › Reparar juego.",
                InGameTips = new[]
                {
                    "Gráficos › DLSS si tienes NVIDIA.",
                    "Si aplicas 120 FPS, no cambies la opción FPS dentro del juego: el menú puede mostrar otro valor y, si la tocas, vuelve a 60."
                },
                Note = "Se cambian los valores que el juego guarda en tu registro de usuario (HKCU), con el juego cerrado. No se toca la memoria ni los archivos del juego."
            },
            new GameDefinition
            {
                Id = Zzz, Name = "Zenless Zone Zero",
                Executables = new[] { "ZenlessZoneZero.exe" }, ChinaExecutables = new[] { "ZenlessZoneZero.exe" },
                HoyoBizGlobal = new[] { "nap_global" }, HoyoBizChina = new[] { "nap_cn" },
                EpicDisplayName = "Zenless Zone Zero", UninstallNames = new[] { "Zenless Zone Zero" },
                GameProcesses = new[] { "ZenlessZoneZero" }, LauncherProcesses = HoyoLauncher,
                AntiCheat = "HoYoKProtect (HoYoverse)",
                Website = "https://zenless.hoyoverse.com/",
                FilesHelp = "Si hay fallos: HoYoPlay › ⚙ junto a Jugar › Reparar juego.",
                InGameTips = new[]
                {
                    "Ajustes › Gráficos › Límite de FPS: Ilimitado (o 120).",
                    "Sincronización vertical: No.",
                    "Calidad baja o personalizada y «Animación de personajes de alta precisión» desactivada."
                },
                Note = "Zenless ya ofrece «Ilimitado» en su menú. Sus ajustes van cifrados dentro de la carpeta del juego: no se tocan. Desde fuera solo se ajusta la GPU."
            },
            new GameDefinition
            {
                Id = Endfield, Name = "Arknights: Endfield",
                FindExeByCompany = true, Companies = new[] { "Hypergryph", "Gryphline" }, ExePrefix = "Endfield",
                SubFolders = new[] { "", @"games\EndField Game" },
                SteamAppId = 4732690, EpicDisplayName = "Endfield", UninstallNames = new[] { "Endfield", "GRYPHLINK" },
                GameProcesses = new[] { "Endfield*" }, LauncherProcesses = new[] { "GRYPHLINK" },
                AntiCheat = "el anticheat de Hypergryph",
                Website = "https://endfield.gryphline.com/",
                FilesHelp = "Si hay fallos: en GRYPHLINK usa su opción de reparar o, en Steam, «Verificar en Steam».",
                InGameTips = new[]
                {
                    "Rendimiento y gráficos › FPS: 120.",
                    "Sincronización vertical: No. NVIDIA Reflex: Activado.",
                    "DLSS «Equilibrado» o TAAU y generación de fotogramas desactivada (añade latencia)."
                },
                Note = "Endfield ya ofrece 120 FPS en su menú y no hay un formato de ajustes documentado: no se toca. Desde fuera solo se ajusta la GPU."
            },
            new GameDefinition
            {
                Id = Genshin, Name = "Genshin Impact",
                Executables = new[] { "GenshinImpact.exe" }, ChinaExecutables = new[] { "YuanShen.exe" },
                HoyoBizGlobal = new[] { "hk4e_global" }, HoyoBizChina = new[] { "hk4e_cn" },
                EpicDisplayName = "Genshin Impact", UninstallNames = new[] { "Genshin Impact" },
                GameProcesses = new[] { "GenshinImpact", "YuanShen" }, LauncherProcesses = HoyoLauncher,
                AntiCheat = "mhyprot / HoYoKProtect (HoYoverse)",
                Website = "https://genshin.hoyoverse.com/",
                FilesHelp = "Si hay fallos: HoYoPlay › ⚙ junto a Jugar › Reparar juego.",
                InGameTips = new[]
                {
                    "Ajustes › Gráficos › FPS: 60 (el máximo oficial en PC a fecha de v5.3).",
                    "Sincronización vertical: No. Calidad personalizada baja."
                },
                Note = "Genshin no permite más de 60 FPS en PC. Los desbloqueadores escriben en la memoria del juego y violan sus términos: iWinInstaller no lo hace. Desde fuera solo se ajusta la GPU."
            }
        };

        public static GameDefinition Get(string id)
        {
            foreach (var game in All) if (game.Id == id) return game;
            return null;
        }
    }
}
