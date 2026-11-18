using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Threading;
using IWinInstaller.App.Modules.Gaming;

namespace IWinInstaller.App.Modules.Rendimiento
{
    public static class PerfStats
    {
        /// <summary>Percentil p (0–100) por interpolación lineal; la lista debe venir ordenada de menor a mayor.</summary>
        public static double Percentile(IList<double> sorted, double p)
        {
            if (sorted == null || sorted.Count == 0) return 0;
            if (sorted.Count == 1) return sorted[0];
            double rank = Math.Max(0, Math.Min(100, p)) / 100.0 * (sorted.Count - 1);
            int low = (int)Math.Floor(rank), high = (int)Math.Ceiling(rank);
            return sorted[low] + (sorted[high] - sorted[low]) * (rank - low);
        }
    }

    /// <summary>
    /// Mide cuánto tarda de más Windows en despertar un hilo que pide dormir 1 ms: refleja el temporizador y la carga del planificador
    /// (lo que se nota como tirones con la CPU ocupada). No sustituye a los FPS del juego: es una referencia comparable antes y después.
    /// </summary>
    public static class SchedulerProbe
    {
        public static List<double> Collect(int milliseconds, CancellationToken token)
        {
            var samples = new List<double>();
            double toMs = 1000.0 / Stopwatch.Frequency;
            long end = Stopwatch.GetTimestamp() + (long)(milliseconds / toMs);
            while (Stopwatch.GetTimestamp() < end && !token.IsCancellationRequested)
            {
                long t0 = Stopwatch.GetTimestamp();
                Thread.Sleep(1);
                samples.Add(Math.Max(0, (Stopwatch.GetTimestamp() - t0) * toMs - 1.0));
            }
            return samples;
        }

        public static void Fill(PerfSnapshot snapshot, IList<double> samples)
        {
            if (samples == null || samples.Count < 5) return;
            var sorted = samples.OrderBy(x => x).ToList();
            snapshot.SchedP50 = PerfStats.Percentile(sorted, 50);
            snapshot.SchedP95 = PerfStats.Percentile(sorted, 95);
            snapshot.SchedP99 = PerfStats.Percentile(sorted, 99);
        }
    }

    public static class PingProbe
    {
        /// <summary>Diez pings a 1.1.1.1 (~10 s) y sus estadísticas con la misma lógica que la página Latencia.</summary>
        public static void Fill(PerfSnapshot snapshot, CancellationToken token, int count = 10)
        {
            var stats = new LatencyStats(count);
            try
            {
                using (var ping = new Ping())
                    for (int i = 0; i < count && !token.IsCancellationRequested; i++)
                    {
                        long? ms = null;
                        try { var reply = ping.Send(IPAddress.Parse("1.1.1.1"), 1000); if (reply.Status == IPStatus.Success) ms = reply.RoundtripTime; }
                        catch (PingException) { }
                        stats.Add(ms);
                        if (i < count - 1) Thread.Sleep(300);
                    }
            }
            catch (InvalidOperationException) { }
            if (stats.Count < 3 || stats.Average == null) return;
            snapshot.PingAvg = stats.Average; snapshot.PingJitter = stats.Jitter; snapshot.PingLoss = stats.LossPercent;
        }
    }

    /// <summary>Frametimes de un juego a partir de MsBetweenPresents (la columna que PresentMon escribe en su CSV).</summary>
    public static class FrameStats
    {
        public static List<double> ParseCsv(string csv)
        {
            var values = new List<double>();
            if (string.IsNullOrEmpty(csv)) return values;
            int column = -1;
            bool header = false;
            foreach (string raw in csv.Split('\n'))
            {
                string line = raw.TrimEnd('\r');
                if (line.Length == 0) continue;
                var cells = line.Split(',');
                if (!header)
                {
                    header = true;
                    column = Array.FindIndex(cells, c => string.Equals(c.Trim(), "MsBetweenPresents", StringComparison.OrdinalIgnoreCase));
                    if (column < 0) return values;
                    continue;
                }
                double ms;
                if (column < cells.Length && double.TryParse(cells[column], NumberStyles.Float, CultureInfo.InvariantCulture, out ms) && ms > 0 && ms < 2000) values.Add(ms);
            }
            return values;
        }

        public static void Fill(PerfSnapshot snapshot, IList<double> frameMs)
        {
            if (frameMs == null || frameMs.Count < 30) return;
            double avg = frameMs.Average();
            var sorted = frameMs.OrderBy(x => x).ToList();
            snapshot.Fps = 1000.0 / avg;
            snapshot.FrameP99 = PerfStats.Percentile(sorted, 99);
            // «1 % low»: FPS de la media del 1 % de fotogramas más lentos
            int worst = Math.Max(1, (int)Math.Ceiling(sorted.Count * 0.01));
            snapshot.Low1Fps = 1000.0 / sorted.Skip(sorted.Count - worst).Average();
        }

        /// <summary>PresentMon instalado (PATH, Intel, CapFrameX) o null.</summary>
        public static string FindPresentMon()
        {
            var folders = new List<string>();
            string path = Environment.GetEnvironmentVariable("PATH") ?? "";
            folders.AddRange(path.Split(Path.PathSeparator).Where(f => f.Trim().Length > 0));
            foreach (var special in new[] { Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.LocalApplicationData })
            {
                string root = Environment.GetFolderPath(special);
                if (root.Length == 0) continue;
                folders.Add(Path.Combine(root, "Intel", "PresentMon"));
                folders.Add(Path.Combine(root, "CapFrameX"));
                folders.Add(Path.Combine(root, "Programs", "CapFrameX"));
            }
            foreach (string folder in folders)
            {
                try
                {
                    if (!Directory.Exists(folder)) continue;
                    var found = Directory.GetFiles(folder, "PresentMon*.exe", SearchOption.TopDirectoryOnly).OrderByDescending(f => f, StringComparer.OrdinalIgnoreCase).FirstOrDefault();
                    if (found != null) return found;
                }
                catch (Exception e) when (e is IOException || e is UnauthorizedAccessException || e is ArgumentException) { }
            }
            return null;
        }

        /// <summary>Captura seconds segundos del proceso con PresentMon (puede pedir permisos de ETW); devuelve el CSV o null con el motivo en error.</summary>
        public static string Capture(string presentMon, string processName, int seconds, out string error)
        {
            error = null;
            string csv = Path.Combine(Path.GetTempPath(), "iwin-presentmon-" + Guid.NewGuid().ToString("N") + ".csv");
            try
            {
                var info = new ProcessStartInfo(presentMon,
                    "-process_name \"" + processName + ".exe\" -timed " + seconds.ToString(CultureInfo.InvariantCulture) + " -terminate_after_timed -stop_existing_session -output_file \"" + csv + "\"")
                { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true };
                using (var process = Process.Start(info))
                {
                    var errorText = process.StandardError.ReadToEndAsync();
                    if (!process.WaitForExit((seconds + 15) * 1000)) { try { process.Kill(); } catch (InvalidOperationException) { } error = "PresentMon no terminó a tiempo."; return null; }
                    string err = errorText.Wait(2000) ? errorText.Result : "";
                    if (!File.Exists(csv)) { error = string.IsNullOrWhiteSpace(err) ? "PresentMon no generó datos (¿el juego está en pantalla completa y activo?)." : err.Trim(); return null; }
                    return File.ReadAllText(csv);
                }
            }
            catch (Exception e) when (e is System.ComponentModel.Win32Exception || e is IOException || e is InvalidOperationException || e is UnauthorizedAccessException)
            { error = "No se pudo ejecutar PresentMon: " + e.Message; return null; }
            finally { try { if (File.Exists(csv)) File.Delete(csv); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
        }
    }

    /// <summary>Una fila de la comparación antes/después.</summary>
    public sealed class CompareLine
    {
        public string Metric { get; set; }
        public string Before { get; set; }
        public string After { get; set; }
        /// <summary>«better», «worse» o «same».</summary>
        public string Verdict { get; set; }
        public string VerdictText { get { return Verdict == "better" ? "Mejor" : Verdict == "worse" ? "Peor" : "Sin cambio notable"; } }
    }

    public static class PerfCompare
    {
        public static List<CompareLine> Compare(PerfSnapshot before, PerfSnapshot after)
        {
            var lines = new List<CompareLine>();
            Add(lines, "Sobrecarga de Sleep(1), mediana", before.SchedP50, after.SchedP50, " ms", false, 0.15, "0.00");
            Add(lines, "Sobrecarga de Sleep(1), p99 (tirones)", before.SchedP99, after.SchedP99, " ms", false, 0.5, "0.00");
            Add(lines, "Ping a Internet, media", before.PingAvg, after.PingAvg, " ms", false, 2, "0.0");
            Add(lines, "Jitter del ping", before.PingJitter, after.PingJitter, " ms", false, 1.5, "0.0");
            Add(lines, "FPS medios", before.Fps, after.Fps, "", true, 3, "0");
            Add(lines, "FPS del 1 % más lento", before.Low1Fps, after.Low1Fps, "", true, 3, "0");
            Add(lines, "Frametime p99", before.FrameP99, after.FrameP99, " ms", false, 0.8, "0.0");
            return lines;
        }

        /// <summary>Cambio relevante: al menos un 10 % y más que el ruido absoluto de cada métrica.</summary>
        private static void Add(List<CompareLine> lines, string metric, double? before, double? after, string unit, bool higherIsBetter, double noise, string format)
        {
            if (!before.HasValue || !after.HasValue) return;
            double diff = after.Value - before.Value;
            double relative = before.Value == 0 ? (diff == 0 ? 0 : 1) : Math.Abs(diff) / Math.Abs(before.Value);
            string verdict = "same";
            if (Math.Abs(diff) >= noise && relative >= 0.10) verdict = (diff > 0) == higherIsBetter ? "better" : "worse";
            lines.Add(new CompareLine
            {
                Metric = metric, Verdict = verdict,
                Before = before.Value.ToString(format, CultureInfo.CurrentCulture) + unit,
                After = after.Value.ToString(format, CultureInfo.CurrentCulture) + unit
            });
        }
    }
}
