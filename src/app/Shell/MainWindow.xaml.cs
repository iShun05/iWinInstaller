using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Animation;

namespace IWinInstaller.App.Shell
{
    public partial class MainWindow : Window
    {
        [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        /// <summary>Barra de título oscura (Windows 10 20H1+) y del color de la barra lateral (Windows 11).</summary>
        private void ApplyDarkTitleBar()
        {
            IntPtr handle = new WindowInteropHelper(this).Handle;
            int dark = 1;
            if (DwmSetWindowAttribute(handle, 20, ref dark, sizeof(int)) != 0) DwmSetWindowAttribute(handle, 19, ref dark, sizeof(int));
            int caption = 0x00151111;   // COLORREF (0x00BBGGRR) de #111115
            DwmSetWindowAttribute(handle, 35, ref caption, sizeof(int));
            int text = 0x00FAF7F7;      // #F7F7FA
            DwmSetWindowAttribute(handle, 36, ref text, sizeof(int));
        }

        /// <summary>«Salir» de la bandeja: el siguiente cierre es definitivo.</summary>
        public bool ExitRequested { get; set; }

        /// <summary>Muestra la ventana (desde la bandeja o al abrir la app por segunda vez) y la trae al frente.</summary>
        public void ShowFromTray()
        {
            Show();
            if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
            Activate();
            Topmost = true; Topmost = false;
            Focus();
        }

        /// <summary>
        /// Fundido y desplazamiento de 8 px al entrar en una sección. Se omite si el usuario desactivó las
        /// animaciones en Ajustes o en Windows (Accesibilidad → Efectos visuales).
        /// </summary>
        private void AnimateContent(ShellViewModel model)
        {
            if (!model.AnimationsEnabled || !SystemParameters.ClientAreaAnimation) return;
            var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
            var duration = new Duration(TimeSpan.FromMilliseconds(180));
            ContentHost.BeginAnimation(OpacityProperty, new DoubleAnimation(0.0, 1.0, duration) { EasingFunction = ease });
            ContentShift.BeginAnimation(System.Windows.Media.TranslateTransform.YProperty, new DoubleAnimation(8.0, 0.0, duration) { EasingFunction = ease });
        }

        public MainWindow(ShellViewModel model)
        {
            InitializeComponent();
            DataContext = model;
            SourceInitialized += (sender, e) => ApplyDarkTitleBar();
            // Paleta de búsqueda (Ctrl + K o botón «Buscar…»)
            model.PaletteRequested += (sender, e) => new Palette.PaletteWindow(this, model.PaletteActions(), model.RunPaletteAction).Show();
            // Ctrl + rueda cambia el tamaño de todo, como en la ventana clásica
            PreviewMouseWheel += (sender, e) =>
            {
                if ((Keyboard.Modifiers & ModifierKeys.Control) == 0) return;
                model.Zoom += e.Delta > 0 ? 0.1 : -0.1;
                e.Handled = true;
            };
            // Transición corta al cambiar de sección
            model.PropertyChanged += (sender, e) => { if (e.PropertyName == "PageId") AnimateContent(model); };
            // Con «Seguir en segundo plano» cerrar la ventana la oculta: la app sigue en la bandeja
            Closing += (sender, e) =>
            {
                if (ExitRequested || !model.BackgroundEnabled) return;
                e.Cancel = true;
                Hide();
            };
            // La ventana nunca abre más grande que la pantalla disponible
            var area = SystemParameters.WorkArea;
            if (Width > area.Width) Width = area.Width;
            if (Height > area.Height) Height = area.Height;
        }
    }
}
