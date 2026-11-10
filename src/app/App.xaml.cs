using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using IWinInstaller.App.Core;
using IWinInstaller.App.Shell;

namespace IWinInstaller.App
{
    public partial class App : Application
    {
        private static string LogDirectory
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "iWinInstaller"); }
        }

        private const string InstanceName = "Local\\iWinInstaller-app";
        private const string ShowSignalName = "Local\\iWinInstaller-app-mostrar";
        // Tamaño a partir del cual interfaz.log se archiva como interfaz.anterior.log
        internal const long MaxLogBytes = 1024 * 1024;
        private static readonly string[] StartAreas = { "appUpdates", "windowsUpdate", "antivirus", "pendingBatch" };
        private Mutex _instance;
        private EventWaitHandle _showSignal;
        private TrayService _tray;

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            bool testMode = !String.IsNullOrEmpty(Environment.GetEnvironmentVariable("IWIN_PRUEBA_GUI"));
            // Una sola instancia: abrir la app otra vez trae al frente la ventana que ya existe
            if (!testMode && !AcquireInstance()) { Shutdown(0); return; }

            RotateLog(Path.Combine(LogDirectory, "interfaz.log"), MaxLogBytes);
            DispatcherUnhandledException += (sender, args) =>
            {
                Log("Error de la interfaz: " + args.Exception);
                MessageBox.Show("Se produjo un error inesperado. El detalle está en " + Path.Combine(LogDirectory, "interfaz.log"), "iWinInstaller", MessageBoxButton.OK, MessageBoxImage.Error);
                args.Handled = true;
            };
            // Fallos fuera del hilo de la interfaz: quedan en el registro en vez de cerrar la app sin rastro
            AppDomain.CurrentDomain.UnhandledException += (sender, args) => Log("Error no controlado" + (args.IsTerminating ? " (la app se cierra)" : "") + ": " + args.ExceptionObject);
            TaskScheduler.UnobservedTaskException += (sender, args) => { Log("Tarea con error sin observar: " + args.Exception); args.SetObserved(); };

            string root = AppDomain.CurrentDomain.BaseDirectory;
            var model = new ShellViewModel(root, Dispatcher, Preferences.Load(Preferences.DefaultPath));
            var window = new MainWindow(model);
            MainWindow = window;
            if (testMode)
            {
                window.Loaded += async (sender, args) => await RunSmokeTest(model);
                window.Show();
                return;
            }

            model.Monitor.Start();
            model.BackgroundChanged += (sender, args) => ApplyBackground(model, window);
            ApplyBackground(model, window);
            ListenForShowSignal(window);
            // «--tray» (arranque con Windows): empieza oculta en la bandeja si el segundo plano está activado
            bool hidden = model.BackgroundEnabled && e.Args.Any(a => String.Equals(a, Autostart.TrayArgument, StringComparison.OrdinalIgnoreCase));
            if (!hidden) window.Show();
            StartChecks(model);
        }

        private static async void StartChecks(ShellViewModel model)
        {
            try
            {
                model.Settings.CheckForUpdateOnStart();
                await model.Home.RefreshAsync(StartAreas, CancellationToken.None);
            }
            catch (Exception ex) { Log("Comprobación inicial: " + ex.Message); }
        }

        /// <summary>Crea o quita el icono de la bandeja según «Seguir en segundo plano».</summary>
        private void ApplyBackground(ShellViewModel model, MainWindow window)
        {
            if (model.BackgroundEnabled && _tray == null)
            {
                try { _tray = new TrayService(model, Dispatcher, window.ShowFromTray, () => { window.ExitRequested = true; Shutdown(0); }); }
                catch (Exception ex) { Log("No se pudo crear el icono de la bandeja: " + ex.Message); }
            }
            else if (!model.BackgroundEnabled && _tray != null)
            {
                _tray.Dispose(); _tray = null;
                // Sin bandeja no puede quedar una ventana oculta e inalcanzable
                if (!window.IsVisible) window.ShowFromTray();
            }
        }

        private bool AcquireInstance()
        {
            try
            {
                bool created;
                _instance = new Mutex(true, InstanceName, out created);
                if (created) { _showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowSignalName); return true; }
                _instance.Dispose(); _instance = null;
                EventWaitHandle existing;
                if (EventWaitHandle.TryOpenExisting(ShowSignalName, out existing)) { existing.Set(); existing.Dispose(); }
                return false;
            }
            // Si Windows no deja crear los objetos con nombre, se abre igualmente
            catch (UnauthorizedAccessException) { return true; }
            catch (WaitHandleCannotBeOpenedException) { return true; }
            catch (IOException) { return true; }
        }

        private void ListenForShowSignal(MainWindow window)
        {
            var signal = _showSignal;
            if (signal == null) return;
            var listener = new Thread(() =>
            {
                try { while (signal.WaitOne()) Dispatcher.BeginInvoke(new Action(window.ShowFromTray)); }
                catch (ObjectDisposedException) { }
                catch (AbandonedMutexException) { }
            }) { IsBackground = true, Name = "iWinInstaller-mostrar" };
            listener.Start();
        }

        protected override void OnExit(ExitEventArgs e)
        {
            if (_tray != null) { _tray.Dispose(); _tray = null; }
            if (_instance != null) { try { _instance.ReleaseMutex(); } catch (ApplicationException) { } _instance.Dispose(); _instance = null; }
            base.OnExit(e);
        }

        /// <summary>Archiva el registro de la interfaz cuando supera el tamaño máximo (se conserva una copia anterior).</summary>
        internal static bool RotateLog(string path, long maxBytes)
        {
            try
            {
                var file = new FileInfo(path);
                if (!file.Exists || file.Length <= maxBytes) return false;
                string previous = Path.Combine(file.DirectoryName, Path.GetFileNameWithoutExtension(path) + ".anterior" + file.Extension);
                if (File.Exists(previous)) File.Delete(previous);
                File.Move(path, previous);
                return true;
            }
            catch (IOException) { return false; }
            catch (UnauthorizedAccessException) { return false; }
        }

        /// <summary>
        /// Prueba de CI (IWIN_PRUEBA_GUI): la ventana se construye y se dibuja, el Inicio rellena sus tarjetas
        /// con el motor real (sin la búsqueda lenta de WinGet) y la ventana clásica completa su propia prueba.
        /// </summary>
        private async Task RunSmokeTest(ShellViewModel model)
        {
            int code = 1;
            try
            {
                using (var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(3)))
                    await model.Home.RefreshAsync(new[] { "antivirus", "pendingBatch" }, timeout.Token);
                var pending = model.Home.Cards.Where(c => c.IsLoading).Select(c => c.Area).ToList();
                // Las tarjetas se aplican en el hilo de la interfaz: se espera a que termine de aplicarlas
                for (int i = 0; i < 50 && pending.Count > 0; i++) { await Task.Delay(100); pending = model.Home.Cards.Where(c => c.IsLoading).Select(c => c.Area).ToList(); }
                if (pending.Count > 0) throw new InvalidOperationException("Tarjetas sin resultado: " + String.Join(", ", pending));
                foreach (var card in model.Home.Cards) Log("Prueba · " + card.Area + ": " + card.State + " · " + card.Summary + (card.HasReason ? " · " + card.Reason : ""));
                code = 0;
            }
            catch (Exception ex) { Log("Prueba fallida: " + ex); code = 1; }
            Shutdown(code);
        }

        internal static void Log(string text)
        {
            try
            {
                Directory.CreateDirectory(LogDirectory);
                File.AppendAllText(Path.Combine(LogDirectory, "interfaz.log"), DateTime.Now.ToString("O") + " " + text + Environment.NewLine);
            }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
