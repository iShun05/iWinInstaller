using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace IWinInstaller.App.Modules.Gaming
{
    /// <summary>Ventana deslizante de pings (60 muestras = 60 s): último, media, jitter, pérdida y máximo.</summary>
    public sealed class LatencyStats
    {
        private readonly int _capacity;
        private readonly Queue<long?> _samples = new Queue<long?>();

        public LatencyStats(int capacity = 60) { _capacity = Math.Max(2, capacity); }

        /// <summary>Añade una muestra en milisegundos; null = sin respuesta.</summary>
        public void Add(long? ms)
        {
            _samples.Enqueue(ms);
            while (_samples.Count > _capacity) _samples.Dequeue();
        }

        public void Clear() { _samples.Clear(); }
        public int Count { get { return _samples.Count; } }
        public IList<long?> Samples { get { return _samples.ToList(); } }
        public long? Last { get { return _samples.Count == 0 ? null : _samples.Last(); } }

        private List<long> Answers { get { return _samples.Where(s => s.HasValue).Select(s => s.Value).ToList(); } }

        public double? Average { get { var a = Answers; return a.Count == 0 ? (double?)null : a.Average(); } }
        public long? Max { get { var a = Answers; return a.Count == 0 ? (long?)null : a.Max(); } }

        /// <summary>Media de la diferencia absoluta entre respuestas consecutivas (RFC 3550, simplificado).</summary>
        public double? Jitter
        {
            get
            {
                var a = Answers;
                if (a.Count < 2) return null;
                double sum = 0;
                for (int i = 1; i < a.Count; i++) sum += Math.Abs(a[i] - a[i - 1]);
                return sum / (a.Count - 1);
            }
        }

        public double LossPercent
        {
            get { return _samples.Count == 0 ? 0 : 100.0 * _samples.Count(s => !s.HasValue) / _samples.Count; }
        }

        /// <summary>Todas las muestras recientes sin respuesta (al menos 10): el destino no contesta a ping.</summary>
        public bool NoAnswer(int minimum = 10)
        {
            return _samples.Count >= minimum && _samples.Skip(_samples.Count - minimum).All(s => !s.HasValue);
        }

        /// <summary>Nota de bufferbloat según la latencia añadida bajo carga (límite inferior incluido en la nota siguiente).</summary>
        public static string BufferbloatGrade(double addedMs)
        {
            if (Double.IsNaN(addedMs)) return "?";
            if (addedMs < 5) return "A+";
            if (addedMs < 30) return "A";
            if (addedMs < 60) return "B";
            if (addedMs < 200) return "C";
            if (addedMs < 400) return "D";
            return "F";
        }

        /// <summary>Percentil p (0–100) con interpolación lineal; NaN si no hay datos.</summary>
        public static double Percentile(IList<double> values, double p)
        {
            if (values == null || values.Count == 0) return Double.NaN;
            var sorted = values.OrderBy(v => v).ToList();
            double rank = Math.Max(0, Math.Min(100, p)) / 100.0 * (sorted.Count - 1);
            int low = (int)Math.Floor(rank), high = (int)Math.Ceiling(rank);
            return sorted[low] + (sorted[high] - sorted[low]) * (rank - low);
        }

        /// <summary>Estado de color: «ok», «warn» o «bad». Router: verde &lt; 5 ms, ámbar &lt; 20. Internet/juego: &lt; 40, &lt; 80.</summary>
        public static string Level(double? average, double lossPercent, bool router)
        {
            if (!average.HasValue) return "bad";
            double good = router ? 5 : 40, warn = router ? 20 : 80, maxLoss = router ? 0 : 2;
            if (average.Value >= warn || lossPercent > maxLoss) return "bad";
            return average.Value < good ? "ok" : "warn";
        }

        /// <summary>Servidor del juego válido: dirección IP o nombre DNS (máx. 253 caracteres).</summary>
        public static bool IsValidHost(string host)
        {
            if (String.IsNullOrWhiteSpace(host)) return false;
            host = host.Trim();
            System.Net.IPAddress address;
            if (System.Net.IPAddress.TryParse(host, out address)) return true;
            return host.Length <= 253 && Regex.IsMatch(host, @"^([a-zA-Z0-9-]{1,63}\.)*[a-zA-Z0-9-]{1,63}$") && !host.StartsWith("-", StringComparison.Ordinal);
        }
    }

    /// <summary>Datos de Wi-Fi de «netsh wlan show interfaces» (inglés o español), sin SSID ni BSSID.</summary>
    public sealed class WifiInfo
    {
        public int? Signal { get; private set; }
        public int? Channel { get; private set; }
        public string Band { get; private set; }
        public string RadioType { get; private set; }

        public static WifiInfo Parse(string text)
        {
            var info = new WifiInfo();
            if (String.IsNullOrEmpty(text)) return info;
            foreach (var raw in text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                int colon = raw.IndexOf(':');
                if (colon < 0) continue;
                string key = raw.Substring(0, colon).Trim().ToLowerInvariant(), value = raw.Substring(colon + 1).Trim();
                Match m;
                if (!info.Signal.HasValue && (m = Regex.Match(value, @"^(\d{1,3})\s*%$")).Success) info.Signal = Int32.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
                else if ((key == "channel" || key == "canal") && (m = Regex.Match(value, @"^(\d{1,3})")).Success) info.Channel = Int32.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
                else if ((key == "band" || key == "banda") && value.Length > 0) info.Band = NormalizeBand(value);
                else if ((key == "radio type" || key == "tipo de radio") && value.Length > 0) info.RadioType = value;
            }
            if (info.Band == null && info.Channel.HasValue) info.Band = info.Channel.Value <= 14 ? "2,4 GHz" : info.Channel.Value <= 177 ? "5 GHz" : null;
            return info;
        }

        private static string NormalizeBand(string value)
        {
            if (value.StartsWith("2", StringComparison.Ordinal)) return "2,4 GHz";
            if (value.StartsWith("5", StringComparison.Ordinal)) return "5 GHz";
            if (value.StartsWith("6", StringComparison.Ordinal)) return "6 GHz";
            return value;
        }
    }
}
