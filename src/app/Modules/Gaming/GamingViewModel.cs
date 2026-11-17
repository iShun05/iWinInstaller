using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using IWinInstaller.App.Core;

namespace IWinInstaller.App.Modules.Gaming
{
    /// <summary>Un destino del ping en vivo: un objeto Ping propio y sin solapar envíos.</summary>
    public sealed class PingTarget : ObservableObject
    {
        public const double GraphWidth = 240, GraphHeight = 44;
        private readonly Ping _ping = new Ping();
        private readonly bool _router;
        private string _host = "", _detail = "", _color = "#8E8E99", _summary = "—";
        private IPAddress _address;
        private PointCollection _points = new PointCollection();

        public PingTarget(string title, bool router) { Title = title; _router = router; Stats = new LatencyStats(60); }

        public string Title { get; private set; }
        public LatencyStats Stats { get; private set; }
        public bool Busy { get; set; }
        public string Host { get { return _host; } private set { Set(ref _host, value ?? ""); } }
        public string Summary { get { return _summary; } private set { Set(ref _summary, value); } }
        public string Detail { get { return _detail; } private set { Set(ref _detail, value); } }
        public string Color { get { return _color; } private set { Set(ref _color, value); } }
        public PointCollection Points { get { return _points; } private set { Set(ref _points, value); } }
        public IPAddress Address { get { return _address; } }
        public Ping Pinger { get { return _ping; } }

        public void SetTarget(string host, IPAddress address)
        {
            if (!Equals(address, _address)) Stats.Clear();
            _address = address;
            Host = host;
            Refresh(false);
        }

        /// <summary>Recalcula los textos; devuelve true si la última muestra es un pico.</summary>
        public bool Add(long? ms, bool internetAnswers)
        {
            double? before = Stats.Average;
            Stats.Add(ms);
            Refresh(internetAnswers);
            return before.HasValue && Stats.Count >= 10 && (!ms.HasValue || ms.Value > before.Value + 50);
        }

        public void Refresh(bool internetAnswers)
        {
            if (_address == null) { Summary = "—"; Detail = _router ? "Sin puerta de enlace: ¿estás conectado?" : "Escribe la IP o el nombre del servidor."; Color = "#8E8E99"; Points = new PointCollection(); return; }
            if (!_router && Title != "Internet" && Stats.NoAnswer() && internetAnswers)
            {
                Summary = "Sin respuesta a ping"; Color = "#8E8E99";
                Detail = "Muchos servidores de juego no contestan a ping: usa el ping del propio juego.";
                return;
            }
            var last = Stats.Last;
            Summary = last.HasValue ? last.Value + " ms" : Stats.Count == 0 ? "midiendo…" : "sin respuesta";
            Detail = String.Format(CultureInfo.CurrentCulture, "media {0} · jitter {1} · pérdida {2:0.#} % · máx. {3}",
                Ms(Stats.Average), Ms(Stats.Jitter), Stats.LossPercent, Stats.Max.HasValue ? Stats.Max.Value + " ms" : "—");
            string level = Stats.Count == 0 ? "none" : LatencyStats.Level(Stats.Average, Stats.LossPercent, _router);
            Color = level == "ok" ? "#6FD38A" : level == "warn" ? "#F5BE5B" : level == "bad" ? "#FF7A7A" : "#8E8E99";
            Points = BuildPoints(Stats.Samples);
        }

        private static string Ms(double? value) { return value.HasValue ? Math.Round(value.Value).ToString(CultureInfo.CurrentCulture) + " ms" : "—"; }

        private static PointCollection BuildPoints(IList<long?> samples)
        {
            var points = new PointCollection();
            if (samples.Count == 0) return points;
            double top = Math.Max(50, samples.Where(s => s.HasValue).Select(s => (double)s.Value).DefaultIfEmpty(0).Max() * 1.2);
            double step = GraphWidth / 59.0, x = GraphWidth - step * (samples.Count - 1);
            foreach (var s in samples)
            {
                // Sin respuesta: arriba del todo, para que se vea como un pico
                double y = s.HasValue ? GraphHeight - Math.Min(s.Value, top) / top * GraphHeight : 0;
                points.Add(new Point(x, y));
                x += step;
            }
            points.Freeze();
            return points;
        }
    }

    /// <summary>Latencia: ping en vivo, bufferbloat, conexión y DNS. Solo mide con la página abierta.</summary>
    public sealed class GamingViewModel : ObservableObject
    {
        private const string InternetHost = "1.1.1.1";
        private const string DownloadUrl = "https://speed.cloudflare.com/__down?bytes=25000000";
        private const string UploadUrl = "https://speed.cloudflare.com/__up";
        private const long ByteCap = 400L * 1024 * 1024;
        private readonly Preferences _preferences;
        private readonly Dispatcher _dispatcher;
        private readonly Action _openTweaks;
        private readonly DispatcherTimer _timer;
        private CancellationTokenSource _run;
        private DateTime _resolvedAt = DateTime.MinValue;
        private string _gameServer, _connection = "", _wifi = "", _advice = "", _dns = "", _bloat = "", _bloatGrade = "", _message = "";
        private bool _running, _bloatBusy;

        public GamingViewModel(Preferences preferences, Dispatcher dispatcher, Action openTweaks)
        {
            _preferences = preferences; _dispatcher = dispatcher; _openTweaks = openTweaks;
            _gameServer = preferences.GameServer ?? "";
            Router = new PingTarget("Router", true);
            Internet = new PingTarget("Internet", false);
            Game = new PingTarget("Servidor del juego", false);
            Targets = new ObservableCollection<PingTarget> { Router, Internet, Game };
            Spikes = new ObservableCollection<string>();
            _timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher) { Interval = TimeSpan.FromSeconds(1) };
            _timer.Tick += (s, e) => Tick();
            BufferbloatCommand = new RelayCommand(_ => { var ignored = RunBufferbloatAsync(); }, _ => !_bloatBusy);
            ClearCommand = new RelayCommand(_ => { foreach (var t in Targets) { t.Stats.Clear(); t.Refresh(false); } Spikes.Clear(); });
            OpenTweaksCommand = new RelayCommand(_ => { if (_openTweaks != null) _openTweaks(); });
            OpenGpuCommand = new RelayCommand(_ => Open("ms-settings:display-advancedgraphics"));
            ApplyServerCommand = new RelayCommand(_ => ApplyServer());
        }

        public PingTarget Router { get; private set; }
        public PingTarget Internet { get; private set; }
        public PingTarget Game { get; private set; }
        public ObservableCollection<PingTarget> Targets { get; private set; }
        public ObservableCollection<string> Spikes { get; private set; }
        public RelayCommand BufferbloatCommand { get; private set; }
        public RelayCommand ClearCommand { get; private set; }
        public RelayCommand OpenTweaksCommand { get; private set; }
        public RelayCommand OpenGpuCommand { get; private set; }
        public RelayCommand ApplyServerCommand { get; private set; }
        public string GameServer { get { return _gameServer; } set { Set(ref _gameServer, value ?? ""); } }
        public string Connection { get { return _connection; } private set { Set(ref _connection, value); } }
        public string Wifi { get { return _wifi; } private set { Set(ref _wifi, value); } }
        public string Advice { get { return _advice; } private set { Set(ref _advice, value); } }
        public string Dns { get { return _dns; } private set { Set(ref _dns, value); } }
        public string Bufferbloat { get { return _bloat; } private set { Set(ref _bloat, value); } }
        public string BufferbloatGrade { get { return _bloatGrade; } private set { Set(ref _bloatGrade, value); } }
        public string Message { get { return _message; } private set { Set(ref _message, value ?? ""); } }
        public bool IsRunning { get { return _running; } }

        /// <summary>Empieza a medir (al entrar en la página).</summary>
        public void Start()
        {
            if (_running) return;
            _running = true;
            _run = new CancellationTokenSource();
            NetworkChange.NetworkAddressChanged += OnAddressChanged;
            RefreshNetwork();
            var ignored = RefreshWifiAsync();
            LoadDns();
            ApplyServer();
            _timer.Start();
        }

        /// <summary>Deja de medir (al salir de la página o cerrar): sin temporizador ni respuestas pendientes.</summary>
        public void Stop()
        {
            if (!_running) return;
            _running = false;
            _timer.Stop();
            NetworkChange.NetworkAddressChanged -= OnAddressChanged;
            if (_run != null) { _run.Cancel(); _run.Dispose(); _run = null; }
            foreach (var t in Targets) { try { t.Pinger.SendAsyncCancel(); } catch (InvalidOperationException) { } t.Busy = false; }
        }

        private void OnAddressChanged(object sender, EventArgs e)
        {
            _dispatcher.BeginInvoke(new Action(() => { if (_running) { RefreshNetwork(); var ignored = RefreshWifiAsync(); } }));
        }

        private void Tick()
        {
            if (!_running) return;
            if (Game.Host.Length > 0 && DateTime.UtcNow - _resolvedAt > TimeSpan.FromMinutes(5)) ApplyServer();
            var token = _run.Token;
            bool internetAnswers = Internet.Stats.Last.HasValue;
            foreach (var target in Targets)
            {
                if (target.Address == null || target.Busy) continue;
                var ignored = PingOnceAsync(target, token, internetAnswers);
            }
        }

        private async Task PingOnceAsync(PingTarget target, CancellationToken token, bool internetAnswers)
        {
            target.Busy = true;
            long? ms = null;
            try
            {
                var reply = await target.Pinger.SendPingAsync(target.Address, 1000);
                if (reply.Status == IPStatus.Success) ms = reply.RoundtripTime;
            }
            catch (PingException) { }
            catch (InvalidOperationException) { }
            catch (OperationCanceledException) { }
            finally { target.Busy = false; }
            if (token.IsCancellationRequested || !_running) return;
            if (target.Add(ms, internetAnswers) && !(target == Game && target.Stats.NoAnswer()))
            {
                Spikes.Insert(0, DateTime.Now.ToString("HH:mm:ss", CultureInfo.CurrentCulture) + " · " + target.Title + " · " + (ms.HasValue ? ms.Value + " ms" : "sin respuesta"));
                while (Spikes.Count > 20) Spikes.RemoveAt(Spikes.Count - 1);
            }
        }

        private async void ApplyServer()
        {
            string host = (GameServer ?? "").Trim();
            _resolvedAt = DateTime.UtcNow;
            if (host.Length == 0) { Game.SetTarget("", null); Save(""); return; }
            if (!LatencyStats.IsValidHost(host)) { Message = "Servidor no válido: escribe una IP (p. ej. 155.133.248.34) o un nombre."; return; }
            Message = "";
            Save(host);
            IPAddress address;
            if (!IPAddress.TryParse(host, out address))
            {
                try { address = (await System.Net.Dns.GetHostAddressesAsync(host)).FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork); }
                catch (SocketException) { address = null; }
                if (address == null) { Message = "No se encontró «" + host + "»."; }
            }
            Game.SetTarget(host, address);
        }

        private void Save(string host)
        {
            if (_preferences.GameServer == host) return;
            _preferences.GameServer = host;
            _preferences.Save();
        }

        /// <summary>Puerta de enlace y tipo de conexión del adaptador principal (cable antes que Wi-Fi, como hace Windows).</summary>
        private void RefreshNetwork()
        {
            NetworkInterface best = null; IPAddress gateway = null;
            try
            {
                foreach (var nic in NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback && n.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
                    .OrderBy(n => n.NetworkInterfaceType == NetworkInterfaceType.Ethernet ? 0 : 1))
                {
                    var gw = nic.GetIPProperties().GatewayAddresses.Select(g => g.Address).FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork && !a.Equals(IPAddress.Any));
                    if (gw == null) continue;
                    best = nic; gateway = gw; break;
                }
            }
            catch (NetworkInformationException) { }
            Router.SetTarget(gateway == null ? "" : gateway.ToString(), gateway);
            Internet.SetTarget(InternetHost, best == null ? null : IPAddress.Parse(InternetHost));
            if (best == null) { Connection = "Sin conexión de red."; Advice = ""; return; }
            bool wifi = best.NetworkInterfaceType == NetworkInterfaceType.Wireless80211;
            long mbps = best.Speed > 0 ? best.Speed / 1000000 : 0;
            Connection = (wifi ? "Wi-Fi" : "Cable (Ethernet)") + (mbps > 0 ? " · enlace " + mbps + " Mbps" : "");
            Advice = wifi ? "Para el ping más estable usa cable. Si no puedes, Wi-Fi de 5 o 6 GHz cerca del router." : "Conexión por cable: la mejor opción para jugar.";
            if (!wifi) Wifi = "";
        }

        private async Task RefreshWifiAsync()
        {
            string text = await Task.Run(() => RunNetsh());
            if (!_running) return;
            var info = WifiInfo.Parse(text);
            if (!info.Signal.HasValue) { Wifi = ""; return; }
            var parts = new List<string> { "Señal " + info.Signal.Value + " %" };
            if (info.Band != null) parts.Add(info.Band);
            if (info.Channel.HasValue) parts.Add("canal " + info.Channel.Value);
            if (!String.IsNullOrEmpty(info.RadioType)) parts.Add(info.RadioType);
            Wifi = String.Join(" · ", parts);
            if (info.Signal.Value < 60) Advice = "Señal Wi-Fi baja: acércate al router o usa cable; provoca picos y pérdida.";
            else if (info.Band == "2,4 GHz") Advice = "Estás en 2,4 GHz, la banda más saturada: cambia a 5 o 6 GHz si tu router la ofrece.";
        }

        private static string RunNetsh()
        {
            try
            {
                var start = new ProcessStartInfo("netsh.exe", "wlan show interfaces")
                {
                    UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true,
                    StandardOutputEncoding = Encoding.GetEncoding(CultureInfo.CurrentCulture.TextInfo.OEMCodePage)
                };
                using (var process = Process.Start(start))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    process.WaitForExit(5000);
                    return output;
                }
            }
            catch (Exception) { return ""; }
        }

        private void LoadDns()
        {
            string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "iWinInstaller", "Latencia", "dns.json");
            try
            {
                if (!File.Exists(path)) { Dns = "«DNS más rápido» no está aplicado. Actívalo en Ajustes de juego: elige el DNS más rápido en cada red."; return; }
                var data = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as Dictionary<string, object>;
                if (data == null) { Dns = ""; return; }
                object chosen, at, results;
                data.TryGetValue("chosen", out chosen); data.TryGetValue("at", out at); data.TryGetValue("results", out results);
                var times = (results as object[] ?? new object[0]).OfType<Dictionary<string, object>>().Select(r =>
                {
                    object provider, ms, failed;
                    r.TryGetValue("provider", out provider); r.TryGetValue("ms", out ms); r.TryGetValue("failed", out failed);
                    string name = Convert.ToString(provider) == "Red" ? "tu red" : Convert.ToString(provider);
                    return name + " " + (failed is bool && (bool)failed || ms == null ? "sin respuesta" : Convert.ToString(ms, CultureInfo.CurrentCulture) + " ms");
                });
                DateTime when;
                string whenText = DateTime.TryParse(Convert.ToString(at), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out when) ? when.ToLocalTime().ToString("dd/MM HH:mm", CultureInfo.CurrentCulture) : "";
                string chosenText = Convert.ToString(chosen) == "Red" ? "el de tu red" : Convert.ToString(chosen);
                Dns = "En uso: " + chosenText + " (" + whenText + ")." + Environment.NewLine + String.Join(" · ", times);
            }
            catch (Exception) { Dns = "No se pudo leer la última medición del DNS."; }
        }

        /// <summary>Latencia añadida al cargar la línea: ping en reposo y con descarga y subida a la vez.</summary>
        public async Task RunBufferbloatAsync()
        {
            if (_bloatBusy) return;
            _bloatBusy = true;
            BufferbloatGrade = ""; Bufferbloat = "Midiendo en reposo…";
            try
            {
                using (var cancel = new CancellationTokenSource(TimeSpan.FromSeconds(40)))
                using (var ping = new Ping())
                {
                    var idle = await PingSeries(ping, TimeSpan.FromSeconds(2), cancel.Token);
                    if (idle.Count < 5) { Bufferbloat = "No se pudo completar la prueba: 1.1.1.1 no responde."; return; }
                    double baseline = LatencyStats.Percentile(idle, 50);
                    long[] total = { 0 };
                    Bufferbloat = "Midiendo con descarga…";
                    var down = await UnderLoad(ping, () => Download(total, cancel.Token), 4, cancel.Token);
                    Bufferbloat = "Midiendo con subida…";
                    var up = await UnderLoad(ping, () => Upload(total, cancel.Token), 2, cancel.Token);
                    if (down.Count < 10 || up.Count < 10) { Bufferbloat = "No se pudo completar la prueba (sin conexión estable)."; return; }
                    double addDown = Math.Max(0, LatencyStats.Percentile(down, 90) - baseline), addUp = Math.Max(0, LatencyStats.Percentile(up, 90) - baseline);
                    string worst = LatencyStats.BufferbloatGrade(Math.Max(addDown, addUp));
                    BufferbloatGrade = worst;
                    Bufferbloat = String.Format(CultureInfo.CurrentCulture, "Reposo {0:0} ms · con descarga +{1:0} ms ({2}) · con subida +{3:0} ms ({4}) · {5:0} MB usados.",
                        baseline, addDown, LatencyStats.BufferbloatGrade(addDown), addUp, LatencyStats.BufferbloatGrade(addUp), total[0] / 1048576.0)
                        + (worst == "A+" || worst == "A" || worst == "B" ? "" : Environment.NewLine + "Tu router deja crecer la cola al descargar o subir: activa SQM/QoS (fq_codel o CAKE) en el router o limita la subida de otros equipos.");
                }
            }
            catch (Exception e) { Bufferbloat = "No se pudo completar la prueba: " + e.Message; }
            finally { _bloatBusy = false; CommandManagerRefresh(); }
        }

        private static void CommandManagerRefresh() { System.Windows.Input.CommandManager.InvalidateRequerySuggested(); }

        private static async Task<List<double>> PingSeries(Ping ping, TimeSpan duration, CancellationToken token)
        {
            var values = new List<double>();
            var watch = Stopwatch.StartNew();
            while (watch.Elapsed < duration && !token.IsCancellationRequested)
            {
                try
                {
                    var reply = await ping.SendPingAsync(InternetHost, 1000);
                    if (reply.Status == IPStatus.Success) values.Add(reply.RoundtripTime);
                }
                catch (PingException) { }
                await Task.Delay(100);
            }
            return values;
        }

        private static async Task<List<double>> UnderLoad(Ping ping, Action flow, int flows, CancellationToken token)
        {
            using (var stop = CancellationTokenSource.CreateLinkedTokenSource(token))
            {
                stop.CancelAfter(TimeSpan.FromSeconds(8));
                var workers = Enumerable.Range(0, flows).Select(_ => Task.Run(() => { while (!stop.IsCancellationRequested) { try { flow(); } catch (IOException) { break; } catch (Exception) { if (stop.IsCancellationRequested) break; Thread.Sleep(200); } } })).ToList();
                await Task.Delay(1000);
                var values = await PingSeries(ping, TimeSpan.FromSeconds(7), stop.Token);
                stop.Cancel();
                await Task.WhenAll(workers);
                return values;
            }
        }

        private static HttpWebRequest NewRequest(string url, CancellationToken token)
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var request = (HttpWebRequest)WebRequest.Create(url);
            request.ServicePoint.ConnectionLimit = Math.Max(request.ServicePoint.ConnectionLimit, 8);
            request.Timeout = 10000; request.ReadWriteTimeout = 10000;
            request.UserAgent = "iWinInstaller";
            token.Register(request.Abort);
            return request;
        }

        private static void Download(long[] total, CancellationToken token)
        {
            if (Interlocked.Read(ref total[0]) > ByteCap || token.IsCancellationRequested) throw new IOException("límite");
            var request = NewRequest(DownloadUrl, token);
            using (var response = request.GetResponse())
            using (var stream = response.GetResponseStream())
            {
                var buffer = new byte[65536];
                int read;
                while (!token.IsCancellationRequested && (read = stream.Read(buffer, 0, buffer.Length)) > 0)
                    if (Interlocked.Add(ref total[0], read) > ByteCap) throw new IOException("límite");
            }
        }

        private static void Upload(long[] total, CancellationToken token)
        {
            const int size = 10 * 1024 * 1024;
            if (Interlocked.Read(ref total[0]) > ByteCap || token.IsCancellationRequested) throw new IOException("límite");
            var request = NewRequest(UploadUrl, token);
            request.Method = "POST"; request.ContentType = "application/octet-stream"; request.ContentLength = size;
            request.AllowWriteStreamBuffering = false;
            var buffer = new byte[65536];
            using (var stream = request.GetRequestStream())
                for (int sent = 0; sent < size && !token.IsCancellationRequested; sent += buffer.Length)
                {
                    stream.Write(buffer, 0, buffer.Length);
                    if (Interlocked.Add(ref total[0], buffer.Length) > ByteCap) throw new IOException("límite");
                }
            if (token.IsCancellationRequested) return;
            using (request.GetResponse()) { }
        }

        private void Open(string uri)
        {
            try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); }
            catch (System.ComponentModel.Win32Exception) { Message = "No se pudo abrir la configuración de Windows."; }
        }
    }
}
