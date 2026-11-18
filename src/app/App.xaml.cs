using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
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

            AppDomain.CurrentDomain.UnhandledException += (sender, args) => Log("Error no controlado: " + args.ExceptionObject);
            // Un fallo de una tarea sin esperar no debe pasar desapercibido, pero tampoco cerrar la app
            TaskScheduler.UnobservedTaskException += (sender, args) => { Log("Tarea con error: " + args.Exception); args.SetObserved(); };

            string root = AppDomain.CurrentDomain.BaseDirectory;
            ShellViewModel model;
            Window window;  // «MainWindow» como tipo chocaría con la propiedad Application.MainWindow
            try
            {
                model = new ShellViewModel(root, Dispatcher, Preferences.Load(Preferences.DefaultPath));
                window = new MainWindow(model);
            }
            catch (Exception ex)
            {
                // Sin ventana, el controlador de arriba dejaría el proceso vivo e invisible: se avisa y se sale
                Log("No se pudo crear la ventana principal: " + ex);
                MessageBox.Show("iWinInstaller no pudo arrancar. El detalle está en " + Path.Combine(LogDirectory, "interfaz.log"), "iWinInstaller", MessageBoxButton.OK, MessageBoxImage.Error);
                Shutdown(1);
                return;
            }
            MainWindow = window;
            bool testMode = !String.IsNullOrEmpty(Environment.GetEnvironmentVariable("IWIN_PRUEBA_GUI"));
            string captureDir = Environment.GetEnvironmentVariable("IWIN_CAPTURA");
            window.Loaded += async (sender, args) =>
            {
                if (!String.IsNullOrEmpty(captureDir))
                {
                    await RunCaptureAsync(model, window, captureDir);
                    return;
                }
                if (!testMode)
                {
                    // async void: una excepción aquí llegaría al controlador global como aviso al usuario
                    try
                    {
                        model.Settings.CheckForUpdateOnStart();
                        await model.Home.RefreshAsync(new[] { "appUpdates", "windowsUpdate", "antivirus", "pendingBatch" }, CancellationToken.None);
                    }
                    catch (Exception ex) { Log("Error al cargar el Inicio: " + ex); }
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

        /// <summary>
        /// Modo captura (IWIN_CAPTURA=carpeta): recorre todas las páginas y guarda un PNG de cada una
        /// para comparar el aspecto antes y después de un cambio de diseño. Solo se usa en CI.
        /// </summary>
        private async Task RunCaptureAsync(ShellViewModel model, Window window, string dir)
        {
            try
            {
                Directory.CreateDirectory(dir);
                window.WindowState = WindowState.Normal;
                window.Width = 1280;
                window.Height = 820;
                await Task.Delay(2500);
                var items = model.Items.ToList();
                for (int i = 0; i < items.Count; i++)
                {
                    try
                    {
                        model.Navigate(items[i].Id);
                        await Task.Delay(3000);  // da tiempo a que lleguen los datos del motor
                        SaveCapture(window, Path.Combine(dir, i.ToString("00") + "-" + items[i].Id + ".png"));
                    }
                    catch (Exception ex) { Log("Captura de " + items[i].Id + " fallida: " + ex); }
                }
                try
                {
                    model.Navigate("install");
                    model.Install.Search = "Brave";
                    await Task.Delay(1500);
                    SaveCapture(window, Path.Combine(dir, "99-install-busqueda.png"));
                }
                catch (Exception ex) { Log("Captura de la búsqueda fallida: " + ex); }
            }
            catch (Exception ex) { Log("Modo captura fallido: " + ex); }
            Shutdown(0);
        }

        /// <summary>Renderiza la ventana (fondo incluido) a 192 DPI, el doble de resolución, y la guarda como PNG.</summary>
        private static void SaveCapture(Window window, string path)
        {
            window.UpdateLayout();
            var content = window.Content as FrameworkElement;
            if (content == null) throw new InvalidOperationException("La ventana no tiene contenido.");
            // El Grid raíz lleva un LayoutTransform de zoom: se toma su contenedor, que mide el área cliente
            var host = VisualTreeHelper.GetParent(content) as FrameworkElement ?? content;
            double width = Math.Max(1, host.ActualWidth), height = Math.Max(1, host.ActualHeight);
            var visual = new DrawingVisual();
            using (DrawingContext dc = visual.RenderOpen())
            {
                dc.DrawRectangle(window.Background, null, new Rect(0, 0, width, height));
                dc.DrawRectangle(new VisualBrush(host) { Stretch = Stretch.None, AlignmentX = AlignmentX.Left, AlignmentY = AlignmentY.Top }, null, new Rect(0, 0, width, height));
            }
            var bitmap = new RenderTargetBitmap((int)Math.Ceiling(width * 2), (int)Math.Ceiling(height * 2), 192, 192, PixelFormats.Pbgra32);
            bitmap.Render(visual);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var stream = File.Create(path)) encoder.Save(stream);
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
