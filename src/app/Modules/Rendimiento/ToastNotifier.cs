using System;
using System.Windows.Forms;
using System.Windows.Threading;

namespace IWinInstaller.App.Modules.Rendimiento
{
    /// <summary>Aviso del sistema (globo de Windows) temporal: crea un icono de bandeja, muestra el texto y lo retira a los 10 s.</summary>
    public static class ToastNotifier
    {
        public static void Show(Dispatcher dispatcher, string title, string text)
        {
            dispatcher.BeginInvoke(new Action(() =>
            {
                try
                {
                    var icon = new NotifyIcon
                    {
                        Icon = System.Drawing.SystemIcons.Warning, Visible = true,
                        BalloonTipTitle = title, BalloonTipText = text, BalloonTipIcon = ToolTipIcon.Warning
                    };
                    icon.ShowBalloonTip(8000);
                    var timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher) { Interval = TimeSpan.FromSeconds(10) };
                    timer.Tick += (s, e) => { timer.Stop(); icon.Visible = false; icon.Dispose(); };
                    timer.Start();
                }
                catch (Exception ex) when (ex is InvalidOperationException || ex is System.ComponentModel.Win32Exception)
                {
                    /* sin aviso del sistema: queda el historial y el aviso dentro de la app */
                }
            }));
        }
    }
}
