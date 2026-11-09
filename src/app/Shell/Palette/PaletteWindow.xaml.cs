using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Input;

namespace IWinInstaller.App.Shell.Palette
{
    /// <summary>Paleta de búsqueda (Ctrl + K): llega a cualquier acción o app con el teclado.</summary>
    public partial class PaletteWindow : Window
    {
        private readonly IList<PaletteAction> _actions;
        private readonly Action<PaletteAction> _run;

        public PaletteWindow(Window owner, IList<PaletteAction> actions, Action<PaletteAction> run)
        {
            InitializeComponent();
            Owner = owner;
            _actions = actions;
            _run = run;
            Loaded += (s, e) => { Query.Focus(); Refresh(); };
            Deactivated += (s, e) => { if (IsVisible) Close(); };
        }

        private void Refresh()
        {
            Results.ItemsSource = PaletteSearch.Find(_actions, Query.Text);
            if (Results.Items.Count > 0) Results.SelectedIndex = 0;
        }

        private void OnQueryChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) { Refresh(); }

        private void OnKey(object sender, KeyEventArgs e)
        {
            switch (e.Key)
            {
                case Key.Escape: Close(); e.Handled = true; break;
                case Key.Down: Move(1); e.Handled = true; break;
                case Key.Up: Move(-1); e.Handled = true; break;
                case Key.Enter: RunSelected(); e.Handled = true; break;
            }
        }

        private void Move(int delta)
        {
            if (Results.Items.Count == 0) return;
            Results.SelectedIndex = Math.Max(0, Math.Min(Results.Items.Count - 1, Results.SelectedIndex + delta));
            Results.ScrollIntoView(Results.SelectedItem);
        }

        private void OnRun(object sender, MouseButtonEventArgs e) { RunSelected(); }

        private void RunSelected()
        {
            var action = Results.SelectedItem as PaletteAction;
            if (action == null) return;
            Close();
            _run(action);
        }
    }
}
