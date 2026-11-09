using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace IWinInstaller.App.Shell
{
    /// <summary>Diálogos que necesitan los módulos; una interfaz para poder probarlos sin ventana.</summary>
    public interface IDialogService
    {
        bool Confirm(string title, string text, string okLabel);
        void Inform(string title, string text);
        string Ask(string title, string text, string suggestion);
        string OpenFile(string filter);
        string SaveFile(string filter, string suggestion);
        void CopyText(string text);
        void OpenUri(string uri);
    }

    /// <summary>Diálogos oscuros con el mismo estilo que la ventana (no los grises de Windows).</summary>
    public sealed class DialogService : IDialogService
    {
        public bool Confirm(string title, string text, string okLabel) { return Show(title, text, okLabel, "Cancelar", null) != null; }
        public void Inform(string title, string text) { Show(title, text, "Entendido", null, null); }
        public string Ask(string title, string text, string suggestion) { return Show(title, text, "Guardar", "Cancelar", suggestion ?? ""); }

        public string OpenFile(string filter)
        {
            var dialog = new Microsoft.Win32.OpenFileDialog { Filter = filter, CheckFileExists = true };
            return dialog.ShowDialog(Application.Current.MainWindow) == true ? dialog.FileName : null;
        }

        public string SaveFile(string filter, string suggestion)
        {
            var dialog = new Microsoft.Win32.SaveFileDialog { Filter = filter, FileName = suggestion, OverwritePrompt = true };
            return dialog.ShowDialog(Application.Current.MainWindow) == true ? dialog.FileName : null;
        }

        public void CopyText(string text) { try { Clipboard.SetText(text ?? ""); } catch (System.Runtime.InteropServices.COMException) { } }

        public void OpenUri(string uri)
        {
            if (uri == null || !uri.StartsWith("https://", StringComparison.Ordinal)) return;
            try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); } catch (System.ComponentModel.Win32Exception) { }
        }

        /// <summary>Devuelve null si se cancela; con campo de texto, su valor; sin él, "".</summary>
        private static string Show(string title, string text, string ok, string cancel, string input)
        {
            var resources = Application.Current.Resources;
            var window = new Window
            {
                Title = title, Owner = Application.Current.MainWindow, WindowStartupLocation = WindowStartupLocation.CenterOwner,
                SizeToContent = SizeToContent.WidthAndHeight, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false,
                Background = (Brush)resources["Background"], Foreground = (Brush)resources["Text"],
                FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"), FontSize = 13, MaxWidth = 620
            };
            var panel = new StackPanel { Margin = new Thickness(24, 20, 24, 18) };
            panel.Children.Add(new TextBlock { Text = title, FontSize = 18, FontWeight = FontWeights.SemiBold, Foreground = (Brush)resources["TextStrong"], Margin = new Thickness(0, 0, 0, 10) });
            var scroll = new ScrollViewer { MaxHeight = 420, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap } };
            panel.Children.Add(scroll);
            TextBox box = null;
            if (input != null)
            {
                box = new TextBox { Text = input, Margin = new Thickness(0, 12, 0, 0), Padding = new Thickness(8, 6, 8, 6), Background = new SolidColorBrush(Color.FromRgb(0x22, 0x22, 0x2B)), Foreground = (Brush)resources["Text"], BorderBrush = (Brush)resources["Border"] };
                panel.Children.Add(box);
            }
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) };
            string result = null;
            if (cancel != null)
            {
                var no = new Button { Content = cancel, Style = (Style)resources["Btn"], IsCancel = true, Margin = new Thickness(0, 0, 8, 0) };
                no.Click += (s, e) => window.Close();
                buttons.Children.Add(no);
            }
            var yes = new Button { Content = ok, Style = (Style)resources["Primary"], IsDefault = true };
            yes.Click += (s, e) => { result = box != null ? box.Text.Trim() : ""; window.Close(); };
            buttons.Children.Add(yes);
            panel.Children.Add(buttons);
            window.Content = panel;
            window.Loaded += (s, e) => { if (box != null) { box.Focus(); box.SelectAll(); } else yes.Focus(); };
            window.ShowDialog();
            return result;
        }
    }
}
