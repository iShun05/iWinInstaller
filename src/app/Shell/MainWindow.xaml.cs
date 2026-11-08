using System.Windows;
using System.Windows.Input;

namespace IWinInstaller.App.Shell
{
    public partial class MainWindow : Window
    {
        public MainWindow(ShellViewModel model)
        {
            InitializeComponent();
            DataContext = model;
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
