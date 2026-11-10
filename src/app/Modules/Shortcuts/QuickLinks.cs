using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using IWinInstaller.App.Core;
using IWinInstaller.App.Shell.Palette;

namespace IWinInstaller.App.Modules.Shortcuts
{
    /// <summary>Un atajo a un ajuste o herramienta de Windows. Solo abre lo que ya trae Windows: no cambia nada por sí mismo.</summary>
    public sealed class QuickLink
    {
        public QuickLink(string id, string group, string title, string description, string target, string arguments = "", string keywords = "")
        {
            Id = id; Group = group; Title = title; Description = description; Target = target; Arguments = arguments ?? ""; Keywords = keywords ?? "";
        }
        public string Id { get; private set; }
        public string Group { get; private set; }
        public string Title { get; private set; }
        public string Description { get; private set; }
        /// <summary>URI «ms-settings:», consola .msc, panel .cpl o ejecutable de Windows.</summary>
        public string Target { get; private set; }
        public string Arguments { get; private set; }
        public string Keywords { get; private set; }
    }

    /// <summary>Un grupo de atajos para la vista.</summary>
    public sealed class QuickLinkGroup
    {
        public QuickLinkGroup(string name, List<QuickLink> links) { Name = name; Links = links; }
        public string Name { get; private set; }
        public List<QuickLink> Links { get; private set; }
    }

    /// <summary>Catálogo fijo de atajos de Windows. Los destinos salen de esta lista, nunca de texto del usuario.</summary>
    public static class QuickLinks
    {
        private static readonly List<QuickLink> Items = new List<QuickLink>
        {
            // Pantalla y sonido
            new QuickLink("display", "Pantalla y sonido", "Pantalla", "Resolución, escala, HDR y varias pantallas.", "ms-settings:display", "", "monitor resolucion escala hdr brillo"),
            new QuickLink("nightlight", "Pantalla y sonido", "Luz nocturna", "Tonos cálidos por la noche.", "ms-settings:nightlight", "", "filtro azul calido noche"),
            new QuickLink("graphics", "Pantalla y sonido", "Gráficos por aplicación", "Elige la gráfica de cada juego o app.", "ms-settings:display-advancedgraphics", "", "gpu grafica dedicada rendimiento juego"),
            new QuickLink("sound", "Pantalla y sonido", "Sonido", "Salida, entrada y volumen.", "ms-settings:sound", "", "audio altavoces microfono volumen"),
            new QuickLink("volumemixer", "Pantalla y sonido", "Mezclador de volumen", "Volumen y dispositivo de cada app.", "ms-settings:apps-volume", "", "audio volumen aplicacion"),
            new QuickLink("soundpanel", "Pantalla y sonido", "Panel de sonido clásico", "Dispositivos de reproducción y grabación.", "mmsys.cpl", "", "audio grabacion reproduccion mejoras"),
            // Red
            new QuickLink("network", "Red e Internet", "Estado de la red", "Conexión actual y uso de datos.", "ms-settings:network-status", "", "internet conexion ip"),
            new QuickLink("wifi", "Red e Internet", "Wi-Fi", "Redes disponibles y conocidas.", "ms-settings:network-wifi", "", "wifi inalambrica"),
            new QuickLink("ethernet", "Red e Internet", "Ethernet", "Conexión por cable.", "ms-settings:network-ethernet", "", "cable lan"),
            new QuickLink("vpn", "Red e Internet", "VPN", "Conexiones VPN.", "ms-settings:network-vpn", "", "vpn tunel"),
            new QuickLink("proxy", "Red e Internet", "Proxy", "Servidor proxy del sistema.", "ms-settings:network-proxy", "", "proxy"),
            new QuickLink("adapters", "Red e Internet", "Adaptadores de red", "Conexiones de red clásicas (IP, DNS).", "ncpa.cpl", "", "ip dns adaptador ipv4"),
            new QuickLink("firewall", "Red e Internet", "Firewall de Windows", "Estado y reglas del cortafuegos.", "firewall.cpl", "", "cortafuegos puertos"),
            // Dispositivos
            new QuickLink("bluetooth", "Dispositivos", "Bluetooth y dispositivos", "Emparejar y quitar dispositivos.", "ms-settings:bluetooth", "", "bluetooth emparejar auriculares mando"),
            new QuickLink("printers", "Dispositivos", "Impresoras y escáneres", "Añadir o quitar impresoras.", "ms-settings:printers", "", "impresora escaner"),
            new QuickLink("mouse", "Dispositivos", "Ratón", "Velocidad, botones y rueda.", "ms-settings:mousetouchpad", "", "raton puntero velocidad"),
            new QuickLink("mousepanel", "Dispositivos", "Ratón (panel clásico)", "Precisión del puntero y aceleración.", "main.cpl", "", "aceleracion puntero precision"),
            new QuickLink("devices", "Dispositivos", "Administrador de dispositivos", "Controladores y hardware.", "devmgmt.msc", "", "drivers controladores hardware"),
            new QuickLink("usb", "Dispositivos", "USB", "Avisos y ahorro de energía de USB.", "ms-settings:usb", "", "usb"),
            // Personalización
            new QuickLink("personalization", "Personalización", "Personalización", "Fondo, colores y temas.", "ms-settings:personalization", "", "tema aspecto"),
            new QuickLink("colors", "Personalización", "Colores y modo oscuro", "Modo claro u oscuro y color de énfasis.", "ms-settings:colors", "", "oscuro claro acento"),
            new QuickLink("background", "Personalización", "Fondo de escritorio", "Imagen, color o presentación.", "ms-settings:personalization-background", "", "fondo wallpaper"),
            new QuickLink("lockscreen", "Personalización", "Pantalla de bloqueo", "Imagen y avisos al bloquear.", "ms-settings:lockscreen", "", "bloqueo"),
            new QuickLink("taskbar", "Personalización", "Barra de tareas", "Iconos, alineación y comportamiento.", "ms-settings:taskbar", "", "barra tareas iconos bandeja"),
            new QuickLink("start", "Personalización", "Menú Inicio", "Qué se muestra en Inicio.", "ms-settings:personalization-start", "", "inicio recomendados"),
            new QuickLink("fonts", "Personalización", "Fuentes", "Tipos de letra instalados.", "ms-settings:fonts", "", "tipografia letra"),
            // Aplicaciones
            new QuickLink("apps", "Aplicaciones", "Aplicaciones instaladas", "Desinstalar o reparar.", "ms-settings:appsfeatures", "", "desinstalar programas"),
            new QuickLink("defaultapps", "Aplicaciones", "Aplicaciones predeterminadas", "Navegador, correo y tipos de archivo.", "ms-settings:defaultapps", "", "navegador predeterminado abrir con"),
            new QuickLink("startupapps", "Aplicaciones", "Aplicaciones de arranque", "Qué se abre al iniciar sesión.", "ms-settings:startupapps", "", "inicio arranque autoarranque"),
            new QuickLink("optionalfeatures", "Aplicaciones", "Características opcionales", "Componentes adicionales de Windows.", "ms-settings:optionalfeatures", "", "caracteristicas opcionales"),
            new QuickLink("windowsfeatures", "Aplicaciones", "Características de Windows", "Hyper-V, WSL, .NET 3.5 y similares.", "optionalfeatures.exe", "", "hyper-v wsl sandbox net"),
            new QuickLink("programs", "Aplicaciones", "Programas y características", "Lista clásica de programas.", "appwiz.cpl", "", "desinstalar clasico"),
            // Cuentas y privacidad
            new QuickLink("account", "Cuentas y privacidad", "Tu cuenta", "Cuenta de Microsoft o local.", "ms-settings:yourinfo", "", "usuario cuenta microsoft"),
            new QuickLink("signin", "Cuentas y privacidad", "Opciones de inicio de sesión", "PIN, huella, cara y contraseña.", "ms-settings:signinoptions", "", "pin hello contrasena huella"),
            new QuickLink("privacy", "Cuentas y privacidad", "Privacidad", "Permisos generales de Windows.", "ms-settings:privacy", "", "privacidad diagnostico publicidad"),
            new QuickLink("camera", "Cuentas y privacidad", "Permiso de cámara", "Qué apps usan la cámara.", "ms-settings:privacy-webcam", "", "webcam camara"),
            new QuickLink("microphone", "Cuentas y privacidad", "Permiso de micrófono", "Qué apps usan el micrófono.", "ms-settings:privacy-microphone", "", "micro microfono"),
            new QuickLink("location", "Cuentas y privacidad", "Ubicación", "Qué apps usan tu ubicación.", "ms-settings:privacy-location", "", "gps ubicacion"),
            new QuickLink("credentials", "Cuentas y privacidad", "Administrador de credenciales", "Contraseñas guardadas por Windows.", "control.exe", "/name Microsoft.CredentialManager", "contrasenas guardadas credenciales"),
            // Sistema
            new QuickLink("about", "Sistema", "Información del equipo", "Nombre, procesador, memoria y edición.", "ms-settings:about", "", "especificaciones nombre equipo version"),
            new QuickLink("storage", "Sistema", "Almacenamiento", "Qué ocupa espacio y Sensor de almacenamiento.", "ms-settings:storagesense", "", "espacio disco sensor"),
            new QuickLink("power", "Sistema", "Energía y batería", "Suspensión, modo de energía y batería.", "ms-settings:powersleep", "", "suspension bateria energia"),
            new QuickLink("powerplans", "Sistema", "Planes de energía", "Planes clásicos y botones de encendido.", "powercfg.cpl", "", "plan alto rendimiento tapa boton"),
            new QuickLink("notifications", "Sistema", "Notificaciones", "Avisos y No molestar.", "ms-settings:notifications", "", "avisos no molestar concentracion"),
            new QuickLink("multitasking", "Sistema", "Multitarea", "Acoplar ventanas y escritorios.", "ms-settings:multitasking", "", "snap acoplar escritorios alt tab"),
            new QuickLink("clipboard", "Sistema", "Portapapeles", "Historial (Win + V) y sincronización.", "ms-settings:clipboard", "", "copiar pegar historial"),
            new QuickLink("datetime", "Sistema", "Fecha y hora", "Zona horaria y sincronización.", "ms-settings:dateandtime", "", "hora zona horaria reloj"),
            new QuickLink("language", "Sistema", "Idioma y región", "Idioma de Windows y formato regional.", "ms-settings:regionlanguage", "", "idioma teclado region formato"),
            new QuickLink("typing", "Sistema", "Escritura y teclado", "Autocorrección y distribución.", "ms-settings:typing", "", "teclado escritura"),
            new QuickLink("gamemode", "Sistema", "Modo de juego", "Prioriza el juego en primer plano.", "ms-settings:gaming-gamemode", "", "juegos gaming rendimiento"),
            new QuickLink("gamebar", "Sistema", "Game Bar y capturas", "Grabación y atajos de Xbox Game Bar.", "ms-settings:gaming-gamebar", "", "xbox grabar captura"),
            new QuickLink("accessibility", "Sistema", "Accesibilidad", "Tamaño del texto, contraste y lector.", "ms-settings:easeofaccess", "", "texto grande contraste narrador lupa"),
            new QuickLink("remotedesktop", "Sistema", "Escritorio remoto", "Permitir conexiones a este PC.", "ms-settings:remotedesktop", "", "rdp remoto"),
            new QuickLink("developers", "Sistema", "Para desarrolladores", "Modo de desarrollador y terminal.", "ms-settings:developers", "", "desarrollador sudo terminal"),
            new QuickLink("activation", "Sistema", "Activación", "Estado de la licencia de Windows.", "ms-settings:activation", "", "licencia clave activar"),
            new QuickLink("sysprops", "Sistema", "Propiedades del sistema", "Variables de entorno, rendimiento y nombre.", "sysdm.cpl", "", "variables entorno path rendimiento visual dominio"),
            new QuickLink("controlpanel", "Sistema", "Panel de control", "El panel clásico completo.", "control.exe", "", "panel control clasico"),
            // Actualización y recuperación
            new QuickLink("windowsupdate", "Actualización y recuperación", "Windows Update", "Buscar e instalar actualizaciones.", "ms-settings:windowsupdate", "", "actualizar parches"),
            new QuickLink("updatehistory", "Actualización y recuperación", "Historial de actualizaciones", "Qué se instaló y desinstalar.", "ms-settings:windowsupdate-history", "", "historial desinstalar actualizacion"),
            new QuickLink("recovery", "Actualización y recuperación", "Recuperación", "Restablecer el PC e inicio avanzado.", "ms-settings:recovery", "", "restablecer formatear inicio avanzado"),
            new QuickLink("troubleshoot", "Actualización y recuperación", "Solucionar problemas", "Asistentes de Windows.", "ms-settings:troubleshoot", "", "solucionador problemas"),
            new QuickLink("backup", "Actualización y recuperación", "Copia de seguridad", "Copia de Windows y sincronización.", "ms-settings:backup", "", "backup copia"),
            new QuickLink("restore", "Actualización y recuperación", "Restaurar sistema", "Volver a un punto de restauración.", "rstrui.exe", "", "punto restauracion volver atras"),
            new QuickLink("protection", "Actualización y recuperación", "Protección del sistema", "Crear puntos de restauración.", "SystemPropertiesProtection.exe", "", "crear punto restauracion"),
            new QuickLink("security", "Actualización y recuperación", "Seguridad de Windows", "Antivirus, firewall y protección.", "ms-settings:windowsdefender", "", "defender antivirus"),
            // Herramientas
            new QuickLink("taskmgr", "Herramientas", "Administrador de tareas", "Procesos, rendimiento e inicio.", "taskmgr.exe", "", "procesos cerrar colgado rendimiento"),
            new QuickLink("resmon", "Herramientas", "Monitor de recursos", "Detalle de disco, red, CPU y memoria.", "resmon.exe", "", "recursos disco red uso"),
            new QuickLink("reliability", "Herramientas", "Monitor de confiabilidad", "Historial de fallos y cambios.", "perfmon.exe", "/rel", "fallos errores cuelgues historial"),
            new QuickLink("eventvwr", "Herramientas", "Visor de eventos", "Registros de Windows.", "eventvwr.msc", "", "eventos registros errores log"),
            new QuickLink("services", "Herramientas", "Servicios", "Iniciar, detener y configurar servicios.", "services.msc", "", "servicios"),
            new QuickLink("taskschd", "Herramientas", "Programador de tareas", "Tareas automáticas.", "taskschd.msc", "", "tareas programadas"),
            new QuickLink("diskmgmt", "Herramientas", "Administración de discos", "Particiones, letras y formato.", "diskmgmt.msc", "", "particion formatear letra unidad"),
            new QuickLink("compmgmt", "Herramientas", "Administración de equipos", "Consola con todas las herramientas.", "compmgmt.msc", "", "usuarios locales grupos consola"),
            new QuickLink("msinfo", "Herramientas", "Información del sistema", "Inventario completo de hardware.", "msinfo32.exe", "", "hardware placa bios inventario"),
            new QuickLink("dxdiag", "Herramientas", "Diagnóstico de DirectX", "Gráfica, sonido y controladores.", "dxdiag.exe", "", "directx grafica drivers"),
            new QuickLink("msconfig", "Herramientas", "Configuración del sistema", "Arranque limpio y modo seguro.", "msconfig.exe", "", "arranque modo seguro"),
            new QuickLink("memtest", "Herramientas", "Diagnóstico de memoria", "Comprueba la RAM en el próximo reinicio.", "mdsched.exe", "", "ram memoria prueba"),
            new QuickLink("cleanmgr", "Herramientas", "Liberador de espacio clásico", "Limpieza de disco de Windows.", "cleanmgr.exe", "", "limpiar disco"),
            new QuickLink("regedit", "Herramientas", "Editor del Registro", "Solo si sabes lo que cambias.", "regedit.exe", "", "registro regedit"),
            new QuickLink("winver", "Herramientas", "Versión de Windows", "Edición y compilación exactas.", "winver.exe", "", "version compilacion build"),
            new QuickLink("godmode", "Herramientas", "Todas las tareas", "Lista completa de ajustes del Panel de control.", "explorer.exe", "shell:::{ED7BA470-8E54-465E-825C-99712043E01C}", "god mode modo dios todos ajustes")
        };

        public static IReadOnlyList<QuickLink> All { get { return Items; } }

        /// <summary>Atajos que también aparecen en el menú de la bandeja.</summary>
        public static readonly string[] TrayIds = { "taskmgr", "display", "sound", "bluetooth", "network", "windowsupdate", "apps", "devices" };

        public static QuickLink Find(string id) { return Items.FirstOrDefault(link => String.Equals(link.Id, id, StringComparison.Ordinal)); }

        public static List<QuickLinkGroup> Groups(string search)
        {
            var words = PaletteSearch.Normalize(search).Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            return Items
                .Where(link => words.Length == 0 || words.All(word => PaletteSearch.Normalize(link.Title + " " + link.Description + " " + link.Group + " " + link.Keywords).Contains(word)))
                .GroupBy(link => link.Group)
                .Select(group => new QuickLinkGroup(group.Key, group.ToList()))
                .ToList();
        }

        /// <summary>Solo destinos conocidos de Windows: «ms-settings:», consolas .msc, paneles .cpl y ejecutables sin ruta.</summary>
        public static bool IsSafeTarget(string target)
        {
            if (String.IsNullOrWhiteSpace(target)) return false;
            if (target.StartsWith("ms-settings:", StringComparison.Ordinal)) return target.Length > "ms-settings:".Length && target.IndexOfAny(new[] { ' ', '"', '&', '|' }) < 0;
            if (target.IndexOfAny(new[] { '\\', '/', ':', ' ', '"', '&', '|' }) >= 0) return false;
            return target.EndsWith(".msc", StringComparison.OrdinalIgnoreCase) || target.EndsWith(".cpl", StringComparison.OrdinalIgnoreCase) || target.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>Abre el atajo. Devuelve el motivo si Windows no pudo abrirlo (p. ej. no existe en esta edición).</summary>
        public static string Open(QuickLink link)
        {
            if (link == null || !IsSafeTarget(link.Target)) return "Atajo no válido.";
            try
            {
                Process.Start(new ProcessStartInfo(link.Target, link.Arguments) { UseShellExecute = true });
                return "";
            }
            catch (System.ComponentModel.Win32Exception e) { return "No se pudo abrir «" + link.Title + "»: " + e.Message; }
            catch (InvalidOperationException e) { return "No se pudo abrir «" + link.Title + "»: " + e.Message; }
            catch (System.IO.FileNotFoundException) { return "«" + link.Title + "» no está disponible en esta edición de Windows."; }
        }
    }

    public sealed class QuickLinksViewModel : ObservableObject
    {
        private string _search = "", _message = "";
        private List<QuickLinkGroup> _groups = QuickLinks.Groups("");

        public QuickLinksViewModel()
        {
            OpenCommand = new RelayCommand(parameter => Message = QuickLinks.Open(parameter as QuickLink));
        }

        public RelayCommand OpenCommand { get; private set; }
        public List<QuickLinkGroup> Groups { get { return _groups; } private set { Set(ref _groups, value); OnPropertyChanged("IsEmpty"); } }
        public bool IsEmpty { get { return _groups.Count == 0; } }
        public string Message { get { return _message; } private set { Set(ref _message, value ?? ""); } }
        public string Search
        {
            get { return _search; }
            set { if (Set(ref _search, value ?? "")) Groups = QuickLinks.Groups(_search); }
        }
    }
}
