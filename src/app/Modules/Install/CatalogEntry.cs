using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace IWinInstaller.App.Modules.Install
{
    /// <summary>Una entrada de apps.json (solo lectura). Las reglas son las mismas que en la ventana clásica.</summary>
    public sealed class CatalogEntry
    {
        public string Id { get; set; }
        public string Section { get; set; }
        public string Group { get; set; }
        public string Subgroup { get; set; }
        public string SubgroupNote { get; set; }
        public string Compare { get; set; }
        public string Name { get; set; }
        public string Desc { get; set; }
        public string Icon { get; set; }
        public string Type { get; set; }
        public bool OptIn { get; set; }
        public bool Extra { get; set; }
        public bool Keep { get; set; }
        public bool Gui { get; set; }
        public bool NoOpen { get; set; }
        public bool Configure { get; set; }
        public bool HasPostInstall { get; set; }
        public string[] Winget { get; set; }

        /// <summary>Opcional: no se marca sola (optin o catálogo ampliado).</summary>
        public bool Optional { get { return OptIn || Extra; } }
        public bool IsTweak { get { return Type == "tweak"; } }
        public bool IsCli { get { return Section == "Terminal"; } }
        public bool OpensInConsole { get { return IsCli && !Gui; } }
        public bool CanOpen { get { return Type != "tweak" && Type != "vboxga" && !NoOpen && Section != "Sistema"; } }
        public bool NeedsConfiguration { get { return Configure || HasPostInstall; } }

        /// <summary>Test-Uninstallable de la ventana clásica.</summary>
        public bool CanUninstall
        {
            get
            {
                if (Keep) return false;
                if (Type == "tweak") return Id != "wsl" && Id != "restorepoint";
                return Type == "winget" || Type == "download" || Type == "manual";
            }
        }

        public string GroupLabel { get { return Section + " · " + Group + (String.IsNullOrEmpty(Subgroup) ? "" : " › " + Subgroup); } }

        public string Initials
        {
            get
            {
                var words = (Name ?? "").Split(new[] { ' ', '.', '-' }, StringSplitOptions.RemoveEmptyEntries)
                    .Where(w => Char.IsLetterOrDigit(w[0])).ToList();
                if (words.Count >= 2) return (words[0].Substring(0, 1) + words[1].Substring(0, 1)).ToUpperInvariant();
                string name = Name ?? "?";
                return name.Substring(0, Math.Min(2, name.Length));
            }
        }

        /// <summary>Símbolo de Segoe Fluent para «glyph:E756»; vacío si el icono es una web.</summary>
        public string Glyph
        {
            get
            {
                if (Icon == null || !Icon.StartsWith("glyph:", StringComparison.Ordinal) || Icon.Length != 10) return "";
                int code;
                return Int32.TryParse(Icon.Substring(6), System.Globalization.NumberStyles.HexNumber, null, out code) ? ((char)code).ToString() : "";
            }
        }

        public string SearchText
        {
            get { return (Name + " " + Desc + " " + Group + " " + Subgroup + " " + Compare + " " + Section + " " + String.Join(" ", Winget ?? new string[0])).ToLowerInvariant(); }
        }

        public static List<CatalogEntry> Load(string path)
        {
            var serializer = new JavaScriptSerializer { MaxJsonLength = 32 * 1024 * 1024 };
            var rows = serializer.DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as object[];
            if (rows == null) throw new InvalidDataException("apps.json no es una lista.");
            var notes = new Dictionary<string, string>();
            var list = new List<CatalogEntry>();
            foreach (var row in rows.OfType<Dictionary<string, object>>())
            {
                var entry = new CatalogEntry
                {
                    Id = S(row, "id"), Section = S(row, "section"), Group = S(row, "group"), Subgroup = S(row, "subgroup"),
                    SubgroupNote = S(row, "subgroupNote"), Compare = S(row, "compare"), Name = S(row, "name"), Desc = S(row, "desc"),
                    Icon = S(row, "icon"), Type = S(row, "type"), OptIn = B(row, "optin"), Extra = B(row, "extra"), Keep = B(row, "keep"),
                    Gui = B(row, "gui"), NoOpen = B(row, "noopen"), Configure = B(row, "configure"), HasPostInstall = row.ContainsKey("postInstall"),
                    Winget = Strings(row, "winget")
                };
                if (!String.IsNullOrEmpty(entry.SubgroupNote)) notes[entry.Group + "/" + entry.Subgroup] = entry.SubgroupNote;
                list.Add(entry);
            }
            // La nota «Cuál elegir» se escribe en una entrada de la subsección y vale para todas
            foreach (var entry in list.Where(e => !String.IsNullOrEmpty(e.Subgroup)))
            {
                string note;
                if (notes.TryGetValue(entry.Group + "/" + entry.Subgroup, out note)) entry.SubgroupNote = note;
            }
            return list;
        }

        private static string S(Dictionary<string, object> row, string key)
        {
            object value;
            return row.TryGetValue(key, out value) && value is string ? (string)value : "";
        }

        private static bool B(Dictionary<string, object> row, string key)
        {
            object value;
            return row.TryGetValue(key, out value) && value is bool && (bool)value;
        }

        private static string[] Strings(Dictionary<string, object> row, string key)
        {
            object value;
            if (!row.TryGetValue(key, out value) || value == null) return new string[0];
            if (value is string) return new[] { (string)value };
            var list = value as object[];
            return list == null ? new string[0] : list.OfType<string>().ToArray();
        }
    }
}
