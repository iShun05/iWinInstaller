# iWinInstaller — Autoinstalador con interfaz gráfica para Windows 10 / 11
# Lee el catálogo de apps.json (y los perfiles de profiles.json); añadir una app = una entrada nueva.
# Uso:
#   Iniciar.bat                                   ventana
#   iWinInstaller.ps1 -Check [-Json]              informe ✓/✗ en consola (o JSON, ver docs/cli.md)
#   iWinInstaller.ps1 -Silent [-Perfil Gaming]    instala un perfil sin ventana
#   iWinInstaller.ps1 -Update [-Scheduled]        actualiza las aplicaciones instaladas (respeta exclusiones)
#   iWinInstaller.ps1 -Updates -List [-Json]      lista las actualizaciones disponibles
#   iWinInstaller.ps1 -Updates -Exclude <id>      mantiene una app en su versión (-Include la vuelve a actualizar)
#   iWinInstaller.ps1 -Status [-Json]             estado del PC (tarjetas del motor)
#   iWinInstaller.ps1 -Silent -Perfil mi.iwin.json instala un perfil exportado desde la ventana
param(
    [switch]$Check,
    [switch]$Silent,
    [switch]$Update,
    [string]$Perfil = 'Todo',
    [string]$WorkerMode,
    [string]$PlanFile,
    [string]$ResultFile,
    [string]$SharedLog,
    [switch]$UpgradePackages,
    [switch]$RemovePackages,
    [switch]$Resume,
    [switch]$AutoUpdate,
    [switch]$Json,
    # Actualizaciones (v4.5): -Updates -List | -Exclude <id> | -Include <id>; -Update -Scheduled; -Status
    [switch]$Updates,
    [switch]$List,
    [string]$Exclude,
    [string]$Include,
    [switch]$Scheduled,
    [switch]$Status,
    # Contrato interfaz ↔ motor (specs/001-centro-de-control/contracts/engine.md)
    [string]$EngineCommand,
    [string]$EngineRequest,
    [string]$EngineResponse,
    [string]$EngineEvents
)
$ProgressPreference = 'SilentlyContinue'
# Salida de herramientas en UTF-8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'

$Version = 'v4.7'
$Instagram = 'https://www.instagram.com/_shun._05/'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
# PowerShell 5.1 devuelve un array JSON como un solo objeto: «ForEach-Object { $_ }» lo desenrolla
$Apps = @(Get-Content (Join-Path $Root 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
$Profiles = Get-Content (Join-Path $Root 'profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ReleaseApi = 'https://api.github.com/repos/iShun05/iWinInstaller/releases/latest'
$UI = -not ($Check -or $Silent -or $Update -or $WorkerMode -or $Resume -or $AutoUpdate -or $EngineCommand -or $Updates -or $Status)

# Registro en archivo: %LOCALAPPDATA%\iWinInstaller\iWinInstaller_AAAA-MM-DD.log
$LogDir = Join-Path $env:LOCALAPPDATA 'iWinInstaller'
New-Item $LogDir -ItemType Directory -Force | Out-Null
$LogFile = Join-Path $LogDir ('iWinInstaller_{0:yyyy-MM-dd_HH-mm-ss-fff}.log' -f (Get-Date))
if ($WorkerMode -and $SharedLog) { $LogFile = $SharedLog }

. (Join-Path $Root 'lifecycle.ps1')

# Motor: los archivos de src/engine se cargan en orden y comparten el ámbito del script.
$EngineFiles = @('01-Core.ps1', '02-Packages.ps1', '03-System.ps1', '04-Remote.ps1', '05-Rgb.ps1', '06-Tweaks.ps1', '07-Profiles.ps1', '08-Batch.ps1', '09-Contract.ps1', '10-Updates.ps1', '11-Status.ps1', '12-Install.ps1', '13-Tools.ps1')
foreach ($engineFile in $EngineFiles) {
    $enginePath = Join-Path $Root "src\engine\$engineFile"
    if (-not (Test-Path -LiteralPath $enginePath)) { throw "Falta un archivo del motor: $engineFile. Ejecuta de nuevo iWinInstaller-Setup.exe." }
    . $enginePath
}

if ($EngineCommand) {
    exit (Invoke-IwinEngineCommand $EngineCommand $EngineRequest $EngineResponse $EngineEvents)
}

if ($WorkerMode) {
    Write-WorkerEvent @{started=$true; pid=$PID}
    try {
        if ($WorkerMode -notin @('machine', 'user')) { throw 'Lote no valido.' }
        if ($WorkerMode -eq 'machine' -and -not (Test-Administrator)) { throw 'El lote del sistema necesita administrador.' }
        if ($WorkerMode -eq 'user' -and (Test-Administrator)) { throw 'El lote por usuario debe ejecutarse sin elevacion.' }
        $ids = @(Get-Content $PlanFile -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
        $selection = @($Apps | Where-Object { $ids -contains $_.id })
        if ($selection.Count -ne @($ids | Select-Object -Unique).Count -or ($selection | Where-Object { $_.type -notin @('winget', 'wingetall', 'tweak') -or (Get-InstallContext $_) -ne $WorkerMode })) { throw 'El lote contiene operaciones no permitidas.' }
        $report = { param($app,$ok) Write-WorkerEvent @{id=$app.id; ok=[bool]$ok; code=$script:LastInstallCode} }
        $fail = if ($RemovePackages) { @(Invoke-Uninstall $selection $report) } else { @(Invoke-Install $selection $report) }
        $exitCode = $fail.Count
    } catch { Write-Log "Error del lote: $($_.Exception.Message)"; $exitCode=1 }
    Write-WorkerEvent @{done=$true; exitCode=$exitCode}
    exit $exitCode
}

if ($Resume) {
    $pending=Get-IwinPendingBatches | Select-Object -First 1
    if (-not $pending) { Write-Log 'No hay lotes pendientes.'; exit 0 }
    $fail=@(Resume-IwinBatch $pending $null)
    exit $fail.Count
}

if ($AutoUpdate) {
    try {
        # Como SYSTEM (tarea de v4.3+) la existencia de la tarea ya es el consentimiento del usuario;
        # con el usuario se sigue respetando su preferencia guardada.
        if(-not (Test-IwinSystemAccount)){
            $prefsPath=Join-Path $LogDir 'preferencias.json'
            if(-not (Test-Path $prefsPath)){exit 0}
            $automatic=(Get-Content $prefsPath -Raw -Encoding UTF8 | ConvertFrom-Json).autoUpdate
            if($automatic -isnot [bool] -or -not $automatic){exit 0}
        }
        Clear-IwinUpdateDownloads
        if(Test-IwinAppOpen){Write-Log 'Actualización pospuesta: iWinInstaller está abierto.';exit 0}
        if(Update-Self){exit 0}else{exit 1}
    }catch{Write-Log "Actualización pendiente: $($_.Exception.Message)";exit 1}
}

# ---------- Modos sin ventana ----------
if ($Check) {
    # Con -Json la salida es un documento estable para scripts (contrato en docs/cli.md)
    if (-not $Json) { Write-Host "iWinInstaller $Version · comprobación en $env:COMPUTERNAME" }
    $wingetReady = Test-Cmd winget
    if (-not $wingetReady -and -not $Json) { Write-Host '✗ Falta winget (instala «App Installer» desde Microsoft Store)' }
    Update-WingetCache
    $missing = @()
    $items = @()
    $group = ''
    foreach ($app in $Apps) {
        $ok = Test-AppInstalled $app
        $items += [ordered]@{ id = $app.id; name = $app.name; section = $app.section; group = $app.group; installed = [bool]$ok; optional = [bool](Test-Optional $app) }
        # Del catálogo ampliado solo se listan las que están instaladas
        if ($app.extra -and -not $ok) { continue }
        if (-not $ok -and -not $app.optin) { $missing += $app.name }
        if ($Json) { continue }
        $label = if ($app.subgroup) { "$($app.group) › $($app.subgroup)" } else { $app.group }
        if ($label -ne $group) { $group = $label; Write-Host "`n[$group]" }
        if ($ok) { Write-Host "✓ $($app.name)" }
        elseif ($app.optin) { Write-Host "– $($app.name) (opcional, no instalado)" }
        else { Write-Host "✗ $($app.name)" }
    }
    $total = @($Apps | Where-Object { -not (Test-Optional $_) }).Count
    if ($Json) {
        [Console]::Out.Write((ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
            contract = 1; version = $Version; winget = [bool]$wingetReady; total = $total; missing = $missing.Count; items = $items })))
    } else {
        Write-Host ''
        if ($missing) { Write-Host "Faltan $($missing.Count) de ${total}: $($missing -join ', ')" } else { Write-Host "Todo listo ($total/$total)." }
    }
    exit $missing.Count
}

if ($Update -and $Scheduled) {
    # Tarea programada: todo lo que ofrece WinGet salvo excluidas y asistentes; no reinicia ni se actualiza a sí misma
    Write-Log "Actualización programada (iWinInstaller $Version)"
    if (-not (Ensure-Winget)) { exit 1 }
    $updateList = Get-IwinUpdateList
    if ($null -eq $updateList) { Write-Log 'No se pudieron comprobar las actualizaciones.'; exit 1 }
    $results = Invoke-IwinUpgradeIds @($updateList | Where-Object { -not $_.excluded } | ForEach-Object { $_.id }) -Scheduled
    $failed = @($results.Keys | Where-Object { $results[$_] -eq 'failed' })
    Write-Log "Actualización programada terminada: $(@($results.Keys).Count - $failed.Count) correctas u omitidas, $($failed.Count) con fallo."
    exit $failed.Count
}

if ($Update) {
    if (Invoke-Update) { exit 0 } else { exit 1 }
}

if ($Updates) {
    if ($Exclude) { Set-IwinExclusion $Exclude $true; Write-Host "$Exclude se mantiene en su versión."; exit 0 }
    if ($Include) { Set-IwinExclusion $Include $false; Write-Host "$Include vuelve a actualizarse."; exit 0 }
    $updateList = Get-IwinUpdateList
    if ($null -eq $updateList) { if (-not $Json) { Write-Host 'No se pudieron comprobar las actualizaciones (WinGet no respondió).' }; exit 1 }
    if ($Json) { [Console]::Out.Write((ConvertTo-Json -Depth 5 -InputObject ([ordered]@{ contract = 1; version = $Version; items = @($updateList); schedule = (Get-IwinAppUpdateSchedule) }))); exit 0 }
    if (-not @($updateList).Count) { Write-Host 'Todo al día.'; exit 0 }
    foreach ($item in $updateList) { Write-Host ("{0} {1}  {2} → {3}{4}" -f $(if ($item.excluded) { '–' } else { '↑' }), $item.name, $item.installedVersion, $item.availableVersion, $(if ($item.excluded) { '  (excluida)' } else { '' })) }
    exit 0
}

if ($Status) {
    $response = & $IwinEngineCommands['status.collect'] ([pscustomobject]@{ contract = 1 })
    if ($Json) { [Console]::Out.Write((ConvertTo-Json -Depth 5 -InputObject ([ordered]@{ contract = 1; version = $Version; cards = @($response.cards) }))); exit 0 }
    foreach ($card in $response.cards) { Write-Host ("{0} {1}{2}" -f $(switch ($card.state) { 'ok' { '✓' } 'attention' { '!' } default { '?' } }), $card.summary, $(if ($card.reason) { " · $($card.reason)" } else { '' })) }
    exit @($response.cards | Where-Object { $_.state -ne 'ok' }).Count
}

if ($Silent) {
    try { $sel = @(Get-ProfileApps $Perfil) } catch { Write-Log "No se pudo leer el perfil: $($_.Exception.Message)"; exit 1 }
    if (-not $sel) { Write-Log "Perfil desconocido o vacío: $Perfil (disponibles: $((@($Profiles.PSObject.Properties.Name) + @((Get-CustomProfiles).Keys)) -join ', '), o la ruta de un .iwin.json)"; exit 1 }
    if (-not (Ensure-Winget)) { exit 1 }
    Write-Log "Modo sin ventana · perfil $Perfil"
    $fail = @(Invoke-Install $sel $null)
    exit $fail.Count
}

# ---------- Ventana (WPF) ----------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# Fila del catálogo con avisos de cambio para que la lista se actualice sola
if (-not ('IwinApp' -as [type])) {
    $refs = @([Windows.Media.ImageSource], [Windows.Threading.Dispatcher], [System.Xaml.XamlType], [System.Net.WebClient]) | ForEach-Object { $_.Assembly.Location } | Select-Object -Unique
    Add-Type -Language CSharp -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
public class IwinApp : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    void N(string p) { PropertyChangedEventHandler h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(p)); }
    public string Id { get; set; }
    public string Name { get; set; }
    public string Desc { get; set; }
    public string Group { get; set; }
    public string Section { get; set; }
    // Subsección: apps que hacen lo mismo, con su comparativa («Cuál elegir») en la cabecera
    public string Subgroup { get; set; }
    string subgroupNote = ""; public string SubgroupNote { get { return subgroupNote; } set { subgroupNote = value ?? ""; } }
    string compare = ""; public string Compare { get { return compare; } set { compare = value ?? ""; } }
    public string GroupLabel { get { return Section + " · " + Group + (string.IsNullOrEmpty(Subgroup) ? "" : " › " + Subgroup); } }
    public string Initials { get; set; }
    public string IconSpec { get; set; }
    public string Glyph { get; set; }
    public bool HasGlyph { get { return !string.IsNullOrEmpty(Glyph); } }
    ImageSource im; public ImageSource Image { get { return im; } set { im = value; N("Image"); N("HasImage"); } }
    public bool HasImage { get { return im != null; } }
    public string Search { get; set; }
    public bool Optional { get; set; }
    bool c; public bool Checked { get { return c; } set { if (c != value) { c = value; N("Checked"); } } }
    bool i; public bool Installed { get { return i; } set { i = value; N("Installed"); N("Configuration"); N("ShowUninstall"); N("ShowOpen"); } }
    // Acciones por fila: desinstalar (o deshacer un ajuste) y abrir, solo cuando está instalada
    public bool CanUninstall { get; set; }
    public bool CanOpen { get; set; }
    // Herramienta de línea de comandos: lleva la etiqueta «Terminal» y se abre en una consola
    public bool IsCli { get; set; }
    public bool OpensInConsole { get; set; }
    public string OpenLabel { get { return OpensInConsole ? "Abrir en terminal" : "Abrir"; } }
    public bool IsTweak { get; set; }
    public string UninstallLabel { get { return IsTweak ? "Deshacer" : "Desinstalar"; } }
    bool previousState; public bool HasPreviousState { get { return previousState; } set { previousState=value;N("HasPreviousState");N("ShowUninstall"); } }
    public bool ShowUninstall { get { return (i || previousState) && CanUninstall; } }
    public bool ShowOpen { get { return i && CanOpen; } }
    public bool NeedsConfiguration { get; set; }
    bool configured; public bool Configured { get { return configured; } set { configured = value; N("Configured"); N("Configuration"); } }
    public string Configuration { get { return !Installed || !NeedsConfiguration ? "" : configured ? "Configuración confirmada por ti" : "Después de instalar · pasos pendientes"; } }
    string s = ""; public string Status { get { return s; } set { s = value; N("Status"); } }
    string k = "none"; public string StatusKind { get { return k; } set { k = value; N("StatusKind"); } }
}
// Iconos de las apps: favicon de su web (caché en disco) o un símbolo de Segoe para los ajustes
public static class IwinIcons {
    public static int Loaded;
    static ImageSource Read(string f) {
        try {
            BitmapImage b = new BitmapImage();
            b.BeginInit(); b.CacheOption = BitmapCacheOption.OnLoad; b.DecodePixelWidth = 64;
            b.StreamSource = new MemoryStream(File.ReadAllBytes(f)); b.EndInit(); b.Freeze();
            return b;
        } catch { return null; }
    }
    static byte[] Get(string url) {
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
        request.Timeout = 5000; request.ReadWriteTimeout = 5000;
        request.UserAgent = "iWinInstaller";
        using (WebResponse response = request.GetResponse())
        using (Stream input = response.GetResponseStream())
        using (MemoryStream output = new MemoryStream()) {
            byte[] buffer = new byte[8192]; int count;
            while ((count = input.Read(buffer, 0, buffer.Length)) > 0) {
                if (output.Length + count > 1048576) return null;
                output.Write(buffer, 0, count);
            }
            return output.ToArray();
        }
    }
    public static void Start(IEnumerable<IwinApp> apps, string dir, Dispatcher ui) {
        try { ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; } catch { }
        Directory.CreateDirectory(dir);
        Dictionary<string, List<IwinApp>> bySite = new Dictionary<string, List<IwinApp>>();
        foreach (IwinApp a in apps) {
            if (string.IsNullOrEmpty(a.IconSpec) || a.IconSpec.StartsWith("glyph:")) continue;
            if (!bySite.ContainsKey(a.IconSpec)) bySite[a.IconSpec] = new List<IwinApp>();
            bySite[a.IconSpec].Add(a);
        }
        List<KeyValuePair<string, List<IwinApp>>> sites = new List<KeyValuePair<string, List<IwinApp>>>(bySite);
        // Cuatro descargas como maximo; un icono nunca debe terminar el proceso de la app.
        for (int worker = 0; worker < Math.Min(4, sites.Count); worker++) {
            int lane = worker;
            ThreadPool.QueueUserWorkItem(delegate {
                for (int index = lane; index < sites.Count; index += 4) {
                    if (ui.HasShutdownStarted || ui.HasShutdownFinished) return;
                    try {
                        string site = sites[index].Key; List<IwinApp> list = sites[index].Value;
                        string name = site.Replace("/", "_").Replace(":", "_");
                        string f = Path.Combine(dir, name + ".png"), none = Path.Combine(dir, name + ".none");
                        if (!File.Exists(f) && !(File.Exists(none) && File.GetLastWriteTime(none) > DateTime.Now.AddDays(-7))) {
                            byte[] data = null;
                            string host = site.Split('/')[0];
                            foreach (string url in new[] { "https://www.google.com/s2/favicons?sz=64&domain_url=https://" + site, "https://icons.duckduckgo.com/ip3/" + host + ".ico" }) {
                                try { data = Get(url); if (data != null && data.Length > 0) break; } catch { data = null; }
                            }
                            if (data != null && data.Length > 0) File.WriteAllBytes(f, data); else File.WriteAllText(none, "");
                        }
                        ImageSource img = File.Exists(f) ? Read(f) : null;
                        if (img == null || ui.HasShutdownStarted) continue;
                        Interlocked.Add(ref Loaded, list.Count);
                        ui.BeginInvoke(new Action(delegate { try { if (!ui.HasShutdownStarted) foreach (IwinApp app in list) app.Image = img; } catch { } }));
                    } catch { /* El icono es opcional: se conservan las iniciales. */ }
                }
            });
        }
    }
}
public static class IwinDwm {
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
    // Barra de título oscura (Windows 10 20H1+ y 11)
    public static void Dark(IntPtr h) { int on = 1; DwmSetWindowAttribute(h, 20, ref on, 4); }
}
// Resolución y frecuencia de cada monitor (user32), sin abrir Configuración
public static class IwinDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, int i, ref DISPLAY_DEVICE d, int flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE m);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE m, IntPtr hwnd, int flags, IntPtr param);
    const int Current = -1, AttachedToDesktop = 1, Primary = 4;
    const int PelsWidth = 0x80000, PelsHeight = 0x100000, Frequency = 0x400000;
    static DEVMODE New() { DEVMODE m = new DEVMODE(); m.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return m; }
    // Monitores activos: «\\.\DISPLAY1|Nombre del monitor|1» (1 = principal)
    public static string[] Monitors() {
        List<string> list = new List<string>();
        DISPLAY_DEVICE d = new DISPLAY_DEVICE(); d.cb = Marshal.SizeOf(d);
        for (int i = 0; EnumDisplayDevices(null, i, ref d, 0); i++) {
            if ((d.StateFlags & AttachedToDesktop) != 0) {
                string name = d.DeviceString;
                DISPLAY_DEVICE mon = new DISPLAY_DEVICE(); mon.cb = Marshal.SizeOf(mon);
                if (EnumDisplayDevices(d.DeviceName, 0, ref mon, 0) && !string.IsNullOrEmpty(mon.DeviceString)) name = mon.DeviceString;
                list.Add(d.DeviceName + "|" + name + "|" + ((d.StateFlags & Primary) != 0 ? "1" : "0"));
            }
            d = new DISPLAY_DEVICE(); d.cb = Marshal.SizeOf(d);
        }
        return list.ToArray();
    }
    // Modo actual: { ancho, alto, Hz }
    public static int[] CurrentMode(string dev) {
        DEVMODE m = New();
        if (!EnumDisplaySettings(dev, Current, ref m)) return null;
        return new int[] { m.dmPelsWidth, m.dmPelsHeight, m.dmDisplayFrequency };
    }
    // Modos admitidos a la profundidad de color actual, sin repetir: { ancho, alto, Hz }
    public static int[][] Modes(string dev) {
        DEVMODE cur = New(); EnumDisplaySettings(dev, Current, ref cur);
        HashSet<string> seen = new HashSet<string>(); List<int[]> list = new List<int[]>();
        DEVMODE m = New();
        for (int i = 0; EnumDisplaySettings(dev, i, ref m); i++) {
            if (m.dmBitsPerPel == cur.dmBitsPerPel && m.dmPelsWidth >= 640 && m.dmDisplayFrequency > 1) {
                string key = m.dmPelsWidth + "x" + m.dmPelsHeight + "@" + m.dmDisplayFrequency;
                if (seen.Add(key)) list.Add(new int[] { m.dmPelsWidth, m.dmPelsHeight, m.dmDisplayFrequency });
            }
            m = New();
        }
        return list.ToArray();
    }
    // 0 = aplicado, 1 = requiere reiniciar, negativo = rechazado (DISP_CHANGE_*). Primero se prueba sin aplicar.
    public static int Apply(string dev, int width, int height, int hz) {
        DEVMODE m = New();
        if (!EnumDisplaySettings(dev, Current, ref m)) return -99;
        m.dmPelsWidth = width; m.dmPelsHeight = height; m.dmDisplayFrequency = hz;
        m.dmFields = PelsWidth | PelsHeight | Frequency;
        int test = ChangeDisplaySettingsEx(dev, ref m, IntPtr.Zero, 2, IntPtr.Zero);
        if (test != 0) return test;
        return ChangeDisplaySettingsEx(dev, ref m, IntPtr.Zero, 1, IntPtr.Zero);
    }
}
'@
}


# Las XAML de la ventana viven en src/ui; se leen como texto UTF-8 sin cambios
function Read-IwinXaml([string]$name) {
    $path = Join-Path $Root "src\ui\$name"
    if (-not (Test-Path -LiteralPath $path)) { throw "Falta un archivo de la interfaz: $name. Ejecuta de nuevo iWinInstaller-Setup.exe." }
    [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}

# Estilos de botón compartidos por la ventana y sus diálogos
$ButtonStyles = Read-IwinXaml 'ButtonStyles.xaml'

[xml]$xaml = (Read-IwinXaml 'MainWindow.xaml').Replace('<!--BOTONES-->', $ButtonStyles)

# Diálogo propio (oscuro y con el mismo zoom): confirmaciones y nombre de perfil
$dialogXaml = (Read-IwinXaml 'Dialog.xaml').Replace('<!--BOTONES-->', $ButtonStyles)

function New-WpfWindow($xml) { [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xml)) }
$win = New-WpfWindow $xaml
$script:FatalUiError=$false
$win.Dispatcher.add_UnhandledException({
    param($sender,$eventArgs)
    $eventArgs.Handled=$true
    $script:FatalUiError=$true
    try {
        Add-Content $LogFile ("ERROR DE INTERFAZ: " + $eventArgs.Exception.ToString()) -Encoding UTF8
        [Console]::Error.WriteLine($eventArgs.Exception.ToString())
        [void](Export-Diagnostic)
    } catch { [Console]::Error.WriteLine($_.ToString()) }
    $win.Close()
})
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml'); if ($n) { $ui[$n] = $win.FindName($n) } }
# Los menús contextuales viven fuera del árbol visual: sus opciones se buscan en el propio menú
foreach ($menu in @($ui.ProfileMore.ContextMenu, $ui.List.ContextMenu, $ui.BtnMore.ContextMenu)) { foreach ($entry in $menu.Items) { if ($entry.Name) { $ui[$entry.Name] = $entry } } }

$win.Title = "iWinInstaller $Version"
$processArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$architectureLabel = switch ($processArchitecture) { 'ARM64' { 'ARM64' } 'AMD64' { 'x64' } 'x86' { 'x86' } default { $processArchitecture } }
$ui.VersionText.Text = "$Version · Windows 10/11 · $architectureLabel"
$iconPng = Join-Path $Root 'assets\icon-128.png'
if (Test-Path $iconPng) { $ui.Logo.Source = New-Object Windows.Media.Imaging.BitmapImage ([Uri]$iconPng) }
$iconIco = Join-Path $Root 'assets\icon.ico'
if (Test-Path $iconIco) { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconIco) }
$win.Add_SourceInitialized({ try { [IwinDwm]::Dark((New-Object Windows.Interop.WindowInteropHelper $win).Handle) } catch { } })

# Registro: Write-Log solo necesita AppendText
$log = $ui.Log
function Set-Status($text) { $ui.StatusText.Text = $text; Invoke-UiPump }

# ---- Preferencias de la ventana (zoom, actividad y barra lateral), solo en este equipo ----
$PrefsFile = Join-Path $LogDir 'preferencias.json'
$Prefs = @{ zoom = 1.0; actividad = $false; secciones = $true; autoUpdate = $false }
$PrefsSaved = $false
if (Test-Path $PrefsFile) {
    try {
        $saved = Get-Content $PrefsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.zoom -is [double] -or $saved.zoom -is [int] -or $saved.zoom -is [decimal]) { $Prefs.zoom = [double]$saved.zoom; $PrefsSaved = $true }
        if ($saved.actividad -is [bool]) { $Prefs.actividad = $saved.actividad }
        if ($saved.secciones -is [bool]) { $Prefs.secciones = $saved.secciones }
        if ($saved.autoUpdate -is [bool]) { $Prefs.autoUpdate = $saved.autoUpdate }
    } catch { }
}
function Save-Prefs {
    if ($env:IWIN_PRUEBA_GUI) { return }
    try { $Prefs | ConvertTo-Json | Set-Content $PrefsFile -Encoding UTF8 } catch { }
}

# Tamaño inicial según la pantalla: en máquinas virtuales y pantallas pequeñas se abre maximizada
$area = [Windows.SystemParameters]::WorkArea
$win.MinWidth = [math]::Min(560, $area.Width); $win.MinHeight = [math]::Min(420, $area.Height)
$win.Width = [math]::Max($win.MinWidth, [math]::Min(1180, $area.Width - 32))
$win.Height = [math]::Max($win.MinHeight, [math]::Min(780, $area.Height - 32))
if ($area.Width -lt 1100 -or $area.Height -lt 720) { $win.WindowState = 'Maximized' }
if (-not $PrefsSaved -and $area.Height -lt 650) { $Prefs.zoom = 0.9 }

$ZoomMin = 0.7; $ZoomMax = 2.0
$script:NavForced = $false
function Update-Layout {
    if ($win.ActualWidth -le 0) { return }
    $zoom = $ui.Zoom.ScaleX
    $width = $win.ActualWidth / $zoom; $height = $win.ActualHeight / $zoom
    # Estrecha: la lista ocupa todo el ancho y las secciones se abren con el botón ☰
    $narrow = $width -lt 860
    $showNav = if ($narrow) { $script:NavForced } else { $Prefs.secciones }
    $ui.NavColumn.Width = New-Object Windows.GridLength ($(if ($showNav) { 232 } else { 0 }))
    $ui.Sidebar.Visibility = if ($showNav) { 'Visible' } else { 'Collapsed' }
    $ui.VersionText.Visibility = if ($width -lt 720) { 'Collapsed' } else { 'Visible' }
    $ui.Subheading.Visibility = if ($height -lt 640) { 'Collapsed' } else { 'Visible' }
    $ui.Log.Height = if ($height -lt 640) { 80 } else { 120 }
    # Compacta: menos márgenes y las acciones secundarias en ⋯ para dejar sitio a la lista
    $compact = $height -lt 640 -or $width -lt 900
    $secondary = if ($compact) { 'Collapsed' } else { 'Visible' }
    foreach ($name in 'LogToggle', 'BtnExport', 'BtnUpdate') { $ui[$name].Visibility = $secondary }
    $ui.BtnMore.Visibility = 'Visible'
    if ($compact -and $ui.BtnResume.Visibility -eq 'Visible') { $ui.BtnResume.Visibility='Collapsed' }
    $ui.Heading.FontSize = if ($compact) { 18 } else { 22 }
}
function Set-Zoom([double]$value) {
    $value = [math]::Round([math]::Min($ZoomMax, [math]::Max($ZoomMin, $value)), 2)
    $ui.Zoom.ScaleX = $value; $ui.Zoom.ScaleY = $value
    $ui.ZoomText.Text = "$([int][math]::Round($value * 100)) %"
    $ui.ZoomOut.IsEnabled = $value -gt $ZoomMin
    $ui.ZoomIn.IsEnabled = $value -lt $ZoomMax
    if ($Prefs.zoom -ne $value) { $Prefs.zoom = $value; Save-Prefs }
    Update-Layout
}
function Show-Log([bool]$visible) {
    $ui.Log.Visibility = if ($visible) { 'Visible' } else { 'Collapsed' }
    $ui.LogToggle.Content = if ($visible) { 'Ocultar actividad' } else { 'Mostrar actividad' }
    $ui.MLog.Header = $ui.LogToggle.Content
    if ($Prefs.actividad -ne $visible) { $Prefs.actividad = $visible; Save-Prefs }
}
Set-Zoom $Prefs.zoom
Show-Log $Prefs.actividad
$win.Add_SizeChanged({ Update-Layout })
$win.Add_StateChanged({ Update-Layout })
$ui.ZoomIn.Add_Click({ Set-Zoom ($ui.Zoom.ScaleX + 0.1) })
$ui.ZoomOut.Add_Click({ Set-Zoom ($ui.Zoom.ScaleX - 0.1) })
$ui.ZoomReset.Add_Click({ Set-Zoom 1 })
$ui.LogToggle.Add_Click({ Show-Log ($ui.Log.Visibility -ne 'Visible') })
$ui.MLog.Add_Click({ Show-Log ($ui.Log.Visibility -ne 'Visible') })
$ui.BtnMore.Add_Click({ $menu = $ui.BtnMore.ContextMenu; $menu.PlacementTarget = $ui.BtnMore; $menu.Placement = 'Top'; $menu.IsOpen = $true })
$ui.NavToggle.Add_Click({
    $zoom = $ui.Zoom.ScaleX
    if ($win.ActualWidth / $zoom -lt 860) { $script:NavForced = -not $script:NavForced }
    else { $Prefs.secciones = -not $Prefs.secciones; Save-Prefs }
    Update-Layout
})
$win.Add_PreviewMouseWheel({
    param($s, $e)
    if ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) {
        Set-Zoom ($ui.Zoom.ScaleX + $(if ($e.Delta -gt 0) { 0.1 } else { -0.1 }))
        $e.Handled = $true
    }
})

# Confirmaciones y nombres: devuelve Ok, el texto escrito y la casilla
function New-IwinDialog([string]$Title, [string]$Text, [string]$Ok = 'Aceptar', [switch]$Danger, [string]$InputText, [string]$CheckText, [bool]$Checked = $false) {
    $dialog = New-WpfWindow ([xml]$dialogXaml)
    $parts = @{}
    foreach ($name in 'Frame', 'DTitle', 'DText', 'DInputFrame', 'DInput', 'DCheck', 'DCancel', 'DOk') { $parts[$name] = $dialog.FindName($name) }
    $parts.Frame.LayoutTransform = New-Object Windows.Media.ScaleTransform ($ui.Zoom.ScaleX, $ui.Zoom.ScaleY)
    $parts.DTitle.Text = $Title; $parts.DText.Text = $Text; $parts.DOk.Content = $Ok
    if ($Danger) { $parts.DOk.Style = $parts.DOk.FindResource('Danger') }
    if ($PSBoundParameters.ContainsKey('InputText')) { $parts.DInputFrame.Visibility = 'Visible'; $parts.DInput.Text = $InputText; $parts.DInput.SelectAll() }
    if ($CheckText) { $parts.DCheck.Visibility = 'Visible'; $parts.DCheck.Content = $CheckText; $parts.DCheck.IsChecked = $Checked }
    if ($win.IsVisible) { $dialog.Owner = $win }
    # Los manejadores se ejecutan después de esta función: llegan a la ventana por el remitente
    $parts.DOk.Add_Click({ param($sender) [Windows.Window]::GetWindow($sender).DialogResult = $true })
    $parts.Frame.Add_MouseLeftButtonDown({ param($sender) try { [Windows.Window]::GetWindow($sender).DragMove() } catch { } })
    $dialog.Add_ContentRendered({
        param($sender)
        $field = $sender.FindName('DInputFrame')
        if ($field.Visibility -eq 'Visible') { [void]$sender.FindName('DInput').Focus() } else { [void]$sender.FindName('DOk').Focus() }
    })
    [pscustomobject]@{ Window = $dialog; Parts = $parts }
}
function Show-IwinDialog {
    $dialog = New-IwinDialog @args
    $ok = [bool]$dialog.Window.ShowDialog()
    [pscustomobject]@{ Ok = $ok; Text = $dialog.Parts.DInput.Text; Checked = [bool]$dialog.Parts.DCheck.IsChecked }
}

# ---- Pantalla: resolución y tasa de refresco de cada monitor ----
$script:DisplayMonitors = @(); $script:DisplayResList = @(); $script:DisplayRateList = @(); $script:DisplayModes = @()
function Get-DisplayMonitor { if ($ui.DisplayMonitor.SelectedIndex -ge 0) { $script:DisplayMonitors[$ui.DisplayMonitor.SelectedIndex] } }
function Update-DisplayCurrent {
    $mon = Get-DisplayMonitor
    $cur = if ($mon) { [IwinDisplay]::CurrentMode($mon.Dev) }
    $ui.DisplayCurrent.Text = if ($cur) { "Ahora: $($cur[0]) × $($cur[1]) a $($cur[2]) Hz" } else { 'No se pudo leer el modo actual de este monitor.' }
}
function Update-DisplayRates {
    $ui.DisplayRate.Items.Clear(); $script:DisplayRateList = @()
    if ($ui.DisplayResolution.SelectedIndex -lt 0) { return }
    $res = $script:DisplayResList[$ui.DisplayResolution.SelectedIndex]
    $script:DisplayRateList = @($script:DisplayModes | Where-Object { $_[0] -eq $res[0] -and $_[1] -eq $res[1] } | ForEach-Object { $_[2] } | Sort-Object -Unique -Descending)
    foreach ($hz in $script:DisplayRateList) { [void]$ui.DisplayRate.Items.Add("$hz Hz") }
    $cur = [IwinDisplay]::CurrentMode((Get-DisplayMonitor).Dev)
    $index = if ($cur) { [array]::IndexOf([int[]]$script:DisplayRateList, [int]$cur[2]) } else { -1 }
    $ui.DisplayRate.SelectedIndex = if ($index -ge 0) { $index } else { 0 }
}
function Update-DisplayResolutions {
    $ui.DisplayResolution.Items.Clear(); $script:DisplayResList = @(); $script:DisplayModes = @()
    $mon = Get-DisplayMonitor
    if (-not $mon) { return }
    $script:DisplayModes = @([IwinDisplay]::Modes($mon.Dev))
    $seen = @{}
    foreach ($m in @($script:DisplayModes | Sort-Object { $_[0] * $_[1] }, { $_[0] } -Descending)) {
        $key = "$($m[0])x$($m[1])"
        if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $script:DisplayResList += , @($m[0], $m[1]) }
    }
    $cur = [IwinDisplay]::CurrentMode($mon.Dev); $select = 0
    for ($i = 0; $i -lt $script:DisplayResList.Count; $i++) {
        $r = $script:DisplayResList[$i]
        $label = "$($r[0]) × $($r[1])"
        if ($i -eq 0) { $label += ' (máxima)' }
        if ($cur -and $r[0] -eq $cur[0] -and $r[1] -eq $cur[1]) { $select = $i; $label += ' · actual' }
        [void]$ui.DisplayResolution.Items.Add($label)
    }
    $ui.DisplayResolution.SelectedIndex = $select
    Update-DisplayCurrent
}
function Show-DisplayPanel {
    $script:DisplayMonitors = @(foreach ($line in @([IwinDisplay]::Monitors())) { $p = $line -split '\|', 3; [pscustomobject]@{ Dev = $p[0]; Name = $p[1]; Primary = $p[2] -eq '1' } })
    $ui.DisplayMonitor.Items.Clear()
    if (-not $script:DisplayMonitors) { Set-Status 'No se encontró ningún monitor activo.'; return }
    $n = 0
    foreach ($mon in $script:DisplayMonitors) { $n++; [void]$ui.DisplayMonitor.Items.Add("$n. $($mon.Name)$(if ($mon.Primary) { ' (principal)' })") }
    $primary = [array]::IndexOf(@($script:DisplayMonitors | ForEach-Object Primary), $true)
    $ui.DisplayMonitor.SelectedIndex = [math]::Max(0, $primary)
    try { Update-PowerPanel } catch { Write-Log "Energía: no se pudo leer el plan ($($_.Exception.Message))" }
    $ui.DisplayPanel.Visibility = 'Visible'
}
# ---- Energía: apagado de pantalla, suspensión e hibernación del plan activo (CA y CC por igual) ----
$PowerSteps = @(0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 120, 180, 300)
function Format-PowerMinutes([int]$m) { if ($m -eq 0) { 'Nunca' } elseif ($m -lt 60) { "$m min" } else { "$($m / 60) h" } }
function Set-PowerCombo($combo, $seconds) {
    $combo.Items.Clear()
    foreach ($m in $PowerSteps) { [void]$combo.Items.Add((Format-PowerMinutes $m)) }
    $minutes = if ($null -eq $seconds) { -1 } else { [int][math]::Ceiling($seconds / 60) }
    $index = [array]::IndexOf([int[]]$PowerSteps, $minutes)
    if ($index -lt 0 -and $minutes -gt 0) { [void]$combo.Items.Add((Format-PowerMinutes $minutes) + ' (actual)'); $index = $combo.Items.Count - 1 }
    $combo.SelectedIndex = [math]::Max(0, $index)
}
function Get-PowerComboMinutes($combo) {
    if ($combo.SelectedIndex -lt $PowerSteps.Count) { return $PowerSteps[$combo.SelectedIndex] }
    [int]([regex]::Match([string]$combo.SelectedItem, '^\d+').Value) * $(if ([string]$combo.SelectedItem -match ' h') { 60 } else { 1 })
}
function Get-HibernateEnabled { try { [bool](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' HibernateEnabled -ErrorAction Stop) } catch { $false } }
function Update-PowerPanel {
    Set-PowerCombo $ui.PowerMonitor (Get-AcPowerValue SUB_VIDEO VIDEOIDLE)
    Set-PowerCombo $ui.PowerSleep (Get-AcPowerValue SUB_SLEEP STANDBYIDLE)
    Set-PowerCombo $ui.PowerHibernateAfter (Get-AcPowerValue SUB_SLEEP HIBERNATEIDLE)
    $ui.PowerHibernate.Items.Clear(); [void]$ui.PowerHibernate.Items.Add('Activada'); [void]$ui.PowerHibernate.Items.Add('Desactivada (libera el archivo hiberfil.sys)')
    $ui.PowerHibernate.SelectedIndex = if (Get-HibernateEnabled) { 0 } else { 1 }
    $plan = (& powercfg /getactivescheme 2>$null | Out-String) -replace '^.*?:\s*', '' -replace '\s+$', ''
    $ui.PowerPlan.Text = if ($plan) { "Plan activo: $plan" } else { '' }
}
$ui.PowerApply.Add_Click({
    $monitor = Get-PowerComboMinutes $ui.PowerMonitor; $sleep = Get-PowerComboMinutes $ui.PowerSleep; $hibAfter = Get-PowerComboMinutes $ui.PowerHibernateAfter
    $hibernate = $ui.PowerHibernate.SelectedIndex -eq 0
    foreach ($pair in @(@('monitor-timeout', $monitor), @('standby-timeout', $sleep), @('hibernate-timeout', $hibAfter))) {
        foreach ($side in 'ac', 'dc') { & powercfg /change "$($pair[0])-$side" $pair[1] 2>$null | Out-Null }
    }
    $failed = $false
    if ($hibernate -ne (Get-HibernateEnabled)) {
        $arg = if ($hibernate) { '/hibernate on' } else { '/hibernate off' }
        try {
            if (Test-Administrator) { & powercfg $arg.Split(' ') | Out-Null; $failed = $LASTEXITCODE -ne 0 }
            else { $p = Start-Process powercfg -ArgumentList $arg -Verb RunAs -WindowStyle Hidden -Wait -PassThru; $failed = $p.ExitCode -ne 0 }
        } catch { $failed = $true }
    }
    Write-Log "Energía: pantalla $monitor min, suspensión $sleep min, hibernar tras $hibAfter min, hibernación $hibernate"
    Set-Status $(if ($failed) { 'Tiempos guardados. La hibernación no cambió (hace falta permiso de administrador).' } else { "Energía: pantalla $(Format-PowerMinutes $monitor), suspensión $(Format-PowerMinutes $sleep), hibernación $(if ($hibernate) { "tras $(Format-PowerMinutes $hibAfter)" } else { 'desactivada' })." })
    Update-PowerPanel
})
$ui.DisplayMonitor.Add_SelectionChanged({ Update-DisplayResolutions })
$ui.DisplayResolution.Add_SelectionChanged({ Update-DisplayRates })
$ui.BtnDisplay.Add_Click({ Show-DisplayPanel })
$ui.MDisplay.Add_Click({ Show-DisplayPanel })
$ui.DisplayClose.Add_Click({ $ui.DisplayPanel.Visibility = 'Collapsed' })
# ---- Seguridad: estado y análisis con Microsoft Defender (cmdlets Defender de Windows) ----
$script:SecurityJob = $null; $script:SecurityTimer = $null
function Format-SecurityDate($date) { if (-not $date -or $date.Year -lt 2000) { 'nunca' } else { $days = [int]((Get-Date) - $date).TotalDays; if ($days -le 0) { 'hoy' } elseif ($days -eq 1) { 'ayer' } else { "hace $days días" } } }
function Update-SecurityPanel {
    $others = @()
    try { $others = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object { $_.displayName -notmatch 'Defender' } | ForEach-Object displayName) } catch {}
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { $mp = $null }
    if (-not $mp) {
        $ui.SecuritySummary.Text = if ($others) { "Protección a cargo de $($others -join ', '). Defender no está disponible en este equipo." } else { 'No se pudo leer Microsoft Defender en este equipo.' }
        $ui.SecurityStatus.Text = 'Abre Seguridad de Windows para revisar la protección.'; $ui.SecurityThreats.Text = '—'
        foreach ($b in 'SecurityQuick','SecurityFull','SecurityFolder','SecurityUpdate') { $ui[$b].IsEnabled = $false }
        return
    }
    $passive = [string]$mp.AMRunningMode -notin @('Normal', '')
    $ok = $mp.RealTimeProtectionEnabled -and $mp.AntivirusEnabled -and -not $passive
    $age = [int]$mp.AntivirusSignatureAge
    $ui.SecuritySummary.Text = if ($passive -and $others) { "Protección en tiempo real a cargo de $($others -join ', '). Defender sigue disponible para análisis manuales." }
        elseif ($ok -and $age -le 3) { 'Protegido: tiempo real activado y firmas al día.' }
        elseif ($ok) { "Protegido, pero las firmas tienen $age días: actualízalas." }
        else { 'Atención: la protección en tiempo real está desactivada.' }
    $ui.SecurityStatus.Text = (@(
        "Tiempo real: $(if ($mp.RealTimeProtectionEnabled) { 'activado' } else { 'desactivado' })  ·  Modo: $($mp.AMRunningMode)",
        "Protección contra alteraciones: $(if ($mp.IsTamperProtected) { 'activada' } else { 'desactivada' })",
        "Firmas: $($mp.AntivirusSignatureVersion) · $(Format-SecurityDate $mp.AntivirusSignatureLastUpdated)",
        "Último análisis rápido: $(Format-SecurityDate $mp.QuickScanEndTime)  ·  completo: $(Format-SecurityDate $mp.FullScanEndTime)"
    ) -join "`n")
    try {
        $names = @{}; foreach ($t in @(Get-MpThreat -ErrorAction Stop)) { $names[[string]$t.ThreatID] = $t.ThreatName }
        $recent = @(Get-MpThreatDetection -ErrorAction Stop | Sort-Object InitialDetectionTime -Descending | Select-Object -First 5)
        $ui.SecurityThreats.Text = if ($recent) { ($recent | ForEach-Object { $name = if ($names.ContainsKey([string]$_.ThreatID)) { $names[[string]$_.ThreatID] } else { "Amenaza $($_.ThreatID)" }; "$($_.InitialDetectionTime.ToString('dd/MM HH:mm')) · $name · $(if ($_.ActionSuccess) { 'resuelta' } else { 'pendiente' })" }) -join "`n" } else { 'Ninguna detectada.' }
    } catch { $ui.SecurityThreats.Text = 'Solo visible con permiso de administrador o en Seguridad de Windows.' }
    $busy = $script:SecurityJob -and -not $script:SecurityJob.HasExited
    foreach ($b in 'SecurityQuick','SecurityFull','SecurityFolder','SecurityUpdate') { $ui[$b].IsEnabled = -not $busy }
}
function Start-SecurityTask([string]$command, [string]$label) {
    if ($script:SecurityJob -and -not $script:SecurityJob.HasExited) { Set-Status 'Ya hay un análisis en curso.'; return }
    # Proceso aparte: un análisis completo puede durar horas y no debe bloquear la ventana.
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$ErrorActionPreference='Stop'; $command"))
    # El handle se guarda al lanzar: sin él, PowerShell 5.1 pierde el código de salida de un proceso que termina rápido.
    try { $script:SecurityJob = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -WindowStyle Hidden -PassThru; $null = $script:SecurityJob.Handle }
    catch { Set-Status "No se pudo iniciar: $($_.Exception.Message)"; return }
    $script:SecurityLabel = $label
    Write-Log "Seguridad: $label iniciado."; Set-Status "$label en curso…"
    foreach ($b in 'SecurityQuick','SecurityFull','SecurityFolder','SecurityUpdate') { $ui[$b].IsEnabled = $false }
    if (-not $script:SecurityTimer) {
        $script:SecurityTimer = New-Object Windows.Threading.DispatcherTimer
        $script:SecurityTimer.Interval = [TimeSpan]::FromSeconds(3)
        $script:SecurityTimer.Add_Tick({
            if (-not $script:SecurityJob -or -not $script:SecurityJob.HasExited) { return }
            $script:SecurityTimer.Stop()
            $code = $script:SecurityJob.ExitCode
            $text = if ($code -eq 0) { "$script:SecurityLabel terminado." } else { "$script:SecurityLabel no se completó (código $code). Puede necesitar permiso de administrador." }
            Write-Log "Seguridad: $text"; Set-Status $text
            try { Update-SecurityPanel } catch {}
        })
    }
    $script:SecurityTimer.Start()
}
function Show-SecurityPanel {
    try { Update-SecurityPanel } catch { Write-Log "Seguridad: no se pudo leer el estado ($($_.Exception.Message))" }
    $ui.SecurityPanel.Visibility = 'Visible'
}
function Show-LinkPanel {
    try { Update-LinkPanel } catch { Write-Log "Vincular: no se pudo leer el estado ($($_.Exception.Message))" }
    $ui.LinkPanel.Visibility = 'Visible'
}
$ui.BtnLink.Add_Click({ Show-LinkPanel })
$ui.MLink.Add_Click({ Show-LinkPanel })
$ui.LinkClose.Add_Click({ $ui.LinkPanel.Visibility = 'Collapsed' })
$ui.LinkCopyMac.Add_Click({ [Windows.Clipboard]::SetText($script:LinkInfo.Mac); Set-Status 'Comando para Mac copiado: pégalo en la Terminal del Mac.' })
$ui.LinkCopyWin.Add_Click({ [Windows.Clipboard]::SetText($script:LinkInfo.Windows); Set-Status 'Comando para Windows copiado: pégalo en PowerShell del otro PC.' })
$ui.LinkTailscale.Add_Click({
    $exe = Join-Path $env:ProgramFiles 'Tailscale\tailscale-ipn.exe'
    if (Test-Path $exe) { Start-Process $exe } else { Set-Status 'Tailscale no está instalado: búscalo en el catálogo (Acceso remoto) e instálalo.' }
})
$ui.LinkPrepare.Add_Click({
    $app = $Apps | Where-Object id -eq 'remotessh' | Select-Object -First 1
    if (-not $app) { return }
    Set-Status 'Preparando el servidor SSH (pide permiso de administrador)…'
    $failed = @(Invoke-InstallWorker @($app) $null)
    Set-Status $(if ($failed) { 'No se pudo preparar el servidor SSH: revisa la actividad.' } else { 'Servidor SSH listo: ahora ejecuta el comando en el otro equipo.' })
    try { Update-LinkPanel } catch {}
})
$ui.LinkLan.Add_Click({
    $on = [bool]$ui.LinkLan.IsChecked
    $script = if ($on) { "Remove-NetFirewallRule -Group '$SshLanGroup' -ErrorAction SilentlyContinue; New-NetFirewallRule -DisplayName 'SSH en red local' -Group '$SshLanGroup' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -RemoteAddress LocalSubnet -Profile Private,Domain | Out-Null" } else { "Remove-NetFirewallRule -Group '$SshLanGroup' -ErrorAction SilentlyContinue" }
    if (Invoke-LinkElevated $script 'Red local') { Write-Log "Vincular: SSH en red local $(if ($on) { 'permitido (solo redes privadas)' } else { 'cerrado' })."; Set-Status $(if ($on) { 'SSH permitido en la red local privada.' } else { 'SSH en red local cerrado; sigue disponible por Tailscale.' }) }
    try { Update-LinkPanel } catch {}
})
$ui.LinkAuthorize.Add_Click({
    $key = ($ui.LinkKey.Text -replace '\s+', ' ').Trim()
    if ($key -match 'PRIVATE KEY') { Set-Status 'Eso es una clave privada: no la compartas. Pega la línea que empieza por ssh-ed25519.'; return }
    if ($key -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com) [A-Za-z0-9+/=]{40,}( [^\r\n]{0,200})?$') { Set-Status 'La clave no tiene el formato esperado (ssh-ed25519 AAAA… usuario@equipo).'; return }
    $path = Get-LinkKeysPath
    if (@(Get-Content $path -ErrorAction SilentlyContinue) -contains $key) { Set-Status 'Ese equipo ya estaba autorizado.'; return }
    if ($path -eq $SshAdminKeys) {
        # El archivo de administradores solo lo pueden escribir administradores y SYSTEM.
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($key))
        $script = "`$k=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')); `$f='$SshAdminKeys'; if(-not (Test-Path `$f)){New-Item `$f -ItemType File -Force | Out-Null}; `$t=[IO.File]::ReadAllText(`$f); if(`$t -and -not `$t.EndsWith(`"``n`")){`$t+=`"``r``n`"}; [IO.File]::WriteAllText(`$f, `$t + `$k + `"``r``n`", (New-Object Text.UTF8Encoding `$false)); icacls.exe `$f /inheritance:r /grant:r '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null; if(`$LASTEXITCODE){exit 3}"
        if (-not (Invoke-LinkElevated $script 'Autorizar equipo')) { return }
    } else {
        New-Item (Split-Path $path) -ItemType Directory -Force | Out-Null
        Add-Content $path $key -Encoding ASCII
    }
    $comment = ($key -split ' ', 3)[2]
    Write-Log "Vincular: equipo autorizado $(if ($comment) { "($comment)" })."
    $ui.LinkKey.Text = ''
    Set-Status "Equipo autorizado. Desde él: ssh $($script:LinkInfo.Alias)"
    try { Update-LinkPanel } catch {}
})
$ui.LinkKeysFile.Add_Click({
    $path = Get-LinkKeysPath
    if (-not (Test-Path $path)) { Set-Status 'Todavía no hay equipos autorizados.'; return }
    $keys = @(Get-Content $path -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(ssh-|ecdsa-|sk-)' } | ForEach-Object { $p = $_ -split ' ', 3; if ($p.Count -ge 3) { $p[2] } else { $p[0] + ' …' + $p[1].Substring([math]::Max(0, $p[1].Length - 8)) } })
    [void](Show-IwinDialog -Title 'Equipos autorizados' -Text $(if ($keys) { ($keys -join "`n") + "`n`nPara quitar uno, borra su línea en:`n$path (necesita administrador)." } else { 'Ninguno.' }) -Ok 'Cerrar')
})
# ---- Informe al terminar: una tarjeta por fallo con motivo, qué hacer y detalle del registro ----
function New-ReportText([string]$text, [string]$color, [double]$size = 12.5, [string]$weight = 'Normal', [string]$font = '') {
    $block = New-Object Windows.Controls.TextBlock
    $block.Text = $text; $block.Foreground = $color; $block.FontSize = $size; $block.FontWeight = $weight
    $block.TextWrapping = 'Wrap'; $block.Margin = '0,2,0,0'
    if ($font) { $block.FontFamily = $font }
    $block
}
function Show-InstallReport($report) {
    if (-not $report) { $report = Get-IwinLastReport }
    $ui.ReportRows.Children.Clear()
    if (-not $report) {
        $ui.ReportSummary.Text = 'Todavía no hay ninguna instalación registrada en este equipo.'
        $ui.ReportRetry.Visibility = 'Collapsed'; $ui.ReportCopy.IsEnabled = $false
        $ui.ReportPanel.Visibility = 'Visible'; return
    }
    $script:ShownReport = $report
    $items = @($report.items)
    $ui.ReportTitle.Text = if ($items.Count) { 'Resultado de la instalación' } else { 'Instalación completada' }
    $ui.ReportSummary.Text = "$($report.created) · $(Get-IwinReportSummary $report)"
    $badges = @{ 'fallo' = @('Falló', '#FF7878', '#3A1E22'); 'manual' = @('Acción manual', '#EBC186', '#3A3020'); 'pausa' = @('Pendiente', '#8CC4FF', '#1E2A3A'); 'sin-ejecutar' = @('Sin ejecutar', '#8CC4FF', '#1E2A3A') }
    foreach ($item in $items) {
        $badge = if ($badges.ContainsKey([string]$item.kind)) { $badges[[string]$item.kind] } else { $badges['fallo'] }
        $card = New-Object Windows.Controls.Border
        $card.Background = '#111116'; $card.BorderBrush = '#2B2B30'; $card.BorderThickness = '1'; $card.CornerRadius = '10'; $card.Padding = '14,10'; $card.Margin = '0,0,0,8'
        $stack = New-Object Windows.Controls.StackPanel
        $head = New-Object Windows.Controls.DockPanel
        $pill = New-Object Windows.Controls.Border
        $pill.Background = $badge[2]; $pill.CornerRadius = '6'; $pill.Padding = '8,2'; $pill.VerticalAlignment = 'Center'; $pill.Margin = '8,0,0,0'
        [Windows.Controls.DockPanel]::SetDock($pill, 'Right')
        $pill.Child = New-ReportText $badge[0] $badge[1] 11.5 'SemiBold'
        $pill.Child.Margin = '0'
        [void]$head.Children.Add($pill)
        $title = New-ReportText ([string]$item.name + $(if ($item.codeText) { '  ·  código ' + $item.codeText })) '#F5F5F7' 14 'SemiBold'
        $title.Margin = '0'
        [void]$head.Children.Add($title)
        [void]$stack.Children.Add($head)
        [void]$stack.Children.Add((New-ReportText ("Motivo: " + $item.reason) '#E4E4E7'))
        [void]$stack.Children.Add((New-ReportText ("Qué hacer: " + $item.hint) '#ADADB5'))
        $details = @($item.details)
        if ($details.Count) {
            $box = New-ReportText ($details -join "`n") '#8B8B95' 11 'Normal' 'Cascadia Mono, Consolas'
            $box.Margin = '0,6,0,0'
            [void]$stack.Children.Add($box)
        }
        $card.Child = $stack
        [void]$ui.ReportRows.Children.Add($card)
    }
    if (@($report.reboot).Count) {
        [void]$ui.ReportRows.Children.Add((New-ReportText ('Requieren reiniciar Windows: ' + (@($report.reboot) -join ', ')) '#EBC186' 12.5 'SemiBold'))
    }
    if (-not $items.Count) { [void]$ui.ReportRows.Children.Add((New-ReportText 'Todo se instaló correctamente.' '#78DC96' 13 'SemiBold')) }
    $retryable = @($items | Where-Object { $_.kind -ne 'manual' })
    $ui.ReportRetry.Visibility = if ($retryable.Count -and -not $script:Busy) { 'Visible' } else { 'Collapsed' }
    $ui.ReportCopy.IsEnabled = $true
    $ui.ReportPanel.Visibility = 'Visible'
}
$ui.MReport.Add_Click({ Show-InstallReport $null })
$ui.ReportClose.Add_Click({ $ui.ReportPanel.Visibility = 'Collapsed' })
$ui.ReportCopy.Add_Click({
    if (-not $script:ShownReport) { return }
    try { [Windows.Clipboard]::SetText((Format-IwinReportText $script:ShownReport)); Set-Status 'Informe copiado: pégalo donde quieras compartirlo.' }
    catch { Set-Status "No se pudo copiar el informe: $($_.Exception.Message)" }
})
$ui.ReportExport.Add_Click({
    try { $path = Export-Diagnostic; Set-Status "Diagnóstico guardado en Descargas: $([IO.Path]::GetFileName($path))"; Start-Process explorer.exe -ArgumentList ('/select,"' + $path + '"') }
    catch { Set-Status "No se pudo guardar el diagnóstico: $($_.Exception.Message)" }
})
$ui.ReportRetry.Add_Click({
    if ($script:Busy -or -not $script:ShownReport) { return }
    $ids = @(@($script:ShownReport.items) | Where-Object { $_.kind -ne 'manual' } | ForEach-Object id)
    $selection = @($Apps | Where-Object { $ids -contains $_.id })
    if (-not $selection.Count) { return }
    $ui.ReportPanel.Visibility = 'Collapsed'
    Start-IwinUiInstall $selection
})
$ui.MSecurity.Add_Click({ Show-SecurityPanel })
$ui.BtnSecurity.Add_Click({ Show-SecurityPanel })
$ui.SecurityClose.Add_Click({ $ui.SecurityPanel.Visibility = 'Collapsed' })
$ui.SecurityOpen.Add_Click({ try { Start-Process 'windowsdefender://threat' } catch { Set-Status 'No se pudo abrir Seguridad de Windows.' } })
$ui.SecurityQuick.Add_Click({ Start-SecurityTask 'Start-MpScan -ScanType QuickScan' 'Análisis rápido' })
$ui.SecurityFull.Add_Click({ Start-SecurityTask 'Start-MpScan -ScanType FullScan' 'Análisis completo' })
$ui.SecurityUpdate.Add_Click({ Start-SecurityTask 'Update-MpSignature' 'Actualización de firmas' })
$ui.SecurityFolder.Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = 'Carpeta que quieres analizar'
    if ($picker.ShowDialog() -ne 'OK' -or -not (Test-Path -LiteralPath $picker.SelectedPath)) { return }
    $path = $picker.SelectedPath.Replace("'", "''")
    Start-SecurityTask "Start-MpScan -ScanType CustomScan -ScanPath '$path'" "Análisis de $([IO.Path]::GetFileName($picker.SelectedPath.TrimEnd('\')))"
})
$ui.DisplayApply.Add_Click({
    $mon = Get-DisplayMonitor
    if (-not $mon -or $ui.DisplayResolution.SelectedIndex -lt 0 -or $ui.DisplayRate.SelectedIndex -lt 0) { return }
    $res = $script:DisplayResList[$ui.DisplayResolution.SelectedIndex]; $hz = $script:DisplayRateList[$ui.DisplayRate.SelectedIndex]
    $before = [IwinDisplay]::CurrentMode($mon.Dev)
    if ($before -and $before[0] -eq $res[0] -and $before[1] -eq $res[1] -and $before[2] -eq $hz) { Set-Status 'Ese ya es el modo actual.'; return }
    $code = [IwinDisplay]::Apply($mon.Dev, $res[0], $res[1], $hz)
    if ($code -eq 1) { Set-Status 'Windows aplicará ese modo después de reiniciar.'; return }
    if ($code -ne 0) { Set-Status "Windows no admite $($res[0]) × $($res[1]) a $hz Hz en este monitor (código $code)."; Write-Log "Pantalla: modo rechazado ($code) en $($mon.Dev)"; return }
    Write-Log "Pantalla: $($mon.Name) a $($res[0])x$($res[1]) $hz Hz"
    # Como Windows: si no se confirma en 15 s (p. ej. la pantalla se queda en negro) vuelve al modo anterior
    $script:DisplayDialog = New-IwinDialog -Title '¿Mantener este modo?' -Text 'Vuelve al anterior en 15 s.' -Ok 'Mantener'
    $script:DisplayDialog.Parts.DCancel.Content = 'Volver'
    $script:DisplayLeft = 15
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({
        $script:DisplayLeft--
        if ($script:DisplayLeft -le 0) { try { $script:DisplayDialog.Window.DialogResult = $false } catch { } }
        else { $script:DisplayDialog.Parts.DText.Text = "Vuelve al anterior en $script:DisplayLeft s." }
    })
    $timer.Start()
    $keep = [bool]$script:DisplayDialog.Window.ShowDialog()
    $timer.Stop()
    if ($keep) { Set-Status "Pantalla: $($res[0]) × $($res[1]) a $hz Hz." }
    elseif ($before) {
        [void][IwinDisplay]::Apply($mon.Dev, $before[0], $before[1], $before[2])
        Set-Status "Se restauró $($before[0]) × $($before[1]) a $($before[2]) Hz."
        Write-Log 'Pantalla: restaurado el modo anterior'
    }
    Update-DisplayResolutions
})

# Estado manual de configuracion: solo IDs y booleanos, sin credenciales.
$ConfigFile = Join-Path $LogDir 'configuracion.json'
$ConfiguredApps = @{}
if (Test-Path $ConfigFile) {
    try {
        $saved = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $saved.PSObject.Properties) { if ($property.Value -is [bool]) { $ConfiguredApps[$property.Name] = $property.Value } }
    } catch { Write-Log 'No se pudo leer el seguimiento de configuracion anterior.' }
}
$script:PostInstallReadOnly=$false
try{$script:PostInstallState=Get-PostInstallState}catch{$script:PostInstallState=@{};$script:PostInstallReadOnly=$true}
foreach($app in $Apps){
    if($ConfiguredApps[$app.id] -and $app.postInstall -and -not $script:PostInstallState.ContainsKey($app.id)){
        $script:PostInstallState[$app.id]=@{steps=@();note='Marcaste esta configuración como lista antes de v3.2. Revisa y confirma los nuevos pasos detallados.'}
    }
}
foreach($app in $Apps){
    if($app.postInstall -and $script:PostInstallState.ContainsKey($app.id)){
        $count=@($app.postInstall.steps).Count
        $ConfiguredApps[$app.id]=@($script:PostInstallState[$app.id].steps | Where-Object {$_ -ge 0 -and $_ -lt $count} | Select-Object -Unique).Count -eq $count
    }
}
# ---- Catálogo ----
$items = New-Object 'System.Collections.ObjectModel.ObservableCollection[IwinApp]'
$SubgroupNotes = @{}
foreach ($app in $Apps) { if ($app.subgroupNote) { $SubgroupNotes["$($app.group)/$($app.subgroup)"] = $app.subgroupNote } }
$byId = @{}
foreach ($app in $Apps) {
    $it = New-Object IwinApp
    $it.Id = $app.id; $it.Name = $app.name; $it.Desc = $app.desc; $it.Group = $app.group; $it.Section = $app.section
    $it.Subgroup = $app.subgroup; $it.Compare = $app.compare
    if ($app.subgroup) { $it.SubgroupNote = $SubgroupNotes["$($app.group)/$($app.subgroup)"] }
    $words = @($app.name -split '[\s\.\-]+' | Where-Object { $_ -match '^[\p{L}\d]' })
    $it.Initials = if ($words.Count -ge 2) { ($words[0].Substring(0, 1) + $words[1].Substring(0, 1)).ToUpper() } else { $app.name.Substring(0, [Math]::Min(2, $app.name.Length)) }
    $it.IconSpec = $app.icon
    if ("$($app.icon)" -match '^glyph:([0-9A-Fa-f]{4})$') { $it.Glyph = [string][char][Convert]::ToInt32($Matches[1], 16) }
    $it.NeedsConfiguration = [bool]($app.configure -or $app.postInstall)
    $it.Configured = [bool]$ConfiguredApps[$app.id]
    $it.Optional = Test-Optional $app
    $it.IsTweak = $app.type -eq 'tweak'
    $it.CanUninstall = Test-Uninstallable $app
    $it.IsCli = $app.section -eq 'Terminal'
    $it.OpensInConsole = $it.IsCli -and -not $app.gui
    $it.CanOpen = $app.type -notin @('tweak', 'vboxga') -and -not $app.noopen -and $app.section -ne 'Sistema'
    $it.Search = "$($app.name) $($app.desc) $($app.group) $($app.subgroup) $($app.compare) $($app.section) $($app.winget)".ToLower()
    $it.Checked = -not $it.Optional
    $items.Add($it); $byId[$app.id] = $it
}
$view = [Windows.Data.CollectionViewSource]::GetDefaultView($items)
$view.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'GroupLabel'))
$ui.List.ItemsSource = $view

$navAll = 'Todo el catálogo'
# Barra lateral: tres secciones (Sistema, Terminal, Aplicaciones) con sus grupos debajo
function Update-Nav {
    $selKey = if ($ui.Nav.SelectedItem) { $ui.Nav.SelectedItem.Key } else { 'all' }
    $rows = @([pscustomobject]@{ Key = 'all'; Kind = 'all'; Name = $navAll; Section = ''; Group = ''; Count = "$(@($items | Where-Object Installed).Count)/$($items.Count)" })
    foreach ($s in @($Apps | ForEach-Object section | Select-Object -Unique)) {
        $si = @($items | Where-Object Section -eq $s)
        $rows += [pscustomobject]@{ Key = "s:$s"; Kind = 'section'; Name = $s.ToUpper(); Section = $s; Group = ''; Count = "$(@($si | Where-Object Installed).Count)/$($si.Count)" }
        foreach ($g in @($Apps | Where-Object section -eq $s | ForEach-Object group | Select-Object -Unique)) {
            $gi = @($si | Where-Object Group -eq $g)
            $rows += [pscustomobject]@{ Key = "g:$s/$g"; Kind = 'group'; Name = $g; Section = $s; Group = $g; Count = "$(@($gi | Where-Object Installed).Count)/$($gi.Count)" }
        }
    }
    $ui.Nav.ItemsSource = $rows
    $ui.Nav.SelectedItem = $rows | Where-Object Key -eq $selKey | Select-Object -First 1
}
Update-Nav
$ui.Nav.SelectedIndex = 0

$view.Filter = [Predicate[object]]{
    param($o)
    $q = $ui.Search.Text.Trim().ToLower()
    $n = $ui.Nav.SelectedItem
    if ($n -and $n.Kind -eq 'section' -and $o.Section -ne $n.Section) { return $false }
    if ($n -and $n.Kind -eq 'group' -and ($o.Section -ne $n.Section -or $o.Group -ne $n.Group)) { return $false }
    if ($q -and -not $o.Search.Contains($q)) { return $false }
    if ($ui.FChecked.IsChecked -and -not $o.Checked) { return $false }
    if ($ui.FMissing.IsChecked -and $o.Installed) { return $false }
    if ($ui.FInstalled.IsChecked -and -not $o.Installed) { return $false }
    if ($ui.FConfigure.IsChecked -and (-not $o.Installed -or -not $o.NeedsConfiguration -or $o.Configured)) { return $false }
    $true
}
function Update-Filter { $view.Refresh() }
# Marcar algo sin instalar lo instala; marcar algo instalado lo propone para desinstalar
function Update-Count {
    $install = @($items | Where-Object { $_.Checked -and -not $_.Installed }).Count
    $remove = @($items | Where-Object { $_.Checked -and ($_.Installed -or $_.HasPreviousState) -and $_.CanUninstall }).Count
    $ui.BtnInstall.Content = if ($install) { "Instalar $install seleccionada$(if ($install -ne 1) { 's' })" } else { 'Nada que instalar' }
    $ui.BtnInstall.IsEnabled = $install -gt 0 -and -not $script:Busy
    $ui.BtnRemove.Content = "Desinstalar $remove"
    $ui.BtnRemove.Visibility = if ($remove) { 'Visible' } else { 'Collapsed' }
    $ui.BtnRemove.IsEnabled = -not $script:Busy
}
foreach ($it in $items) { $it.add_PropertyChanged({ param($s, $e) if ($e.PropertyName -in @('Checked', 'Installed')) { Update-Count } }) }
Update-Count

$ui.Search.Add_TextChanged({ $ui.SearchHint.Visibility = if ($ui.Search.Text) { 'Collapsed' } else { 'Visible' }; Update-Filter })
foreach ($f in 'FAll', 'FChecked', 'FMissing', 'FInstalled', 'FConfigure') { $ui[$f].Add_Checked({ Update-Filter }) }
$ui.Nav.Add_SelectionChanged({
    if ($ui.Nav.SelectedItem) { $ui.Heading.Text = $(if ($ui.Nav.SelectedItem.Kind -eq 'section') { $ui.Nav.SelectedItem.Section } else { $ui.Nav.SelectedItem.Name }) }
    # En ventana estrecha las secciones se cierran al elegir una
    if ($script:NavForced) { $script:NavForced = $false; Update-Layout }
    Update-Filter
})
$ui.SelectVisible.Add_Click({ foreach ($o in $view) { if (-not $o.Installed) { $o.Checked = $true } } })
$ui.ClearVisible.Add_Click({ foreach ($o in $view) { $o.Checked = $false } })

# ---- Perfiles: los de serie (profiles.json) y los propios (★, en %LOCALAPPDATA%\iWinInstaller\perfiles) ----
$script:LoadingProfiles = $false
function Update-ProfileList([string]$select = 'Manual') {
    $script:LoadingProfiles = $true
    try {
        $ui.Profile.Items.Clear()
        $Profiles.PSObject.Properties.Name | ForEach-Object { [void]$ui.Profile.Items.Add($_) }
        foreach ($name in (Get-CustomProfiles).Keys) { [void]$ui.Profile.Items.Add($CustomMark + $name) }
    } finally { $script:LoadingProfiles = $false }
    $ui.Profile.SelectedItem = if ($ui.Profile.Items.Contains($select)) { $select } else { 'Manual' }
}
$ui.Profile.Add_SelectionChanged({
    if ($script:LoadingProfiles -or -not $ui.Profile.SelectedItem) { return }
    try { $ids = @(Get-ProfileApps ([string]$ui.Profile.SelectedItem) | ForEach-Object id) }
    catch { Set-Status "No se pudo leer el perfil: $($_.Exception.Message)"; return }
    foreach ($it in $items) { $it.Checked = ($ids -contains $it.Id) -and -not $it.Installed }
})
Update-ProfileList 'Manual'

function Get-SelectionIds([bool]$withInstalled) { @($items | Where-Object { $_.Checked -or ($withInstalled -and $_.Installed) } | ForEach-Object Id) }
function Get-ProfileSuggestion {
    $current = [string]$ui.Profile.SelectedItem
    if ($current.StartsWith($CustomMark)) { return $current.Substring($CustomMark.Length) }
    "Mi PC $(Get-Date -Format 'yyyy-MM-dd')"
}
$ProfileFilter = 'Perfil de iWinInstaller (*.iwin.json)|*.iwin.json|JSON (*.json)|*.json'
$ui.ProfileSave.Add_Click({
    $answer = Show-IwinDialog -Title 'Guardar perfil' -Text 'Guarda lo marcado para volver a marcarlo con un clic desde el desplegable. Para llevarlo a otro PC usa ⋯ › Exportar a un archivo.' -Ok 'Guardar' -InputText (Get-ProfileSuggestion) -CheckText 'Incluir también lo que ya está instalado en este PC' -Checked $true
    if (-not $answer.Ok) { return }
    $name = Get-SafeProfileName $answer.Text
    if (-not $name) { Set-Status 'Escribe un nombre para el perfil.'; return }
    $ids = Get-SelectionIds $answer.Checked
    if (-not $ids) { Set-Status 'No hay nada marcado para guardar.'; return }
    New-Item $ProfileDir -ItemType Directory -Force | Out-Null
    $path = Get-CustomProfilePath $name
    if ((Test-Path -LiteralPath $path) -and -not (Show-IwinDialog -Title "¿Reemplazar «$name»?" -Text 'Ya tienes un perfil con ese nombre.' -Ok 'Reemplazar').Ok) { return }
    try { Write-ProfileFile $path $name $ids } catch { Set-Status "No se pudo guardar: $($_.Exception.Message)"; return }
    Update-ProfileList ($CustomMark + $name)
    Set-Status "Perfil «$name» guardado con $($ids.Count) elementos."
})
$ui.ProfileImport.Add_Click({
    $picker = New-Object Microsoft.Win32.OpenFileDialog
    $picker.Filter = $ProfileFilter; $picker.Title = 'Importar perfil de iWinInstaller'
    if (-not $picker.ShowDialog($win)) { return }
    try { $imported = Read-ProfileFile $picker.FileName } catch { Set-Status "No se pudo importar: $($_.Exception.Message)"; return }
    if (-not $imported.Apps) { Set-Status 'El perfil no contiene aplicaciones de este catálogo.'; return }
    New-Item $ProfileDir -ItemType Directory -Force | Out-Null
    # Se reescribe con los ids válidos: el archivo original no se copia tal cual
    Write-ProfileFile (Get-CustomProfilePath $imported.Name) $imported.Name $imported.Apps
    Update-ProfileList ($CustomMark + $imported.Name)
    $note = if ($imported.Ignored) { " $($imported.Ignored) no existen en esta versión y se ignoran." } else { '' }
    Write-Log "Perfil importado: $($imported.Name) ($($imported.Apps.Count) elementos)"
    Set-Status "Perfil «$($imported.Name)» importado: $($imported.Apps.Count) elementos; lo que falta queda marcado.$note"
})
$ui.ProfileMore.Add_Click({
    $current = [string]$ui.Profile.SelectedItem
    $ui.ProfileDelete.IsEnabled = $current.StartsWith($CustomMark)
    $ui.ProfileDelete.Header = if ($current.StartsWith($CustomMark)) { "Eliminar «$($current.Substring($CustomMark.Length))»" } else { 'Eliminar perfil (solo los propios)' }
    $menu = $ui.ProfileMore.ContextMenu
    $menu.PlacementTarget = $ui.ProfileMore; $menu.Placement = 'Top'; $menu.IsOpen = $true
})
$ui.ProfileExport.Add_Click({
    $answer = Show-IwinDialog -Title 'Exportar perfil' -Text 'Crea un archivo .iwin.json con lo marcado. En el otro PC ábrelo con Importar…, o instálalo sin ventana con: iWinInstaller.ps1 -Silent -Perfil archivo.iwin.json' -Ok 'Elegir dónde guardarlo' -InputText (Get-ProfileSuggestion) -CheckText 'Incluir también lo que ya está instalado en este PC' -Checked $true
    if (-not $answer.Ok) { return }
    $name = Get-SafeProfileName $answer.Text
    if (-not $name) { $name = 'Perfil' }
    $ids = Get-SelectionIds $answer.Checked
    if (-not $ids) { Set-Status 'No hay nada marcado para exportar.'; return }
    $picker = New-Object Microsoft.Win32.SaveFileDialog
    $picker.Filter = $ProfileFilter; $picker.FileName = "$name.iwin.json"; $picker.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if (-not $picker.ShowDialog($win)) { return }
    $path = $picker.FileName
    if ($path -notmatch '\.json$') { $path += '.iwin.json' }
    try { Write-ProfileFile $path $name $ids; Set-Status "Perfil exportado con $($ids.Count) elementos: $path" }
    catch { Set-Status "No se pudo exportar: $($_.Exception.Message)" }
})
$ui.ProfileDelete.Add_Click({
    $current = [string]$ui.Profile.SelectedItem
    if (-not $current.StartsWith($CustomMark)) { return }
    $name = $current.Substring($CustomMark.Length)
    if (-not (Show-IwinDialog -Title "¿Eliminar el perfil «$name»?" -Text 'Solo se borra el perfil; las aplicaciones instaladas no cambian.' -Ok 'Eliminar' -Danger).Ok) { return }
    Remove-Item -LiteralPath (Get-CustomProfilePath $name) -Force -ErrorAction SilentlyContinue
    Update-ProfileList 'Manual'
    Set-Status "Perfil «$name» eliminado."
})
$ui.ProfileFolder.Add_Click({ New-Item $ProfileDir -ItemType Directory -Force | Out-Null; Start-Process explorer.exe $ProfileDir })

$ui.LogLink.Add_Click({ if (Test-Path $LogFile) { Start-Process notepad.exe $LogFile } else { Start-Process $LogDir } })
$ui.IgLink.Add_Click({ Start-Process $Instagram })
$exportDiagnostic = {
    try { $report = Export-Diagnostic; Set-Status "Diagnóstico guardado en Descargas: $([IO.Path]::GetFileName($report))"; Start-Process explorer.exe -ArgumentList ('/select,"' + $report + '"') }
    catch { Write-Log "No se pudo exportar: $($_.Exception.Message)"; Set-Status 'No se pudo guardar el diagnóstico. Consulta el registro.' }
}
$ui.BtnExport.Add_Click($exportDiagnostic)
$ui.MExport.Add_Click($exportDiagnostic)

# ---- Acciones de una fila: abrir, configuración y desinstalar ----
function Open-AppItem($item) {
    if (-not $item) { return }
    try {
        # Acceso del menú Inicio: nombre exacto o, si no, el más corto que empiece igual (p. ej. «7-Zip File Manager»)
        $shell = New-Object -ComObject Shell.Application
        $entries = @($shell.NameSpace('shell:AppsFolder').Items() | Where-Object { $_.Name -notmatch '(?i)uninstall|desinstal' })
        $found = @($entries | Where-Object { $_.Name -eq $item.Name })
        if (-not $found -and -not $item.OpensInConsole) {
            $found = @($entries | Where-Object { $_.Name.StartsWith($item.Name, [StringComparison]::OrdinalIgnoreCase) -or $item.Name.StartsWith($_.Name + ' ', [StringComparison]::OrdinalIgnoreCase) } | Sort-Object { $_.Name.Length })
        }
        if ($found) { $found[0].InvokeVerb(); Set-Status "Abriendo $($item.Name)…"; return }
        if ($item.OpensInConsole) { Open-CliItem $item; return }
        Start-Process explorer.exe 'shell:AppsFolder'; Set-Status "Elige $($item.Name) en la lista de aplicaciones."
    } catch { Write-Log "No se pudo abrir $($item.Name): $($_.Exception.Message)" }
}
# Herramientas de terminal: consola nueva con el PATH recién leído (la app pudo instalarse después de abrir iWinInstaller)
function Open-CliItem($item) {
    $app = $Apps | Where-Object id -eq $item.Id | Select-Object -First 1
    $cmd = @($app.commands)[0]
    $hint = if ($cmd) { "Escribe $cmd para usar $($item.Name)." } else { "$($item.Name) está disponible en esta terminal." }
    $script = "`$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User'); Write-Host '$($hint -replace "'", "''")' -ForegroundColor Cyan"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $shellExe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) { Start-Process $wt.Source -ArgumentList @('new-tab', '--title', "`"$($item.Name)`"", $shellExe, '-NoExit', '-EncodedCommand', $encoded) }
    else { Start-Process $shellExe -ArgumentList @('-NoExit', '-EncodedCommand', $encoded) }
    Set-Status "Terminal abierta para $($item.Name)."
}
function Switch-Configured($item) {
    if (-not $item -or -not $item.Installed -or -not $item.NeedsConfiguration) { return }
    $item.Configured = -not $item.Configured
    $ConfiguredApps[$item.Id] = $item.Configured
    $temporary = $ConfigFile + '.tmp'
    $ConfiguredApps | ConvertTo-Json | Set-Content $temporary -Encoding UTF8
    Move-Item $temporary $ConfigFile -Force
    Update-Filter
}

function Set-Busy($busy, [bool]$CanPause = $false) {
    $script:Busy = $busy
    foreach ($b in 'BtnInstall', 'BtnVerify', 'BtnUpdate', 'MUpdate', 'MAppUpdate', 'MAutoUpdate', 'BtnRemove', 'BtnResume', 'MResume', 'AfterCheckAll', 'Profile', 'ProfileSave', 'ProfileImport') { $ui[$b].IsEnabled = -not $busy }
    $win.Cursor = if ($busy) { [Windows.Input.Cursors]::AppStarting } else { $null }
    $ui.BtnCancel.Visibility = if ($busy -and $CanPause) { 'Visible' } else { 'Collapsed' }
    if (-not $busy) { Update-Count; Update-IwinRecoveryUi }
}

# Desinstala con confirmación; se puede pedir desde la fila, el menú, la tecla Supr o lo marcado
function Start-Uninstall($targets) {
    if ($script:Busy) { Set-Status 'Espera a que termine la operación en curso.'; return }
    $targets = @($targets | Where-Object { $_ -and ($_.Installed -or $_.HasPreviousState) -and $_.CanUninstall })
    if (-not $targets) { return }
    $list = ($targets | ForEach-Object { '•  ' + $_.Name }) -join "`n"
    $onlyTweaks = @($targets | Where-Object IsTweak).Count -eq $targets.Count
    $title = if ($targets.Count -eq 1) { "¿$($targets[0].UninstallLabel) $($targets[0].Name)?" } else { "¿Desinstalar $($targets.Count) elementos?" }
    $text = if ($onlyTweaks) { "Se recuperan los valores guardados antes del cambio (desde v3.2):`n$list" } else { "Se quita de este PC:`n$list`n`nSe usa el desinstalador oficial de cada aplicación; algunas abren su propio asistente. Tus documentos no se borran salvo que ese asistente lo pregunte." }
    $okText = if ($onlyTweaks) { 'Deshacer' } else { 'Desinstalar' }
    if (-not (Show-IwinDialog -Title $title -Text $text -Ok $okText -Danger).Ok) { return }
    $sel = @($Apps | Where-Object { $targets.Id -contains $_.id })
    Set-Busy $true $true; Show-Log $true
    $ui.Bar.Maximum = $sel.Count; $ui.Bar.Value = 0
    foreach ($a in $sel) { $byId[$a.id].Status = 'En cola'; $byId[$a.id].StatusKind = 'busy' }
    $fail = @(Invoke-Uninstall $sel {
        param($a, $ok)
        $it = $byId[$a.id]
        if ($ok) { $it.HasPreviousState=Test-IwinPreviousState $a; $it.Installed = if($it.IsTweak){Test-Tweak $a.id}else{$false}; $it.Checked = $false; $it.Status = $(if ($it.IsTweak) { 'Deshecho' } else { 'Desinstalada' }); $it.StatusKind = 'none' }
        else { $it.Status = 'Sigue instalada'; $it.StatusKind = 'bad' }
        if ($ui.Bar.Value -ge $ui.Bar.Maximum) { $ui.Bar.Maximum++ }
        $ui.Bar.Value++
        Set-Status "$($a.name) · $(if ($ok) {'quitada'} else {'sigue instalada'}) · $($ui.Bar.Value)/$($ui.Bar.Maximum)"
    })
    Set-Status $(if ($fail) { "Terminado: $($fail.Count) sigue(n) instalada(s). Consulta la actividad." } else { 'Desinstalación terminada.' })
    Update-Nav; Update-Filter
    Set-Busy $false
}

# Botones dentro de cada fila (Abrir / Desinstalar): un único manejador para toda la lista
$ui.List.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($s, $e)
    $button = $e.OriginalSource
    if (-not ($button -is [Windows.Controls.Button]) -or -not $button.Tag) { return }
    $item = $button.DataContext
    switch ([string]$button.Tag) {
        'setup' { Show-AfterInstall $item.Id }
        'open' { Open-AppItem $item }
        'uninstall' { Start-Uninstall @($item) }
    }
    $e.Handled = $true
})
$ui.List.Add_ContextMenuOpening({
    param($s, $e)
    $item = $ui.List.SelectedItem
    if (-not $item) { $e.Handled = $true; return }
    # Solo se muestran las acciones que tienen sentido para esa fila
    $show = { param($m, $on) $m.Visibility = if ($on) { 'Visible' } else { 'Collapsed' } }
    & $show $ui.MOpen $item.ShowOpen
    $ui.MOpen.Header = $item.OpenLabel
    & $show $ui.MConfigured ($item.Installed -and $item.NeedsConfiguration)
    $ui.MConfigured.Header = 'Pasos, notas y comprobación…'
    & $show $ui.MUninstall $item.ShowUninstall
    $ui.MUninstall.IsEnabled = -not $script:Busy
    $ui.MUninstall.Header = "$($item.UninstallLabel)…"
    if (-not ($item.ShowOpen -or $item.ShowUninstall -or ($item.Installed -and $item.NeedsConfiguration))) { $e.Handled = $true }
})
$ui.MOpen.Add_Click({ Open-AppItem $ui.List.SelectedItem })
$ui.MConfigured.Add_Click({ if($ui.List.SelectedItem){Show-AfterInstall $ui.List.SelectedItem.Id} })
$ui.MUninstall.Add_Click({ Start-Uninstall @($ui.List.SelectedItem) })
$ui.BtnRemove.Add_Click({ Start-Uninstall @($items | Where-Object { $_.Checked -and ($_.Installed -or $_.HasPreviousState) -and $_.CanUninstall }) })

# Teclado: Ctrl + F busca, Ctrl + +/−/0 cambia el tamaño, Espacio marca y Supr desinstala la fila
$win.Add_PreviewKeyDown({
    param($s, $e)
    $ctrl = [Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control
    if ($ctrl -and $e.Key -in @('OemPlus', 'Add')) { Set-Zoom ($ui.Zoom.ScaleX + 0.1); $e.Handled = $true }
    elseif ($ctrl -and $e.Key -in @('OemMinus', 'Subtract')) { Set-Zoom ($ui.Zoom.ScaleX - 0.1); $e.Handled = $true }
    elseif ($ctrl -and $e.Key -in @('D0', 'NumPad0')) { Set-Zoom 1; $e.Handled = $true }
    elseif ($ctrl -and $e.Key -eq 'F') { [void]$ui.Search.Focus(); $ui.Search.SelectAll(); $e.Handled = $true }
    elseif ($e.Key -eq 'Escape' -and $ui.ReportPanel.Visibility -eq 'Visible') { $ui.ReportPanel.Visibility = 'Collapsed'; $e.Handled = $true }
    elseif ($e.Key -eq 'Escape' -and $ui.AfterPanel.Visibility -eq 'Visible' -and -not $script:Busy) { $ui.AfterBack.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)));$e.Handled=$true }
    elseif ($e.Key -eq 'Escape' -and $ui.Search.IsKeyboardFocusWithin -and $ui.Search.Text) { $ui.Search.Text = ''; $e.Handled = $true }
    elseif ($ui.List.IsKeyboardFocusWithin -and $ui.List.SelectedItem) {
        if ($e.Key -eq 'Delete') { Start-Uninstall @($ui.List.SelectedItem); $e.Handled = $true }
        elseif ($e.Key -eq 'Space' -and $e.OriginalSource -is [Windows.Controls.ListBoxItem]) { $ui.List.SelectedItem.Checked = -not $ui.List.SelectedItem.Checked; $e.Handled = $true }
    }
})

# Comprueba qué está instalado; lo instalado se desmarca para no volver a instalarlo
function Invoke-Verify([switch]$Quiet) {
    if (-not (Ensure-Winget)) { Set-Status 'No se pudo preparar winget. Consulta el registro y vuelve a intentarlo.'; return }
    Set-Busy $true
    Set-Status 'Comprobando qué tienes instalado…'
    Update-WingetCache
    $ui.Bar.Maximum = $Apps.Count; $ui.Bar.Value = 0; $missing = @()
    foreach ($app in $Apps) {
        $it = $byId[$app.id]
        $it.HasPreviousState=Test-IwinPreviousState $app
        $it.Status = 'Comprobando…'; $it.StatusKind = 'busy'
        Invoke-UiPump
        $ready = Test-AppInstalled $app
        if ($ready) { $it.Installed = $true; $it.Status = 'Instalada'; $it.StatusKind = 'ok'; $it.Checked = $false }
        else {
            $it.Installed = $false
            if ($it.Optional) { $it.Status = ''; $it.StatusKind = 'none' }
            else { $it.Status = 'Falta'; $it.StatusKind = 'bad'; $missing += $app.name }
        }
        $ui.Bar.Value++
    }
    $total = @($Apps | Where-Object { -not (Test-Optional $_) }).Count
    $ok = $total - $missing.Count
    $msg = if ($missing) { "$ok de $total listas. Faltan: $($missing -join ', ')" } else { "Todo listo ($ok/$total)." }
    if (@(Get-IwinRebootPending).Count) { $msg += ' Hay cambios pendientes de reiniciar.' }
    if (-not $Quiet) { Write-Log "Verificación: $msg" }
    Set-Status $msg
    Update-Nav; Update-Filter
    Set-Busy $false
}

$ui.BtnVerify.Add_Click({ Invoke-Verify })
$updateAll = {
    if ($script:Busy) { return }
    Set-Busy $true $true; Show-Log $true
    Set-Status 'Actualizando aplicaciones…'
    $ok = Invoke-Update
    Set-Status $(if ($ok) { 'Actualización terminada.' } else { 'Actualización incompleta. Consulta el registro.' })
    Set-Busy $false
}
$ui.BtnUpdate.Add_Click($updateAll)
$ui.MUpdate.Add_Click($updateAll)
function Confirm-IwinPlan($selection, [string]$operation = 'install') {
    $plan = if ($operation -eq 'uninstall') { @($selection) } else { @(Get-InstallPlan $selection) }
    $preflightResult = if ($operation -eq 'uninstall') { [pscustomobject]@{Ok=$true;Text='Se usará el desinstalador oficial o el estado anterior guardado.'} } else { Get-IwinPreflight $plan }
    $lines=@($plan | ForEach-Object {
        $context = if ((Get-InstallContext $_) -eq 'machine') { 'administrador' } else { 'tu usuario' }
        $extra = if ($_.type -eq 'tweak') { ' · ajuste de Windows' } else { '' }
        if ($_.restart) { $extra += ' · reinicio o nueva sesión' }
        "• $($_.name) · $context$extra"
    })
    $title = if($operation -eq 'uninstall'){'Antes de reanudar la desinstalación'}else{'Antes de instalar'}
    $body = $preflightResult.Text + "`n`n" + ($lines -join "`n") + "`n`nPuedes pausar entre aplicaciones. No se reinicia Windows automáticamente."
    if (-not $preflightResult.Ok) { [void](Show-IwinDialog -Title 'Revisa el equipo antes de continuar' -Text $body -Ok 'Volver'); return $false }
    (Show-IwinDialog -Title $title -Text $body -Ok $(if($operation -eq 'uninstall'){'Reanudar'}else{'Continuar'})).Ok
}
function Start-IwinUiInstall($selection, $pending = $null) {
    if ($script:Busy) { return }
    Set-Busy $true $true
    try {
        if (-not (Confirm-IwinPlan $selection $(if($pending){$pending.Data.operation}else{'install'}))) { return }
        Show-Log $true
        $ui.Bar.Maximum = [math]::Max(1,$selection.Count); $ui.Bar.Value = 0
        $progress = {
            param($a,$ok)
            $it=$byId[$a.id]
            if (-not $it) { return }
            $it.HasPreviousState=Test-IwinPreviousState $a
            $reboot=(Test-IwinRebootCode $script:LastInstallCode) -or ($ok -and [bool]$a.restart)
            $removing=$script:Batch -and $script:Batch.operation -eq 'uninstall'
            if ($ok) {
                $it.Installed=if($removing){Test-AppInstalled $a}else{$true};$it.Checked=$false
                $it.Status=if($reboot){'Requiere reinicio'}elseif($removing){'Restaurada / retirada'}else{'Instalada'}
                $it.StatusKind=if($reboot){'busy'}else{'ok'}
            } else {
                $it.Status=if(Test-IwinStop){'Pendiente'}else{'No completada'};$it.StatusKind='bad';$it.Checked=$true
            }
            if ($ui.Bar.Value -ge $ui.Bar.Maximum) { $ui.Bar.Maximum++ }
            $ui.Bar.Value++
            Set-Status "$($a.name) · $($it.Status) · $($ui.Bar.Value)/$($ui.Bar.Maximum)"
        }
        $script:LastReport = $null
        $fail=if($pending){@(Resume-IwinBatch $pending $progress)}else{@(Invoke-Install $selection $progress)}
        $failedCount=@($fail | Where-Object { $_ -and $_.id } | ForEach-Object id | Select-Object -Unique).Count
        $msg=if(Test-IwinStop){'Lote pausado. Reanuda cuando quieras; no se interrumpió la aplicación en curso.'}elseif($failedCount){"Quedan $failedCount elementos pendientes: el informe explica cada uno."}else{'Instalación terminada. Abre «Después de instalar» para completar y comprobar la configuración.'}
        if (@(Get-IwinRebootPending).Count) { $msg += ' Hay cambios que requieren reiniciar Windows.' }
        Set-Status $msg
        Update-Nav; Update-Filter
    } catch { Write-Log "No se pudo completar: $($_.Exception.Message)"; Set-Status $_.Exception.Message }
    finally { Set-Busy $false }
    # Al terminar con algo pendiente se abre el informe con el motivo de cada fallo.
    if ($script:LastReport -and @($script:LastReport.items).Count) {
        try { Show-InstallReport $script:LastReport } catch { Write-Log "No se pudo mostrar el informe: $($_.Exception.Message)" }
    }
}
$ui.BtnInstall.Add_Click({
    $selection=@($Apps | Where-Object { $byId[$_.id].Checked -and -not $byId[$_.id].Installed })
    if($selection.Count){Start-IwinUiInstall $selection}
})
$ui.BtnCancel.Add_Click({ Request-IwinStop; $ui.BtnCancel.IsEnabled=$false; Set-Status 'Se pausará cuando termine esta aplicación. El resto quedará guardado.' })
$resumeClick={
    if($script:Busy){return}
    $pending=Get-IwinPendingBatches | Select-Object -First 1
    if(-not $pending){Update-IwinRecoveryUi;return}
    $ids=@($pending.Data.items | Where-Object state -ne 'done' | ForEach-Object id)
    $selection=@($Apps | Where-Object {$ids -contains $_.id})
    Start-IwinUiInstall $selection $pending
}
$ui.BtnResume.Add_Click($resumeClick)
$ui.MResume.Add_Click($resumeClick)
$win.Add_Closing({
    param($sender,$eventArgs)
    if($script:Busy){$eventArgs.Cancel=$true;Request-IwinStop;Set-Status 'Termina la aplicación actual antes de cerrar. Los pendientes están guardados.'}
    elseif($script:PostInstallState){try{Save-PostInstallState}catch{Write-Log 'No se pudieron guardar las notas.'}}
})


# Seguimiento por paso: el usuario confirma el uso; las pruebas técnicas se muestran aparte.
function Update-IwinRecoveryUi {
    $pending=@(Get-IwinPendingBatches)
    $ui.BtnResume.Visibility=if($pending.Count){'Visible'}else{'Collapsed'}
    $ui.MResume.IsEnabled=$pending.Count -gt 0 -and -not $script:Busy
    $ui.BtnCancel.IsEnabled=$true
    $reboot=@(Get-IwinRebootPending).Count
    $ui.BtnAfter.Content=if($reboot){'Después de instalar · reinicio'}else{'Después de instalar'}
    Update-Layout
}
function Update-AfterSummary {
    $remaining=0; $checked=0
    foreach($expander in $ui.AfterRows.Children){
        $row=$expander.Tag
        if(-not $row){continue}
        $entry=$script:PostInstallState[$row.App.id]
        $left=@($row.Guide.steps).Count - @($entry.steps | Where-Object {$_ -ge 0 -and $_ -lt @($row.Guide.steps).Count} | Select-Object -Unique).Count
        $remaining += $left
        $row.Header.Text=$row.App.name + $(if($left){" · $left paso(s) pendiente(s)"}else{' · pasos confirmados por ti'})
        if($row.TechnicalOk -eq $true){$checked++}
    }
    $ui.AfterSummary.Text="$(@($ui.AfterRows.Children | Where-Object Tag).Count) opciones · $remaining pasos pendientes · $checked comprobadas técnicamente en esta sesión. Las cuentas, vinculaciones y pruebas físicas las confirmas tú."
    if(@(Get-IwinRebootPending).Count){$ui.AfterSummary.Text+=' Reinicia Windows para terminar los cambios indicados y vuelve a comprobar.'}
}
function Sync-PostInstallManual($id) {
    $app=$Apps | Where-Object id -eq $id | Select-Object -First 1
    $guide=Get-PostInstallGuide $app
    $complete=@($script:PostInstallState[$id].steps | Select-Object -Unique).Count -eq @($guide.steps).Count
    $ConfiguredApps[$id]=$complete
    if($byId.ContainsKey($id)){$byId[$id].Configured=$complete}
    Save-PostInstallState
    Write-IwinJson $ConfigFile $ConfiguredApps
    Update-AfterSummary
    Update-Filter
}
function Invoke-AfterRowCheck($row) {
    $row.Technical.Text='Comprobando…'
    Invoke-UiPump
    $result=Test-PostInstall $row.App
    $row.Technical.Text=$result.Text
    $row.TechnicalOk=$result.Ok
    $row.Technical.Foreground=if($result.Ok){'#86DBA4'}else{'#EBC186'}
    Update-AfterSummary
}
function Show-AfterInstall([string]$focusId='') {
    if($script:Busy){Set-Status 'Espera a que termine o pausa el lote para revisar los pasos.';return}
    $ui.AfterRows.Children.Clear()
    $pendingIds=@(Get-IwinPendingBatches | ForEach-Object {$_.Data.items.id}) + @(Get-IwinRebootPending)
    $relevant=@($Apps | Where-Object {$_.postInstall -and ($byId[$_.id].Installed -or $_.id -eq $focusId -or $pendingIds -contains $_.id)})
    if(-not $relevant.Count){
        $empty=New-Object Windows.Controls.TextBlock
        $empty.Text='Aún no hay opciones que configurar. Instala una aplicación o abre «Pasos y notas» en su fila para consultar las instrucciones.'
        $empty.TextWrapping='Wrap';$empty.Foreground='#ADADB5';$empty.Margin='0,16,0,0'
        [void]$ui.AfterRows.Children.Add($empty)
    }
    foreach($app in $relevant){
        $guide=Get-PostInstallGuide $app
        if(-not $script:PostInstallState.ContainsKey($app.id)){$script:PostInstallState[$app.id]=@{steps=@();note=''}}
        $expander=New-Object Windows.Controls.Expander
        $expander.Style=$win.FindResource('AfterExpander')
        $expander.IsExpanded=($app.id -eq $focusId -or ($relevant.Count -eq 1))
        $header=New-Object Windows.Controls.TextBlock
        $header.TextWrapping='Wrap';$header.FontSize=15;$header.FontWeight='SemiBold';$header.Foreground='#F5F5F7'
        $expander.Header=$header
        $body=New-Object Windows.Controls.StackPanel
        $body.Margin='0,4,0,20'
        $technical=New-Object Windows.Controls.TextBlock
        $technical.Text='Sin comprobar en esta sesión. Los pasos marcados son tu confirmación manual.'
        $technical.TextWrapping='Wrap';$technical.Foreground='#ADADB5';$technical.Margin='0,0,0,12'
        [void]$body.Children.Add($technical)
        $row=[pscustomobject]@{App=$app;Guide=$guide;Header=$header;Technical=$technical;TechnicalOk=$null}
        $expander.Tag=$row
        for($index=0;$index -lt @($guide.steps).Count;$index++){
            $stepCheck=New-Object Windows.Controls.CheckBox
            $stepCheck.Style=$win.FindResource('PostStep')
            [Windows.Automation.AutomationProperties]::SetName($stepCheck,[string]$guide.steps[$index])
            $label=New-Object Windows.Controls.TextBlock
            $label.Text=$guide.steps[$index];$label.TextWrapping='Wrap';$label.Foreground='#E6E6EB'
            $stepCheck.Content=$label;$stepCheck.Margin='0,4,0,7';$stepCheck.Padding='4,0,0,0';$stepCheck.HorizontalContentAlignment='Stretch'
            $stepCheck.IsChecked=@($script:PostInstallState[$app.id].steps) -contains $index
            $stepCheck.Tag=@{Id=$app.id;Index=$index}
            $stepCheck.IsEnabled=-not $script:PostInstallReadOnly
            $stepCheck.Add_Click({
                param($sender)
                $id=$sender.Tag.Id;$index=[int]$sender.Tag.Index
                $entry=$script:PostInstallState[$id]
                $entry.steps=@($entry.steps | Where-Object {$_ -ne $index})
                if($sender.IsChecked){$entry.steps+= $index}
                try{Sync-PostInstallManual $id}catch{Set-Status "No se pudo guardar el seguimiento: $($_.Exception.Message)"}
            })
            [void]$body.Children.Add($stepCheck)
        }
        $note=New-Object Windows.Controls.TextBlock
        $note.Text=$guide.note;$note.TextWrapping='Wrap';$note.Foreground='#ADADB5';$note.Margin='0,10,0,12'
        [void]$body.Children.Add($note)
        $buttons=New-Object Windows.Controls.WrapPanel
        $verify=New-Object Windows.Controls.Button
        $verify.Content='Comprobar de nuevo';$verify.Style=$win.FindResource('Btn');$verify.Margin='0,0,8,8';$verify.Tag=$row
        $verify.Add_Click({param($sender)
            if($script:Busy){return}
            Set-Busy $true
            try{Update-LocalInventory -Appx;Invoke-AfterRowCheck $sender.Tag}catch{Set-Status $_.Exception.Message}finally{Set-Busy $false}
        })
        [void]$buttons.Children.Add($verify)
        if($byId[$app.id].CanOpen){
            $open=New-Object Windows.Controls.Button
            $open.Content=$byId[$app.id].OpenLabel;$open.Style=$win.FindResource('Btn');$open.Margin='0,0,8,8';$open.Tag=$app.id
            $open.Add_Click({param($sender)Open-AppItem $byId[[string]$sender.Tag]})
            [void]$buttons.Children.Add($open)
        }
        if($app.id -in @('sunshine','remotehost')){
            $panel=New-Object Windows.Controls.Button
            $panel.Content='Abrir panel de Sunshine';$panel.Style=$win.FindResource('Btn');$panel.Margin='0,0,8,8'
            $panel.Add_Click({Start-Process 'https://localhost:47990'})
            [void]$buttons.Children.Add($panel)
        }
        $guideUri=$null
        if($guide.link){try{$guideUri=[uri]$guide.link}catch{}}
        if($guideUri -and $guideUri.IsAbsoluteUri -and $guideUri.Scheme -eq 'https' -and -not $guideUri.UserInfo){
            $help=New-Object Windows.Controls.Button
            $help.Content=if($guide.linkLabel){$guide.linkLabel}else{'Ver instrucciones'}
            $help.Style=$win.FindResource('Btn');$help.Margin='0,0,8,8';$help.Tag=$guideUri.AbsoluteUri
            $help.Add_Click({param($sender)try{Start-Process ([string]$sender.Tag)}catch{Set-Status 'No se pudo abrir el navegador. Revisa tu navegador predeterminado.'}})
            [void]$buttons.Children.Add($help)
        }
        [void]$body.Children.Add($buttons)
        $label=New-Object Windows.Controls.TextBlock
        $label.Text='Tus notas · no incluyas contraseñas';$label.Foreground='#ADADB5';$label.Margin='0,6,0,6'
        [void]$body.Children.Add($label)
        $field=New-Object Windows.Controls.TextBox
        [Windows.Automation.AutomationProperties]::SetName($field,('Tus notas para '+$app.name))
        $field.Text=$script:PostInstallState[$app.id].note;$field.Tag=$app.id;$field.AcceptsReturn=$true;$field.TextWrapping='Wrap'
        $field.MinHeight=62;$field.MaxHeight=150;$field.VerticalScrollBarVisibility='Auto';$field.MaxLength=2000
        $field.Background='#1C1C20';$field.Foreground='#F5F5F7';$field.CaretBrush='#8CC4FF';$field.BorderBrush='#3B3B42';$field.Padding='10';$field.IsReadOnly=$script:PostInstallReadOnly
        $field.Add_TextChanged({param($sender)$script:PostInstallState[[string]$sender.Tag].note=$sender.Text})
        $field.Add_LostKeyboardFocus({try{Save-PostInstallState}catch{Set-Status 'No se pudieron guardar las notas. Comprueba el espacio y los permisos.'}})
        [void]$body.Children.Add($field)
        $expander.Content=$body
        [void]$ui.AfterRows.Children.Add($expander)
    }
    $ui.CatalogPanel.IsEnabled=$false;$ui.ActionPanel.IsEnabled=$false;$ui.Search.IsEnabled=$false
    $ui.CatalogPanel.Visibility='Hidden';$ui.ActionPanel.Visibility='Hidden'
    $ui.AfterPanel.Visibility='Visible'
    Update-AfterSummary
    if([Windows.SystemParameters]::ClientAreaAnimation){
        $fade=New-Object Windows.Media.Animation.DoubleAnimation(0.85,1,[TimeSpan]::FromMilliseconds(140))
        $ui.AfterPanel.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
    }
    $win.UpdateLayout()
    if($focusId){
        $target=$ui.AfterRows.Children | Where-Object {$_.Tag -and $_.Tag.App.id -eq $focusId} | Select-Object -First 1
        if($target){$position=$target.TranslatePoint((New-Object Windows.Point(0,0)),$ui.AfterScroll.Content);$ui.AfterScroll.ScrollToVerticalOffset($position.Y)}
    }
    [void]$ui.AfterBack.Focus()
}
$ui.BtnAfter.Add_Click({Show-AfterInstall})
$ui.MAfter.Add_Click({Show-AfterInstall})
$ui.AfterBack.Add_Click({
    try{Save-PostInstallState}catch{Set-Status 'No se pudieron guardar las notas.'}
    $ui.AfterPanel.Visibility='Collapsed'
    $ui.CatalogPanel.Visibility='Visible';$ui.ActionPanel.Visibility='Visible'
    $ui.CatalogPanel.IsEnabled=$true;$ui.ActionPanel.IsEnabled=$true;$ui.Search.IsEnabled=$true
    [void]$ui.BtnAfter.Focus()
})
$ui.AfterCheckAll.Add_Click({
    if($script:Busy){return}
    Set-Busy $true
    try{
        Update-LocalInventory -Appx
        foreach($expander in $ui.AfterRows.Children){if($expander.Tag){Invoke-AfterRowCheck $expander.Tag}}
        Set-Status 'Comprobación terminada. Revisa los resultados técnicos y los pasos manuales pendientes.'
    }catch{Set-Status $_.Exception.Message}finally{Set-Busy $false}
})

Update-IwinRecoveryUi

$ui.MAutoUpdate.IsChecked=$Prefs.autoUpdate
$ui.MAutoUpdate.Add_Click({
    if($script:Busy){$ui.MAutoUpdate.IsChecked=$Prefs.autoUpdate;return}
    $previous=$Prefs.autoUpdate
    try{
        Set-IwinAutoUpdate ([bool]$ui.MAutoUpdate.IsChecked)
        $Prefs.autoUpdate=[bool]$ui.MAutoUpdate.IsChecked
        Write-IwinJson $PrefsFile $Prefs
        Set-Status $(if($Prefs.autoUpdate){'Actualización automática activada: al abrir, al iniciar sesión y una vez al día. Solo iWinInstaller.'}else{'Actualización automática desactivada.'})
    }catch{
        $Prefs.autoUpdate=$previous;$ui.MAutoUpdate.IsChecked=$previous
        try{Set-IwinAutoUpdate $previous}catch{Write-Log 'No se pudo recuperar el estado anterior de la tarea; revísala en el Programador de tareas.'}
        Set-Status "No se pudo guardar el cambio: $($_.Exception.Message)"
    }
})
$ui.MAppUpdate.Add_Click({
    if($script:Busy){return}
    Set-Busy $true
    try{[void](Update-Self);Set-Status 'Consulta el resultado en Actividad. Si hay versión nueva, se aplica al cerrar.'}catch{Set-Status $_.Exception.Message}finally{Set-Busy $false}
})

# Iconos en segundo plano (la lista no espera a internet; sin red quedan las iniciales)
$IconDir = Join-Path $LogDir 'iconos'
try { [IwinIcons]::Start($items, $IconDir, $win.Dispatcher) } catch { }

# Al abrirse, comprueba lo instalado sin que haya que pulsar nada
$win.Add_ContentRendered({
    Update-Layout
    if ([Windows.SystemParameters]::ClientAreaAnimation) {
        $animation = New-Object Windows.Media.Animation.DoubleAnimation(0, 1, [TimeSpan]::FromMilliseconds(180))
        $win.BeginAnimation([Windows.UIElement]::OpacityProperty, $animation)
    }
    Invoke-Verify -Quiet
    if(-not $env:IWIN_PRUEBA_GUI){Clear-IwinUpdateDownloads}
    if($Prefs.autoUpdate -and -not $env:IWIN_PRUEBA_GUI){
        Set-Busy $true
        try{[void](Update-Self)}catch{Write-Log "Actualización pendiente: $($_.Exception.Message)"}finally{Set-Busy $false}
    }
})

# Prueba automática (GitHub Actions): construye la ventana y sale sin mostrarla
if ($env:IWIN_PRUEBA_GUI) {
    # Muestra y despacha eventos reales: construir XAML no ejecuta el arranque de la ventana.
    $win.WindowState = 'Normal'
    $win.Show()
    for ($pass=0; $pass -lt 10; $pass++) { Invoke-UiPump; Start-Sleep -Milliseconds 100 }
    if ($ui.Profile.SelectedItem -ne 'Manual' -or @($items | Where-Object Checked).Count) { throw 'La ventana debe abrir sin aplicaciones preseleccionadas.' }
    $expectedArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $expectedArchitectureLabel = switch ($expectedArchitecture) { 'AMD64' { 'x64' } default { $expectedArchitecture } }
    if ($ui.VersionText.Text -notmatch [regex]::Escape($expectedArchitectureLabel)) { throw "La ventana debe mostrar la arquitectura $expectedArchitectureLabel." }
    foreach ($profileName in @('Base','Gaming','Todo')) { $ui.Profile.SelectedItem=$profileName; Invoke-UiPump }
    Set-Busy $true
    $probe=$items | Select-Object -First 1
    $probe.Checked=-not $probe.Checked
    if ($ui.BtnInstall.IsEnabled) { throw 'No se puede iniciar otro lote mientras la app esta ocupada.' }
    Set-Busy $false

    # Zoom: se aplica, tiene límites y vuelve al 100 %
    Set-Zoom 1.5; Invoke-UiPump
    if ($ui.Zoom.ScaleX -ne 1.5 -or $ui.ZoomText.Text -ne '150 %') { throw 'El zoom no se aplica.' }
    Set-Zoom 0.1; if ($ui.Zoom.ScaleX -ne $ZoomMin) { throw 'El zoom debe tener un mínimo.' }
    Set-Zoom 9; if ($ui.Zoom.ScaleX -ne $ZoomMax) { throw 'El zoom debe tener un máximo.' }
    Set-Zoom 1

    # Informe al terminar: se pinta con fallos reales de ejemplo y se cierra con Escape
    $sample = [pscustomobject]@{ format='iWinInstaller-informe'; version=1; app=$Version; operation='install'; created='prueba'; total=3; ok=1; failed=1; manual=1; pending=0; reboot=@('WSL'); log=''
        items=@([pscustomobject]@{ id='pwsh'; name='PowerShell 7'; kind='fallo'; code=-2147024891; codeText='0x80070005'; reason='Acceso denegado al instalar.'; hint='Cierra la app y reintenta.'; details=@('Installer failed with exit code: 0x80070005') },
                [pscustomobject]@{ id='nortonvpn'; name='Norton VPN'; kind='manual'; code=0; codeText=''; reason='Se instala desde la web.'; hint='Completa su instalador.'; details=@() }) }
    Show-InstallReport $sample
    for ($pass=0; $pass -lt 3; $pass++) { Invoke-UiPump; Start-Sleep -Milliseconds 60 }
    if ($ui.ReportPanel.Visibility -ne 'Visible' -or $ui.ReportRows.Children.Count -lt 3 -or $ui.ReportRetry.Visibility -ne 'Visible') { throw 'El informe final debe mostrar una tarjeta por fallo y el reinicio pendiente.' }
    if ((Format-IwinReportText $sample) -notmatch 'PowerShell 7 \[pwsh\] · código 0x80070005') { throw 'El texto copiable del informe no es correcto.' }
    $ui.ReportPanel.Visibility = 'Collapsed'

    # Pantalla pequeña (máquina virtual 800x600 o menos): la lista sigue teniendo sitio
    foreach ($size in @(@(1180, 780), @(800, 600), @(600, 440))) {
        $win.Width = $size[0]; $win.Height = $size[1]
        for ($pass=0; $pass -lt 5; $pass++) { Invoke-UiPump; Start-Sleep -Milliseconds 60 }
        Update-Layout; Invoke-UiPump
        $listHeight = [int]$ui.List.ActualHeight; $listWidth = [int]$ui.List.ActualWidth
        Write-Host "Ventana $($size[0])x$($size[1]): lista ${listWidth}x$listHeight px, secciones $($ui.Sidebar.Visibility)"
        $minimum = if ($size[1] -ge 600) { 250 } else { 120 }
        if ($listHeight -lt $minimum) { throw "La lista queda demasiado baja en $($size[0])x$($size[1]): $listHeight px" }
        if ($size[0] -lt 860 -and $ui.Sidebar.Visibility -ne 'Collapsed') { throw 'En ventanas estrechas las secciones deben ocultarse.' }
    }
    $win.Width = 1180; $win.Height = 780; Invoke-UiPump

    # Marcar una app instalada la propone para desinstalar
    $probe = $items | Where-Object { $_.CanUninstall -and -not $_.IsTweak } | Select-Object -First 1
    $probe.Installed = $true; $probe.Checked = $true; Invoke-UiPump
    if ($ui.BtnRemove.Visibility -ne 'Visible' -or $ui.BtnRemove.Content -ne 'Desinstalar 1') { throw 'Lo instalado y marcado debe ofrecer Desinstalar.' }
    if (-not $probe.ShowUninstall) { throw 'La fila instalada debe mostrar Desinstalar.' }
    $probe.Checked = $false; $probe.Installed = $false; Invoke-UiPump
    if ($ui.BtnRemove.Visibility -ne 'Collapsed') { throw 'Sin nada instalado marcado no debe ofrecer Desinstalar.' }
    if (@($items | Where-Object { $_.Id -in @('vcredist', 'dotnet', 'msstore') -and $_.CanUninstall }).Count) { throw 'Los componentes del sistema no se ofrecen para desinstalar.' }
    # Etiqueta «Terminal» y forma de abrir: consola para las herramientas, la app para las terminales gráficas
    if (@($items | Where-Object { $_.IsCli -ne ($_.Section -eq 'Terminal') }).Count) { throw 'La etiqueta Terminal no coincide con la sección.' }
    if (-not ($byId['git'].CanOpen -and $byId['git'].OpensInConsole -and $byId['git'].OpenLabel -eq 'Abrir en terminal')) { throw 'Git debería abrirse en una terminal.' }
    if ($byId['terminal'].OpensInConsole -or -not $byId['vlc'].CanOpen -or $byId['nfhack'].CanOpen -or $byId['darkmode'].CanOpen) { throw 'Abrir no se ofrece donde corresponde.' }
    Write-Host "Etiqueta Terminal: $(@($items | Where-Object IsCli).Count) entradas; abrir en terminal: $(@($items | Where-Object OpensInConsole).Count)"

    # Diálogo propio
    $dialog = New-IwinDialog -Title 'Prueba' -Text 'Texto de prueba' -Ok 'Aceptar' -InputText 'Mi perfil' -CheckText 'Casilla' -Checked $true
    $dialog.Window.Show(); Invoke-UiPump
    if ($dialog.Parts.DInput.Text -ne 'Mi perfil' -or -not $dialog.Parts.DCheck.IsChecked) { throw 'El diálogo no muestra sus valores.' }
    $dialog.Window.Close()

    # Perfiles exportables: ida y vuelta, ids desconocidos ignorados y archivos ajenos rechazados
    $profileFile = Join-Path $env:TEMP ('iwin-perfil-' + [guid]::NewGuid().ToString('N') + '.iwin.json')
    try {
        Write-ProfileFile $profileFile 'Prueba <de> perfil' @('git', 'vscode', 'noexiste', 'git')
        $read = Read-ProfileFile $profileFile
        if ($read.Name -ne 'Prueba de perfil' -or @($read.Apps).Count -ne 2 -or $read.Ignored -ne 1) { throw "Perfil leído mal: $($read | ConvertTo-Json -Compress)" }
        if (@(Get-ProfileApps $profileFile).Count -ne 2) { throw 'Un perfil exportado debe poder instalarse por su ruta.' }
        Set-Content $profileFile '{"formato":"otro","apps":["git"]}' -Encoding UTF8
        $rejected = $false
        try { [void](Read-ProfileFile $profileFile) } catch { $rejected = $true }
        if (-not $rejected) { throw 'Un archivo que no es un perfil debe rechazarse.' }
    } finally { Remove-Item $profileFile -Force -ErrorAction SilentlyContinue }
    Write-Host 'Perfiles: exportar, importar y rechazar archivos ajenos OK'
    function Save-IwinUiSnapshot($name) {
        if(-not $env:RUNNER_TEMP){return}
        $dir=Join-Path $env:RUNNER_TEMP 'iwin-ui';New-Item $dir -ItemType Directory -Force | Out-Null
        $win.UpdateLayout();Invoke-UiPump
        $content=$win.Content
        $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$content.ActualWidth,[int]$content.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($content)
        $png=New-Object Windows.Media.Imaging.PngBitmapEncoder
        $png.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $dir ($name+'.png')))
        try{$png.Save($stream)}finally{$stream.Dispose()}
    }
    $win.Width=1180;$win.Height=780;Invoke-UiPump;Update-Layout
    Save-IwinUiSnapshot 'catalogo-escritorio'
    $previousLogDir=$LogDir;$previousConfig=$ConfigFile;$previousPostState=$script:PostInstallState;$previousConfigured=$ConfiguredApps.Clone()
    $postFixture=Join-Path $env:TEMP ('iwin-post-ui-'+[guid]::NewGuid().ToString('N'))
    try{
        $LogDir=$postFixture;$ConfigFile=Join-Path $postFixture 'configuracion.json';$script:PostInstallState=@{}
        Show-AfterInstall 'remotehost';Invoke-UiPump
        if($ui.AfterPanel.Visibility -ne 'Visible'){throw 'El panel de postinstalación debe abrirse sin salir de la app'}
        if($ui.CatalogPanel.IsEnabled -or $ui.ActionPanel.IsEnabled -or $ui.CatalogPanel.Visibility -ne 'Hidden' -or $ui.ActionPanel.Visibility -ne 'Hidden'){throw 'Los controles de catálogo no deben pintarse ni tomar foco detrás de las notas'}
        $row=$ui.AfterRows.Children | Where-Object {$_.Tag -and $_.Tag.App.id -eq 'remotehost'} | Select-Object -First 1
        if(-not $row -or -not $row.IsExpanded){throw 'La nota de la fila debe abrir sus pasos'}
        $field=$row.Content.Children | Where-Object {$_ -is [Windows.Controls.TextBox]} | Select-Object -First 1
        $field.Text="Vincular el Mac · prueba de notas largas con acentos y varias líneas.`nPendiente comprobar desde otra red."
        $stepControl=$row.Content.Children | Where-Object {$_ -is [Windows.Controls.CheckBox]} | Select-Object -First 1
        $stepControl.IsChecked=$true
        $stepControl.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        Save-PostInstallState
        $stored=Get-PostInstallState
        if($stored.remotehost.note -ne $field.Text -or @($stored.remotehost.steps).Count -ne 1){throw 'Pasos y notas deben guardarse desde los controles reales'}
        if($row.Tag.TechnicalOk -ne $null){throw 'Marcar pasos no demuestra una comprobación técnica'}
        Save-IwinUiSnapshot 'postinstalacion-escritorio'
        $win.Width=600;$win.Height=440;Invoke-UiPump;Update-Layout
        if($ui.AfterScroll.ActualHeight -lt 100){throw 'La postinstalación debe dejar espacio para desplazarse en una pantalla pequeña'}
        Save-IwinUiSnapshot 'postinstalacion-compacta'
        $ui.AfterBack.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        if($ui.AfterPanel.Visibility -ne 'Collapsed' -or -not $ui.CatalogPanel.IsEnabled -or -not $ui.ActionPanel.IsEnabled){throw 'Volver debe recuperar el catálogo y sus controles'}
        Save-IwinUiSnapshot 'catalogo-compacto'
    }finally{
        $LogDir=$previousLogDir;$ConfigFile=$previousConfig;$script:PostInstallState=$previousPostState;$ConfiguredApps=$previousConfigured
        $win.Width=1180;$win.Height=780
        Remove-Item $postFixture -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'Postinstalación: controles reales, notas, confirmación manual y ventanas de 1180x780/600x440 correctos.'


    # Las tres secciones filtran solo lo suyo
    foreach ($sec in @('Sistema','Terminal','Aplicaciones')) {
        $ui.Nav.SelectedItem = @($ui.Nav.ItemsSource) | Where-Object Key -eq "s:$sec" | Select-Object -First 1
        Invoke-UiPump
        $vis = @($view | ForEach-Object { $_ })
        if (-not $vis.Count -or @($vis | Where-Object Section -ne $sec).Count) { throw "La sección $sec no filtra bien." }
        Write-Host "Sección ${sec}: $($vis.Count) entradas"
    }
    $ui.Nav.SelectedIndex = 0; Invoke-UiPump
    $ui.Search.Text = 'spotify'
    $shown = @($view | ForEach-Object { $_.Name })
    $conIcono = @($Apps | Where-Object { $_.icon -and $_.icon -notlike 'glyph:*' }).Count
    $t = [Diagnostics.Stopwatch]::StartNew()
    while ([IwinIcons]::Loaded -lt $conIcono -and $t.Elapsed.TotalSeconds -lt 60) { Invoke-UiPump; Start-Sleep -Milliseconds 200 }
    Invoke-UiPump
    $sinIcono = @($items | Where-Object { -not $_.Image -and -not $_.Glyph } | ForEach-Object Name)
    Write-Host "Iconos: $([IwinIcons]::Loaded)/$conIcono descargados, $(@($items | Where-Object Glyph).Count) símbolos; sin icono: $($sinIcono -join ', ')"
    Write-Host "Ventana construida: $($items.Count) filas; buscar «spotify» deja $($shown.Count) visibles ($($shown -join ', '))"
    $win.Close()
    if ($script:FatalUiError) { exit 1 }
    exit 0
}
[void]$win.ShowDialog()
if ($script:FatalUiError) { exit 1 }
