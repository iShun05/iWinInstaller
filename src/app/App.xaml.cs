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

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            DispatcherUnhandledException += (sender, args) =>
            {
                Log("Error de la interfaz: " + args.Exception);
                MessageBox.Show("Se produjo un error inesperado. El detalle está en " + Path.Combine(LogDirectory, "interfaz.log"), "iWinInstaller", MessageBoxButton.OK, MessageBoxImage.Error);
                args.Handled = true;
            };

            string root = AppDomain.CurrentDomain.BaseDirectory;
            var model = new ShellViewModel(root, Dispatcher, Preferences.Load(Preferences.DefaultPath));
            var window = new MainWindow(model);
            MainWindow = window;
            bool testMode = !String.IsNullOrEmpty(Environment.GetEnvironmentVariable("IWIN_PRUEBA_GUI"));
            window.Loaded += async (sender, args) =>
            {
                if (!testMode)
                {
                    model.Settings.CheckForUpdateOnStart();
                    await model.Home.RefreshAsync(new[] { "appUpdates", "windowsUpdate", "antivirus", "pendingBatch" }, CancellationToken.None);
                    return;
                }
                await RunSmokeTest(model);
            };
            window.Show();
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
