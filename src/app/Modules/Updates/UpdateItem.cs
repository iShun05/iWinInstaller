using System;
using System.Collections.Generic;
using System.Linq;
using IWinInstaller.App.Core;

namespace IWinInstaller.App.Modules.Updates
{
    /// <summary>Una aplicación con versión nueva, tal como la devuelve updates.list.</summary>
    public sealed class UpdateItem : ObservableObject
    {
        private bool _isSelected;
        private bool _excluded;
        private string _status = "";

        public string Id { get; set; }
        public string Name { get; set; }
        public string InstalledVersion { get; set; }
        public string AvailableVersion { get; set; }
        public string Source { get; set; }
        public string CatalogId { get; set; }
        public bool Interactive { get; set; }

        public bool IsSelected { get { return _isSelected; } set { Set(ref _isSelected, value && !Excluded); } }
        public bool Excluded
        {
            get { return _excluded; }
            set { if (Set(ref _excluded, value)) { if (value) IsSelected = false; OnPropertyChanged("VersionText"); } }
        }
        public string Status { get { return _status; } set { if (Set(ref _status, value ?? "")) OnPropertyChanged("HasStatus"); } }
        public bool HasStatus { get { return !String.IsNullOrEmpty(Status); } }

        public string VersionText
        {
            get { return (String.IsNullOrEmpty(InstalledVersion) ? "?" : InstalledVersion) + "  →  " + AvailableVersion + (Excluded ? "   (se mantiene)" : ""); }
        }
        public string Note { get { return Interactive ? "Abre su asistente: complétalo cuando aparezca." : ""; } }
        public bool HasNote { get { return Interactive; } }

        /// <summary>Convierte la respuesta de updates.list. Ignora filas sin id o sin versión nueva.</summary>
        public static List<UpdateItem> FromResponse(Dictionary<string, object> response)
        {
            var list = new List<UpdateItem>();
            object items;
            if (response == null || !response.TryGetValue("items", out items) || !(items is object[])) return list;
            foreach (var row in ((object[])items).OfType<Dictionary<string, object>>())
            {
                var item = new UpdateItem
                {
                    Id = Read(row, "id"),
                    Name = Read(row, "name"),
                    InstalledVersion = Read(row, "installedVersion"),
                    AvailableVersion = Read(row, "availableVersion"),
                    Source = Read(row, "source"),
                    CatalogId = Read(row, "catalogId"),
                    Interactive = ReadBool(row, "interactive")
                };
                if (String.IsNullOrWhiteSpace(item.Id) || String.IsNullOrWhiteSpace(item.AvailableVersion)) continue;
                if (String.IsNullOrWhiteSpace(item.Name)) item.Name = item.Id;
                item.Excluded = ReadBool(row, "excluded");
                item.IsSelected = !item.Excluded;
                list.Add(item);
            }
            return list.OrderBy(i => i.Excluded).ThenBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        }

        internal static string Read(Dictionary<string, object> row, string key)
        {
            object value;
            return row.TryGetValue(key, out value) && value != null ? Convert.ToString(value) : "";
        }

        internal static bool ReadBool(Dictionary<string, object> row, string key)
        {
            object value;
            return row.TryGetValue(key, out value) && value is bool && (bool)value;
        }
    }

    /// <summary>Programación de la actualización automática de apps (updates.schedule).</summary>
    public sealed class UpdateSchedule
    {
        public bool Enabled { get; set; }
        public string Frequency { get; set; }
        public string Time { get; set; }

        public static UpdateSchedule FromResponse(Dictionary<string, object> response)
        {
            var schedule = new UpdateSchedule { Enabled = false, Frequency = "weekly", Time = "12:00" };
            object value;
            var data = response != null && response.TryGetValue("schedule", out value) ? value as Dictionary<string, object> : null;
            if (data == null) return schedule;
            schedule.Enabled = UpdateItem.ReadBool(data, "enabled");
            string frequency = UpdateItem.Read(data, "frequency");
            schedule.Frequency = frequency == "daily" ? "daily" : "weekly";
            string time = UpdateItem.Read(data, "time");
            schedule.Time = IsValidTime(time) ? time : "12:00";
            return schedule;
        }

        public static bool IsValidTime(string time)
        {
            TimeSpan parsed;
            return !String.IsNullOrEmpty(time) && time.Length == 5 && TimeSpan.TryParseExact(time, "hh\\:mm", null, out parsed);
        }
    }
}
