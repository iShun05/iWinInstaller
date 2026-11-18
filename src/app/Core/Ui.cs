using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace IWinInstaller.App.Core
{
    /// <summary>
    /// Propiedades adjuntas del sistema de diseño (v5.7): icono de un botón, botón que abre un menú
    /// y entrada animada de una página. Se usan desde Theme.xaml y las vistas.
    /// </summary>
    public static class Ui
    {
        /// <summary>Glifo de Segoe Fluent Icons que el botón muestra delante del texto.</summary>
        public static readonly DependencyProperty IconProperty =
            DependencyProperty.RegisterAttached("Icon", typeof(string), typeof(Ui), new FrameworkPropertyMetadata(null));
        public static string GetIcon(DependencyObject element) { return (string)element.GetValue(IconProperty); }
        public static void SetIcon(DependencyObject element, string value) { element.SetValue(IconProperty, value); }

        /// <summary>El botón abre su ContextMenu debajo, alineado a la izquierda, y muestra un chevrón.</summary>
        public static readonly DependencyProperty OpensMenuProperty =
            DependencyProperty.RegisterAttached("OpensMenu", typeof(bool), typeof(Ui), new FrameworkPropertyMetadata(false, OnOpensMenuChanged));
        public static bool GetOpensMenu(DependencyObject element) { return (bool)element.GetValue(OpensMenuProperty); }
        public static void SetOpensMenu(DependencyObject element, bool value) { element.SetValue(OpensMenuProperty, value); }

        private static void OnOpensMenuChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var button = d as ButtonBase;
            if (button == null) return;
            button.Click -= OpenMenu;
            if ((bool)e.NewValue)
            {
                button.Click += OpenMenu;
                // El clic derecho no debe abrir el menú en otra posición
                ContextMenuService.SetIsEnabled(button, false);
            }
        }

        private static void OpenMenu(object sender, RoutedEventArgs e)
        {
            var button = (ButtonBase)sender;
            var menu = button.ContextMenu;
            if (menu == null) return;
            menu.DataContext = button.DataContext;
            menu.PlacementTarget = button;
            menu.Placement = PlacementMode.Bottom;
            menu.VerticalOffset = 4;
            menu.IsOpen = true;
        }

        /// <summary>La página entra con un fundido y un desplazamiento corto cada vez que se hace visible.</summary>
        public static readonly DependencyProperty EntranceProperty =
            DependencyProperty.RegisterAttached("Entrance", typeof(bool), typeof(Ui), new FrameworkPropertyMetadata(false, OnEntranceChanged));
        public static bool GetEntrance(DependencyObject element) { return (bool)element.GetValue(EntranceProperty); }
        public static void SetEntrance(DependencyObject element, bool value) { element.SetValue(EntranceProperty, value); }

        private static void OnEntranceChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var element = d as UIElement;
            if (element == null) return;
            element.IsVisibleChanged -= PlayEntrance;
            if ((bool)e.NewValue) element.IsVisibleChanged += PlayEntrance;
        }

        /// <summary>Respeta «Mostrar animaciones en Windows»: sin animaciones del sistema, no se anima nada.</summary>
        public static bool MotionEnabled { get { return SystemParameters.ClientAreaAnimation && RenderCapability.Tier > 0; } }

        private static void PlayEntrance(object sender, DependencyPropertyChangedEventArgs e)
        {
            var element = (UIElement)sender;
            if (!(bool)e.NewValue || !MotionEnabled) return;
            var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
            var duration = TimeSpan.FromMilliseconds(220);
            var move = element.RenderTransform as TranslateTransform;
            if (move == null || move.IsFrozen) { move = new TranslateTransform(); element.RenderTransform = move; }
            element.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, duration) { EasingFunction = ease });
            move.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(10, 0, duration) { EasingFunction = ease });
        }
    }

    /// <summary>
    /// Gravedad de un mensaje de estado para la barra de aviso: error, warning, success o info.
    /// Los modelos solo publican texto; la gravedad se deduce de las frases que ya usan.
    /// </summary>
    public sealed class MessageSeverity : IValueConverter
    {
        public static readonly MessageSeverity Instance = new MessageSeverity();

        public static string Classify(string message)
        {
            if (String.IsNullOrWhiteSpace(message)) return "none";
            string text = message.ToLowerInvariant();
            if (text.Contains("no se pud") || text.Contains("error") || text.Contains("falta ") || text.StartsWith("falta", StringComparison.Ordinal)
                || text.Contains("falló") || text.Contains("no terminó") || text.Contains("no responde") || text.Contains("no respondió"))
                return "error";
            if (text.Contains("cancelad") || text.Contains("pausad") || text.Contains("reiniciar") || text.Contains("atención") || text.Contains("aviso"))
                return "warning";
            if (text.Contains("copiado") || text.Contains("guardad") || text.Contains("eliminad") || text.Contains("aplicad") || text.Contains("listo")
                || text.Contains("correctamente") || text.Contains("completad") || text.Contains("terminad"))
                return "success";
            return "info";
        }

        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) { return Classify(value as string); }
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) { return Binding.DoNothing; }
    }

    /// <summary>Visible si el texto no está vacío.</summary>
    public sealed class TextToVisibility : IValueConverter
    {
        public static readonly TextToVisibility Instance = new TextToVisibility();
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            return String.IsNullOrWhiteSpace(value as string) ? Visibility.Collapsed : Visibility.Visible;
        }
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) { return Binding.DoNothing; }
    }
}
