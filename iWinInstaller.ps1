# iWinInstaller — Autoinstalador con interfaz gráfica para Windows 10 / 11
# Lee el catálogo de apps.json (y los perfiles de profiles.json); añadir una app = una entrada nueva.
# Uso:
#   Iniciar.bat / iWinInstaller.exe               ventana (interfaz nueva)
#   iWinInstaller.ps1 -Check [-Json]              informe ✓/✗ en consola (o JSON, ver docs/cli.md)
#   iWinInstaller.ps1 -Silent [-Perfil Gaming]    instala un perfil sin ventana
#   iWinInstaller.ps1 -Update [-Scheduled]        actualiza las aplicaciones instaladas (respeta exclusiones)
#   iWinInstaller.ps1 -Updates -List [-Json]      lista las actualizaciones disponibles
#   iWinInstaller.ps1 -Updates -Exclude <id>      mantiene una app en su versión (-Include la vuelve a actualizar)
#   iWinInstaller.ps1 -Status [-Json]             estado del PC (tarjetas del motor)
#   iWinInstaller.ps1 -Clean [-Categories a,b] [-Yes]  estima (o con -Yes, libera) espacio
#   iWinInstaller.ps1 -MachineReport <ruta>       informe del equipo en JSON (sin datos sensibles)
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
    # Mantenimiento (v4.9): -Clean [-Categories a,b] [-Yes]; -MachineReport <ruta> [-IncludeSensitive]
    [switch]$Clean,
    [string[]]$Categories,
    [switch]$Yes,
    [string]$MachineReport,
    [switch]$IncludeSensitive,
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

$Version = 'v5.2'
$Instagram = 'https://www.instagram.com/_shun._05/'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
# PowerShell 5.1 devuelve un array JSON como un solo objeto: «ForEach-Object { $_ }» lo desenrolla
$Apps = @(Get-Content (Join-Path $Root 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
$Profiles = Get-Content (Join-Path $Root 'profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ReleaseApi = 'https://api.github.com/repos/iShun05/iWinInstaller/releases/latest'
$UI = -not ($Check -or $Silent -or $Update -or $WorkerMode -or $Resume -or $AutoUpdate -or $EngineCommand -or $Updates -or $Status -or $Clean -or $MachineReport)

# Registro en archivo: %LOCALAPPDATA%\iWinInstaller\iWinInstaller_AAAA-MM-DD.log
$LogDir = Join-Path $env:LOCALAPPDATA 'iWinInstaller'
New-Item $LogDir -ItemType Directory -Force | Out-Null
$LogFile = Join-Path $LogDir ('iWinInstaller_{0:yyyy-MM-dd_HH-mm-ss-fff}.log' -f (Get-Date))
if ($WorkerMode -and $SharedLog) { $LogFile = $SharedLog }

# Equipos restringidos (AppLocker/WDAC): en ConstrainedLanguage el motor no puede funcionar. Se avisa a la
# interfaz con un motivo claro (código 12 del contrato) en lugar de fallar más adelante con un error opaco.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    $blocked = "PowerShell está en modo restringido ($($ExecutionContext.SessionState.LanguageMode)) por una directiva de este equipo (AppLocker o Control de aplicaciones). iWinInstaller no puede trabajar así: pide a quien administra el equipo que permita la carpeta de iWinInstaller."
    if ($EngineEvents) { try { Add-Content -LiteralPath $EngineEvents -Value ('{"type":"log","level":"error","text":"' + ($blocked -replace '"', "'") + '"}') -Encoding UTF8 } catch { } }
    Write-Host $blocked
    exit 12
}
# Proxy corporativo con autenticación integrada: se usan las credenciales de la sesión de Windows
try { if ([Net.WebRequest]::DefaultWebProxy) { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultCredentials } } catch { }

. (Join-Path $Root 'lifecycle.ps1')

# Motor: los archivos de src/engine se cargan en orden y comparten el ámbito del script.
$EngineFiles = @('01-Core.ps1', '02-Packages.ps1', '03-System.ps1', '04-Remote.ps1', '05-Rgb.ps1', '06-Tweaks.ps1', '07-Profiles.ps1', '08-Batch.ps1', '09-Contract.ps1', '10-Updates.ps1', '11-Status.ps1', '12-Install.ps1', '13-Tools.ps1', '14-Maintenance.ps1')
foreach ($engineFile in $EngineFiles) {
    $enginePath = Join-Path $Root "src\engine\$engineFile"
    if (-not (Test-Path -LiteralPath $enginePath)) { throw "Falta un archivo del motor: $engineFile. Ejecuta de nuevo iWinInstaller-Setup.exe." }
    . $enginePath
}

# Los registros antiguos no se acumulan sin límite (los lotes hijos comparten el registro del padre)
if (-not $WorkerMode) { Clear-IwinOldLogs $LogDir }

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

if ($Clean) {
    # Sin -Yes solo estima: nunca borra sin una confirmación explícita
    $estimate = & $IwinEngineCommands['maintenance.estimate'] ([pscustomobject]@{ contract = 1 })
    $chosen = @($estimate.categories | Where-Object { -not $Categories -or $Categories -contains $_.id })
    if (-not $Yes) {
        foreach ($row in $chosen) { Write-Host ("{0,-24} {1,10:N1} MB{2}" -f $row.id, ($row.estimatedBytes / 1MB), $(if ($row.admin) { '  (administrador)' } else { '' })) }
        Write-Host 'Añade -Yes para liberarlo.'
        exit 0
    }
    $done = & $IwinEngineCommands['maintenance.clean'] ([pscustomobject]@{ contract = 1; categories = @($chosen | ForEach-Object id) })
    foreach ($row in $done.categories) { Write-Host ("{0,-24} {1,10:N1} MB liberados{2}" -f $row.id, ($row.freedBytes / 1MB), $(if ($row.denied) { '  (permiso denegado)' } else { '' })) }
    exit @($done.categories | Where-Object { $_.denied }).Count
}

if ($MachineReport) {
    $saved = & $IwinEngineCommands['report.machine'] ([pscustomobject]@{ contract = 1; path = [IO.Path]::GetFullPath($MachineReport); includeSensitive = [bool]$IncludeSensitive })
    Write-Host "Informe del equipo: $($saved.path)"
    exit 0
}

if ($Silent) {
    try { $sel = @(Get-ProfileApps $Perfil) } catch { Write-Log "No se pudo leer el perfil: $($_.Exception.Message)"; exit 1 }
    if (-not $sel) { Write-Log "Perfil desconocido o vacío: $Perfil (disponibles: $((@($Profiles.PSObject.Properties.Name) + @((Get-CustomProfiles).Keys)) -join ', '), o la ruta de un .iwin.json)"; exit 1 }
    if (-not (Ensure-Winget)) { exit 1 }
    Write-Log "Modo sin ventana · perfil $Perfil"
    $fail = @(Invoke-Install $sel $null)
    exit $fail.Count
}

# ---------- Ventana ----------
# Desde v5.0 la única ventana es la interfaz nueva (iWinInstaller.App.exe). Este script es el motor y la consola.
$appExe = Join-Path $Root 'iWinInstaller.App.exe'
if (Test-Path -LiteralPath $appExe) { Start-Process -FilePath $appExe -WorkingDirectory $Root; exit 0 }
Write-Host 'Falta la interfaz (iWinInstaller.App.exe). Instala iWinInstaller desde su release o compílala con scripts/build_exe.ps1.'
Write-Host 'Sin ventana sigue disponible la consola: -Check, -Silent, -Update, -Updates, -Status, -Clean… (ver docs/cli.md).'
exit 1
