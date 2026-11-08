using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Windows.Threading;
using IWinInstaller.App.Core;
using IWinInstaller.App.Engine;
using IWinInstaller.App.Modules.Home;
using IWinInstaller.App.Modules.Updates;

namespace IWinInstaller.App.Shell
{
    /// <summary>Una entrada de la navegación lateral.</summary>
    public sealed class NavItem
    {
        public NavItem(string id, string title, string description, bool isClassic)
        {
            Id = id; Title = title; Description = description; IsClassic = isClassic;
        }
        public string Id { get; private set; }
        public string Title { get; private set; }
        public string Description { get; private set; }
        /// <summary>Todavía se abre en la ventana clásica (hasta v4.7).</summary>
        public bool IsClassic { get; private set; }
    }

    public sealed class ShellViewModel : ObservableObject
    {
        public const string InstagramUrl = "https://www.instagram.com/_shun._05/";
        private readonly Preferences _preferences;
        private NavItem _selected;
        private double _zoom;

        public ShellViewModel(string root, Dispatcher dispatcher, Preferences preferences)
        {
            _preferences = preferences;
            _zoom = Preferences.ClampZoom(preferences.Zoom);
            Engine = new EngineClient(root);
            Legacy = new LegacyBridge(root);
            Home = new HomeViewModel(Engine, dispatcher);
            Updates = new UpdatesViewModel(Engine, dispatcher);
            Router = new ActionRouter(Legacy, Navigate);
            Items = new ObservableCollection<NavItem>
            {
                new NavItem("home", "Inicio", "Estado del PC de un vistazo.", false),
                new NavItem("install", "Instalar", "Catálogo, perfiles, guías después de instalar e informe.", true),
                new NavItem("updates", "Actualizaciones", "Versiones nuevas, exclusiones y actualización programada.", false),
                new NavItem("system", "Sistema", "Ajustes de Windows, pantalla y energía.", true),
                new NavItem("remote", "Acceso remoto", "Escritorio remoto, SSH y vincular equipos.", true),
                new NavItem("security", "Seguridad", "Microsoft Defender y antivirus.", true)
            };
            _selected = Items[0];
            OpenActionCommand = new RelayCommand(p =>
            {
                var card = p as StatusCard;
                if (card != null) Router.Run(card.ActionId);
            });
            OpenClassicCommand = new RelayCommand(_ => Legacy.Open(), _ => Legacy.IsAvailable);
            OpenInstagramCommand = new RelayCommand(_ => { try { Process.Start(new ProcessStartInfo(InstagramUrl) { UseShellExecute = true }); } catch (System.ComponentModel.Win32Exception) { } });
            ZoomInCommand = new RelayCommand(_ => Zoom += 0.1);
            ZoomOutCommand = new RelayCommand(_ => Zoom -= 0.1);
            ZoomResetCommand = new RelayCommand(_ => Zoom = 1.0);
        }

        public EngineClient Engine { get; private set; }
        public LegacyBridge Legacy { get; private set; }
        public HomeViewModel Home { get; private set; }
        public UpdatesViewModel Updates { get; private set; }
        public ActionRouter Router { get; private set; }
        public ObservableCollection<NavItem> Items { get; private set; }
        public RelayCommand OpenActionCommand { get; private set; }
        public RelayCommand OpenClassicCommand { get; private set; }
        public RelayCommand OpenInstagramCommand { get; private set; }
        public RelayCommand ZoomInCommand { get; private set; }
        public RelayCommand ZoomOutCommand { get; private set; }
        public RelayCommand ZoomResetCommand { get; private set; }

        public NavItem Selected
        {
            get { return _selected; }
            set
            {
                if (value == null || !Set(ref _selected, value)) return;
                OnPropertyChanged("IsHome"); OnPropertyChanged("IsClassicPage"); OnPropertyChanged("PageId");
                if (value.Id == "updates") Updates.EnsureLoaded();
            }
        }
        public bool IsHome { get { return Selected != null && Selected.Id == "home"; } }
        /// <summary>Id de la página activa (para mostrar su vista).</summary>
        public string PageId { get { return Selected == null ? "" : Selected.Id; } }
        public bool IsClassicPage { get { return Selected != null && Selected.IsClassic; } }

        public double Zoom
        {
            get { return _zoom; }
            set
            {
                if (Set(ref _zoom, Preferences.ClampZoom(value)))
                {
                    OnPropertyChanged("ZoomText");
                    _preferences.Zoom = _zoom;
                    _preferences.Save();
                }
            }
        }
        public string ZoomText { get { return Math.Round(Zoom * 100) + " %"; } }

        /// <summary>Versión visible: «v4.4» a partir de la versión del ensamblado.</summary>
        public string VersionText
        {
            get
            {
                var version = Assembly.GetExecutingAssembly().GetName().Version;
                return "iWinInstaller v" + version.Major + "." + version.Minor;
            }
        }

        public void Navigate(string id)
        {
            var item = Items.FirstOrDefault(i => i.Id == id);
            if (item != null) Selected = item;
        }
    }
}
