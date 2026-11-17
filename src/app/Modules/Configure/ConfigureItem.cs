using System;
using IWinInstaller.App.Core;
using IWinInstaller.App.Modules.Install;

namespace IWinInstaller.App.Modules.Configure
{
    /// <summary>Una app instalada que hay que configurar por dentro: nota del catálogo y su check.</summary>
    public sealed class ConfigureItem : ObservableObject
    {
        private bool _configured;
        private string _reopenedFrom = "";

        public ConfigureItem(CatalogEntry entry) { Entry = entry; }

        public CatalogEntry Entry { get; private set; }
        public string Id { get { return Entry.Id; } }
        public string Name { get { return Entry.Name; } }
        public string Initials { get { return Entry.Initials; } }
        public string Group { get { return Entry.Group; } }
        public string Note { get { return Entry.ConfigNote; } }
        public bool CanOpen { get { return Entry.CanOpen; } }
        public string Version { get; set; }
        public int StepCount { get; set; }

        public bool Configured
        {
            get { return _configured; }
            set { if (Set(ref _configured, value)) { OnPropertyChanged("Status"); OnPropertyChanged("NeedsAttention"); } }
        }

        /// <summary>Versión anterior en la que se marcó como hecha, si la app se actualizó desde entonces.</summary>
        public string ReopenedFrom
        {
            get { return _reopenedFrom; }
            set { if (Set(ref _reopenedFrom, value ?? "")) { OnPropertyChanged("Status"); OnPropertyChanged("NeedsAttention"); } }
        }

        public bool NeedsAttention { get { return !Configured && ReopenedFrom.Length > 0; } }

        public string Status
        {
            get
            {
                string version = String.IsNullOrEmpty(Version) ? "" : " · versión " + Version;
                if (Configured) return "Configurada" + version;
                if (ReopenedFrom.Length > 0) return "Se actualizó de " + ReopenedFrom + " a " + (String.IsNullOrEmpty(Version) ? "una versión nueva" : Version) + ": revisa su configuración";
                return "Pendiente" + version;
            }
        }
    }
}
