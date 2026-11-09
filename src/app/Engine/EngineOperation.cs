using System;
using System.IO;

namespace IWinInstaller.App.Engine
{
    /// <summary>
    /// Operación larga del motor que se puede pausar: crea el archivo «cancel» junto al Request y el lote
    /// para al terminar la aplicación en curso (nunca a mitad de un instalador).
    /// </summary>
    public sealed class EngineOperation
    {
        private readonly object _lock = new object();
        private string _workDirectory;
        private bool _pauseRequested;

        public bool PauseRequested { get { lock (_lock) return _pauseRequested; } }

        internal void Attach(string workDirectory)
        {
            lock (_lock)
            {
                _workDirectory = workDirectory;
                if (_pauseRequested) WriteCancel();
            }
        }

        public void RequestPause()
        {
            lock (_lock)
            {
                _pauseRequested = true;
                if (_workDirectory != null) WriteCancel();
            }
        }

        private void WriteCancel()
        {
            try { File.WriteAllText(Path.Combine(_workDirectory, "cancel"), "stop"); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
