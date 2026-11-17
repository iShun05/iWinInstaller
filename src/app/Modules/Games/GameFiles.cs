using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>Una línea de pkg_version (lista de archivos que publican los juegos de HoYoverse).</summary>
    public sealed class PkgEntry
    {
        public string RemoteName { get; set; }
        public string Md5 { get; set; }
        public long Size { get; set; }
    }

    public sealed class FileProblem
    {
        public FileProblem(string path, string kind) { Path = path; Kind = kind; }
        public string Path { get; private set; }
        /// <summary>«falta», «tamaño», «MD5» o «carpeta».</summary>
        public string Kind { get; private set; }
    }

    public sealed class FileCheckResult
    {
        public FileCheckResult() { Problems = new List<FileProblem>(); }
        public string Mode { get; set; }
        public int Total { get; set; }
        public int Missing { get; set; }
        public int WrongSize { get; set; }
        public int WrongMd5 { get; set; }
        public bool NoList { get; set; }
        public bool Cancelled { get; set; }
        public List<FileProblem> Problems { get; private set; }
        public int Bad { get { return Missing + WrongSize + WrongMd5; } }
        public bool Ok { get { return !NoList && !Cancelled && Bad == 0; } }
        /// <summary>Más del 5 % mal: la lista probablemente está desactualizada (no «archivos dañados»).</summary>
        public bool ListLooksStale { get { return Total > 0 && Bad * 20 > Total; } }

        public void Add(string path, string kind)
        {
            if (kind == "falta") Missing++; else if (kind == "tamaño") WrongSize++; else if (kind == "MD5") WrongMd5++;
            Problems.Add(new FileProblem(path, kind));
        }
    }

    public static class PkgVersion
    {
        public static List<PkgEntry> Parse(string text)
        {
            var result = new List<PkgEntry>();
            if (string.IsNullOrEmpty(text)) return result;
            foreach (string raw in text.Split('\n'))
            {
                string line = raw.Trim();
                if (line.Length == 0) continue;
                var data = MiniJson.TryParseObject(line);
                if (data == null) continue;
                string name = MiniJson.GetString(data, "remoteName");
                double? size = MiniJson.GetNumber(data, "fileSize");
                if (string.IsNullOrEmpty(name) || !size.HasValue || size.Value < 0) continue;
                result.Add(new PkgEntry { RemoteName = name, Md5 = MiniJson.GetString(data, "md5"), Size = (long)size.Value });
            }
            return result;
        }

        /// <summary>Ruta segura dentro de la carpeta del juego, o null si la entrada intenta salir de ella.</summary>
        public static string Resolve(string folder, string remoteName)
        {
            if (string.IsNullOrEmpty(remoteName) || Path.IsPathRooted(remoteName)) return null;
            string root = Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(Path.Combine(root, remoteName.Replace('/', Path.DirectorySeparatorChar)));
            return full.StartsWith(root, StringComparison.OrdinalIgnoreCase) ? full : null;
        }

        /// <summary>Lee todas las listas *pkg_version de la raíz del juego (la principal y las de audio).</summary>
        public static List<PkgEntry> LoadAll(string folder)
        {
            var all = new List<PkgEntry>();
            if (!Directory.Exists(folder)) return all;
            foreach (string list in Directory.GetFiles(folder, "*pkg_version", SearchOption.TopDirectoryOnly))
                all.AddRange(Parse(File.ReadAllText(list, Encoding.UTF8)));
            return all;
        }

        /// <summary>Rápida: existe y el tamaño coincide. Completa (md5 = true): además el MD5. Cancelable.</summary>
        public static FileCheckResult Check(string folder, IList<PkgEntry> entries, bool md5, IProgress<double> progress, CancellationToken token)
        {
            var result = new FileCheckResult { Mode = md5 ? "completa" : "rápida", Total = entries.Count };
            if (entries.Count == 0) { result.NoList = true; return result; }
            long totalBytes = 0, doneBytes = 0;
            foreach (var e in entries) totalBytes += e.Size;
            for (int i = 0; i < entries.Count; i++)
            {
                if (token.IsCancellationRequested) { result.Cancelled = true; return result; }
                var entry = entries[i];
                string path = Resolve(folder, entry.RemoteName);
                if (path == null) continue;
                var info = new FileInfo(path);
                if (!info.Exists) result.Add(entry.RemoteName, "falta");
                else if (info.Length != entry.Size) result.Add(entry.RemoteName, "tamaño");
                else if (md5 && !string.IsNullOrEmpty(entry.Md5))
                {
                    string hash = Md5Of(path, token);
                    if (hash == null) { result.Cancelled = true; return result; }
                    if (!hash.Equals(entry.Md5, StringComparison.OrdinalIgnoreCase)) result.Add(entry.RemoteName, "MD5");
                }
                doneBytes += entry.Size;
                if (progress != null) progress.Report(md5 && totalBytes > 0 ? (double)doneBytes / totalBytes : (double)(i + 1) / entries.Count);
            }
            return result;
        }

        private static string Md5Of(string path, CancellationToken token)
        {
            using (var md5 = MD5.Create())
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 1 << 20, FileOptions.SequentialScan))
            {
                var buffer = new byte[1 << 20];
                int read;
                while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    if (token.IsCancellationRequested) return null;
                    md5.TransformBlock(buffer, 0, read, null, 0);
                }
                md5.TransformFinalBlock(buffer, 0, 0);
                var sb = new StringBuilder();
                foreach (byte b in md5.Hash) sb.Append(b.ToString("x2", CultureInfo.InvariantCulture));
                return sb.ToString();
            }
        }
    }

    public static class BasicFileCheck
    {
        /// <summary>Fortnite: ejecutable, Paks con algún .pak/.utoc y la carpeta .egstore de Epic.</summary>
        public static FileCheckResult Fortnite(string folder)
        {
            var result = new FileCheckResult { Mode = "básica", Total = 3 };
            if (!File.Exists(Path.Combine(folder, GameDefinitions.FortniteExe))) result.Add(GameDefinitions.FortniteExe, "falta");
            string paks = Path.Combine(folder, @"FortniteGame\Content\Paks");
            bool hasPaks = Directory.Exists(paks) &&
                (Directory.GetFiles(paks, "*.pak", SearchOption.TopDirectoryOnly).Length > 0 || Directory.GetFiles(paks, "*.utoc", SearchOption.TopDirectoryOnly).Length > 0);
            if (!hasPaks) result.Add(@"FortniteGame\Content\Paks", "falta");
            if (!Directory.Exists(Path.Combine(folder, ".egstore"))) result.Add(".egstore", "falta");
            return result;
        }

        /// <summary>Solo el ejecutable (Endfield, o un juego de HoYoverse sin lista de archivos).</summary>
        public static FileCheckResult Executable(string exePath)
        {
            var result = new FileCheckResult { Mode = "básica", Total = 1 };
            if (!File.Exists(exePath)) result.Add(Path.GetFileName(exePath), "falta");
            return result;
        }
    }
}
