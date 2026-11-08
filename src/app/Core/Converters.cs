using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace IWinInstaller.App.Core
{
    /// <summary>Invierte un booleano (p. ej. desactivar una casilla cuando la app está excluida).</summary>
    public sealed class InverseBoolean : IValueConverter
    {
        public static readonly InverseBoolean Instance = new InverseBoolean();
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) { return !(value is bool && (bool)value); }
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) { return !(value is bool && (bool)value); }
    }

    /// <summary>Visible solo cuando el valor coincide con el parámetro (la página activa de la navegación).</summary>
    public sealed class EqualsToVisibility : IValueConverter
    {
        public static readonly EqualsToVisibility Instance = new EqualsToVisibility();
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            return String.Equals(System.Convert.ToString(value, CultureInfo.InvariantCulture), System.Convert.ToString(parameter, CultureInfo.InvariantCulture), StringComparison.Ordinal) ? Visibility.Visible : Visibility.Collapsed;
        }
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) { return Binding.DoNothing; }
    }
}
