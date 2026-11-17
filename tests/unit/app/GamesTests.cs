using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using IWinInstaller.App.Modules.Games;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    /// <summary>Entorno en memoria para probar detección, ajustes y copias sin Windows.</summary>
    internal sealed class FakeGameEnvironment : IGameEnvironment
    {
        public readonly Dictionary<string, object> Values = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
        public readonly Dictionary<string, string> Files = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public readonly HashSet<string> Dirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        public readonly Dictionary<string, string> Companies = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public int Gpus = 2;

        public FakeGameEnvironment(string local) { LocalAppData = local; ProgramData = Path.Combine(local, "ProgramData"); }
        public string LocalAppData { get; private set; }
        public string ProgramData { get; private set; }

        private static string Id(string key, string name) { return key + "|" + name; }
        public object GetValue(string key, string name) { object v; return Values.TryGetValue(Id(key, name), out v) ? v : null; }
        public string[] SubKeyNames(string key)
        {
            string prefix = key + "\\";
            return Values.Keys.Where(k => k.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                .Select(k => k.Substring(prefix.Length).Split('\\', '|')[0]).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        }
        public void SetValue(string key, string name, object value, RegKind kind) { Values[Id(key, name)] = value; }
        public void DeleteValue(string key, string name) { Values.Remove(Id(key, name)); }

        public void AddFile(string path, string text = "")
        {
            Files[path] = text;
            for (string dir = Path.GetDirectoryName(path); !string.IsNullOrEmpty(dir); dir = Path.GetDirectoryName(dir)) Dirs.Add(dir);
        }
        public bool FileExists(string path) { return path != null && (Files.ContainsKey(path) || File.Exists(path)); }
        public bool DirectoryExists(string path) { return path != null && Dirs.Contains(path.TrimEnd('\\', '/')); }
        public string ReadAllText(string path) { string t; return Files.TryGetValue(path, out t) ? t : File.ReadAllText(path); }
        public string[] GetFiles(string directory, string pattern)
        {
            string suffix = pattern.TrimStart('*');
            return Files.Keys.Where(f => string.Equals(Path.GetDirectoryName(f), directory, StringComparison.OrdinalIgnoreCase)
                && f.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)).ToArray();
        }
        public string[] GetDirectories(string directory)
        {
            return Dirs.Where(d => string.Equals(Path.GetDirectoryName(d), directory, StringComparison.OrdinalIgnoreCase)).ToArray();
        }
        public string CompanyName(string path) { string c; return Companies.TryGetValue(path, out c) ? c : null; }
        public bool AnyProcessRunning(IEnumerable<string> names) { return false; }
        public int GpuCount() { return Gpus; }
    }

    [TestClass]
    public class GamesTests
    {
        private static string NewTempDir()
        {
            string dir = Path.Combine(Path.GetTempPath(), "iwin-games-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            return dir;
        }

        // ---------- JSON ----------

        [TestMethod]
        public void MiniJsonLeeYEscribe()
        {
            var data = MiniJson.TryParseObject("{\"a\":\"x\\\\y\",\"n\":1.5,\"b\":true,\"l\":[1,null],\"o\":{}}");
            Assert.AreEqual("x\\y", MiniJson.GetString(data, "a"));
            Assert.AreEqual(1.5, MiniJson.GetNumber(data, "n").Value, 1e-9);
            Assert.IsNull(MiniJson.TryParseObject("{\"a\":"));
            var round = MiniJson.TryParseObject(MiniJson.Serialize(data));
            Assert.AreEqual("x\\y", MiniJson.GetString(round, "a"));
        }

        // ---------- .ini ----------

        [TestMethod]
        public void IniCambiaSoloLaLineaYConservaElResto()
        {
            string text = "[/Script/FortniteGame.FortGameUserSettings]\r\nbUseVSync=True\r\n+Paths=x\r\nFrameRateLimit=60.000000\r\n\r\n[ScalabilityGroups]\r\nsg.TextureQuality=3\r\n";
            byte[] original = Encoding.UTF8.GetBytes(text);
            var ini = IniDocument.Parse(original);
            Assert.AreEqual("True", ini.Get("/script/fortnitegame.fortgameusersettings", "bUseVSync"), "sin distinguir mayúsculas");
            ini.Set(GameTweaks.FortniteSection, "bUseVSync", "False");
            string result = Encoding.UTF8.GetString(ini.ToBytes());
            Assert.AreEqual(text.Replace("bUseVSync=True", "bUseVSync=False"), result);
        }

        [TestMethod]
        public void IniConservaBomYSaltosLf()
        {
            byte[] bom = { 0xEF, 0xBB, 0xBF };
            byte[] body = Encoding.UTF8.GetBytes("[A]\nk=1\n");
            var ini = IniDocument.Parse(bom.Concat(body).ToArray());
            ini.Set("A", "nueva", "2");
            byte[] bytes = ini.ToBytes();
            CollectionAssert.AreEqual(bom, bytes.Take(3).ToArray());
            Assert.AreEqual("[A]\nk=1\nnueva=2\n", Encoding.UTF8.GetString(bytes, 3, bytes.Length - 3));
        }

        [TestMethod]
        public void IniUtf16YSeccionNueva()
        {
            var original = new byte[] { 0xFF, 0xFE }.Concat(Encoding.Unicode.GetBytes("[A]\r\nk=1")).ToArray();
            var ini = IniDocument.Parse(original);
            ini.Set("D3DRHIPreference", "PreferredRHI", "dx11");
            byte[] bytes = ini.ToBytes();
            Assert.AreEqual(0xFF, bytes[0]);
            Assert.AreEqual("[A]\r\nk=1\r\n\r\n[D3DRHIPreference]\r\nPreferredRHI=dx11\r\n", Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2));
        }

        [TestMethod]
        public void IniNoTocaLineasConPrefijoDeUnreal()
        {
            var ini = IniDocument.Parse(Encoding.UTF8.GetBytes("[S]\n+k=1\n"));
            Assert.IsNull(ini.Get("S", "k"));
            ini.Set("S", "k", "2");
            Assert.AreEqual("[S]\n+k=1\nk=2\n", Encoding.UTF8.GetString(ini.ToBytes()));
        }

        [TestMethod]
        public void IniSinSaltoFinalSeConserva()
        {
            var ini = IniDocument.Parse(Encoding.UTF8.GetBytes("[S]\r\na=1"));
            ini.Set("S", "b", "2");
            Assert.AreEqual("[S]\r\na=1\r\nb=2", Encoding.UTF8.GetString(ini.ToBytes()));
        }

        // ---------- Star Rail ----------

        [TestMethod]
        public void StarRailCambiaFpsYConservaElResto()
        {
            string json = "{\"FPS\":60,\"EnableVSync\":true,\"RenderScale\":1.0,\"Extra\":\"FPS\"}";
            byte[] data = StarRailSettings.Encode(json, true);
            Assert.AreEqual(0, data[data.Length - 1]);
            string decoded; bool nul;
            Assert.IsTrue(StarRailSettings.TryDecode(data, out decoded, out nul));
            Assert.IsTrue(nul);
            string changed = StarRailSettings.SetRaw(StarRailSettings.SetRaw(decoded, "FPS", "120"), "EnableVSync", "false");
            Assert.AreEqual("{\"FPS\":120,\"EnableVSync\":false,\"RenderScale\":1.0,\"Extra\":\"FPS\"}", changed);
            Assert.AreEqual(changed, StarRailSettings.SetRaw(changed, "NoExiste", "1"), "una clave ausente no se añade");
            Assert.AreEqual(120, StarRailSettings.GetInt(changed, "FPS"));
        }

        [TestMethod]
        public void StarRailRechazaDatosQueNoSonJson()
        {
            string json; bool nul;
            Assert.IsFalse(StarRailSettings.TryDecode(new byte[] { 1, 2, 3, 0 }, out json, out nul));
            Assert.IsFalse(StarRailSettings.TryDecode(null, out json, out nul));
        }

        [TestMethod]
        public void StarRailOptimizarSoloBajaCalidadesYMarcaPersonalizado()
        {
            var env = new FakeGameEnvironment(NewTempDir());
            string json = "{\"FPS\":60,\"EnableVSync\":true,\"ShadowQuality\":4,\"LightQuality\":1,\"SFXQuality\":1}";
            env.SetValue(StarRailSettings.RegistryKey, StarRailSettings.ModelValue, StarRailSettings.Encode(json, true), RegKind.Binary);
            env.SetValue(StarRailSettings.RegistryKey, StarRailSettings.QualityValue, 3, RegKind.DWord);
            var game = GameDefinitions.Get(GameDefinitions.StarRail);
            var install = new GameInstall { Folder = @"C:\HSR", ExePath = @"C:\HSR\StarRail.exe" };
            var plan = GameTweaks.Build(game, install, env, 144);
            var fps = plan.Items.Single(i => i.Id == "sr-fps");
            Assert.IsFalse(fps.IsChecked, "120 FPS no oficial: desmarcado por defecto");
            Assert.IsTrue(fps.IsUnofficial);
            fps.IsChecked = true;
            var store = new GameBackupStore(Path.Combine(env.LocalAppData, "Juegos"), env);
            var lines = GameTweaks.Apply(game, install, env, plan, store, 144, new DateTime(2026, 11, 17, 19, 0, 0, DateTimeKind.Utc));
            Assert.IsTrue(lines.All(l => l.StartsWith("✓", StringComparison.Ordinal)), string.Join(" | ", lines));
            string after; bool nul;
            StarRailSettings.TryDecode((byte[])env.GetValue(StarRailSettings.RegistryKey, StarRailSettings.ModelValue), out after, out nul);
            Assert.AreEqual("{\"FPS\":120,\"EnableVSync\":false,\"ShadowQuality\":2,\"LightQuality\":1,\"SFXQuality\":1}", after, "SFX 1 no sube a 2");
            Assert.AreEqual(0, env.GetValue(StarRailSettings.RegistryKey, StarRailSettings.QualityValue));

            // Restaurar devuelve el JSON y la calidad originales
            var set = store.Latest(GameDefinitions.StarRail);
            var restored = store.Restore(set, GameTweaks.Allowed(game, install, env));
            Assert.IsTrue(restored.All(l => l.StartsWith("✓", StringComparison.Ordinal)), string.Join(" | ", restored));
            StarRailSettings.TryDecode((byte[])env.GetValue(StarRailSettings.RegistryKey, StarRailSettings.ModelValue), out after, out nul);
            Assert.AreEqual(json, after);
            Assert.AreEqual(3, env.GetValue(StarRailSettings.RegistryKey, StarRailSettings.QualityValue));
        }

        // ---------- GPU ----------

        [TestMethod]
        public void GpuCambiaSoloSuParYConservaLosDemas()
        {
            Assert.AreEqual("GpuPreference=2;", GpuPreference.SetPair(null, "GpuPreference", "2"));
            Assert.AreEqual("SwapEffectUpgradeEnable=1;AutoHDREnable=1;GpuPreference=2;",
                GpuPreference.SetPair("SwapEffectUpgradeEnable=1;AutoHDREnable=1;GpuPreference=0;", "GpuPreference", "2"));
            Assert.AreEqual("GpuPreference=2;SwapEffectUpgradeEnable=1;", GpuPreference.SetPair("SwapEffectUpgradeEnable=1;", "GpuPreference", "2"));
            Assert.AreEqual("1", GpuPreference.GetPair("a=3;GpuPreference=1;", "gpupreference"));
        }

        [TestMethod]
        public void GpuConUnaSolaGraficaSaleDesmarcada()
        {
            var env = new FakeGameEnvironment(NewTempDir()) { Gpus = 1 };
            var plan = GameTweaks.Build(GameDefinitions.Get(GameDefinitions.Genshin), new GameInstall { Folder = @"C:\G", ExePath = @"C:\G\GenshinImpact.exe" }, env, 60);
            var gpu = plan.Items.Single(i => i.Id == "gpu");
            Assert.IsFalse(gpu.IsChecked);
            StringAssert.Contains(gpu.Note, "una sola GPU");
            Assert.AreEqual(1, plan.Items.Count, "Genshin solo tiene el ajuste de GPU");
        }

        // ---------- Archivos ----------

        [TestMethod]
        public void PkgVersionComprobacionRapidaYCompleta()
        {
            string dir = NewTempDir();
            File.WriteAllText(Path.Combine(dir, "a.bin"), "hola");
            Directory.CreateDirectory(Path.Combine(dir, "sub"));
            File.WriteAllText(Path.Combine(dir, "sub", "b.bin"), "123");
            string list =
                "{\"remoteName\": \"a.bin\", \"md5\": \"4d186321c1a7f0f354b297e8914ab240\", \"fileSize\": 4}\n" +
                "{\"remoteName\": \"sub/b.bin\", \"md5\": \"00000000000000000000000000000000\", \"fileSize\": 3}\n" +
                "{\"remoteName\": \"c.bin\", \"md5\": \"x\", \"fileSize\": 1}\n" +
                "{\"remoteName\": \"../fuera.bin\", \"md5\": \"x\", \"fileSize\": 1}\n" +
                "basura\n";
            var entries = PkgVersion.Parse(list);
            Assert.AreEqual(4, entries.Count);
            var quick = PkgVersion.Check(dir, entries, false, null, CancellationToken.None);
            Assert.AreEqual(1, quick.Missing, "c.bin falta; ../fuera.bin se ignora");
            Assert.AreEqual(0, quick.WrongMd5);
            var full = PkgVersion.Check(dir, entries, true, null, CancellationToken.None);
            Assert.AreEqual(1, full.WrongMd5);
            Assert.AreEqual("MD5", full.Problems.Single(p => p.Path == "sub/b.bin").Kind);
            Assert.IsTrue(full.ListLooksStale, "2 de 4 mal: más del 5 %");
            Assert.IsNull(PkgVersion.Resolve(dir, "../x"));
        }

        [TestMethod]
        public void SinListaNoEsCorrecto()
        {
            var result = PkgVersion.Check(NewTempDir(), new List<PkgEntry>(), false, null, CancellationToken.None);
            Assert.IsTrue(result.NoList);
            Assert.IsFalse(result.Ok);
        }

        // ---------- Detección ----------

        [TestMethod]
        public void EpicSteamYHoyoConfig()
        {
            var epic = EpicManifest.Parse("{\"AppName\":\"Fortnite\",\"DisplayName\":\"Fortnite\",\"InstallLocation\":\"D:\\\\Epic\\\\Fortnite\",\"AppVersionString\":\"++Fortnite+Release-33.00\",\"InstallSize\":120000000000}");
            Assert.AreEqual(@"D:\Epic\Fortnite", epic.InstallLocation);
            Assert.AreEqual(120000000000L, epic.InstallSize);
            Assert.IsTrue(GameLocator.MatchesEpic(GameDefinitions.Get(GameDefinitions.Fortnite), epic));
            Assert.IsFalse(GameLocator.MatchesEpic(GameDefinitions.Get(GameDefinitions.Genshin), epic));

            string vdf = "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"C:\\\\Program Files (x86)\\\\Steam\"\n\t}\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\"E:\\\\SteamLibrary\"\n\t}\n}";
            CollectionAssert.AreEqual(new[] { @"C:\Program Files (x86)\Steam", @"E:\SteamLibrary" }, SteamLibrary.ParseFolders(vdf));
            string acf = "\"AppState\"\n{\n\t\"appid\"\t\t\"4732690\"\n\t\"installdir\"\t\t\"Arknights Endfield\"\n\t\"SizeOnDisk\"\t\t\"50000\"\n}";
            Assert.AreEqual("Arknights Endfield", SteamLibrary.ParseField(acf, "installdir"));
            Assert.AreEqual("50000", SteamLibrary.ParseField(acf, "sizeondisk"));

            Assert.AreEqual("3.2.0", HoyoConfig.ParseVersion("[general]\r\nchannel=1\r\ngame_version=3.2.0\r\n"));
            Assert.IsNull(HoyoConfig.ParseVersion("[general]\r\n"));
        }

        [TestMethod]
        public void HoyoPlayGanaYLaGlobalVaAntesQueLaChina()
        {
            string root = NewTempDir();
            var env = new FakeGameEnvironment(root);
            string cn = Path.Combine(root, "CN"), gi = Path.Combine(root, "GI");
            env.SetValue(@"HKCU\Software\Cognosphere\HYP\1_0\hk4e_cn", "GameInstallPath", cn, RegKind.String);
            env.SetValue(@"HKCU\Software\Cognosphere\HYP\1_0\hk4e_global", "GameInstallPath", gi, RegKind.String);
            env.AddFile(Path.Combine(cn, "YuanShen.exe"));
            env.AddFile(Path.Combine(gi, "GenshinImpact.exe"));
            var found = GameLocator.Locate(GameDefinitions.Get(GameDefinitions.Genshin), env, null);
            Assert.AreEqual(Path.Combine(gi, "GenshinImpact.exe"), found.ExePath);
            Assert.AreEqual("HoYoPlay", found.Source);
            Assert.IsFalse(found.IsChina);
        }

        [TestMethod]
        public void RutaSinEjecutableSeDescartaYSeUsaElDesinstalador()
        {
            string root = NewTempDir();
            var env = new FakeGameEnvironment(root);
            string empty = Path.Combine(root, "Vacia"), game = Path.Combine(root, "Star Rail");
            env.SetValue(@"HKCU\Software\Cognosphere\HYP\1_0\hkrpg_global", "GameInstallPath", empty, RegKind.String);
            env.Dirs.Add(empty);
            string key = GameLocator.UninstallRoots[0] + @"\HSR";
            env.SetValue(key, "DisplayName", "Honkai: Star Rail", RegKind.String);
            env.SetValue(key, "InstallLocation", "\"" + game + "\"", RegKind.String);
            string exe = Path.Combine(game, "Games", "StarRail.exe");
            env.AddFile(exe);
            var found = GameLocator.Locate(GameDefinitions.Get(GameDefinitions.StarRail), env, null);
            Assert.AreEqual(exe, found.ExePath, "un nivel por debajo de InstallLocation");
            Assert.AreEqual("Windows", found.Source);
        }

        [TestMethod]
        public void EndfieldPorSteamYEmpresa()
        {
            string root = NewTempDir();
            var env = new FakeGameEnvironment(root);
            string steam = Path.Combine(root, "steam"), lib = Path.Combine(root, "Lib");
            env.SetValue(@"HKCU\Software\Valve\Steam", "SteamPath", steam, RegKind.String);
            env.AddFile(Path.Combine(steam, "steamapps", "libraryfolders.vdf"), "\"path\" \"" + lib.Replace("\\", "\\\\") + "\"");
            env.AddFile(Path.Combine(lib, "steamapps", "appmanifest_4732690.acf"), "\"installdir\" \"Arknights Endfield\"\n\"SizeOnDisk\" \"42\"\n\"buildid\" \"7\"");
            string dir = Path.Combine(lib, "steamapps", "common", "Arknights Endfield");
            env.AddFile(Path.Combine(dir, "UnityCrashHandler64.exe"));
            env.AddFile(Path.Combine(dir, "Juego.exe"));
            env.Companies[Path.Combine(dir, "Juego.exe")] = "Shanghai Hypergryph Network Technology Co., Ltd.";
            var found = GameLocator.Locate(GameDefinitions.Get(GameDefinitions.Endfield), env, null);
            Assert.AreEqual(Path.Combine(dir, "Juego.exe"), found.ExePath);
            Assert.AreEqual(42L, found.SizeBytes);
            Assert.AreEqual("build 7", found.Version);
            Assert.IsTrue(found.FromSteam);
        }

        // ---------- Fortnite y copias ----------

        [TestMethod]
        public void FortniteOptimizarYRestaurar()
        {
            string local = NewTempDir();
            var env = new FakeGameEnvironment(local);
            string ini = GameTweaks.FortniteIniPath(env);
            Directory.CreateDirectory(Path.GetDirectoryName(ini));
            string original = "[/Script/FortniteGame.FortGameUserSettings]\r\nbUseVSync=True\r\nFrameRateLimit=60.000000\r\nFullscreenMode=1\r\n\r\n[ScalabilityGroups]\r\nsg.TextureQuality=3\r\n";
            File.WriteAllText(ini, original, new UTF8Encoding(false));
            var game = GameDefinitions.Get(GameDefinitions.Fortnite);
            var install = new GameInstall { Folder = @"C:\Fortnite", ExePath = @"C:\Fortnite\" + GameDefinitions.FortniteExe };
            var plan = GameTweaks.Build(game, install, env, 144);
            Assert.AreEqual(0, plan.Warnings.Count, string.Join(" | ", plan.Warnings));
            Assert.IsFalse(plan.Items.Single(i => i.Id == "fn-fullscreen").IsChecked, "pantalla completa exclusiva desmarcada");
            plan.Items.Single(i => i.Id == "fn-fps").SelectedIndex = 1;
            var store = new GameBackupStore(Path.Combine(local, "Juegos"), env);
            var lines = GameTweaks.Apply(game, install, env, plan, store, 144, new DateTime(2026, 11, 17, 19, 0, 0, DateTimeKind.Utc));
            Assert.IsTrue(lines.All(l => l.StartsWith("✓", StringComparison.Ordinal)), string.Join(" | ", lines));

            var doc = IniDocument.Parse(File.ReadAllBytes(ini));
            Assert.AreEqual("False", doc.Get(GameTweaks.FortniteSection, "bUseVSync"));
            Assert.AreEqual("141.000000", doc.Get(GameTweaks.FortniteSection, "FrameRateLimit"));
            Assert.AreEqual("1", doc.Get(GameTweaks.FortniteSection, "FullscreenMode"));
            Assert.AreEqual("0", doc.Get("ScalabilityGroups", "sg.TextureQuality"));
            Assert.AreEqual("dx11", doc.Get("D3DRHIPreference", "PreferredRHI"));
            Assert.AreEqual("es31", doc.Get("D3DRHIPreference", "PreferredFeatureLevel"));
            Assert.AreEqual("0", doc.Get("PerformanceMode", "MeshQuality"));
            Assert.AreEqual("GpuPreference=2;", env.GetValue(GpuPreference.RegistryKey, install.ExePath));

            var restored = store.Restore(store.Latest(GameDefinitions.Fortnite), GameTweaks.Allowed(game, install, env));
            Assert.IsTrue(restored.All(l => l.StartsWith("✓", StringComparison.Ordinal)), string.Join(" | ", restored));
            Assert.AreEqual(original, File.ReadAllText(ini));
            Assert.IsNull(env.GetValue(GpuPreference.RegistryKey, install.ExePath), "no existía: se borra");
        }

        [TestMethod]
        public void FortniteSoloLecturaNoSeToca()
        {
            string local = NewTempDir();
            var env = new FakeGameEnvironment(local);
            string ini = GameTweaks.FortniteIniPath(env);
            Directory.CreateDirectory(Path.GetDirectoryName(ini));
            File.WriteAllText(ini, "[A]\r\n");
            File.SetAttributes(ini, FileAttributes.ReadOnly);
            try
            {
                var plan = GameTweaks.Build(GameDefinitions.Get(GameDefinitions.Fortnite), new GameInstall { Folder = @"C:\F", ExePath = @"C:\F\x.exe" }, env, 60);
                Assert.IsNull(plan.FortniteIni);
                Assert.IsFalse(plan.Items.Any(i => i.Id.StartsWith("fn-", StringComparison.Ordinal)));
                StringAssert.Contains(plan.Warnings[0], "solo lectura");
            }
            finally { File.SetAttributes(ini, FileAttributes.Normal); }
        }

        [TestMethod]
        public void LaListaBlancaRechazaOtrosDestinosYArchivosFueraDeLaCopia()
        {
            var env = new FakeGameEnvironment(NewTempDir());
            var game = GameDefinitions.Get(GameDefinitions.Genshin);
            var install = new GameInstall { Folder = @"C:\G", ExePath = @"C:\G\GenshinImpact.exe" };
            var allowed = GameTweaks.Allowed(game, install, env);
            Assert.IsTrue(allowed(new BackupItem { Kind = "reg-string", Target = GpuPreference.RegistryKey, Name = @"C:\G\GenshinImpact.exe" }));
            Assert.IsFalse(allowed(new BackupItem { Kind = "reg-string", Target = GpuPreference.RegistryKey, Name = @"C:\Windows\explorer.exe" }));
            Assert.IsFalse(allowed(new BackupItem { Kind = "reg-string", Target = @"HKCU\Software\Microsoft\Windows\CurrentVersion\Run", Name = "x" }));
            Assert.IsFalse(allowed(new BackupItem { Kind = "reg-binary", Target = StarRailSettings.RegistryKey, Name = StarRailSettings.ModelValue }), "Star Rail no es este juego");
            Assert.IsFalse(allowed(new BackupItem { Kind = "file", Target = @"C:\Windows\win.ini" }));

            string copy = NewTempDir();
            File.WriteAllText(Path.Combine(copy, "GameUserSettings.ini"), "x");
            Assert.IsNotNull(GameBackupStore.SafeSource(copy, "GameUserSettings.ini"));
            Assert.IsNull(GameBackupStore.SafeSource(copy, @"..\otro.ini"));
            Assert.IsNull(GameBackupStore.SafeSource(copy, "../otro.ini"));
        }

        [TestMethod]
        public void SeGuardanLasDiezUltimasCopias()
        {
            var env = new FakeGameEnvironment(NewTempDir());
            var store = new GameBackupStore(Path.Combine(env.LocalAppData, "Juegos"), env);
            var start = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            for (int i = 0; i < 12; i++)
                store.Create(GameDefinitions.Zzz, new List<BackupItem> { store.CaptureRegistry(GpuPreference.RegistryKey, @"C:\Z\ZenlessZoneZero.exe") }, null, start.AddMinutes(i));
            var all = store.List(GameDefinitions.Zzz);
            Assert.AreEqual(GameBackupStore.Keep, all.Count);
            Assert.AreEqual(start.AddMinutes(11), all[0].At);
        }

        [TestMethod]
        public void LimiteDeFpsSegunLaOpcion()
        {
            Assert.AreEqual("144.000000", GameTweaks.FortniteFpsValue(0, 144));
            Assert.AreEqual("141.000000", GameTweaks.FortniteFpsValue(1, 144));
            Assert.AreEqual("0.000000", GameTweaks.FortniteFpsValue(2, 144));
            Assert.AreEqual("0.000000", GameTweaks.FortniteFpsValue(0, 0), "sin Hz conocidos: sin límite");
            Assert.AreEqual("Sin límite", GameTweaks.FortniteFps("0.000000"));
            Assert.AreEqual("240 FPS", GameTweaks.FortniteFps("240.000000"));
        }
    }
}
