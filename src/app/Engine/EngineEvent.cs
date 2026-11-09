using System;
using System.Collections.Generic;
using System.Web.Script.Serialization;

namespace IWinInstaller.App.Engine
{
    /// <summary>Un evento del motor (una línea JSONL de -EngineEvents).</summary>
    public sealed class EngineEvent
    {
        public string Type { get; set; }
        public string Id { get; set; }
        public string Phase { get; set; }
        public string Outcome { get; set; }
        public string Level { get; set; }
        public string Text { get; set; }
        public int? ExitCode { get; set; }
        public bool? Installed { get; set; }
        public bool? PreviousState { get; set; }

        /// <summary>Convierte una línea JSONL. Devuelve null si está vacía o mal formada (se ignora).</summary>
        public static EngineEvent Parse(string line)
        {
            if (String.IsNullOrWhiteSpace(line)) return null;
            Dictionary<string, object> data;
            try { data = new JavaScriptSerializer().DeserializeObject(line) as Dictionary<string, object>; }
            catch (ArgumentException) { return null; }
            catch (InvalidOperationException) { return null; }
            if (data == null) return null;
            var result = new EngineEvent
            {
                Type = Read(data, "type"),
                Id = Read(data, "id"),
                Phase = Read(data, "phase"),
                Outcome = Read(data, "outcome"),
                Level = Read(data, "level"),
                Text = Read(data, "text")
            };
            object flag;
            if (data.TryGetValue("installed", out flag) && flag is bool) result.Installed = (bool)flag;
            if (data.TryGetValue("previousState", out flag) && flag is bool) result.PreviousState = (bool)flag;
            int code;
            if (Int32.TryParse(Read(data, "exitCode"), out code)) result.ExitCode = code;
            return String.IsNullOrEmpty(result.Type) ? null : result;
        }

        private static string Read(Dictionary<string, object> data, string key)
        {
            object value;
            return data.TryGetValue(key, out value) && value != null ? Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) : null;
        }
    }
}
