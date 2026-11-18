using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management;
using IWinInstaller.App.Modules.Equipo;

namespace IWinInstaller.App.Modules.Rendimiento
{
    public sealed class ThermalSample
    {
        public DateTime AtUtc { get; set; }
        public double? CpuC { get; set; }
        public double? GpuC { get; set; }
        /// <summary>% de la frecuencia máxima que la CPU está usando ahora.</summary>
        public double? CpuFreqPercent { get; set; }
        public double? CpuLoad { get; set; }
        /// <summary>La gráfica NVIDIA informa de recorte de reloj por temperatura.</summary>
        public bool GpuThermalThrottle { get; set; }
    }

    public interface IThermalSource
    {
        ThermalSample Read();
    }

    /// <summary>
    /// Vigila una partida: avisa si la CPU o la gráfica pasan de la temperatura de riesgo varias muestras seguidas, o si la CPU recorta
    /// su frecuencia con carga alta, y al terminar guarda un resumen. Entre avisos del mismo tipo esperan dos minutos para no molestar.
    /// </summary>
    public sealed class ThermalTracker
    {
        public const double CpuHot = 90, GpuHot = 88, ThrottleBelowPercent = 70, MinLoad = 70, ThrottleTempFloor = 80;
        public static readonly TimeSpan Cooldown = TimeSpan.FromMinutes(2);
        private readonly Action<ThermalEvent> _raise;
        private readonly string _game;
        private int _hotRun, _throttleRun, _hotCount, _throttleCount, _samples;
        private double? _peakCpu, _peakGpu;
        private DateTime _lastHot = DateTime.MinValue, _lastThrottle = DateTime.MinValue;

        public ThermalTracker(string game, Action<ThermalEvent> raise) { _game = game; _raise = raise; }

        public int Samples { get { return _samples; } }
        public double? PeakCpu { get { return _peakCpu; } }
        public double? PeakGpu { get { return _peakGpu; } }
        public int HotAlerts { get { return _hotCount; } }
        public int ThrottleAlerts { get { return _throttleCount; } }

        public void Add(ThermalSample s)
        {
            _samples++;
            if (s.CpuC.HasValue) _peakCpu = Math.Max(_peakCpu ?? 0, s.CpuC.Value);
            if (s.GpuC.HasValue) _peakGpu = Math.Max(_peakGpu ?? 0, s.GpuC.Value);

            bool hot = (s.CpuC.HasValue && s.CpuC.Value >= CpuHot) || (s.GpuC.HasValue && s.GpuC.Value >= GpuHot);
            _hotRun = hot ? _hotRun + 1 : 0;
            if (_hotRun >= 2 && s.AtUtc - _lastHot >= Cooldown)
            {
                _lastHot = s.AtUtc; _hotCount++;
                bool cpu = s.CpuC.HasValue && s.CpuC.Value >= CpuHot;
                double peak = cpu ? s.CpuC.Value : s.GpuC.Value;
                _raise(new ThermalEvent
                {
                    AtUtc = s.AtUtc, Kind = "hot", Game = _game, PeakC = peak,
                    Detail = (cpu ? "CPU" : "Gráfica") + " a " + Math.Round(peak).ToString(CultureInfo.CurrentCulture) + " °C durante la partida. Revisa ventilación, polvo y el plan de energía."
                });
            }

            bool cpuThrottle = s.CpuFreqPercent.HasValue && s.CpuFreqPercent.Value < ThrottleBelowPercent && s.CpuLoad.HasValue && s.CpuLoad.Value >= MinLoad
                && (!s.CpuC.HasValue || s.CpuC.Value >= ThrottleTempFloor);
            _throttleRun = cpuThrottle || s.GpuThermalThrottle ? _throttleRun + 1 : 0;
            if (_throttleRun >= (s.GpuThermalThrottle ? 2 : 3) && s.AtUtc - _lastThrottle >= Cooldown)
            {
                _lastThrottle = s.AtUtc; _throttleCount++;
                string who = s.GpuThermalThrottle ? "La gráfica está recortando su reloj por temperatura" :
                    "La CPU va al " + Math.Round(s.CpuFreqPercent.Value).ToString(CultureInfo.CurrentCulture) + " % de su frecuencia con la carga alta";
                _raise(new ThermalEvent { AtUtc = s.AtUtc, Kind = "throttle", Game = _game, PeakC = s.CpuC ?? s.GpuC, Detail = who + ": hay throttling térmico o de potencia." });
            }
        }

        /// <summary>Resumen al terminar la partida; null si no hubo muestras.</summary>
        public ThermalEvent Finish(DateTime atUtc)
        {
            if (_samples == 0) return null;
            var parts = new List<string>();
            if (_peakCpu.HasValue) parts.Add("CPU máx. " + Math.Round(_peakCpu.Value).ToString(CultureInfo.CurrentCulture) + " °C");
            if (_peakGpu.HasValue) parts.Add("GPU máx. " + Math.Round(_peakGpu.Value).ToString(CultureInfo.CurrentCulture) + " °C");
            if (parts.Count == 0) parts.Add("sin sensores de temperatura accesibles");
            parts.Add(_hotCount + " aviso(s) de calor");
            parts.Add(_throttleCount + " de throttling");
            return new ThermalEvent
            {
                AtUtc = atUtc, Kind = "summary", Game = _game, Detail = string.Join(" · ", parts),
                PeakC = _peakCpu.HasValue || _peakGpu.HasValue ? Math.Max(_peakCpu ?? 0, _peakGpu ?? 0) : (double?)null
            };
        }
    }

    public static class NvidiaSmi
    {
        /// <summary>«65, Not Active, Active» → temperatura y recorte térmico. Acepta también solo la temperatura.</summary>
        public static bool TryParse(string line, out double temperature, out bool thermalThrottle)
        {
            temperature = 0; thermalThrottle = false;
            if (string.IsNullOrWhiteSpace(line)) return false;
            var cells = line.Trim().Split(',').Select(c => c.Trim()).ToArray();
            if (!double.TryParse(cells[0], NumberStyles.Float, CultureInfo.InvariantCulture, out temperature) || temperature <= 0 || temperature > 150) return false;
            thermalThrottle = cells.Skip(1).Any(c => string.Equals(c, "Active", StringComparison.OrdinalIgnoreCase));
            return true;
        }
    }

    /// <summary>Lectura real: zonas térmicas de Windows, contadores de frecuencia/carga y nvidia-smi si existe. Todo con permisos de usuario.</summary>
    public sealed class WindowsThermalSource : IThermalSource, IDisposable
    {
        private PerformanceCounter _freq, _load;
        private bool _countersTried;
        private string _smi;
        private bool _smiTried;
        private DateTime _lastSmi = DateTime.MinValue;
        private double? _gpuC;
        private bool _gpuThrottle;

        private static bool Expected(Exception e)
        {
            return e is ManagementException || e is UnauthorizedAccessException || e is InvalidOperationException || e is Win32Exception ||
                   e is IOException || e is System.Runtime.InteropServices.COMException;
        }

        public ThermalSample Read()
        {
            var sample = new ThermalSample { AtUtc = DateTime.UtcNow };
            sample.CpuC = CpuTemperature();
            ReadCounters(sample);
            ReadGpu(sample);
            return sample;
        }

        private static double? CpuTemperature()
        {
            try
            {
                var readings = new List<double>();
                using (var searcher = new ManagementObjectSearcher(@"root\cimv2", "SELECT Temperature, HighPrecisionTemperature FROM Win32_PerfFormattedData_Counters_ThermalZoneInformation"))
                using (var results = searcher.Get())
                    foreach (ManagementBaseObject row in results)
                        using (row)
                        {
                            double c = HealthRules.CelsiusFromTenthsKelvin(ToDouble(row["HighPrecisionTemperature"]));
                            if (c == 0) c = HealthRules.CelsiusFromKelvin(ToDouble(row["Temperature"]));
                            if (c > 0) readings.Add(c);
                        }
                if (readings.Count == 0)
                    using (var searcher = new ManagementObjectSearcher(@"root\WMI", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature"))
                    using (var results = searcher.Get())
                        foreach (ManagementBaseObject row in results)
                            using (row)
                            {
                                double c = HealthRules.CelsiusFromTenthsKelvin(ToDouble(row["CurrentTemperature"]));
                                if (c > 0) readings.Add(c);
                            }
                return readings.Count == 0 ? (double?)null : readings.Max();
            }
            catch (Exception e) when (Expected(e)) { return null; }
        }

        private static double ToDouble(object value)
        {
            try { return value == null ? 0 : Convert.ToDouble(value, CultureInfo.InvariantCulture); }
            catch (FormatException) { return 0; }
            catch (InvalidCastException) { return 0; }
        }

        private void ReadCounters(ThermalSample sample)
        {
            try
            {
                if (!_countersTried)
                {
                    _countersTried = true;
                    _freq = new PerformanceCounter("Processor Information", "% of Maximum Frequency", "_Total", true);
                    _load = new PerformanceCounter("Processor Information", "% Processor Utility", "_Total", true);
                    _freq.NextValue(); _load.NextValue();   // la primera lectura siempre es 0
                    return;
                }
                if (_freq != null) sample.CpuFreqPercent = Math.Min(100, _freq.NextValue());
                if (_load != null) sample.CpuLoad = Math.Min(100, _load.NextValue());
            }
            catch (Exception e) when (Expected(e)) { _freq = null; _load = null; }
        }

        private void ReadGpu(ThermalSample sample)
        {
            if (!_smiTried)
            {
                _smiTried = true;
                foreach (string candidate in new[]
                {
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "nvidia-smi.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "NVIDIA Corporation", "NVSMI", "nvidia-smi.exe")
                })
                    if (File.Exists(candidate)) { _smi = candidate; break; }
            }
            if (_smi != null && DateTime.UtcNow - _lastSmi >= TimeSpan.FromSeconds(9))
            {
                _lastSmi = DateTime.UtcNow;
                double t; bool throttle;
                string line = Run("--query-gpu=temperature.gpu,clocks_throttle_reasons.hw_thermal_slowdown,clocks_throttle_reasons.sw_thermal_slowdown --format=csv,noheader,nounits")
                              ?? Run("--query-gpu=temperature.gpu --format=csv,noheader,nounits");
                if (NvidiaSmi.TryParse(line == null ? null : line.Split('\n')[0], out t, out throttle)) { _gpuC = t; _gpuThrottle = throttle; }
                else { _gpuC = null; _gpuThrottle = false; }
            }
            sample.GpuC = _gpuC; sample.GpuThermalThrottle = _gpuThrottle;
        }

        private string Run(string arguments)
        {
            try
            {
                var info = new ProcessStartInfo(_smi, arguments) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
                using (var p = Process.Start(info))
                {
                    var outText = p.StandardOutput.ReadToEndAsync();
                    p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit(3000)) { try { p.Kill(); } catch (InvalidOperationException) { } return null; }
                    return p.ExitCode == 0 && outText.Wait(1000) ? outText.Result : null;
                }
            }
            catch (Exception e) when (Expected(e)) { return null; }
        }

        public void Dispose()
        {
            if (_freq != null) _freq.Dispose();
            if (_load != null) _load.Dispose();
        }
    }
}
