using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;

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
            // La ventana nunca abre más grande que la pantalla disponible
            var area = SystemParameters.WorkArea;
            if (Width > area.Width) Width = area.Width;
            if (Height > area.Height) Height = area.Height;
        }
    }
}
