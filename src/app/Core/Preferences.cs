using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace IWinInstaller.App.Core
{
    /// <summary>Preferencias de la interfaz nueva en %LOCALAPPDATA%\iWinInstaller\interfaz.json.</summary>
    public sealed class Preferences
    {
        public const double MinZoom = 0.7;
        public const double MaxZoom = 2.0;
        private readonly string _path;

        public Preferences(string path) { _path = path; Zoom = 1.0; }

        public double Zoom { get; set; }

        public static string DefaultPath
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "iWinInstaller", "interfaz.json"); }
        }

        /// <summary>Limita el zoom al 70–200 % y lo redondea a pasos de 10 %.</summary>
        public static double ClampZoom(double value)
        {
            if (Double.IsNaN(value) || Double.IsInfinity(value)) return 1.0;
            return Math.Round(Math.Min(MaxZoom, Math.Max(MinZoom, value)) * 10) / 10;
        }

        public static Preferences Load(string path)
        {
            var preferences = new Preferences(path);
            try
            {
                if (!File.Exists(path)) return preferences;
                var data = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as Dictionary<string, object>;
                object zoom;
                if (data != null && data.TryGetValue("zoom", out zoom) && zoom != null)
                    preferences.Zoom = ClampZoom(Convert.ToDouble(zoom, System.Globalization.CultureInfo.InvariantCulture));
            }
            catch (Exception) { /* un archivo dañado no impide abrir la app: se usan los valores por defecto */ }
            return preferences;
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path));
                var data = new Dictionary<string, object> { { "format", "iWinInstaller-interfaz" }, { "version", 1 }, { "zoom", ClampZoom(Zoom) } };
                string temporary = _path + ".tmp";
                File.WriteAllText(temporary, new JavaScriptSerializer().Serialize(data), new UTF8Encoding(false));
                if (File.Exists(_path)) File.Replace(temporary, _path, null); else File.Move(temporary, _path);
            }
            catch (Exception) { /* no poder guardar el zoom no es un error para el usuario */ }
        }
    }
}
