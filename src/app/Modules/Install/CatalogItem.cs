using System;
using System.Windows.Media;
using IWinInstaller.App.Core;

namespace IWinInstaller.App.Modules.Install
{
    /// <summary>Fila del catálogo: la entrada fija más el estado que cambia (marcada, instalada, estado del lote).</summary>
    public sealed class CatalogItem : ObservableObject
    {
        private bool _isChecked;
        private bool _installed;
        private bool _hasPreviousState;
        private bool _configured;
        private bool _inventoryKnown;
        private string _status = "";
        private string _statusKind = "none";
        private ImageSource _image;

        public CatalogItem(CatalogEntry entry) { Entry = entry; }

        public CatalogEntry Entry { get; private set; }
        public string Id { get { return Entry.Id; } }
        public string Name { get { return Entry.Name; } }
        public string Desc { get { return Entry.Desc; } }
        public string Compare { get { return Entry.Compare; } }
        public string GroupLabel { get { return Entry.GroupLabel; } }
        public string SubgroupNote { get { return Entry.SubgroupNote; } }
        public string Initials { get { return Entry.Initials; } }
        public string Glyph { get { return Entry.Glyph; } }
        public bool HasGlyph { get { return Glyph.Length > 0; } }
        public bool HasCompare { get { return !String.IsNullOrEmpty(Compare); } }
        public bool IsCli { get { return Entry.IsCli; } }
        public bool NeedsConfiguration { get { return Entry.NeedsConfiguration; } }
        public string OpenLabel { get { return Entry.OpensInConsole ? "Abrir en terminal" : "Abrir"; } }
        public string UninstallLabel { get { return Entry.IsTweak ? "Deshacer" : "Desinstalar"; } }

        public ImageSource Image { get { return _image; } set { if (Set(ref _image, value)) OnPropertyChanged("HasImage"); } }
        public bool HasImage { get { return _image != null; } }

        public bool IsChecked { get { return _isChecked; } set { Set(ref _isChecked, value); } }

        public bool Installed
        {
            get { return _installed; }
            set { if (Set(ref _installed, value)) { OnPropertyChanged("ShowUninstall"); OnPropertyChanged("ShowOpen"); OnPropertyChanged("Configuration"); } }
        }

        /// <summary>El inventario ya se leyó: hasta entonces no se afirma «instalada» ni «falta».</summary>
        public bool InventoryKnown { get { return _inventoryKnown; } set { Set(ref _inventoryKnown, value); } }

        public bool HasPreviousState { get { return _hasPreviousState; } set { if (Set(ref _hasPreviousState, value)) OnPropertyChanged("ShowUninstall"); } }
        public bool ShowUninstall { get { return (Installed || HasPreviousState) && Entry.CanUninstall; } }
        public bool ShowOpen { get { return Installed && Entry.CanOpen; } }

        public bool Configured { get { return _configured; } set { if (Set(ref _configured, value)) OnPropertyChanged("Configuration"); } }
        public string Configuration
        {
            get { return !Installed || !NeedsConfiguration ? "" : Configured ? "Configuración confirmada por ti" : "Después de instalar · pasos pendientes"; }
        }
        public bool HasConfiguration { get { return Configuration.Length > 0; } }

        public string Status { get { return _status; } set { if (Set(ref _status, value ?? "")) OnPropertyChanged("HasStatus"); } }
        public bool HasStatus { get { return _status.Length > 0; } }
        /// <summary>none, ok, bad o busy (mismos colores que la ventana clásica).</summary>
        public string StatusKind { get { return _statusKind; } set { Set(ref _statusKind, value ?? "none"); } }

        /// <summary>Aplica el resultado de un evento «item» del motor.</summary>
        public void ApplyOutcome(string outcome, bool installed, bool previousState, bool removing)
        {
            Installed = installed;
            HasPreviousState = previousState;
            switch (outcome)
            {
                case "success": Status = removing ? "Restaurada / retirada" : "Instalada"; StatusKind = "ok"; IsChecked = false; break;
                case "rebootRequired": Status = "Requiere reinicio"; StatusKind = "busy"; IsChecked = false; break;
                case "pending": Status = "Pendiente"; StatusKind = "bad"; IsChecked = true; break;
                default: Status = "No completada"; StatusKind = "bad"; IsChecked = true; break;
            }
            OnPropertyChanged("HasConfiguration");
        }
    }
}
