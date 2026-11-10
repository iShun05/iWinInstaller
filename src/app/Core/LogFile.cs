using System;
using System.IO;

namespace IWinInstaller.App.Core
{
    /// <summary>Mantenimiento del registro de la interfaz (interfaz.log).</summary>
    public static class LogFile
    {
        /// <summary>Tamaño a partir del cual interfaz.log se archiva como interfaz.anterior.log.</summary>
        public const long MaxBytes = 1024 * 1024;

        /// <summary>Archiva el registro cuando supera el tamaño máximo (se conserva una copia anterior).</summary>
        public static bool Rotate(string path, long maxBytes)
        {
            try
            {
                var file = new FileInfo(path);
                if (!file.Exists || file.Length <= maxBytes) return false;
                string previous = Path.Combine(file.DirectoryName, Path.GetFileNameWithoutExtension(path) + ".anterior" + file.Extension);
                if (File.Exists(previous)) File.Delete(previous);
                File.Move(path, previous);
                return true;
            }
            catch (IOException) { return false; }
            catch (UnauthorizedAccessException) { return false; }
        }
    }
}
