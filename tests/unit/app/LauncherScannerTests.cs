using System.Linq;
using IWinInstaller.App.Modules.Games;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace IWinInstaller.App.Tests
{
    [TestClass]
    public class LauncherScannerTests
    {
        private static FakeGameEnvironment NewEnv() { return new FakeGameEnvironment(@"C:\Users\t\AppData\Local"); }

        [TestMethod]
        public void XboxLeeMicrosoftGameConfig()
        {
            var env = NewEnv();
            env.AddFile(@"D:\XboxGames\Forza\Content\MicrosoftGame.Config",
                "<Game configVersion=\"1\"><Identity Name=\"X.Forza\" Version=\"1.2.3.0\"/><ShellVisuals DefaultDisplayName=\"Forza Horizon 5\"/>" +
                "<ExecutableList><Executable Name=\"forza.exe\"/></ExecutableList></Game>");
            env.AddFile(@"D:\XboxGames\Forza\Content\forza.exe");
            env.AddFile(@"D:\XboxGames\Raro\Content\MicrosoftGame.Config", "<Game><ShellVisuals DefaultDisplayName=\"ms-resource:Name\"/></Game>");
            var games = LauncherScanner.ScanXbox(env);
            Assert.AreEqual(2, games.Count);
            var forza = games.Single(g => g.Name == "Forza Horizon 5");
            Assert.AreEqual("1.2.3.0", forza.Version);
            Assert.AreEqual(@"D:\XboxGames\Forza\Content\forza.exe", forza.ExePath);
            Assert.AreEqual("Raro", games.Single(g => g.Folder.EndsWith("Raro")).Name);
        }

        [TestMethod]
        public void XboxConfigInvalidoOSinDtd()
        {
            Assert.IsNull(XboxGameConfig.Parse("<Game"));
            Assert.IsNull(XboxGameConfig.Parse("<!DOCTYPE a [<!ENTITY x SYSTEM \"file:///c:/x\">]><a>&x;</a>"));
            Assert.IsNull(XboxGameConfig.Parse(""));
        }

        [TestMethod]
        public void BattleNetUsaDesinstalarDeBlizzard()
        {
            var env = NewEnv();
            string key = @"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Overwatch";
            env.Values[key + "|Publisher"] = "Blizzard Entertainment";
            env.Values[key + "|DisplayName"] = "Overwatch 2";
            env.Values[key + "|InstallLocation"] = @"C:\Games\Overwatch";
            env.Values[key + "|DisplayVersion"] = "2.9";
            env.Dirs.Add(@"C:\Games\Overwatch");
            string launcher = @"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Battle.net";
            env.Values[launcher + "|Publisher"] = "Blizzard Entertainment";
            env.Values[launcher + "|DisplayName"] = "Battle.net";
            env.Values[launcher + "|InstallLocation"] = @"C:\Program Files (x86)\Battle.net";
            env.Dirs.Add(@"C:\Program Files (x86)\Battle.net");
            var games = LauncherScanner.ScanBattleNet(env);
            Assert.AreEqual(1, games.Count);
            Assert.AreEqual("Overwatch 2", games[0].Name);
            Assert.AreEqual("2.9", games[0].Version);
        }

        [TestMethod]
        public void EaUbisoftYGog()
        {
            var env = NewEnv();
            env.Values[@"HKLM\SOFTWARE\WOW6432Node\EA Games\Apex|Install Dir"] = @"C:\EA\Apex\";
            env.Dirs.Add(@"C:\EA\Apex");
            env.Values[@"HKLM\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs\635|InstallDir"] = "C:/Ubi/games/Rayman Legends/";
            env.Dirs.Add(@"C:\Ubi\games\Rayman Legends");
            env.Values[@"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Uplay Install 635|DisplayName"] = "Rayman Legends";
            string gog = @"HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\1207658924";
            env.Values[gog + "|gameName"] = "The Witcher 3";
            env.Values[gog + "|path"] = @"C:\GOG\Witcher3";
            env.Values[gog + "|ver"] = "4.04";
            env.Dirs.Add(@"C:\GOG\Witcher3");
            string dlc = @"HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\1207658930";
            env.Values[dlc + "|gameName"] = "Witcher DLC";
            env.Values[dlc + "|path"] = @"C:\GOG\Witcher3";
            env.Values[dlc + "|dependsOn"] = "1207658924";

            Assert.AreEqual("Apex", LauncherScanner.ScanEa(env).Single().Name);
            var ubi = LauncherScanner.ScanUbisoft(env).Single();
            Assert.AreEqual("Rayman Legends", ubi.Name);
            Assert.AreEqual(@"C:\Ubi\games\Rayman Legends", ubi.Folder.TrimEnd('\\'));
            var g = LauncherScanner.ScanGog(env).Single();
            Assert.AreEqual("The Witcher 3", g.Name);
            Assert.AreEqual("4.04", g.Version);
        }

        [TestMethod]
        public void EpicYSteamExcluyenHerramientas()
        {
            var env = NewEnv();
            string manifests = System.IO.Path.Combine(env.ProgramData, "Epic", "EpicGamesLauncher", "Data", "Manifests");
            env.AddFile(System.IO.Path.Combine(manifests, "a.item"), "{\"AppName\":\"Sugar\",\"DisplayName\":\"Rocket League\",\"InstallLocation\":\"C:\\\\Epic\\\\RL\",\"AppVersionString\":\"1.0\",\"InstallSize\":1073741824}");
            env.AddFile(System.IO.Path.Combine(manifests, "b.item"), "{\"AppName\":\"UE_5.3\",\"DisplayName\":\"Unreal Engine\",\"InstallLocation\":\"C:\\\\Epic\\\\UE\"}");
            env.Dirs.Add(@"C:\Epic\RL"); env.Dirs.Add(@"C:\Epic\UE");
            env.Values[@"HKCU\Software\Valve\Steam|SteamPath"] = @"C:\Steam";
            env.AddFile(@"C:\Steam\steamapps\appmanifest_730.acf", "\"AppState\"\n{\n\"name\"\t\"Counter-Strike 2\"\n\"installdir\"\t\"Counter-Strike Global Offensive\"\n\"SizeOnDisk\"\t\"5000\"\n\"buildid\"\t\"42\"\n}");
            env.AddFile(@"C:\Steam\steamapps\appmanifest_228980.acf", "\"AppState\"\n{\n\"name\"\t\"Steamworks Common Redistributables\"\n\"installdir\"\t\"Steamworks Shared\"\n}");
            env.Dirs.Add(@"C:\Steam\steamapps\common\Counter-Strike Global Offensive");
            env.Dirs.Add(@"C:\Steam\steamapps\common\Steamworks Shared");
            Assert.AreEqual("Rocket League", LauncherScanner.ScanEpic(env).Single().Name);
            var steam = LauncherScanner.ScanSteam(env).Single();
            Assert.AreEqual("Counter-Strike 2", steam.Name);
            Assert.AreEqual("build 42", steam.Version);
        }

        [TestMethod]
        public void ScanExcluyeLosJuegosConTarjetaYNoRepite()
        {
            var env = NewEnv();
            string gog = @"HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\1";
            env.Values[gog + "|gameName"] = "Uno"; env.Values[gog + "|path"] = @"C:\G\Uno"; env.Dirs.Add(@"C:\G\Uno");
            string gog2 = @"HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\2";
            env.Values[gog2 + "|gameName"] = "Dos"; env.Values[gog2 + "|path"] = @"C:\G\Dos\"; env.Dirs.Add(@"C:\G\Dos");
            var all = LauncherScanner.Scan(env, new[] { @"c:\g\uno" });
            Assert.AreEqual(1, all.Count);
            Assert.AreEqual("Dos", all[0].Name);
            Assert.AreEqual(0, LauncherScanner.Scan(NewEnv(), null).Count);
        }
    }
}
