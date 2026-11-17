using System.Collections.Generic;

namespace IWinInstaller.App.Modules.Games
{
    public enum RegKind { Binary, DWord, String }

    /// <summary>
    /// Todo lo que la página Juegos lee o escribe fuera de sí misma (registro, disco, procesos y GPU), detrás de una
    /// interfaz para probar la detección y las copias sin Windows. Las claves del registro van completas: «HKCU\…» o «HKLM\…».
    /// </summary>
    public interface IGameEnvironment
    {
        string LocalAppData { get; }
        string ProgramData { get; }

        /// <summary>byte[] (binario), int (DWORD), string o null si no existe.</summary>
        object GetValue(string key, string name);
        string[] SubKeyNames(string key);
        void SetValue(string key, string name, object value, RegKind kind);
        void DeleteValue(string key, string name);

        bool FileExists(string path);
        bool DirectoryExists(string path);
        string ReadAllText(string path);
        string[] GetFiles(string directory, string pattern);
        string[] GetDirectories(string directory);
        /// <summary>Empresa de la información de versión del archivo, o null.</summary>
        string CompanyName(string path);

        /// <summary>True si hay algún proceso con uno de esos nombres (sin .exe; un * final es prefijo).</summary>
        bool AnyProcessRunning(IEnumerable<string> names);
        /// <summary>GPU físicas (sin el adaptador básico de Microsoft ni los remotos); -1 si no se sabe.</summary>
        int GpuCount();
    }
}
