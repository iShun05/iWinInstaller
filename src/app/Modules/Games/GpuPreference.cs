using System;
using System.Collections.Generic;
using System.Text;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>
    /// Preferencia de GPU por programa de Windows (Configuración › Pantalla › Gráficos):
    /// HKCU\Software\Microsoft\DirectX\UserGpuPreferences, valor = ruta del ejecutable, dato «k=v;k=v;».
    /// Solo se cambia el par GpuPreference; los demás (SwapEffectUpgradeEnable, AutoHDREnable…) se conservan.
    /// </summary>
    public static class GpuPreference
    {
        public const string RegistryKey = @"HKCU\Software\Microsoft\DirectX\UserGpuPreferences";
        public const string PairName = "GpuPreference";
        /// <summary>2 = alto rendimiento (1 = ahorro de energía, 0 = lo decide Windows).</summary>
        public const string HighPerformance = "2";

        private static List<KeyValuePair<string, string>> Split(string data)
        {
            var pairs = new List<KeyValuePair<string, string>>();
            if (string.IsNullOrEmpty(data)) return pairs;
            foreach (string part in data.Split(';'))
            {
                string p = part.Trim();
                if (p.Length == 0) continue;
                int eq = p.IndexOf('=');
                pairs.Add(eq < 0 ? new KeyValuePair<string, string>(p, null) : new KeyValuePair<string, string>(p.Substring(0, eq), p.Substring(eq + 1)));
            }
            return pairs;
        }

        public static string GetPair(string data, string name)
        {
            foreach (var pair in Split(data))
                if (string.Equals(pair.Key, name, StringComparison.OrdinalIgnoreCase)) return pair.Value;
            return null;
        }

        public static string SetPair(string data, string name, string value)
        {
            var pairs = Split(data);
            bool found = false;
            for (int i = 0; i < pairs.Count; i++)
            {
                if (!string.Equals(pairs[i].Key, name, StringComparison.OrdinalIgnoreCase)) continue;
                pairs[i] = new KeyValuePair<string, string>(pairs[i].Key, value);
                found = true;
            }
            if (!found) pairs.Insert(0, new KeyValuePair<string, string>(name, value));
            var sb = new StringBuilder();
            foreach (var pair in pairs) sb.Append(pair.Key).Append(pair.Value == null ? "" : "=" + pair.Value).Append(';');
            return sb.ToString();
        }

        public static string Describe(string value)
        {
            if (value == "2") return "Alto rendimiento";
            if (value == "1") return "Ahorro de energía";
            return "Lo decide Windows";
        }
    }
}
