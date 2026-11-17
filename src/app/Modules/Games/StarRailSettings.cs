using System;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>
    /// Gráficos de Honkai: Star Rail: JSON en UTF‑8 que el propio juego guarda en
    /// HKCU\Software\Cognosphere\Star Rail\GraphicsSettings_Model_h2986158309 (REG_BINARY, normalmente con \0 final).
    /// Se cambian valores en el sitio, sin reserializar, y nunca se añaden claves.
    /// </summary>
    public static class StarRailSettings
    {
        public const string RegistryKey = @"HKCU\Software\Cognosphere\Star Rail";
        public const string ModelValue = "GraphicsSettings_Model_h2986158309";
        public const string QualityValue = "GraphicsSettings_GraphicsQuality_h523255858";
        /// <summary>Marca de prueba A/B que Collapse Launcher comprueba antes de guardar; aquí solo se avisa.</summary>
        public const string AbTestValue = "App_Settings_h2319593470";
        /// <summary>Valor de QualityValue para «Personalizado».</summary>
        public const int CustomQuality = 0;

        public static bool TryDecode(byte[] data, out string json, out bool nulTerminated)
        {
            json = null; nulTerminated = false;
            if (data == null || data.Length == 0) return false;
            int length = data.Length;
            if (data[length - 1] == 0) { nulTerminated = true; length--; }
            try { json = new UTF8Encoding(false, true).GetString(data, 0, length); }
            catch (ArgumentException) { return false; }
            return MiniJson.TryParseObject(json) != null;
        }

        public static byte[] Encode(string json, bool nulTerminated)
        {
            byte[] body = new UTF8Encoding(false).GetBytes(json);
            if (!nulTerminated) return body;
            var result = new byte[body.Length + 1];
            Buffer.BlockCopy(body, 0, result, 0, body.Length);
            return result;
        }

        private static Regex KeyPattern(string key)
        {
            return new Regex("\"" + Regex.Escape(key) + "\"\\s*:\\s*(-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?|true|false)", RegexOptions.CultureInvariant);
        }

        /// <summary>Texto del valor (número o true/false) de una clave de primer nivel, o null si no existe.</summary>
        public static string GetRaw(string json, string key)
        {
            if (json == null) return null;
            var match = KeyPattern(key).Match(json);
            return match.Success ? match.Groups[1].Value : null;
        }

        public static int? GetInt(string json, string key)
        {
            string raw = GetRaw(json, key);
            double value;
            return raw != null && double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out value) ? (int?)(int)value : null;
        }

        /// <summary>Sustituye el valor de la primera aparición de la clave; si no existe, devuelve el JSON sin cambios.</summary>
        public static string SetRaw(string json, string key, string raw)
        {
            if (json == null) return null;
            var match = KeyPattern(key).Match(json);
            if (!match.Success) return json;
            var group = match.Groups[1];
            return json.Substring(0, group.Index) + raw + json.Substring(group.Index + group.Length);
        }

        /// <summary>Nombre de la calidad según la escala del juego (0 desactivado … 5 muy alto).</summary>
        public static string QualityName(int? value)
        {
            if (!value.HasValue) return "—";
            switch (value.Value)
            {
                case 0: return "Desactivado";
                case 1: return "Muy bajo";
                case 2: return "Bajo";
                case 3: return "Medio";
                case 4: return "Alto";
                case 5: return "Muy alto";
                default: return value.Value.ToString(CultureInfo.InvariantCulture);
            }
        }
    }
}
