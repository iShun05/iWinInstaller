using System;
using System.Collections.Generic;
using System.Linq;

namespace IWinInstaller.App.Modules.Install
{
    /// <summary>Una tarjeta del informe al terminar: motivo, código, qué hacer y líneas del registro.</summary>
    public sealed class ReportItem
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Kind { get; set; }
        public string Reason { get; set; }
        public string Code { get; set; }
        public string Action { get; set; }
        public string Lines { get; set; }
        public bool HasCode { get { return !String.IsNullOrEmpty(Code); } }
        public bool HasLines { get { return !String.IsNullOrEmpty(Lines); } }
        public string KindText
        {
            get
            {
                switch (Kind) { case "manual": return "Acción manual"; case "pausa": case "sin-ejecutar": return "Pendiente"; default: return "Falló"; }
            }
        }
    }

    /// <summary>Informe de la última instalación (report.last), con el texto listo para copiar.</summary>
    public sealed class ReportViewModel
    {
        public string Summary { get; set; }
        public string Text { get; set; }
        public List<ReportItem> Items { get; set; }
        public string[] RetryIds { get { return Items.Where(i => i.Kind != "manual").Select(i => i.Id).Where(id => !String.IsNullOrEmpty(id)).Distinct().ToArray(); } }
        public bool CanRetry { get { return RetryIds.Length > 0; } }

        /// <summary>Lee la respuesta de report.last. Devuelve null si no hay informe.</summary>
        public static ReportViewModel FromResponse(Dictionary<string, object> response)
        {
            object value;
            var report = response != null && response.TryGetValue("report", out value) ? value as Dictionary<string, object> : null;
            if (report == null) return null;
            var model = new ReportViewModel { Summary = Read(response, "summary"), Text = Read(response, "text"), Items = new List<ReportItem>() };
            object items;
            if (report.TryGetValue("items", out items) && items is object[])
            {
                foreach (var row in ((object[])items).OfType<Dictionary<string, object>>())
                {
                    object lines;
                    string joined = row.TryGetValue("details", out lines) && lines is object[] ? String.Join(Environment.NewLine, ((object[])lines).Select(l => Convert.ToString(l))) : Read(row, "details");
                    model.Items.Add(new ReportItem
                    {
                        Id = Read(row, "id"), Name = Read(row, "name"), Kind = Read(row, "kind"), Reason = Read(row, "reason"),
                        Code = CodeText(Read(row, "code"), Read(row, "codeText")), Action = Read(row, "hint"), Lines = joined
                    });
                }
            }
            return model;
        }

        private static string CodeText(string code, string text)
        {
            if (String.IsNullOrEmpty(code) || code == "0") return text ?? "";
            return String.IsNullOrEmpty(text) ? "Código " + code : "Código " + code + " · " + text;
        }

        private static string Read(Dictionary<string, object> row, string key)
        {
            object value;
            return row.TryGetValue(key, out value) && value != null ? Convert.ToString(value) : "";
        }
    }
}
