using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace IWinInstaller.App.Core
{
    /// <summary>Detecta un valor alto sostenido: avisa una vez y no repite hasta que baja con margen.</summary>
    public sealed class SustainedThreshold
    {
        private readonly int _limit, _release, _samples;
        private int _count;
        private bool _raised;

        public SustainedThreshold(int limit, int release, int samples)
        {
            _limit = limit; _release = release; _samples = Math.Max(1, samples);
        }

        /// <summary>Devuelve true solo en la muestra en la que el valor lleva «samples» lecturas seguidas por encima del límite.</summary>
        public bool Push(int value)
        {
            if (value < _release) { _count = 0; _raised = false; return false; }
            if (value < _limit) { _count = 0; return false; }
            if (_raised) return false;
            _count++;
            if (_count < _samples) return false;
            _raised = true;
            return true;
        }
    }

    /// <summary>Aviso del monitor (uso alto sostenido).</summary>
    public sealed class MonitorAlertEventArgs : EventArgs
    {
        public MonitorAlertEventArgs(string title, string text) { Title = title; Text = text; }
        public string Title { get; private set; }
        public string Text { get; private set; }
    }

    /// <summary>
    /// Monitor ligero del equipo: procesador, memoria y disco del sistema cada pocos segundos, con llamadas
    /// directas a Windows (sin contadores de rendimiento ni PowerShell). Lo usan el Inicio y la bandeja.
    /// </summary>
    public sealed class LiveMonitor : ObservableObject
    {
        public const int IntervalSeconds = 3;
        // Cinco minutos seguidos por encima del 90 %; se rearma al bajar del 75 %
        private const int SustainedSamples = 300 / IntervalSeconds;

#pragma warning disable 0649
        private struct FileTime { public uint Low; public uint High; }

        [StructLayout(LayoutKind.Sequential)]
        private struct MemoryStatus
        {
            public uint Length;
            public uint MemoryLoad;
            public ulong TotalPhys;
            public ulong AvailPhys;
            public ulong TotalPageFile;
            public ulong AvailPageFile;
            public ulong TotalVirtual;
            public ulong AvailVirtual;
            public ulong AvailExtendedVirtual;
        }
#pragma warning restore 0649

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);

        private readonly DispatcherTimer _timer;
        private readonly SustainedThreshold _cpuAlert = new SustainedThreshold(90, 75, SustainedSamples);
        private readonly SustainedThreshold _memoryAlert = new SustainedThreshold(90, 75, SustainedSamples);
        private ulong _lastIdle, _lastTotal;
        private bool _hasSample;
        private int _cpu, _memory, _ticks;
        private string _memoryDetail = "", _diskText = "";

        public LiveMonitor(Dispatcher dispatcher)
        {
            _timer = new DispatcherTimer(TimeSpan.FromSeconds(IntervalSeconds), DispatcherPriority.Background, (sender, e) => Sample(), dispatcher);
            _timer.Stop();
        }

        /// <summary>Uso alto sostenido de procesador o memoria.</summary>
        public event EventHandler<MonitorAlertEventArgs> Alert;

        public int Cpu { get { return _cpu; } private set { if (Set(ref _cpu, value)) { OnPropertyChanged("CpuText"); OnPropertyChanged("Summary"); } } }
        public int Memory { get { return _memory; } private set { if (Set(ref _memory, value)) { OnPropertyChanged("MemoryText"); OnPropertyChanged("Summary"); } } }
        public string CpuText { get { return Cpu + " %"; } }
        public string MemoryText { get { return Memory + " %"; } }
        /// <summary>«6,9 de 16 GB».</summary>
        public string MemoryDetail { get { return _memoryDetail; } private set { Set(ref _memoryDetail, value); } }
        /// <summary>«C: 120 GB libres».</summary>
        public string DiskText { get { return _diskText; } private set { Set(ref _diskText, value); } }
        /// <summary>Línea corta para la bandeja.</summary>
        public string Summary { get { return "CPU " + Cpu + " % · RAM " + Memory + " %"; } }

        public void Start() { if (!_timer.IsEnabled) { Sample(); _timer.Start(); } }
        public void Stop() { _timer.Stop(); }

        /// <summary>Porcentaje de uso entre dos lecturas de tiempos del sistema (el tiempo de núcleo incluye el inactivo).</summary>
        public static int CpuPercent(ulong previousIdle, ulong previousTotal, ulong idle, ulong total)
        {
            if (total <= previousTotal || idle < previousIdle) return 0;
            double span = total - previousTotal;
            double busy = span - (idle - previousIdle);
            return (int)Math.Round(Math.Max(0, Math.Min(100, 100.0 * busy / span)));
        }

        public static string FormatGigabytes(double bytes)
        {
            double gigabytes = bytes / (1024.0 * 1024 * 1024);
            return gigabytes.ToString(gigabytes >= 100 ? "0" : "0.#", CultureInfo.GetCultureInfo("es-ES"));
        }

        private static ulong Ticks(FileTime time) { return ((ulong)time.High << 32) | time.Low; }

        private void Sample()
        {
            try
            {
                FileTime idle, kernel, user;
                if (GetSystemTimes(out idle, out kernel, out user))
                {
                    ulong idleTicks = Ticks(idle), total = Ticks(kernel) + Ticks(user);
                    if (_hasSample) Cpu = CpuPercent(_lastIdle, _lastTotal, idleTicks, total);
                    _lastIdle = idleTicks; _lastTotal = total; _hasSample = true;
                }
                var status = new MemoryStatus { Length = (uint)Marshal.SizeOf(typeof(MemoryStatus)) };
                if (GlobalMemoryStatusEx(ref status) && status.TotalPhys > 0)
                {
                    Memory = (int)status.MemoryLoad;
                    MemoryDetail = FormatGigabytes(status.TotalPhys - status.AvailPhys) + " de " + FormatGigabytes(status.TotalPhys) + " GB";
                }
                // El disco cambia despacio: una lectura por minuto
                if (_ticks++ % (60 / IntervalSeconds) == 0) ReadDisk();
                if (_cpuAlert.Push(Cpu)) Raise("Procesador al límite", "Lleva cinco minutos por encima del 90 %. Abre el Administrador de tareas para ver qué lo ocupa.");
                if (_memoryAlert.Push(Memory)) Raise("Memoria casi llena", "Lleva cinco minutos por encima del 90 % (" + MemoryDetail + "). Cierra lo que no uses.");
            }
            catch (Exception e) { App.Log("Monitor: " + e.Message); _timer.Stop(); }
        }

        private void ReadDisk()
        {
            try
            {
                string root = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
                var drive = new DriveInfo(root);
                DiskText = root.TrimEnd('\\') + " " + FormatGigabytes(drive.AvailableFreeSpace) + " GB libres";
            }
            catch (IOException) { DiskText = ""; }
            catch (UnauthorizedAccessException) { DiskText = ""; }
            catch (ArgumentException) { DiskText = ""; }
        }

        private void Raise(string title, string text)
        {
            var handler = Alert;
            if (handler != null) handler(this, new MonitorAlertEventArgs(title, text));
        }
    }
}
