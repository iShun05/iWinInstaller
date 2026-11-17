using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using IWinInstaller.App.Core;

namespace IWinInstaller.App.Modules.Drivers
{
    /// <summary>Actualizaciones › Drivers y firmware: avisa de versiones nuevas sin descargar ni instalar nada.</summary>
    public sealed class DriversViewModel : ObservableObject
    {
        private bool _isBusy;
        private bool _loaded;
        private string _message = "Pulsa «Comprobar drivers» para buscar versiones nuevas.";
        private CancellationTokenSource _cancellation;

        public DriversViewModel()
        {
            Rows = new ObservableCollection<DriverRow>();
            CheckCommand = new RelayCommand(_ => { var ignored = CheckAsync(); }, _ => !IsBusy);
            CancelCommand = new RelayCommand(_ => { if (_cancellation != null) _cancellation.Cancel(); }, _ => IsBusy);
            OpenCommand = new RelayCommand(p => Open(p as DriverRow), p => p is DriverRow && ((DriverRow)p).HasLink);
        }

        public ObservableCollection<DriverRow> Rows { get; private set; }
        public RelayCommand CheckCommand { get; private set; }
        public RelayCommand CancelCommand { get; private set; }
        public RelayCommand OpenCommand { get; private set; }
        public bool IsBusy { get { return _isBusy; } private set { Set(ref _isBusy, value); } }
        public string Message { get { return _message; } private set { Set(ref _message, value); } }
        public bool HasRows { get { return Rows.Count > 0; } }

        public void EnsureLoaded() { if (!_loaded) { _loaded = true; var ignored = CheckAsync(); } }

        public async Task CheckAsync()
        {
            if (IsBusy) return;
            IsBusy = true;
            _cancellation = new CancellationTokenSource();
            Message = "Leyendo drivers y consultando Windows Update y NVIDIA… (puede tardar un minuto)";
            try
            {
                var token = _cancellation.Token;
                var scan = await Task.Run(() => DriverProbe.Scan(token), token);
                var rows = DriverReport.Build(scan, DateTime.Now);
                Rows.Clear();
                foreach (var row in rows.OrderBy(r => r.State == DriverState.UpdateAvailable ? 0 : 1)) Rows.Add(row);
                OnPropertyChanged("HasRows");
                Message = DriverReport.Summary(rows, scan);
            }
            catch (OperationCanceledException) { Message = "Comprobación cancelada."; }
            finally { IsBusy = false; _cancellation.Dispose(); _cancellation = null; }
        }

        private void Open(DriverRow row)
        {
            if (row == null || !row.HasLink) return;
            // Solo webs https y la página de Windows Update: nada de rutas ni ejecutables
            if (!row.LinkUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase) && !row.LinkUrl.StartsWith("ms-settings:windowsupdate", StringComparison.OrdinalIgnoreCase)) return;
            try { Process.Start(new ProcessStartInfo(row.LinkUrl) { UseShellExecute = true }); }
            catch (System.ComponentModel.Win32Exception) { Message = "No se pudo abrir " + row.LinkUrl; }
        }
    }
}
