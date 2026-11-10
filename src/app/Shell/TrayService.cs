using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Windows.Threading;
using IWinInstaller.App.Core;
using IWinInstaller.App.Modules.Shortcuts;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace IWinInstaller.App.Shell
{
    /// <summary>Arranque con Windows: valor propio en la clave Run del usuario (sin administrador, se quita al desactivarlo).</summary>
    public static class Autostart
    {
        public const string TrayArgument = "--tray";
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "iWinInstaller";

        /// <summary>Orden que se registra: la app, minimizada en la bandeja.</summary>
        public static string CommandFor(string executable) { return "\"" + executable + "\" " + TrayArgument; }

        public static bool IsEnabled()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RunKey, false))
                    return key != null && key.GetValue(ValueName) is string;
            }
            catch (System.Security.SecurityException) { return false; }
            catch (UnauthorizedAccessException) { return false; }
        }

        /// <summary>Devuelve el motivo si no se pudo cambiar.</summary>
        public static string Set(bool enabled, string executable)
        {
            try
            {
                using (var key = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (key == null) return "No se pudo abrir la clave de arranque del usuario.";
                    if (enabled) key.SetValue(ValueName, CommandFor(executable), RegistryValueKind.String);
                    else key.DeleteValue(ValueName, false);
                }
                return "";
            }
            catch (System.Security.SecurityException e) { return e.Message; }
            catch (UnauthorizedAccessException e) { return e.Message; }
        }
    }

    /// <summary>Qué tarjetas han pasado a «Requiere atención» desde la comprobación anterior.</summary>
    public sealed class AttentionTracker
    {
        private HashSet<string> _known;

        /// <summary>La primera comprobación fija la referencia y no avisa: solo se avisa de lo que cambia después.</summary>
        public List<StatusCard> NewAlerts(IEnumerable<StatusCard> cards)
        {
            var attention = cards.Where(card => card.IsVisible && card.State == StatusState.Attention).ToList();
            var fresh = _known == null ? new List<StatusCard>() : attention.Where(card => !_known.Contains(card.Area)).ToList();
            _known = new HashSet<string>(attention.Select(card => card.Area));
            return fresh;
        }
    }

    /// <summary>
    /// Segundo plano: icono en la bandeja con el uso del equipo, atajos y avisos cuando algo pasa a requerir atención.
    /// Solo existe si el usuario activa «Seguir en segundo plano»; no instala ni actualiza nada por su cuenta.
    /// </summary>
    public sealed class TrayService : IDisposable
    {
        // Comprobación completa del estado (incluye WinGet): cada dos horas
        private static readonly TimeSpan CheckInterval = TimeSpan.FromHours(2);
        private readonly ShellViewModel _model;
        private readonly Dispatcher _dispatcher;
        private readonly Action _show;
        private readonly Forms.NotifyIcon _icon;
        private readonly Forms.ToolStripMenuItem _usage;
        private readonly DispatcherTimer _checkTimer;
        private readonly AttentionTracker _tracker = new AttentionTracker();
        private Icon _ownedIcon;
        private bool _disposed;

        public TrayService(ShellViewModel model, Dispatcher dispatcher, Action show, Action exit)
        {
            _model = model; _dispatcher = dispatcher; _show = show;
            _usage = new Forms.ToolStripMenuItem("Comprobando…") { Enabled = false };
            var menu = new Forms.ContextMenuStrip { Renderer = new Forms.ToolStripProfessionalRenderer(new DarkMenuColors()), ShowImageMargin = false, BackColor = DarkMenuColors.Surface, ForeColor = DarkMenuColors.Text };
            menu.Items.Add(Item("Abrir iWinInstaller", (sender, e) => _show()));
            menu.Items.Add(_usage);
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add(Item("Comprobar el equipo ahora", (sender, e) => { var ignored = CheckAsync(); }));
            menu.Items.Add(Item("Buscar acción o app…", (sender, e) => { _show(); _model.OpenPaletteCommand.Execute(null); }));
            var shortcuts = new Forms.ToolStripMenuItem("Windows a mano") { ForeColor = DarkMenuColors.Text };
            foreach (string id in QuickLinks.TrayIds)
            {
                var link = QuickLinks.Find(id);
                if (link != null) shortcuts.DropDownItems.Add(Item(link.Title, (sender, e) => QuickLinks.Open(link)));
            }
            shortcuts.DropDownItems.Add(new Forms.ToolStripSeparator());
            shortcuts.DropDownItems.Add(Item("Ver todos…", (sender, e) => { _show(); _model.Navigate("shortcuts"); }));
            var dropDown = shortcuts.DropDown as Forms.ToolStripDropDownMenu;
            if (dropDown != null) { dropDown.ShowImageMargin = false; dropDown.BackColor = DarkMenuColors.Surface; dropDown.ForeColor = DarkMenuColors.Text; }
            menu.Items.Add(shortcuts);
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add(Item("Salir", (sender, e) => exit()));

            _icon = new Forms.NotifyIcon { Icon = LoadIcon(), Text = "iWinInstaller", ContextMenuStrip = menu, Visible = true };
            _icon.DoubleClick += (sender, e) => _show();
            _icon.BalloonTipClicked += (sender, e) => _show();

            _model.Monitor.PropertyChanged += OnMonitorChanged;
            _model.Monitor.Alert += OnMonitorAlert;
            _model.Monitor.Start();
            _checkTimer = new DispatcherTimer(CheckInterval, DispatcherPriority.Background, (sender, e) => { var ignored = CheckAsync(); }, dispatcher);
            // Referencia inicial para los avisos: el estado que ya muestra el Inicio
            _dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => _tracker.NewAlerts(_model.Home.Cards)));
        }

        /// <summary>Texto del icono: Windows admite 63 caracteres como máximo.</summary>
        public static string TooltipText(string summary)
        {
            string text = "iWinInstaller · " + (summary ?? "");
            return text.Length > 63 ? text.Substring(0, 63) : text;
        }

        private static Forms.ToolStripMenuItem Item(string text, EventHandler click)
        {
            var item = new Forms.ToolStripMenuItem(text) { ForeColor = DarkMenuColors.Text };
            item.Click += click;
            return item;
        }

        private Icon LoadIcon()
        {
            try { _ownedIcon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location); }
            catch (ArgumentException) { _ownedIcon = null; }
            catch (System.IO.IOException) { _ownedIcon = null; }
            return _ownedIcon ?? SystemIcons.Application;
        }

        private void OnMonitorChanged(object sender, System.ComponentModel.PropertyChangedEventArgs e)
        {
            if (_disposed || e.PropertyName != "Summary") return;
            _icon.Text = TooltipText(_model.Monitor.Summary);
            string disk = _model.Monitor.DiskText;
            _usage.Text = _model.Monitor.Summary + (disk.Length > 0 ? " · " + disk : "");
        }

        private void OnMonitorAlert(object sender, MonitorAlertEventArgs e) { Notify(e.Title, e.Text); }

        /// <summary>Repite las comprobaciones del Inicio y avisa solo de lo que acaba de pasar a requerir atención.</summary>
        private async System.Threading.Tasks.Task CheckAsync()
        {
            if (_disposed || _model.Home.IsRefreshing) return;
            try
            {
                await _model.Home.RefreshAsync(new[] { "appUpdates", "windowsUpdate", "antivirus", "pendingBatch" }, CancellationToken.None);
                // Las tarjetas se aplican en el hilo de la interfaz con prioridad normal: esta acción va detrás
                await _dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() =>
                {
                    foreach (var card in _tracker.NewAlerts(_model.Home.Cards)) Notify(card.Title, card.Summary);
                }));
            }
            catch (Exception e) { App.Log("Comprobación en segundo plano: " + e.Message); }
        }

        public void Notify(string title, string text)
        {
            if (_disposed || !_model.NotificationsEnabled || String.IsNullOrWhiteSpace(text)) return;
            try { _icon.ShowBalloonTip(8000, String.IsNullOrWhiteSpace(title) ? "iWinInstaller" : title, text, Forms.ToolTipIcon.Warning); }
            catch (InvalidOperationException) { }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _checkTimer.Stop();
            _model.Monitor.PropertyChanged -= OnMonitorChanged;
            _model.Monitor.Alert -= OnMonitorAlert;
            _icon.Visible = false;
            if (_icon.ContextMenuStrip != null) _icon.ContextMenuStrip.Dispose();
            _icon.Dispose();
            if (_ownedIcon != null) _ownedIcon.Dispose();
        }

        /// <summary>Menú de la bandeja en negro, como el resto de la app.</summary>
        private sealed class DarkMenuColors : Forms.ProfessionalColorTable
        {
            public static readonly Color Surface = Color.FromArgb(0x15, 0x15, 0x1A);
            public static readonly Color Text = Color.FromArgb(0xE8, 0xE8, 0xEE);
            private static readonly Color Hover = Color.FromArgb(0x26, 0x26, 0x2E);
            private static readonly Color Line = Color.FromArgb(0x34, 0x34, 0x3D);
            public override Color ToolStripDropDownBackground { get { return Surface; } }
            public override Color MenuBorder { get { return Line; } }
            public override Color MenuItemBorder { get { return Hover; } }
            public override Color MenuItemSelected { get { return Hover; } }
            public override Color MenuItemSelectedGradientBegin { get { return Hover; } }
            public override Color MenuItemSelectedGradientEnd { get { return Hover; } }
            public override Color MenuItemPressedGradientBegin { get { return Hover; } }
            public override Color MenuItemPressedGradientEnd { get { return Hover; } }
            public override Color ImageMarginGradientBegin { get { return Surface; } }
            public override Color ImageMarginGradientMiddle { get { return Surface; } }
            public override Color ImageMarginGradientEnd { get { return Surface; } }
            public override Color SeparatorDark { get { return Line; } }
            public override Color SeparatorLight { get { return Line; } }
        }
    }
}
