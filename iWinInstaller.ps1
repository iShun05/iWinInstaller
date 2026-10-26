# iWinInstaller — Autoinstalador con interfaz gráfica para Windows 10 / 11
# Lee el catálogo de apps.json (y los perfiles de profiles.json); añadir una app = una entrada nueva.
# Uso:
#   Iniciar.bat                                   ventana
#   iWinInstaller.ps1 -Check                      informe ✓/✗ en consola
#   iWinInstaller.ps1 -Silent [-Perfil Gaming]    instala un perfil sin ventana
#   iWinInstaller.ps1 -Update                     actualiza las aplicaciones instaladas
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
    [switch]$AutoUpdate
)
$ProgressPreference = 'SilentlyContinue'
# Salida de herramientas en UTF-8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'

$Version = 'v3.2'
$Instagram = 'https://www.instagram.com/_shun._05/'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
# PowerShell 5.1 devuelve un array JSON como un solo objeto: «ForEach-Object { $_ }» lo desenrolla
$Apps = @(Get-Content (Join-Path $Root 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
$Profiles = Get-Content (Join-Path $Root 'profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ReleaseApi = 'https://api.github.com/repos/iShun05/iWinInstaller/releases/latest'
$UI = -not ($Check -or $Silent -or $Update -or $WorkerMode -or $Resume -or $AutoUpdate)

# Registro en archivo: %LOCALAPPDATA%\iWinInstaller\iWinInstaller_AAAA-MM-DD.log
$LogDir = Join-Path $env:LOCALAPPDATA 'iWinInstaller'
New-Item $LogDir -ItemType Directory -Force | Out-Null
$LogFile = Join-Path $LogDir ('iWinInstaller_{0:yyyy-MM-dd_HH-mm-ss-fff}.log' -f (Get-Date))
if ($WorkerMode -and $SharedLog) { $LogFile = $SharedLog }

. (Join-Path $Root 'lifecycle.ps1')

# ---------- Utilidades comunes ----------
$log = $null
function Write-Log($msg) {
    $line = "$(Get-Date -Format HH:mm:ss)  $msg"
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
    $detail = $msg -match '^    '
    if ($WorkerMode -and $ResultFile -and -not $detail) { Write-WorkerEvent @{message=[string]$msg} }
    if ($detail) { return }
    if ($log) { $log.AppendText("$line`r`n"); $log.ScrollToEnd(); Invoke-UiPump }
    elseif ($Check) { Write-Host $msg }
    else { Write-Host $line }
}

# Procesa los eventos de la ventana (WPF) para que no se congele durante las instalaciones
function Invoke-UiPump {
    if (-not $UI -or -not ('Windows.Threading.Dispatcher' -as [type])) { return }
    $f = New-Object Windows.Threading.DispatcherFrame
    [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [Action]{ $f.Continue = $false })
    [Windows.Threading.Dispatcher]::PushFrame($f)
}

# Espera a un proceso sin congelar la ventana; si pasa del límite lo cierra (winget a veces se queda colgado)
function Wait-Proc($p, [int]$timeoutSec = 1800) {
    if (-not $p) { return }
    $t = [Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited) {
        if ($t.Elapsed.TotalSeconds -gt $timeoutSec) {
            Write-Log "  Sin respuesta tras $timeoutSec s: se cancela $($p.ProcessName)."
            try { $p.Kill() } catch { }
            return
        }
        Invoke-UiPump; Start-Sleep -Milliseconds 80
    }
    $p.WaitForExit()
}

# winget no actualiza el PATH de este proceso: se relee tras instalar Git, GitHub CLI o Python.
function Update-EnvPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Get-NormName($s) { ($s -replace '@.*$', '' -replace '[^A-Za-z0-9]', '').ToLower() }
function Test-Cmd($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# Un error de stderr al comprobar una herramienta significa que hay que repararla, no cerrar la app.
function Test-WingetReady {
    if (-not (Test-Cmd winget)) { return $false }
    $previous=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $global:LASTEXITCODE=1
        & winget --version *> $null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
    finally { $ErrorActionPreference=$previous }
}

# La distribucion EXE incluye los paquetes oficiales y sus huellas verificadas al compilar.
function Install-BundledWinget {
    $dir=Join-Path $Root 'prerequisites'
    if (-not (Test-Path $dir)) { return $false }
    $temporary=Join-Path $env:TEMP ('iwin-deps-'+[guid]::NewGuid().ToString('N'))
    try {
        $metadata=Get-Content (Join-Path $Root 'native\prerequisites.json') -Raw | ConvertFrom-Json
        foreach ($asset in $metadata.assets) {
            $file=Join-Path $dir $asset.name
            if (-not (Test-Path $file) -or (Get-FileHash $file).Hash.ToLowerInvariant() -ne $asset.digest.Substring(7)) { throw "Paquete incluido dañado: $($asset.name)" }
        }
        Write-Log 'Preparando winget con los archivos de Microsoft incluidos...'
        Expand-Archive (Join-Path $dir 'DesktopAppInstaller_Dependencies.zip') $temporary
        $arch=if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        $folder=switch ($arch) { 'AMD64' {'x64'} 'ARM64' {'arm64'} 'x86' {'x86'} default {throw 'Arquitectura no compatible'} }
        $files=@(Get-ChildItem (Join-Path $temporary $folder) -Recurse -File | Where-Object Extension -in @('.appx','.msix'))
        if (-not $files.Count) { throw 'Faltan las dependencias de la arquitectura actual.' }
        # Las dependencias que Windows ya tiene en esa versión o más nueva se omiten: reinstalarlas falla
        # (0x80073D02) si alguna app del sistema las está usando, como Widgets en Windows 11 ARM.
        $dependencies=@($files | Where-Object {
            if ($_.BaseName -notmatch '^(?<name>[^_]+)_(?<version>\d+(\.\d+){1,3})') { return $true }
            $name=$Matches.name; $version=[version]$Matches.version
            -not @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue | Where-Object { [version]$_.Version -ge $version }).Count
        } | ForEach-Object FullName)
        Write-Log "  Dependencias: $($dependencies.Count) de $($files.Count) (el resto ya está en Windows)."
        $add=@{Path=(Join-Path $dir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'); ErrorAction='Stop'}
        if ($dependencies.Count) { $add.DependencyPath=$dependencies }
        try { Add-AppxPackage @add }
        catch {
            # Si App Installer ya está en esa versión basta con registrarlo para el usuario
            if ($_.Exception.Message -notmatch '0x80073D06|0x80073D02') { throw }
            Write-Log "  $($_.Exception.Message.Split([char]10)[0])"
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        }
        Update-EnvPath
        return (Test-WingetReady)
    } catch { Write-Log "  No se pudo preparar el paquete incluido: $($_.Exception.Message)" }
    finally { Remove-Item $temporary -Recurse -Force -ErrorAction SilentlyContinue }
    return $false
}

# Prepara winget solo si falta o no responde, sin sustituir una instalacion funcional.
function Ensure-Winget {
    Update-EnvPath
    if (Test-WingetReady) { return $true }
    if (Install-BundledWinget) { return $true }
    Write-Log 'Preparando el instalador de aplicaciones de Windows…'
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
    } catch { Write-Log '  App Installer aún no está disponible: se intenta el método oficial de Microsoft.' }
    Update-EnvPath
    if (Test-WingetReady) { return $true }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Repair-WinGetPackageManager -Latest -ErrorAction Stop | Out-Null
        Update-EnvPath
        if (Test-WingetReady) { return $true }
        throw 'winget sigue sin estar disponible'
    } catch {
        Write-Log "  No se pudo preparar winget: $($_.Exception.Message). Instala o actualiza App Installer desde Microsoft Store y vuelve a intentarlo."
        return $false
    }
}


# Ejecuta una herramienta de consola volcando su salida al registro; devuelve el código de salida.
function Invoke-Logged($exe, [string[]]$argv) {
    & $exe @argv 2>&1 | ForEach-Object { Write-Log "    $_" }
    $LASTEXITCODE
}

# Ejecuta PowerShell como administrador (pide UAC). Devuelve $true si terminó bien.
function Invoke-Elevated($cmd) {
    $cmd = '$ErrorActionPreference = ''Stop''; ' + $cmd + '; if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }'
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    try {
        $start = @{FilePath='powershell'; PassThru=$true; WindowStyle='Hidden'; ArgumentList=@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)}
        if (-not (Test-Administrator)) { $start.Verb = 'RunAs' }
        $p = Start-Process @start
        Wait-Proc $p
        return ($p.HasExited -and $p.ExitCode -eq 0)
    } catch {
        Write-Log '  Permiso de administrador denegado.'
        return $false
    }
}

# ---------- winget ----------
# winget devuelve estos códigos cuando la app ya estaba instalada / sin actualización: se consideran éxito.
$wingetOk = @(0, 3010, 1641, -1978334967, -1978334965, -1978335135, -1978335189)

# Argumentos comunes de winget: id exacto y, si la entrada lo indica, origen (p. ej. msstore para ChatGPT).
function Get-WingetArgs($app) {
    $a = @('-e', '--id', $app.winget)
    $source = if ($app.source) { $app.source } else { 'winget' }
    $a += @('--source', $source)
    $a
}

# Ids instalados según «winget export» (una sola llamada para todo el catálogo; $null si falla)
$WingetIds = $null
function Update-WingetCache {
    $script:WingetIds = $null
    if (-not (Test-Cmd winget)) { return }
    Update-LocalInventory -Appx
    $tmp = Join-Path $env:TEMP ('iwin_export_' + [Guid]::NewGuid().ToString('N') + '.json')
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $p = Start-Process winget -PassThru -WindowStyle Hidden -ArgumentList @('export', '--source', 'winget', '-o', ('"' + $tmp + '"'), '--accept-source-agreements', '--disable-interactivity')
    Wait-Proc $p 180
    if (Test-Path $tmp) {
        try { $script:WingetIds = @((Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json).Sources.Packages.PackageIdentifier) } catch { }
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# Inventario local: no consulta internet por cada tarjeta.
$RegistryApps = @()
$AppxApps = @()
function Update-LocalInventory([switch]$Appx) {
    $keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $script:RegistryApps = @(Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName)
    if ($Appx) { $script:AppxApps = @(Get-AppxPackage -ErrorAction SilentlyContinue) }
    Update-EnvPath
}
function Test-LocalApp($app) {
    $names = @($app.name) + @($app.detectNames) + @($app.detect)
    foreach ($entry in $RegistryApps) {
        foreach ($name in $names) {
            if ($name -and ($entry.DisplayName -eq $name -or $entry.DisplayName -match ('^' + [regex]::Escape($name) + '(?:\s+\d|\s*\()'))) { return $true }
        }
    }
    foreach ($pkg in $AppxApps) {
        if (@($app.families) -contains $pkg.PackageFamilyName -and (-not $app.architecture -or [string]$pkg.Architecture -eq $app.architecture)) { return $true }
        $short = ([string]$pkg.Name -split '\.')[-1] -replace 'Desktop$', ''
        if ((Get-NormName $short) -eq (Get-NormName $app.name)) { return $true }
    }
    foreach ($command in @($app.commands)) {
        if ($command) {
            $found = Get-Command $command -ErrorAction SilentlyContinue
            if ($found -and $found.CommandType -eq 'Application' -and $found.Source -notlike '*WindowsApps\python*.exe') { return $true }
        }
    }
    return $false
}
function Test-Administrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-InstallContext($app) {
    if ($app.context) { return $app.context }
    if ($app.type -eq 'tweak') { return 'machine' }
    return 'user'
}

# Conserva stdout, stderr, codigo y duracion para poder diagnosticar fallos reales.
function Invoke-Winget([string[]]$arguments, [string]$label, [int]$timeoutSec = 900) {
    $stem = Join-Path $LogDir ('winget-' + ($label -replace '[^A-Za-z0-9_-]', '_') + '-' + [Guid]::NewGuid().ToString('N'))
    $quoted = @($arguments | ForEach-Object {
        if ($_ -match '"') { throw 'Argumento de winget no valido.' }
        '"' + $_ + '"'
    }) -join ' '
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process winget -PassThru -WindowStyle Hidden -ArgumentList $quoted -RedirectStandardOutput "$stem.out.txt" -RedirectStandardError "$stem.err.txt"
    $null = $p.Handle
    $phase = ''
    while (-not $p.HasExited -and $timer.Elapsed.TotalSeconds -lt $timeoutSec) {
        $tail = if (Test-Path "$stem.out.txt") { (Get-Content "$stem.out.txt" -Tail 8 -ErrorAction SilentlyContinue) -join ' ' } else { '' }
        $nextPhase = if ($tail -match '(?i)uninstall|Desinstalando') { 'Desinstalando' } elseif ($tail -match '(?i)Starting.*install|Installing|Instalando|Starting package') { 'Instalando' } elseif ($tail -match '(?i)verified|verificado|hash') { 'Verificando' } elseif ($tail -match '(?i)Downloading|Descargando') { 'Descargando' } else { $phase }
        if ($nextPhase -and $nextPhase -ne $phase) {
            $phase = $nextPhase
            Write-Log "  $label · $phase…"
            if ($WorkerMode -and $ResultFile) { Write-WorkerEvent @{current=$label; phase=$phase} }
            elseif ($UI -and $byId -and $byId.ContainsKey($label)) { $byId[$label].Status=$phase+'…'; Set-Status "$($byId[$label].Name) · $phase…" }
        }
        Invoke-UiPump; Start-Sleep -Milliseconds 200
    }
    Wait-Proc $p 1
    $code = if ($p.HasExited) { $p.ExitCode } else { -1 }
    foreach ($file in @("$stem.out.txt", "$stem.err.txt")) {
        if (Test-Path $file) {
            Get-Content $file -Encoding UTF8 | ForEach-Object {
                $line = ($_ -replace '\x1b\[[0-9;?]*[A-Za-z]', '').Trim()
                if ($line -and $line -notmatch '^[-\\|/ ]+$') { Write-Log "    $line" }
            }
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Log "  $label · codigo $code · $([math]::Round($timer.Elapsed.TotalSeconds, 1)) s"
    if ($label -notlike '*-verificar') { $script:LastInstallCode = $code }
    return $code
}
# Google cambia el MSI estable sin mantener la huella del catalogo: exige su firma valida.
function Install-Chrome($app) {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $name = switch ($arch) { 'AMD64' { 'googlechromestandaloneenterprise64.msi' } 'ARM64' { 'googlechromestandaloneenterprise_arm64.msi' } 'x86' { 'googlechromestandaloneenterprise.msi' } default { throw 'Arquitectura de Chrome no compatible.' } }
    $msi = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N') + '.msi')
    $msiLog = Join-Path $LogDir ('chrome-msi-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    $client = New-Object Net.WebClient
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Log '  Descargando Chrome desde Google...'
        $download = $client.DownloadFileTaskAsync([uri]('https://dl.google.com/dl/chrome/install/' + $name), $msi)
        while (-not $download.IsCompleted) {
            if ($timer.Elapsed.TotalMinutes -gt 10) { $client.CancelAsync(); throw 'Tiempo de descarga de Chrome agotado.' }
            Invoke-UiPump; Start-Sleep -Milliseconds 100
        }
        [void]$download.GetAwaiter().GetResult()
        $signature = Get-AuthenticodeSignature $msi
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)(?:CN|O)=Google LLC(?:,|$)') { throw 'El instalador de Chrome no tiene una firma valida de Google LLC.' }
        Write-Log "  Firma de Google comprobada; SHA256 $((Get-FileHash $msi -Algorithm SHA256).Hash)"
        $p = Start-Process msiexec.exe -PassThru -WindowStyle Hidden -ArgumentList "/i `"$msi`" /qn /norestart /L*v `"$msiLog`""
        $null = $p.Handle
        Wait-Proc $p 900
        $code = if ($p.HasExited) { $p.ExitCode } else { -1 }
        $script:LastInstallCode = $code
        Write-Log "  chrome · codigo $code · $([math]::Round($timer.Elapsed.TotalSeconds,1)) s"
        if ($code -notin @(0,3010)) { return $false }
        Update-LocalInventory
        if (Test-LocalApp $app) { $script:WingetIds += 'Google.Chrome'; return $true }
        return $false
    } finally {
        if (Test-Path $msiLog) { Get-Content $msiLog -Tail 200 -Encoding UTF8 | ForEach-Object { Write-Log "    $_" }; Remove-Item $msiLog -Force -ErrorAction SilentlyContinue }
        $client.Dispose()
        Remove-Item $msi -Force -ErrorAction SilentlyContinue
    }
}
function Install-WingetPackage($app, [string]$id) {
    if ($id -eq 'Google.Chrome') { return (Install-Chrome $app) }
    $source = if ($app.source) { $app.source } else { 'winget' }
    $operation = if ($UpgradePackages) { 'upgrade' } else { 'install' }
    $arguments = @($operation, '-e', '--id', $id, '--source', $source, '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')
    if ($app.scope) { $arguments += @('--scope', $app.scope) }
    if ($app.architecture) { $arguments += @('--architecture', $app.architecture) }
    $code = Invoke-Winget $arguments $app.id
    if ($code -notin $wingetOk) { return $false }
    if (Test-IwinRebootCode $code) { Write-Log '  Requiere reiniciar Windows y volver a verificar.'; return $true }
    Update-LocalInventory -Appx:((Get-InstallContext $app) -eq 'user')
    # El codigo de exito no basta: debe aparecer en el inventario o en winget list.
    if ($app.type -ne 'wingetall' -and (Test-LocalApp $app)) { $script:WingetIds += $id; return $true }
    if ($app.architecture -and $app.families) { Write-Log '  No se confirma la arquitectura requerida del paquete.'; return $false }
    $check = Invoke-Winget @('list', '-e', '--id', $id, '--source', $source, '--disable-interactivity', '--accept-source-agreements') ($app.id + '-verificar') 45
    if ($check -eq 0) { $script:WingetIds += $id; return $true }
    return $false
}

function Write-WorkerEvent($event) {
    Add-Content $ResultFile ($event | ConvertTo-Json -Compress) -Encoding UTF8
}
function Invoke-InstallWorker($selection, [scriptblock]$onProgress, [switch]$AsUser, [switch]$Remove) {
    $stem = Join-Path $env:TEMP ('iwin-batch-' + [Guid]::NewGuid().ToString('N'))
    $plan = "$stem.plan.json"; $result = "$stem.result.jsonl"
    @($selection | ForEach-Object id) | ConvertTo-Json -Compress | Set-Content $plan -Encoding UTF8
    New-Item $result -ItemType File -Force | Out-Null
    if (Test-IwinStop) { foreach ($app in $selection) { Complete-IwinItem $app $false $onProgress; $app }; return }
    $script:ActiveCancelFile = $plan + '.cancel'
    $mode = if ($AsUser) { 'user' } else { 'machine' }
    $args0 = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Root 'iWinInstaller.ps1')`" -WorkerMode $mode -PlanFile `"$plan`" -ResultFile `"$result`" -SharedLog `"$LogFile`""
    if ($UpgradePackages) { $args0 += ' -UpgradePackages' }
    if ($Remove) { $args0 += ' -RemovePackages' }
    $busyText = if ($Remove) { 'Desinstalando…' } else { 'Instalando…' }
    $process = $null; $seen = 0; $reported = @{}; $done = $false; $exitedOnce = $false
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ($AsUser) {
            # Explorer ejecuta las apps por usuario con el token de la sesion de escritorio.
            $shell = New-Object -ComObject Shell.Application
            $desktop = @($shell.Windows() | Where-Object { [IO.Path]::GetFileName($_.FullName) -eq 'explorer.exe' }) | Select-Object -First 1
            if (-not $desktop) {
                $shell.Explore('shell:AppsFolder')
                for ($attempt=0; $attempt -lt 20 -and -not $desktop; $attempt++) {
                    Invoke-UiPump; Start-Sleep -Milliseconds 250
                    $desktop = @($shell.Windows() | Where-Object { [IO.Path]::GetFileName($_.FullName) -eq 'explorer.exe' }) | Select-Object -First 1
                }
            }
            if (-not $desktop) { throw 'No se encuentra la sesion de escritorio para instalar las apps por usuario.' }
            $desktop.Document.Application.ShellExecute('powershell.exe', $args0, $Root, 'open', 0)
        } else {
            $start = @{ FilePath = 'powershell.exe'; ArgumentList = $args0; PassThru = $true; WindowStyle = 'Hidden' }
            if (-not (Test-Administrator)) { $start.Verb = 'RunAs' }
            $process = Start-Process @start
        }
        while (-not $done) {
            $lines = @(Get-Content $result -Encoding UTF8 -ErrorAction SilentlyContinue)
            while ($seen -lt $lines.Count) {
                try { $event = $lines[$seen] | ConvertFrom-Json -ErrorAction Stop } catch { break }
                $seen++
                if ($event.started) { $timer.Restart(); if ($AsUser -and $event.pid -is [int]) { $process = Get-Process -Id $event.pid -ErrorAction SilentlyContinue } }
                if ($event.message -is [string] -and $event.message.Length -le 2000 -and $log) {
                    $log.AppendText("$(Get-Date -Format HH:mm:ss)  $($event.message)`r`n"); $log.ScrollToEnd()
                }
                if ($event.current) { $currentApp=$selection | Where-Object id -eq $event.current | Select-Object -First 1; if($currentApp){Set-IwinBatchRunning $currentApp} }
                if ($event.current -and $UI -and $byId -and $byId.ContainsKey($event.current)) {
                    $byId[$event.current].Status = $busyText; $byId[$event.current].StatusKind = 'busy'
                    if ($event.phase -in @('Descargando','Instalando','Verificando','Desinstalando')) { $byId[$event.current].Status=$event.phase+'…'; Set-Status "$($byId[$event.current].Name) · $($event.phase)…" } else { Set-Status "$($busyText.TrimEnd('…')) $($byId[$event.current].Name)…" }
                }
                if ($event.id -and $event.ok -is [bool]) {
                    $app = $selection | Where-Object id -eq $event.id | Select-Object -First 1
                    if ($app -and -not $reported.ContainsKey($event.id)) {
                        $reported[$event.id] = [bool]$event.ok
                        $script:LastInstallCode = if ($event.code -is [int] -or $event.code -is [long]) { $event.code } else { 0 }
                        Complete-IwinItem $app ([bool]$event.ok) $onProgress
                    }
                }
                if ($event.done) { $done = $true }
            }
            if ($done) { break }
            if ($process -and $process.HasExited) { if ($exitedOnce) { break }; $exitedOnce=$true; continue }
            if ($seen -eq 0 -and $timer.Elapsed.TotalSeconds -gt 45) { throw 'El lote no llego a iniciarse.' }
            if ($timer.Elapsed.TotalHours -gt 3) { throw 'El lote supero su limite de tiempo.' }
            Invoke-UiPump; Start-Sleep -Milliseconds 250
        }
    } catch { Write-Log "  No se pudo completar el lote $mode`: $($_.Exception.Message)" }
    finally { Remove-Item $plan, $result, ($plan + '.cancel') -Force -ErrorAction SilentlyContinue; $script:ActiveCancelFile=$null }
    foreach ($app in $selection) {
        if (-not $reported.ContainsKey($app.id)) { $script:LastInstallCode=0; Complete-IwinItem $app $false $onProgress; $app }
        elseif (-not $reported[$app.id]) { $app }
    }
    Update-LocalInventory -Appx
}

function Export-Diagnostic {
    $downloadPath = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' '{374DE290-123F-4565-9164-39C4925E467B}'
    $downloads = if ($downloadPath) { [Environment]::ExpandEnvironmentVariables($downloadPath) } else { Join-Path $env:USERPROFILE 'Downloads' }
    New-Item $downloads -ItemType Directory -Force | Out-Null
    $destination = Join-Path $downloads ('iWinInstaller-diagnostico-' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '.txt')
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $header = "iWinInstaller $Version`r`nWindows: $($os.Caption) $($os.Version)`r`nArquitectura: $env:PROCESSOR_ARCHITECTURE`r`nAdministrador: $(Test-Administrator)`r`nFecha: $(Get-Date -Format o)`r`n`r`n"
    $body = if (Test-Path $LogFile) { Get-Content $LogFile -Raw -Encoding UTF8 } else { 'Sin operaciones registradas.' }
    $text = $header + $body
    if ($env:USERPROFILE) { $text = $text.Replace($env:USERPROFILE, '%USERPROFILE%') }
    $text = $text -replace '(?i)(https?://)[^/\s@]+@', '$1[OCULTO]@'
    $text = $text -replace 'gh[pousr]_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]+', '[SECRETO OCULTO]'
    $text = $text -replace '(?i)(Authorization\s*:\s*(?:Bearer|token)\s+)\S+', '$1[OCULTO]' -replace '(?i)([?&](?:token|access_token|key|signature|sig)=)[^&\s]+', '$1[OCULTO]'
    $text = $text -replace '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[CORREO OCULTO]'
    [IO.File]::WriteAllText($destination, $text, [Text.Encoding]::UTF8)
    return $destination
}

# Entradas opcionales (optin o extra, catálogo ampliado). No se marcan solas ni cuentan como falta.
function Test-Optional($app) { [bool]($app.optin -or $app.extra) }

# ---------- VirtualBox Guest Additions: el ISO viene con VirtualBox; si falta, se descarga el de la última versión ----------
$VBoxISO = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxGuestAdditions.iso'
$VBoxDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'VirtualBox'

function Install-VBoxGA {
    if (Test-Path $VBoxISO) { Write-Log "  Incluidas con VirtualBox: $VBoxISO"; return $true }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $v = ([string](Invoke-WebRequest 'https://download.virtualbox.org/virtualbox/LATEST.TXT' -UseBasicParsing).Content).Trim()
        New-Item $VBoxDir -ItemType Directory -Force | Out-Null
        $dest = Join-Path $VBoxDir "VBoxGuestAdditions_$v.iso"
        Write-Log "  Descargando Guest Additions $v..."
        if ($v -notmatch '^\d+(\.\d+){1,3}$') { throw "versión no válida: $v" }
        $base = "https://download.virtualbox.org/virtualbox/$v"
        $sums = [string](Invoke-WebRequest "$base/SHA256SUMS" -UseBasicParsing).Content
        $match = [regex]::Match($sums, "(?m)^([a-fA-F0-9]{64}) \*?VBoxGuestAdditions_$([regex]::Escape($v))\.iso\r?$")
        if (-not $match.Success) { throw 'Oracle no publica el hash SHA256 de esta versión.' }
        $expected = $match.Groups[1].Value
        Invoke-WebRequest "$base/VBoxGuestAdditions_$v.iso" -OutFile $dest -UseBasicParsing
        if ((Get-FileHash $dest -Algorithm SHA256).Hash -ne $expected) { Remove-Item $dest -Force; throw 'El ISO no supera la comprobación SHA256.' }
        Write-Log "  Guardado en $dest (SHA256 comprobado)"
        return $true
    } catch {
        Write-Log "  Descarga fallida ($($_.Exception.Message))."
        return $false
    }
}

function Test-VBoxGA {
    (Test-Path $VBoxISO) -or [bool](Get-ChildItem $VBoxDir -Filter 'VBoxGuestAdditions_*.iso' -ErrorAction SilentlyContinue)
}

# WSL instala una plataforma de aplicaciones; no modifica preferencias personales.
# Ajustes de Windows. Los de HKCU van en el lote de usuario y los de equipo en el de administrador.
$ExplorerAdv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$Personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$AppModelUnlock = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$HighPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
# Menú contextual clásico de Windows 11: una clave vacía de usuario; borrarla lo deshace
$ClassicMenu = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$SearchPolicy = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
$MouseKey = 'HKCU:\Control Panel\Mouse'
$FileSystemKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$DevSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'
function Get-RegValue($path, $name) { (Get-ItemProperty $path -Name $name -ErrorAction SilentlyContinue).$name }
function Set-RegDword($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path -Name $name -Value $value -Type DWord -Force
}
function Set-RegString($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path -Name $name -Value $value -Type String -Force
}
# Ajustes de equipo: directamente si ya hay permisos, si no con una solicitud de administrador
function Invoke-MachineTweak($cmd) {
    if (Test-Administrator) { Invoke-Expression $cmd; return $true }
    Invoke-Elevated $cmd
}
# ---------- PC anfitrión de escritorio remoto (Sunshine + Tailscale) ----------
# Deja el PC disponible sin estar delante: no se suspende, los servicios arrancan solos y se reinician si fallan.
# Sunshine corre como servicio y transmite también la pantalla de inicio de sesión: tras un corte se entra desde Moonlight.
$RemoteServices = @('SunshineService', 'Tailscale')
$KdeRuleGroup = 'iWinInstaller KDE Connect'
$WinlogonKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$PasswordLessKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
# Valor de corriente alterna de un ajuste de energía del plan activo (powercfg muestra CA y después CC)
function Get-AcPowerValue([string]$sub, [string]$setting) {
    $hex = [regex]::Matches((& powercfg /query SCHEME_CURRENT $sub $setting 2>$null | Out-String), '0x[0-9a-fA-F]{8}')
    if ($hex.Count -lt 2) { return $null }
    [Convert]::ToInt64($hex[$hex.Count - 2].Value, 16)
}
function Get-TailscaleExe {
    $exe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path $exe) { return $exe }
    (Get-Command tailscale.exe -ErrorAction SilentlyContinue).Source
}
function Get-AutologonExe {
    $dirs = @((Join-Path $env:ProgramFiles 'WinGet\Links'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'))
    foreach ($name in 'Autologon64.exe', 'Autologon.exe') {
        foreach ($dir in $dirs) { $path = Join-Path $dir $name; if (Test-Path $path) { return $path } }
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $null
}
# Accesos web en el escritorio y el menú Inicio públicos (carpeta «Acceso remoto»; Organize-Desktop no mueve carpetas)
$RemoteLinks = [ordered]@{
    'Sunshine (panel)' = 'https://localhost:47990'
    'Tailscale (equipos)' = 'https://login.tailscale.com/admin/machines'
    'Escritorio remoto de Chrome' = 'https://remotedesktop.google.com/access'
}
function Get-RemoteLinkDirs {
    @([Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('CommonPrograms')) |
        Where-Object { $_ } | ForEach-Object { Join-Path $_ 'Acceso remoto' }
}
function Set-RemoteLinks {
    foreach ($dir in Get-RemoteLinkDirs) {
        New-Item $dir -ItemType Directory -Force | Out-Null
        foreach ($name in $RemoteLinks.Keys) {
            Set-Content (Join-Path $dir "$name.url") @('[InternetShortcut]', "URL=$($RemoteLinks[$name])") -Encoding ASCII
        }
        Write-Log "  Accesos directos en $dir"
    }
}
function Set-RemoteHost {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    $ok = $true
    # Energía: nunca suspender ni hibernar con corriente; sin hibernación tampoco hay inicio rápido,
    # que deja el equipo a medias tras un corte e impide Wake-on-LAN desde apagado
    & powercfg /change standby-timeout-ac 0
    & powercfg /change hibernate-timeout-ac 0
    & powercfg /hibernate off 2>$null
    if ((Get-AcPowerValue 'SUB_SLEEP' 'STANDBYIDLE') -ne 0) { Write-Log '  No se pudo desactivar la suspensión.'; $ok = $false }
    # Red: Wake-on-LAN y sin ahorro de energía en los adaptadores físicos
    foreach ($nic in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -ne 'Disabled')) {
        try {
            Set-NetAdapterPowerManagement -Name $nic.Name -WakeOnMagicPacket Enabled -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop
            Write-Log "  Wake-on-LAN activado en $($nic.Name)"
        } catch { Write-Log "  $($nic.Name): el adaptador no admite Wake-on-LAN o ahorro configurable." }
    }
    # Servicios: arranque automático y reinicio a los 10 s si se cierran
    foreach ($svc in $RemoteServices) {
        if (-not (Get-Service $svc -ErrorAction SilentlyContinue)) { Write-Log "  Falta el servicio ${svc}: instala Sunshine y Tailscale."; $ok = $false; continue }
        Set-Service $svc -StartupType Automatic
        & sc.exe failure $svc reset= 86400 actions= restart/10000/restart/10000/restart/60000 | Out-Null
        Start-Service $svc -ErrorAction SilentlyContinue
        Write-Log "  ${svc}: automático y con reinicio tras fallo"
    }
    # KDE Connect (portapapeles compartido): sus puertos solo desde la red de Tailscale, sea cual sea el perfil de red
    try {
        Remove-NetFirewallRule -Group $KdeRuleGroup -ErrorAction SilentlyContinue
        foreach ($proto in 'TCP', 'UDP') {
            New-NetFirewallRule -DisplayName "KDE Connect por Tailscale ($proto)" -Group $KdeRuleGroup -Direction Inbound -Action Allow -Protocol $proto -LocalPort '1714-1764' -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
        }
        Write-Log '  Firewall: KDE Connect permitido desde Tailscale (puertos 1714-1764).'
    } catch { Write-Log "  No se pudo abrir KDE Connect en el firewall: $($_.Exception.Message)" }
    # Tailscale sin sesión de Windows abierta (modo desatendido); requiere haber iniciado sesión en Tailscale
    $ts = Get-TailscaleExe
    if ($ts) {
        & $ts status *> $null
        if ($LASTEXITCODE -eq 0) {
            & $ts set --unattended=true 2>&1 | ForEach-Object { Write-Log "    $_" }
            if ($LASTEXITCODE -eq 0) { Write-Log '  Tailscale en modo desatendido.' } else { Write-Log '  Tailscale no aceptó el modo desatendido; actívalo en su menú (Preferences › Run unattended).' }
        } else {
            Write-Log '  Tailscale: abre la app, inicia sesión y vuelve a aplicar este ajuste para el modo desatendido.'
        }
        Write-Log '  En login.tailscale.com › Machines › este PC › «Disable key expiry» para que no caduque.'
    }
    # Inicio de sesión automático (opcional): Autologon guarda la contraseña cifrada como secreto LSA
    if ((Get-RegValue $WinlogonKey 'AutoAdminLogon') -ne '1') {
        $autologon = Get-AutologonExe
        if ($autologon) {
            # Con «solo Windows Hello» activado, Windows ignora el inicio automático
            Set-RegDword $PasswordLessKey 'DevicePasswordLessBuildVersion' 0
            Start-Process $autologon -ArgumentList '/accepteula'
            Write-Log '  Autologon abierto: escribe tu contraseña de Windows (no el PIN) y pulsa Enable.'
        } else {
            Write-Log '  Sin inicio automático: tras un reinicio, inicia sesión desde Moonlight en la pantalla de bloqueo.'
        }
    }
    try { Set-RemoteLinks } catch { Write-Log "  No se pudieron crear los accesos directos: $($_.Exception.Message)" }
    Write-Log '  Primera vez en casa: abre https://localhost:47990, crea el usuario de Sunshine y empareja Moonlight con su PIN.'
    if (Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object FriendlyName -match 'Virtual Display') {
        Write-Log '  Pantalla virtual presente: Sunshine transmite aunque apagues o desconectes los monitores. Con el monitor encendido, Win + P › Duplicar evita que el ratón se vaya a la pantalla virtual.'
    } else {
        Write-Log '  Sin pantalla virtual: al apagar o desconectar el monitor Sunshine se queda sin imagen. Instala «Pantalla virtual» o usa un adaptador HDMI fantasma.'
    }
    Write-Log '  BIOS/UEFI: «Restore on AC Power Loss» = Power On para que arranque solo tras un corte de luz.'
    return $ok
}
function Reset-RemoteHost { Restore-TweakSnapshot 'remotehost' }

function Test-RemoteHost {
    if ((Get-AcPowerValue 'SUB_SLEEP' 'STANDBYIDLE') -ne 0) { return $false }
    foreach ($svc in $RemoteServices) {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if (-not $s -or $s.StartType -ne 'Automatic') { return $false }
    }
    $true
}
# ---------- Luces RGB apagadas (OpenRGB) ----------
# Muchas placas, memorias, gráficas y controladoras vuelven a su efecto de serie al quitarles la corriente:
# una tarea del sistema vuelve a apagarlas en cada arranque, sin necesidad de iniciar sesión.
$RgbDir = Join-Path $env:ProgramData 'iWinInstaller\OpenRGB'
$RgbScript = Join-Path $RgbDir 'apagar-rgb.ps1'
$RgbTaskPath = '\iWinInstaller\'
$RgbTaskName = 'Apagar luces RGB'
# Software del fabricante que reescribe los colores y compite con OpenRGB por el mismo controlador
$RgbVendorApps = 'Armoury Crate|Aura Sync|LightingService|iCUE|Mystic Light|MSI Center|RGB Fusion|GIGABYTE Control Center|NZXT CAM|SignalRGB|Razer Synapse|Logitech G HUB|L-Connect|Polychrome|MasterPlus|TT RGB Plus|SteelSeries GG|FURY CTRL|HyperX NGENUITY|Corsair'
# Fabricantes USB habituales de controladoras RGB (VID)
$RgbUsbVendors = @{ '1B1C' = 'Corsair'; '1E71' = 'NZXT'; '0B05' = 'ASUS Aura'; '1462' = 'MSI Mystic Light'; '048D' = 'ITE (Gigabyte RGB Fusion)'; '26CE' = 'ASRock Polychrome'; '0CF2' = 'Lian Li (ENE)'; '2516' = 'Cooler Master'; '264A' = 'Thermaltake'; '3633' = 'DeepCool'; '1532' = 'Razer'; '046D' = 'Logitech'; '1038' = 'SteelSeries'; '0951' = 'HyperX'; '03F0' = 'HyperX (HP)' }
function Get-OpenRgbExe {
    $exe = Join-Path $env:ProgramFiles 'OpenRGB\OpenRGB.exe'
    if (Test-Path $exe) { return $exe }
    foreach ($key in Get-AllInstalledEntries) {
        if ($key.DisplayName -like 'OpenRGB*' -and $key.InstallLocation) {
            $exe = Join-Path $key.InstallLocation 'OpenRGB.exe'
            if (Test-Path $exe) { return $exe }
        }
    }
    $null
}
function Get-AllInstalledEntries {
    $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    @(Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object DisplayName)
}
# Elige, por dispositivo de «OpenRGB --list-devices», el modo que deja los LED apagados: Off, Direct o Static en negro
function Get-RgbOffArguments {
    param([string[]]$Lines)
    $result = @(); $device = $null
    foreach ($line in $Lines) {
        if ($line -match '^(\d+): ') { $device = $Matches[1]; continue }
        if ($null -eq $device -or $line -notmatch '^\s+Modes:(.*)$') { continue }
        $modes = @([regex]::Matches($Matches[1], '\[?"[^"]*"\]?|\S+') | ForEach-Object { $_.Value.Trim('[', ']').Trim('"') })
        $pick = $null
        foreach ($want in 'Off', 'Direct', 'Static') { if ($modes -contains $want) { $pick = $want; break } }
        $result += @('-d', $device)
        if ($pick -eq 'Off') { $result += @('-m', 'Off') }
        elseif ($pick) { $result += @('-m', $pick, '-c', '000000', '-b', '0') }
        else { $result += @('-c', '000000', '-b', '0') }  # sin modo conocido: negro en el modo actual
        $device = $null
    }
    , $result
}
# Script que ejecuta la tarea como SYSTEM; registra la última ejecución en apagar-rgb.log
function Get-RgbBootScript([string]$exe) {
    @"
# Generado por iWinInstaller. Apaga las luces RGB que detecta OpenRGB; lo ejecuta la tarea «$RgbTaskName».
param([switch]`$Once)
`$ErrorActionPreference = 'Continue'
`$exe = '$($exe -replace "'", "''")'
`$config = Split-Path -Parent `$MyInvocation.MyCommand.Path
# OpenRGB escribe en la consola del proceso padre si la hay: sin consola, su salida llega por la tubería
Add-Type -Namespace IwinRgb -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool FreeConsole();'
[void][IwinRgb.Native]::FreeConsole()
function Invoke-OpenRgb([string[]]`$ArgumentList, [int]`$TimeoutMs = 300000) {
    `$psi = New-Object Diagnostics.ProcessStartInfo `$exe
    `$psi.Arguments = (@('--config', ('"' + `$config + '"'), '--noautoconnect') + `$ArgumentList) -join ' '
    `$psi.UseShellExecute = `$false; `$psi.CreateNoWindow = `$true
    `$psi.RedirectStandardOutput = `$true; `$psi.RedirectStandardError = `$true
    `$p = [Diagnostics.Process]::Start(`$psi)
    try {
        # Leer ambas tuberías sin bloquear permite aplicar el límite aunque OpenRGB no cierre stdout.
        `$stderr = `$p.StandardError.ReadToEndAsync()
        `$stdout = `$p.StandardOutput.ReadToEndAsync()
        if (-not `$p.WaitForExit(`$TimeoutMs)) {
            `$p.Kill()
            [void]`$p.WaitForExit(5000)
            throw 'OpenRGB superó el tiempo de espera.'
        }
        `$script:code = `$p.ExitCode
        @((`$stdout.Result + "``n" + `$stderr.Result) -split "``r?``n" | Where-Object { `$_ })
    } finally { `$p.Dispose() }
}
function Get-RgbOffArguments {
$(${function:Get-RgbOffArguments}.ToString())
}
`$out = @("`$(Get-Date -Format s) Inicio")
`$passes = if (`$Once) { 1 } else { 2 }
`$failed = `$false
try {
for (`$pass = 1; `$pass -le `$passes; `$pass++) {
    # Las controladoras USB pueden reiniciarse al cargar sus drivers: una segunda pasada al minuto las vuelve a apagar
    if (`$pass -gt 1) { Start-Sleep -Seconds 60 }
    `$list = Invoke-OpenRgb @('--list-devices')
    if (`$code -ne 0) { throw "OpenRGB no pudo enumerar dispositivos (código `$code)." }
    `$devices = @(`$list | Where-Object { `$_ -match '^\d+: ' })
    `$out += "Pasada `${pass}: `$(`$devices.Count) dispositivos"
    `$out += `$devices | ForEach-Object { "  `$_" }
    `$offArgs = Get-RgbOffArguments `$list
    if (`$offArgs.Count) {
        `$res = Invoke-OpenRgb `$offArgs
        `$out += "  Código `$code"
        `$errors = @(`$res | Where-Object { `$_ -match '(?i)error|wrong|failed' })
        `$out += `$errors | ForEach-Object { "  `$_" }
        if (`$code -ne 0 -or `$errors.Count) { throw "OpenRGB no pudo aplicar el apagado (código `$code)." }
        `$out += "Apagado aplicado: `$(`$devices.Count) dispositivos"
    }
}
} catch { `$failed = `$true; `$out += "ERROR: `$(`$_.Exception.Message)" }
finally { `$out | Set-Content (Join-Path `$config 'apagar-rgb.log') -Encoding UTF8 }
if (`$failed) { exit 1 }
"@
}
# Solo lectura: componentes, posibles controladoras USB y software RGB que hay que cerrar o quitar
function Write-RgbInventory {
    try {
        $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        Write-Log "    Placa base: $($board.Manufacturer) $($board.Product)"
        foreach ($ram in @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)) { Write-Log "    RAM: $($ram.Manufacturer) $(([string]$ram.PartNumber).Trim()) ($($ram.DeviceLocator))" }
        foreach ($gpu in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) { Write-Log "    Gráfica: $($gpu.Name)" }
    } catch { Write-Log "    Inventario incompleto: $($_.Exception.Message)" }
    $usb = @{}
    foreach ($dev in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
        if ($dev.InstanceId -match 'VID_([0-9A-F]{4})' -and $RgbUsbVendors.ContainsKey($Matches[1].ToUpper())) { $usb[$RgbUsbVendors[$Matches[1].ToUpper()]] = $true }
    }
    if ($usb.Count) { Write-Log "    USB con posible RGB: $(@($usb.Keys | Sort-Object) -join ', ')" }
    $vendor = @(Get-AllInstalledEntries | Where-Object { $_.DisplayName -match $RgbVendorApps } | ForEach-Object DisplayName | Sort-Object -Unique)
    if ($vendor) {
        Write-Log "  Software RGB del fabricante: $($vendor -join ', ')."
        Write-Log '  Puede volver a encender las luces: desinstálalo o quítalo del inicio (si controla ventiladores, configúralos antes en la BIOS).'
    }
}
function Set-RgbOff {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    $exe = Get-OpenRgbExe
    if (-not $exe) { Write-Log '  Falta OpenRGB: instálalo desde Sistema › Iluminación RGB.'; return $false }
    if (-not (Get-AllInstalledEntries | Where-Object DisplayName -like 'PawnIO*')) { Write-Log '  Falta PawnIO: sin él OpenRGB no llega a la placa base ni a la RAM.' }
    Write-RgbInventory
    # Carpeta solo para SYSTEM y administradores: la tarea corre como SYSTEM y OpenRGB carga plugins de su configuración
    New-Item $RgbDir -ItemType Directory -Force | Out-Null
    & icacls.exe $RgbDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log '  No se pudieron proteger los permisos de la carpeta.'; return $false }
    Set-Content $RgbScript (Get-RgbBootScript $exe) -Encoding UTF8
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$RgbScript`""
    # Al arrancar (sin sesión) y al iniciar sesión, que es cuando algunos drivers reinician sus LED
    $boot = New-ScheduledTaskTrigger -AtStartup; $boot.Delay = 'PT30S'
    $logon = New-ScheduledTaskTrigger -AtLogOn; $logon.Delay = 'PT20S'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskPath $RgbTaskPath -TaskName $RgbTaskName -Action $action -Trigger $boot, $logon -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log "  Tarea «$RgbTaskName» creada: apaga las luces en cada arranque, también sin sesión."
    # Primera aplicación ahora, para ver qué detecta OpenRGB
    # Un informe de una ejecución anterior no prueba el resultado de esta pasada.
    $reportPath = Join-Path $RgbDir 'apagar-rgb.log'
    Remove-Item $reportPath -Force -ErrorAction SilentlyContinue
    $run = Start-Process $ps -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$RgbScript`" -Once" -WindowStyle Hidden -Wait -PassThru
    $report = @(Get-Content (Join-Path $RgbDir 'apagar-rgb.log') -Encoding UTF8 -ErrorAction SilentlyContinue)
    $report | Select-Object -Skip 1 | ForEach-Object { Write-Log "    $_" }
    if ($run.ExitCode -ne 0) { Write-Log "  OpenRGB no completó el apagado (código $($run.ExitCode)). Consulta el diagnóstico de la tarea."; return $false }
    $found = $report | Where-Object { $_ -match '^Apagado aplicado: (\d+) dispositivos$' } | ForEach-Object { [int]$Matches[1] }
    if (-not $found) {
        Write-Log '  OpenRGB no detectó ningún dispositivo. Reinicia (PawnIO se carga al arrancar) y vuelve a aplicar.'
        return $false
    }
    Write-Log "  $found dispositivos con orden de apagado aplicada. Si algo sigue encendido, no es compatible con OpenRGB: apágalo desde la BIOS o el botón/cable de su controladora."
    Write-Log '  BIOS/UEFI: desactiva también el LED de la placa al arrancar y apagado (ASUS «LED lighting», MSI «EZ LED Control», Gigabyte «RGB Fusion», ASRock «RGB LED»).'
    return $true
}
function Reset-RgbOff {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    Unregister-ScheduledTask -TaskPath $RgbTaskPath -TaskName $RgbTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $RgbDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log '  Las luces vuelven a su efecto de serie tras apagar el PC, o configúralas desde OpenRGB.'
    return (-not (Get-ScheduledTask -TaskPath $RgbTaskPath -TaskName $RgbTaskName -ErrorAction SilentlyContinue))
}
function Test-RgbOff {
    if (-not (Test-Path $RgbScript)) { return $false }
    $report = @(Get-Content (Join-Path $RgbDir 'apagar-rgb.log') -Encoding UTF8 -ErrorAction SilentlyContinue)
    if (-not ($report -match '^Apagado aplicado: [1-9][0-9]* dispositivos$') -or ($report -match '^ERROR:')) { return $false }
    # Sin administrador no se ven las tareas de SYSTEM: basta con el script, que solo puede escribir un administrador
    if (-not (Test-Administrator)) { return $true }
    [bool](Get-ScheduledTask -TaskPath $RgbTaskPath -TaskName $RgbTaskName -ErrorAction SilentlyContinue)
}
function Install-Tweak($id) {
    try {
        $ErrorActionPreference = 'Stop'
        Save-TweakSnapshot $id
        switch ($id) {
            'wsl' {
                $ok = Invoke-Elevated 'wsl.exe --install --no-launch'
                if ($ok) { Write-Log '  Reinicia Windows para terminar de instalar WSL.' }
                return $ok
            }
            'restorepoint' {
                $cmd = 'Enable-ComputerRestore -Drive "$env:SystemDrive\"; Checkpoint-Computer -Description "iWinInstaller" -RestorePointType MODIFY_SETTINGS'
                if (Test-Administrator) { Invoke-Expression $cmd; return $true }
                return (Invoke-Elevated $cmd)
            }
            'showext' { Set-RegDword $ExplorerAdv 'HideFileExt' 0; return $true }
            'showhidden' { Set-RegDword $ExplorerAdv 'Hidden' 1; return $true }
            'darkmode' { Set-RegDword $Personalize 'AppsUseLightTheme' 0; Set-RegDword $Personalize 'SystemUsesLightTheme' 0; return $true }
            'power' {
                & powercfg /setactive $HighPerf 2>$null
                if ($LASTEXITCODE -ne 0) { & powercfg -duplicatescheme $HighPerf $HighPerf *> $null; & powercfg /setactive $HighPerf 2>$null }
                return ($LASTEXITCODE -eq 0)
            }
            'devmode' {
                $cmd = "if (-not (Test-Path '$AppModelUnlock')) { New-Item '$AppModelUnlock' -Force | Out-Null }; Set-ItemProperty '$AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -Value 1 -Type DWord -Force"
                return (Invoke-MachineTweak $cmd)
            }
            'longpaths' { return (Invoke-MachineTweak "Set-ItemProperty '$FileSystemKey' -Name LongPathsEnabled -Value 1 -Type DWord -Force") }
            'classicmenu' {
                New-Item "$ClassicMenu\InprocServer32" -Force | Out-Null
                Set-ItemProperty "$ClassicMenu\InprocServer32" -Name '(default)' -Value '' -Force
                Write-Log '  Se verá al reiniciar el Explorador o la sesión.'
                return $true
            }
            'nobing' { Set-RegDword $SearchPolicy 'DisableSearchBoxSuggestions' 1; Write-Log '  Se aplica al reiniciar la sesión.'; return $true }
            'taskbarleft' { Set-RegDword $ExplorerAdv 'TaskbarAl' 0; return $true }
            'clockseconds' { Set-RegDword $ExplorerAdv 'ShowSecondsInSystemClock' 1; return $true }
            'thispc' { Set-RegDword $ExplorerAdv 'LaunchTo' 1; return $true }
            'endtask' { Set-RegDword $DevSettings 'TaskbarEndTask' 1; return $true }
            'remotehost' { return (Set-RemoteHost) }
            'rgboff' { return (Set-RgbOff) }
            'mouseaccel' {
                Set-RegString $MouseKey 'MouseSpeed' '0'; Set-RegString $MouseKey 'MouseThreshold1' '0'; Set-RegString $MouseKey 'MouseThreshold2' '0'
                Write-Log '  Se aplica al reiniciar la sesión.'
                return $true
            }
        }
    } catch { Write-Log "  $($_.Exception.Message)" }
    return $false
}

# Deshace un ajuste dejando el valor que trae Windows. WSL y el punto de restauración no se deshacen desde aquí.
function Uninstall-Tweak($id) {
    try { return (Restore-TweakSnapshot $id) }
    catch { Write-Log "  $($_.Exception.Message)"; return $false }
}

function Test-Tweak($id) {
    # wsl.exe y powercfg escriben en stderr cuando falta la función; con Stop eso cortaría la ventana
    $ErrorActionPreference = 'Continue'
    try { return (Test-TweakCore $id) } catch { return $false }
}
function Test-TweakCore($id) {
    switch ($id) {
        'wsl' {
            if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
            & wsl.exe --status 2>&1 | Out-Null
            return ($LASTEXITCODE -eq 0)
        }
        # Se crea en cada instalación; nunca cuenta como hecho de antemano
        'restorepoint' { return $false }
        'showext' { return ((Get-RegValue $ExplorerAdv 'HideFileExt') -eq 0) }
        'showhidden' { return ((Get-RegValue $ExplorerAdv 'Hidden') -eq 1) }
        'darkmode' { return ((Get-RegValue $Personalize 'AppsUseLightTheme') -eq 0) }
        'power' { return ((& powercfg /getactivescheme 2>$null | Out-String) -match $HighPerf) }
        'devmode' { return ((Get-RegValue $AppModelUnlock 'AllowDevelopmentWithoutDevLicense') -eq 1) }
        'longpaths' { return ((Get-RegValue $FileSystemKey 'LongPathsEnabled') -eq 1) }
        'classicmenu' { return (Test-Path "$ClassicMenu\InprocServer32") }
        'nobing' { return ((Get-RegValue $SearchPolicy 'DisableSearchBoxSuggestions') -eq 1) }
        'taskbarleft' { return ((Get-RegValue $ExplorerAdv 'TaskbarAl') -eq 0) }
        'clockseconds' { return ((Get-RegValue $ExplorerAdv 'ShowSecondsInSystemClock') -eq 1) }
        'thispc' { return ((Get-RegValue $ExplorerAdv 'LaunchTo') -eq 1) }
        'endtask' { return ((Get-RegValue $DevSettings 'TaskbarEndTask') -eq 1) }
        'mouseaccel' { return ((Get-RegValue $MouseKey 'MouseSpeed') -eq '0') }
        'remotehost' { return (Test-RemoteHost) }
        'rgboff' { return (Test-RgbOff) }
    }
    return $false
}

function Update-Self {
    if (-not (Test-Path (Join-Path $Root 'instalado.txt'))) { return $true }
    $script:StopRequested=$false
    $lock=New-Object Threading.Mutex($false,('Local\iWinInstaller-update-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    $locked=$false
    try {
        try{$locked=$lock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){Write-Log '  Ya hay una actualización en preparación.';return $true}
        $release = (Invoke-IwinWebTransfer $ReleaseApi $null 20) | ConvertFrom-Json -ErrorAction Stop
        $tag = $release.tag_name
        if ($tag -notmatch '^v\d+\.\d+$') { throw 'No se pudo consultar una versión válida.' }
        if ([version]$tag.Substring(1) -le [version]$Version.Substring(1)) { Write-Log "  iWinInstaller ya está al día ($Version)."; return $true }
        Write-Log "  iWinInstaller: actualizando de $Version a $tag"
        if (Test-Path (Join-Path $Root 'iWinInstaller.exe')) {
            $updateDir=Join-Path (Join-Path $LogDir 'actualizacion') $tag
            New-Item $updateDir -ItemType Directory -Force | Out-Null
            $asset = $release.assets | Where-Object name -eq 'iWinInstaller-Setup.exe' | Select-Object -First 1
            if (-not $asset -or $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw 'Falta la descarga con su hash SHA256.' }
            $expected=$Matches[1]
            $setup=Join-Path $updateDir 'iWinInstaller-Setup.exe'
            if(-not (Test-Path $setup) -or (Get-FileHash $setup).Hash -ne $expected){
                $download=$setup+'.part'
                try{
                    [void](Invoke-IwinWebTransfer $asset.browser_download_url $download 600)
                    if((Get-FileHash $download).Hash -ne $expected){throw 'La actualización no supera la comprobación SHA256.'}
                    Move-Item $download $setup -Force -ErrorAction Stop
                }finally{Remove-Item $download -Force -ErrorAction SilentlyContinue}
            }
            foreach($running in @(Get-Process -Name iWinInstaller-Setup -ErrorAction SilentlyContinue)){try{if($running.Path -eq $setup){Write-Log '  La nueva versión ya está preparada para aplicarse al cerrar.';return $true}}catch{}}
            $p=Start-Process $setup -ArgumentList '--silent' -PassThru
            if (($UI -or $AutoUpdate) -and $env:IWIN_HOST_PID -match '^\d+$') {
                Write-Log '  Versión verificada. Se aplica cuando cierre iWinInstaller; conserva notas, perfiles y lotes.'
                return $true
            }
        } else {
            $p=Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Root 'install.ps1')`" -Silent"
        }
        Wait-Proc $p 600
        return ($p.HasExited -and $p.ExitCode -eq 0)
    }finally{if($locked){$lock.ReleaseMutex()};$lock.Dispose()}
}

function Invoke-Update {
    Write-Log "Actualizando (iWinInstaller $Version)..."
    if (-not (Ensure-Winget)) { return $false }
    Update-WingetCache
    $installed = @($Apps | Where-Object { $_.type -in @('winget','wingetall') -and (Test-AppInstalled $_) })
    $previousUpgrade = $UpgradePackages
    $script:UpgradePackages = $true
    try { $fail = @(Invoke-Install $installed $null); $ok = $fail.Count -eq 0 }
    finally { $script:UpgradePackages = $previousUpgrade }
    if(Test-IwinStop){Write-Log 'Actualización de aplicaciones pausada; no se sustituye iWinInstaller durante la pausa.';return $false}
    try {
        if (-not (Update-Self)) { $ok = $false }
    } catch { Write-Log "  Error de actualización: $($_.Exception.Message)"; $ok = $false }
    Write-Log $(if ($ok) { 'Actualización terminada.' } else { 'Actualización incompleta: consulta los errores del registro.' })
    $ok
}

# ---------- Instalar / verificar una entrada del catálogo ----------
function Install-App($app) {
    switch ($app.type) {
        'tweak' { return (Install-Tweak $app.id) }
        'vboxga' { return (Install-VBoxGA) }
        'wingetall' {
            $ok = $true
            foreach ($id in @($app.winget)) {
                if ($WingetIds -contains $id -and -not $UpgradePackages) { continue }
                if (-not (Install-WingetPackage $app $id)) { $ok = $false }
            }
            return $ok
        }
        'winget' { return (Install-WingetPackage $app $app.winget) }
        'manual' { Write-Log '  Se instala desde la web o la cuenta del proveedor: completa su asistente y vuelve a verificar.'; if (-not $Silent) { Start-Process $app.page }; return $false }
    }
    # type = download: instalador oficial con asistente (HoYoPlay y Riot no ofrecen instalación silenciosa)
    if ($Silent) { Write-Log '  Necesita su asistente: se omite en modo sin ventana.'; return $false }
    $tmp = Join-Path $env:TEMP ('iwin-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest $app.url -OutFile $tmp -UseBasicParsing
        $bytes = [IO.File]::ReadAllBytes($tmp)
        if ($bytes.Length -lt 1MB -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw 'la descarga no es un ejecutable de Windows' }
        # Firma válida y del fabricante esperado: una firma cualquiera no basta
        $signature = Get-AuthenticodeSignature $tmp
        if ($signature.Status -ne 'Valid') { throw 'el instalador no tiene una firma digital válida' }
        if (-not $app.signer -or $signature.SignerCertificate.Subject -notmatch $app.signer) { throw "la firma no es del fabricante esperado ($($signature.SignerCertificate.Subject))" }
        Write-Log "  Se abrirá el asistente de $($app.name): complétalo para continuar."
        $p = Start-Process $tmp -PassThru
        $null = $p.Handle
        Wait-Proc $p
        return ($p.HasExited -and $p.ExitCode -in @(0,3010,1641))
    } catch {
        Write-Log "  Descarga automática fallida ($($_.Exception.Message)). Abriendo la web oficial."
        Start-Process $app.page
        return $false
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

# ¿Está lista? winget: «winget list» con su id. download: nombre en la lista de programas de Windows.
function Test-AppInstalled($app) {
    switch ($app.type) {
        'tweak' { return (Test-Tweak $app.id) }
        'vboxga' { return (Test-VBoxGA) }
        'wingetall' {
            if ($null -eq $WingetIds) { Update-WingetCache }
            return [bool](@($app.winget | Where-Object { $WingetIds -notcontains $_ }).Count -eq 0)
        }
        'winget' {
            if (Test-LocalApp $app) { return $true }
            if ($app.architecture -and $app.families) { return $false }
            return ($WingetIds -contains $app.winget)
        }
    }
    $keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $name = if ($app.detect) { $app.detect } else { $app.name }
    return [bool](Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$name*" })
}

# Entradas de un perfil (profiles.json agrupa por «group»)
# Un perfil lista grupos (sus apps principales) o ids concretos (también del catálogo ampliado).
# ---------- Perfiles propios ----------
# Un perfil es un JSON con ids del catálogo; nunca contiene órdenes, rutas ni datos del equipo.
$ProfileDir = Join-Path $LogDir 'perfiles'
$ProfileFormat = 'iWinInstaller-perfil'
$CustomMark = '★ '
function Get-SafeProfileName([string]$name) {
    $clean = (($name -replace '[^\p{L}\p{N} ._()+-]', '') -replace '\s+', ' ').Trim(' .')
    if ($clean.Length -gt 60) { $clean = $clean.Substring(0, 60).Trim() }
    $clean
}
function Read-ProfileFile([string]$path) {
    $file = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($file.Length -gt 1MB) { throw 'El archivo es demasiado grande para ser un perfil.' }
    try { $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { throw 'El archivo no es un JSON válido.' }
    if ($data.formato -ne $ProfileFormat -or $null -eq $data.apps) { throw 'No es un perfil de iWinInstaller.' }
    $known = @{}; foreach ($a in $Apps) { $known[$a.id] = $true }
    $listed = @($data.apps | ForEach-Object { $_ })
    $ids = @($listed | Where-Object { $_ -is [string] -and $known.ContainsKey($_) } | Select-Object -Unique)
    $name = Get-SafeProfileName ([string]$data.nombre)
    if (-not $name) { $name = Get-SafeProfileName ([IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '\.iwin$', '') }
    if (-not $name) { $name = 'Perfil importado' }
    [pscustomobject]@{ Name = $name; Apps = $ids; Ignored = $listed.Count - $ids.Count }
}
function Write-ProfileFile([string]$path, [string]$name, $ids) {
    $data = [ordered]@{ formato = $ProfileFormat; version = 1; nombre = (Get-SafeProfileName $name); creado = (Get-Date -Format 'yyyy-MM-dd'); apps = @($ids | Select-Object -Unique) }
    $temporary = $path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($data | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}
function Get-CustomProfilePath([string]$name) { Join-Path $ProfileDir ((Get-SafeProfileName $name) + '.iwin.json') }
# Perfiles guardados en este equipo: nombre -> ids. Un archivo dañado se ignora sin cerrar la app.
function Get-CustomProfiles {
    $result = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $ProfileDir -Filter '*.iwin.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $entry = Read-ProfileFile $file.FullName; $result[$entry.Name] = $entry.Apps } catch { Write-Log "  Perfil ignorado ($($file.Name)): $($_.Exception.Message)" }
    }
    $result
}

# Marcas del hardware de este PC en líneas «Placa: …», «GPU: …», «GPUVEN_xxxx», «VID_xxxx»… para los «hardware» de apps.json
function Get-HardwareText {
    if ($null -ne $script:HardwareText) { return $script:HardwareText }
    $lines = @()
    try {
        foreach ($b in @(Get-CimInstance Win32_BaseBoard -ErrorAction Stop)) { $lines += "Placa: $($b.Manufacturer) $($b.Product)" }
        foreach ($c in @(Get-CimInstance Win32_Processor -ErrorAction Stop)) { $lines += "CPU: $($c.Name)" }
        foreach ($g in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) {
            $lines += "GPU: $($g.Name)"
            # Fabricante de la tarjeta (ASUS, MSI, Gigabyte…): subsistema del identificador PCI
            if ($g.PNPDeviceID -match 'SUBSYS_[0-9A-F]{4}([0-9A-F]{4})') { $lines += "GPUVEN_$($Matches[1].ToUpper())" }
        }
        foreach ($r in @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)) { $lines += "RAM: $($r.Manufacturer) $(([string]$r.PartNumber).Trim())" }
        foreach ($d in @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop)) { $lines += "Disco: $($d.Model)" }
    } catch { Write-Log "  Inventario de hardware incompleto: $($_.Exception.Message)" }
    foreach ($dev in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
        if ($dev.InstanceId -match 'VID_([0-9A-F]{4})') { $lines += "VID_$($Matches[1].ToUpper())" }
    }
    $script:HardwareText = @($lines | Select-Object -Unique)
    $script:HardwareText
}
# Apps del fabricante que corresponden a este PC; con las luces apagadas se omiten las que vuelven a encenderlas
function Get-HardwareApps {
    $text = Get-HardwareText
    $rgbOff = Test-RgbOff
    @($Apps | Where-Object { $_.hardware -and ($text -match $_.hardware) -and -not ($rgbOff -and $_.rgb) })
}
function Get-ProfileApps($name) {
    # Perfil exportado (archivo) o guardado en este equipo: exactamente los ids que contiene
    $ids = $null
    if ($name -match '\.json$' -and (Test-Path -LiteralPath $name -PathType Leaf)) { $ids = (Read-ProfileFile $name).Apps }
    else {
        $plain = $name -replace ('^' + [regex]::Escape($CustomMark)), ''
        $path = Get-CustomProfilePath $plain
        if (($name.StartsWith($CustomMark) -or -not ($Profiles.PSObject.Properties.Name -contains $name)) -and $plain -and (Test-Path -LiteralPath $path)) { $ids = (Read-ProfileFile $path).Apps }
    }
    if ($null -ne $ids) { return @($Apps | Where-Object { $ids -contains $_.id }) }
    # Desde la consola los acentos pueden llegar mal codificados: se compara solo con las letras ASCII
    $key = $name -replace '[^A-Za-z]', ''
    $match = $Profiles.PSObject.Properties.Name | Where-Object { ($_ -replace '[^A-Za-z]', '') -eq $key } | Select-Object -First 1
    if ($match) { $name = $match }
    $groups = @($Profiles.$name)
    if (-not $groups) { return @() }
    if ($groups -contains '@hardware') { return (Get-HardwareApps) }
    if ($groups -contains '*') { return @($Apps | Where-Object { -not (Test-Optional $_) }) }
    # «@Sistema», «@Terminal» o «@Aplicaciones» incluyen toda esa sección
    @($Apps | Where-Object { ($groups -contains $_.id -and -not $_.optin) -or (($groups -contains $_.group -or $groups -contains "@$($_.section)") -and -not (Test-Optional $_)) })
}

function Get-DesktopPaths {
    @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')) | Where-Object { $_ } | Select-Object -Unique
}

function Organize-Desktop([string]$destinationFolder = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Aplicaciones')) {
    $shell = New-Object -ComObject WScript.Shell
    $moved = 0
    foreach ($desktop in Get-DesktopPaths) {
        if (-not (Test-Path $desktop)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $desktop -File) {
            try {
                $isApplication = $false
                if ($file.Extension -eq '.lnk') {
                    $target = $shell.CreateShortcut($file.FullName).TargetPath
                    $isApplication = $target -match '(?i)\.(exe|com)$|^shell:AppsFolder'
                } elseif ($file.Extension -eq '.url') {
                    $isApplication = [bool](Select-String -LiteralPath $file.FullName -Pattern '^URL=(steam|com\.epicgames\.launcher)://' -Quiet)
                }
                if (-not $isApplication) { continue }
                $folder = $destinationFolder
                New-Item $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                $destination = Join-Path $folder $file.Name
                $suffix = 1
                while (Test-Path -LiteralPath $destination) {
                    $destination = Join-Path $folder ($file.BaseName + " ($suffix)" + $file.Extension)
                    $suffix++
                }
                [IO.File]::Move($file.FullName, $destination)
                $moved++
            } catch { Write-Log "  Acceso conservado en el escritorio ($($file.Name)): $($_.Exception.Message)" }
        }
    }
    Write-Log "Escritorio organizado: $moved accesos movidos a Aplicaciones."
}

# Instala dependencias y apps antes de la configuracion; devuelve los fallos confirmados.
function Invoke-Install($sel, [scriptblock]$onProgress) {
    $sel = @(Get-InstallPlan $sel)
    if ($script:ResumingBatch -and $script:Batch) { $done=@($script:Batch.items | Where-Object state -eq 'done' | ForEach-Object id); $sel=@($sel | Where-Object { $done -notcontains $_.id }) }
    if (-not $WorkerMode -and -not $script:ResumingBatch) { Start-IwinBatch $sel $(if($UpgradePackages){'upgrade'}else{'install'}) }
    $script:LastInstallCode = 0
    if (($sel | Where-Object id -eq 'rgboff') -and ($clash = @($sel | Where-Object rgb))) {
        Write-Log "Aviso: $(($clash | ForEach-Object name) -join ', ') puede volver a encender las luces."
    }
    if (($sel | Where-Object { $_.type -in @('winget', 'wingetall') }) -and -not (Ensure-Winget)) {
        foreach ($app in $sel) { Complete-IwinItem $app $false $onProgress }
        return $sel
    }

    Write-Log "Instalando $($sel.Count) elementos · registro: $LogFile"
    Update-WingetCache
    $fail = @()
    if (-not $WorkerMode) {
        $machine = @($sel | Where-Object { $_.type -in @('winget','wingetall','tweak') -and (Get-InstallContext $_) -eq 'machine' })
        if ($machine) {
            Write-Log 'Lote del sistema: una unica solicitud de administrador si hace falta.'
            $fail += @(Invoke-InstallWorker $machine $onProgress)
            $sel = @($sel | Where-Object { $machine.id -notcontains $_.id })
        }
        if (Test-Administrator) {
            $userApps = @($sel | Where-Object { $_.type -in @('winget','wingetall','tweak') -and (Get-InstallContext $_) -eq 'user' })
            if ($userApps) {
                $fail += @(Invoke-InstallWorker $userApps $onProgress -AsUser)
                $sel = @($sel | Where-Object { $userApps.id -notcontains $_.id })
            }
        }
    }
    foreach ($app in $sel) {
        $script:LastInstallCode = 0
        if (Test-IwinStop) { $fail += $app; Complete-IwinItem $app $false $onProgress; continue }
        Set-IwinBatchRunning $app
        # Lo que ya está instalado no se vuelve a instalar
        try { $alreadyInstalled = (Test-AppInstalled $app) } catch {
            Write-Log "  No se pudo comprobar $($app.name): $($_.Exception.Message)"
            $fail += $app
            Complete-IwinItem $app $false $onProgress
            continue
        }
        if ($alreadyInstalled -and -not $UpgradePackages) {
            Write-Log "Ya instalada, se omite: $($app.name)"
            Complete-IwinItem $app $true $onProgress
            continue
        }
        Write-Log "Instalando $($app.name)..."
        if ($WorkerMode -and $ResultFile) { Write-WorkerEvent @{current=$app.id} }
        elseif ($UI -and $byId -and $byId.ContainsKey($app.id)) { $byId[$app.id].Status='Instalando…'; $byId[$app.id].StatusKind='busy'; Set-Status "Instalando $($app.name)…" }
        $ok = $false
        try {
            $ok = Invoke-IwinInstallAction $app
            if (-not $ok -and $app.type -in @('winget','wingetall') -and $LastInstallCode -in @(-1978335224,-1978335173,-1978335123)) {
                Write-Log '  Reintentando...'
                Start-Sleep -Seconds 1
                $ok = Invoke-IwinInstallAction $app
            }
            if ($ok -and $app.type -in @('download', 'vboxga')) {
                $cached = $WingetIds
                $script:WingetIds = $null
                try { $ok = Test-AppInstalled $app } finally { $script:WingetIds = $cached }
                if ($ok -and $null -ne $WingetIds -and $app.type -in @('winget', 'wingetall')) { $script:WingetIds += @($app.winget) }
                if (-not $ok) { Write-Log '  No se confirmó la instalación: sigue pendiente.' }
            }
        } catch { Write-Log "  Error: $($_.Exception.Message)"; $ok = $false }
        if ($ok) { Write-Log "  OK: $($app.name)" } else { Write-Log "  FALLÓ: $($app.name)"; $fail += $app }
        Complete-IwinItem $app $ok $onProgress
    }
    Organize-Desktop
    if ($fail) {
        Write-Log "Terminado con fallos en: $(($fail | ForEach-Object name) -join ', ')"
        if (-not $WorkerMode -and $LogFile) { try { $report = Export-Diagnostic; Write-Log "Diagnostico guardado en $report" } catch { Write-Log "No se pudo exportar el diagnostico: $($_.Exception.Message)" } }
    } else { Write-Log 'Todo instalado correctamente.' }
    $fail
}

# ---------- Desinstalar ----------
# Componentes que Windows u otras apps necesitan (keep), lotes de runtimes y WSL no se ofrecen.
function Test-Uninstallable($app) {
    if ($app.keep) { return $false }
    if ($app.type -eq 'tweak') { return ($app.id -notin @('wsl', 'restorepoint')) }
    $app.type -in @('winget', 'download', 'manual')
}

# Entradas de «Programas y características» que corresponden a la app (mismo criterio que la detección)
function Get-UninstallEntries($app) {
    $names = @($app.name) + @($app.detectNames) + @($app.detect) | Where-Object { $_ }
    @($RegistryApps | Where-Object {
        $entry = $_
        ($entry.UninstallString -or $entry.QuietUninstallString) -and @($names | Where-Object { $entry.DisplayName -eq $_ -or $entry.DisplayName -match ('^' + [regex]::Escape($_) + '(?:\s+\d|\s*\()') }).Count
    })
}

# Orden silencioso si existe; los MSI se convierten a /x sin ventana. Si no, el asistente del fabricante.
function Get-UninstallCommand($entry) {
    if ($entry.QuietUninstallString) { return [string]$entry.QuietUninstallString }
    $command = [string]$entry.UninstallString
    if ($command -match '(?i)msiexec(?:\.exe)?\s+/[IX]\s*(\{[0-9A-F-]{36}\})') { return "msiexec.exe /x $($Matches[1]) /qn /norestart" }
    $command
}

function Invoke-RegistryUninstall($app) {
    $entries = @(Get-UninstallEntries $app)
    if (-not $entries) { Write-Log '  No aparece en Programas y características.'; return $false }
    foreach ($entry in $entries) {
        $command = Get-UninstallCommand $entry
        Write-Log "  Desinstalador de $($entry.DisplayName)"
        Write-Log "    $command"
        $p = Start-Process cmd.exe -PassThru -WindowStyle Hidden -ArgumentList ('/d /c "' + $command + '"')
        $null = $p.Handle
        Wait-Proc $p 1800
        Write-Log "  codigo $(if ($p.HasExited) { $p.ExitCode } else { -1 })"
    }
    $true
}

# Apps de Microsoft Store o paquetes MSIX: se quitan solo del usuario actual
function Remove-AppxApp($app) {
    $packages = @($AppxApps | Where-Object {
        (@($app.families) -contains $_.PackageFamilyName) -or ((Get-NormName (([string]$_.Name -split '\.')[-1] -replace 'Desktop$', '')) -eq (Get-NormName $app.name))
    })
    foreach ($package in $packages) {
        Write-Log "  Quitando el paquete $($package.PackageFullName)"
        try { Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop } catch { Write-Log "  $($_.Exception.Message)" }
    }
    [bool]$packages.Count
}

function Test-StillInstalled($app) {
    Update-LocalInventory -Appx
    if ($null -ne $WingetIds) { $script:WingetIds = @($WingetIds | Where-Object { $_ -ne $app.winget }) }
    if ($app.type -ne 'winget') { return (Test-AppInstalled $app) }
    if (Test-LocalApp $app) { return $true }
    # Sin rastro en el inventario local: winget confirma que su paquete ya no figura
    $source = if ($app.source) { $app.source } else { 'winget' }
    $code = Invoke-Winget @('list', '-e', '--id', $app.winget, '--source', $source, '--disable-interactivity', '--accept-source-agreements') ($app.id + '-verificar') 45
    if ($code -eq 0) { return $true }
    if ($code -eq -1978335212) { return $false }
    throw 'No se pudo comprobar la desinstalación. No se considera ausente; comprueba la conexión y vuelve a verificar.'
}

function Uninstall-App($app) {
    if ($app.type -eq 'tweak') { return (Uninstall-Tweak $app.id) }
    if ($app.type -eq 'winget') {
        $source = if ($app.source) { $app.source } else { 'winget' }
        $code = Invoke-Winget @('uninstall', '-e', '--id', $app.winget, '--source', $source, '--silent', '--disable-interactivity', '--accept-source-agreements') $app.id
        if ($code -in @(0, 3010, 1641)) { Write-Log '  winget terminó la desinstalación.' }
        if (-not (Test-StillInstalled $app)) { return $true }
        # Instalada por otra vía (Store, su web): se intenta con el paquete o el desinstalador de Windows
        if ((Remove-AppxApp $app) -and -not (Test-StillInstalled $app)) { return $true }
    }
    if ($Silent) { Write-Log '  Necesita el desinstalador del fabricante: se omite en modo sin ventana.'; return $false }
    [void](Invoke-RegistryUninstall $app)
    -not (Test-StillInstalled $app)
}

# Mismo reparto que la instalación: un lote de administrador y otro del usuario de escritorio
function Invoke-Uninstall($sel, [scriptblock]$onProgress) {
    if (-not $WorkerMode -and -not $script:ResumingBatch) { Start-IwinBatch $sel 'uninstall' }
    $script:LastInstallCode = 0
    $skip = @($sel | Where-Object { -not (Test-Uninstallable $_) })
    foreach ($app in $skip) { Write-Log "No se desinstala desde aquí: $($app.name)"; Complete-IwinItem $app $false $onProgress }
    $sel = @($sel | Where-Object { Test-Uninstallable $_ })
    $fail = @($skip)
    if (($sel | Where-Object type -eq 'winget') -and -not (Ensure-Winget)) {
        foreach ($app in $sel) { Complete-IwinItem $app $false $onProgress }
        return @($fail + $sel)
    }
    Write-Log "Desinstalando $($sel.Count) elementos · registro: $LogFile"
    Update-WingetCache
    if (-not $WorkerMode) {
        $machine = @($sel | Where-Object { $_.type -in @('winget', 'tweak') -and (Get-InstallContext $_) -eq 'machine' })
        if ($machine) {
            Write-Log 'Lote del sistema: una unica solicitud de administrador si hace falta.'
            $fail += @(Invoke-InstallWorker $machine $onProgress -Remove)
            $sel = @($sel | Where-Object { $machine.id -notcontains $_.id })
        }
        if (Test-Administrator) {
            $userApps = @($sel | Where-Object { $_.type -in @('winget', 'tweak') -and (Get-InstallContext $_) -eq 'user' })
            if ($userApps) {
                $fail += @(Invoke-InstallWorker $userApps $onProgress -AsUser -Remove)
                $sel = @($sel | Where-Object { $userApps.id -notcontains $_.id })
            }
        }
    }
    foreach ($app in $sel) {
        $script:LastInstallCode = 0
        if (Test-IwinStop) { $fail += $app; Complete-IwinItem $app $false $onProgress; continue }
        Set-IwinBatchRunning $app
        try { $present = Test-AppInstalled $app } catch { $present = $true }
        if (-not $present) {
            Write-Log "No estaba instalada: $($app.name)"
            Complete-IwinItem $app $true $onProgress
            continue
        }
        Write-Log "Desinstalando $($app.name)..."
        if ($WorkerMode -and $ResultFile) { Write-WorkerEvent @{current=$app.id} }
        elseif ($UI -and $byId -and $byId.ContainsKey($app.id)) { $byId[$app.id].Status='Desinstalando…'; $byId[$app.id].StatusKind='busy'; Set-Status "Desinstalando $($app.name)…" }
        $ok = $false
        try { $ok = Uninstall-App $app } catch { Write-Log "  Error: $($_.Exception.Message)" }
        if ($ok) { Write-Log "  Desinstalada: $($app.name)" } else { Write-Log "  SIGUE INSTALADA: $($app.name)"; $fail += $app }
        Complete-IwinItem $app $ok $onProgress
    }
    if ($fail) { Write-Log "Desinstalación terminada con fallos en: $(($fail | ForEach-Object name) -join ', ')" } else { Write-Log 'Desinstalación terminada.' }
    $fail
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

function Resume-IwinBatch($pending, [scriptblock]$onProgress) {
    if (-not $pending) { throw 'No hay lotes pendientes.' }
    $script:Batch=$pending.Data; $script:BatchPath=$pending.Path
    $script:ResumingBatch=$true; $script:StopRequested=$false
    $priorUpgrade=$UpgradePackages
    $script:UpgradePackages=$script:Batch.operation -eq 'upgrade'
    try {
        $ids=@($script:Batch.items | Where-Object state -ne 'done' | ForEach-Object id)
        $selection=@($Apps | Where-Object { $ids -contains $_.id })
        if ($script:Batch.operation -eq 'uninstall') { Invoke-Uninstall $selection $onProgress }
        else { Invoke-Install $selection $onProgress }
    } finally { $script:ResumingBatch=$false; $script:UpgradePackages=$priorUpgrade }
}
if ($Resume) {
    $pending=Get-IwinPendingBatches | Select-Object -First 1
    if (-not $pending) { Write-Log 'No hay lotes pendientes.'; exit 0 }
    $fail=@(Resume-IwinBatch $pending $null)
    exit $fail.Count
}

if ($AutoUpdate) {
    try {
        $prefsPath=Join-Path $LogDir 'preferencias.json'
        if(-not (Test-Path $prefsPath)){exit 0}
        $automatic=(Get-Content $prefsPath -Raw -Encoding UTF8 | ConvertFrom-Json).autoUpdate
        if($automatic -isnot [bool] -or -not $automatic){exit 0}
        Clear-IwinUpdateDownloads
        if(Test-IwinAppOpen){Write-Log 'Actualización pospuesta: iWinInstaller está abierto.';exit 0}
        if(Update-Self){exit 0}else{exit 1}
    }catch{Write-Log "Actualización pendiente: $($_.Exception.Message)";exit 1}
}

# ---------- Modos sin ventana ----------
if ($Check) {
    Write-Host "iWinInstaller $Version · comprobación en $env:COMPUTERNAME"
    if (-not (Test-Cmd winget)) { Write-Host '✗ Falta winget (instala «App Installer» desde Microsoft Store)' }
    Update-WingetCache
    $missing = @()
    $group = ''
    foreach ($app in $Apps) {
        $ok = Test-AppInstalled $app
        # Del catálogo ampliado solo se listan las que están instaladas
        if ($app.extra -and -not $ok) { continue }
        if ($app.group -ne $group) { $group = $app.group; Write-Host "`n[$group]" }
        if ($ok) { Write-Host "✓ $($app.name)" }
        elseif ($app.optin) { Write-Host "– $($app.name) (opcional, no instalado)" }
        else { Write-Host "✗ $($app.name)"; $missing += $app.name }
    }
    Write-Host ''
    $total = @($Apps | Where-Object { -not (Test-Optional $_) }).Count
    if ($missing) { Write-Host "Faltan $($missing.Count) de ${total}: $($missing -join ', ')" } else { Write-Host "Todo listo ($total/$total)." }
    exit $missing.Count
}

if ($Update) {
    if (Invoke-Update) { exit 0 } else { exit 1 }
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
    public string GroupLabel { get { return Section + " · " + Group; } }
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
    public bool ShowUninstall { get { return i && CanUninstall; } }
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
'@
}


# Estilos de botón compartidos por la ventana y sus diálogos
$ButtonStyles = @'
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#EDEDF2"/>
      <Setter Property="Background" Value="#22222B"/>
      <Setter Property="BorderBrush" Value="#30303A"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#8CC4FF"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#8CC4FF"/>
      <Setter Property="BorderBrush" Value="#8CC4FF"/>
      <Setter Property="Foreground" Value="#0B0B0F"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#3A1E24"/>
      <Setter Property="BorderBrush" Value="#5A2A32"/>
      <Setter Property="Foreground" Value="#FFB0B0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="#C8C8D2"/>
      <Setter Property="Padding" Value="10,5"/>
    </Style>
    <Style x:Key="GhostDanger" TargetType="Button" BasedOn="{StaticResource Ghost}">
      <Setter Property="Foreground" Value="#FF9A9A"/>
    </Style>
'@

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="iWinInstaller" Width="1180" Height="780" MinWidth="560" MinHeight="420"
        WindowStartupLocation="CenterScreen" Background="#0F0F13" Foreground="#EDEDF2"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="PostStep" TargetType="CheckBox">
      <Setter Property="MinHeight" Value="32"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Border x:Name="focus" Background="Transparent" CornerRadius="7" BorderBrush="Transparent" BorderThickness="1" Padding="5">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Border x:Name="box" Width="18" Height="18" CornerRadius="5" BorderBrush="#777782" BorderThickness="1.5" VerticalAlignment="Top" Margin="0,1,0,0">
                <Path x:Name="tick" Data="M3,8 L6,11 L13,4" Stroke="#0B0B0F" StrokeThickness="1.8" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Grid.Column="1" VerticalAlignment="Center" RecognizesAccessKey="True"/>
            </Grid>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True"><Setter TargetName="box" Property="Background" Value="#8CC4FF"/><Setter TargetName="box" Property="BorderBrush" Value="#8CC4FF"/><Setter TargetName="tick" Property="Visibility" Value="Visible"/></Trigger>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="focus" Property="BorderBrush" Value="#8CC4FF"/></Trigger>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="focus" Property="Background" Value="#19191D"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="focus" Property="Background" Value="#26262C"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="focus" Property="Opacity" Value="0.45"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="AfterExpander" TargetType="Expander">
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Expander">
          <Border BorderBrush="#2B2B30" BorderThickness="0,0,0,1" Margin="0,0,0,4">
            <StackPanel>
              <ToggleButton IsChecked="{Binding IsExpanded, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}" HorizontalContentAlignment="Stretch" Padding="0,14" Foreground="#F5F5F7">
                <ToggleButton.Template><ControlTemplate TargetType="ToggleButton">
                  <Border x:Name="hover" Background="Transparent" Padding="{TemplateBinding Padding}" CornerRadius="8">
                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="28"/></Grid.ColumnDefinitions>
                      <ContentPresenter/>
                      <Path x:Name="arrow" Grid.Column="1" Data="M1,1 L6,6 L1,11" Stroke="#ADADB5" StrokeThickness="1.5" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5"><Path.RenderTransform><RotateTransform Angle="0"/></Path.RenderTransform></Path>
                    </Grid>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="hover" Property="Background" Value="#19191D"/></Trigger>
                    <Trigger Property="IsPressed" Value="True"><Setter TargetName="hover" Property="Background" Value="#26262C"/></Trigger>
                    <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="hover" Property="BorderBrush" Value="#8CC4FF"/><Setter TargetName="hover" Property="BorderThickness" Value="1"/></Trigger>
                    <Trigger Property="IsChecked" Value="True"><Setter TargetName="arrow" Property="RenderTransform"><Setter.Value><RotateTransform Angle="90"/></Setter.Value></Setter></Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate></ToggleButton.Template>
                <ContentPresenter Content="{TemplateBinding Header}"/>
              </ToggleButton>
              <ContentPresenter x:Name="body" Content="{TemplateBinding Content}" Visibility="Collapsed"/>
            </StackPanel>
          </Border>
          <ControlTemplate.Triggers><Trigger Property="IsExpanded" Value="True"><Setter TargetName="body" Property="Visibility" Value="Visible"/></Trigger></ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <SolidColorBrush x:Key="Panel" Color="#111113"/>
    <SolidColorBrush x:Key="Card" Color="#19191C"/>
    <SolidColorBrush x:Key="Line" Color="#2B2B30"/>
    <SolidColorBrush x:Key="Muted" Color="#ADADB5"/>
    <SolidColorBrush x:Key="Faint" Color="#8B8B95"/>
    <SolidColorBrush x:Key="Accent" Color="#8CC4FF"/>
    <BooleanToVisibilityConverter x:Key="Vis"/>

    <!-- Barras de desplazamiento finas y oscuras: las de serie son claras y anchas -->
    <Style x:Key="ThumbStyle" TargetType="Thumb">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Border x:Name="t" Background="#3A3A46" CornerRadius="4"/>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="Background" Value="#565668"/></Trigger>
              <Trigger Property="IsDragging" Value="True"><Setter TargetName="t" Property="Background" Value="#8CC4FF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb><Thumb Style="{StaticResource ThumbStyle}" Margin="2,1"/></Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="MinWidth" Value="0"/>
          <Setter Property="Height" Value="10"/>
          <Setter Property="MinHeight" Value="10"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Grid Background="Transparent">
                  <Track x:Name="PART_Track" IsDirectionReversed="False">
                    <Track.Thumb><Thumb Style="{StaticResource ThumbStyle}" Margin="1,2"/></Track.Thumb>
                  </Track>
                </Grid>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="#1E1E26"/>
      <Setter Property="Foreground" Value="#EDEDF2"/>
      <Setter Property="BorderBrush" Value="#3A3A45"/>
      <Setter Property="Padding" Value="8,5"/>
    </Style>

    <!-- Desplegable de perfiles: superficie oscura, foco visible y selección por teclado. -->
    <Style x:Key="ProfileItem" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#EDEDF2"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="row" CornerRadius="6" Padding="12,8" Margin="2" Background="Transparent">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="22"/></Grid.ColumnDefinitions>
                <ContentPresenter/>
                <TextBlock x:Name="mark" Grid.Column="1" Text="✓" Foreground="#8CC4FF" Visibility="Hidden" HorizontalAlignment="Right"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="row" Property="Background" Value="#29243B"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="mark" Property="Visibility" Value="Visible"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="row" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ProfileMenu" TargetType="ComboBox">
      <Setter Property="Foreground" Value="#EDEDF2"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource ProfileItem}"/>
      <Setter Property="ScrollViewer.CanContentScroll" Value="True"/>
      <Setter Property="MaxDropDownHeight" Value="360"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="toggle" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="surface" Background="#19191C" BorderBrush="#33333D" BorderThickness="1" CornerRadius="8">
                      <Path Data="M0,0 L4,4 L8,0" Stroke="#C8C8D0" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,14,0"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="surface" Property="Background" Value="#22222A"/></Trigger>
                      <Trigger Property="IsPressed" Value="True"><Setter TargetName="surface" Property="Background" Value="#23344A"/></Trigger>
                      <Trigger Property="IsChecked" Value="True"><Setter TargetName="surface" Property="BorderBrush" Value="#8CC4FF"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}" Margin="12,0,34,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
              <Border x:Name="focus" BorderBrush="#8CC4FF" BorderThickness="2" CornerRadius="8" Visibility="Collapsed" IsHitTestVisible="False"/>
              <Popup x:Name="PART_Popup" Placement="Bottom" AllowsTransparency="True" Focusable="False" IsOpen="{TemplateBinding IsDropDownOpen}">
                <Border Background="#111115" BorderBrush="#41414B" BorderThickness="1" CornerRadius="10" Padding="4" Margin="0,6,0,0" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                  <ScrollViewer VerticalScrollBarVisibility="Auto"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter TargetName="focus" Property="Visibility" Value="Visible"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="TextMenu" TargetType="ContextMenu">
      <Setter Property="Foreground" Value="#EDEDF2"/>
      <Setter Property="Template">
        <Setter.Value><ControlTemplate TargetType="ContextMenu">
          <Border Background="#111115" BorderBrush="#41414B" BorderThickness="1" CornerRadius="10" Padding="5"><StackPanel IsItemsHost="True"/></Border>
        </ControlTemplate></Setter.Value>
      </Setter>
      <Setter Property="ItemContainerStyle">
        <Setter.Value><Style TargetType="MenuItem">
          <Setter Property="Foreground" Value="#EDEDF2"/>
          <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="MenuItem">
            <Border x:Name="row" Background="Transparent" CornerRadius="6" Padding="14,9"><ContentPresenter ContentSource="Header" RecognizesAccessKey="True"/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="row" Property="Background" Value="#29243B"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="row" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate></Setter.Value></Setter>
        </Style></Setter.Value>
      </Setter>
    </Style>
<!--BOTONES-->
    <Style x:Key="Chip" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#ADADB5"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" Background="Transparent" BorderBrush="#2A2A33" BorderThickness="1" CornerRadius="14" Padding="12,4">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#1C1C24"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="#182536"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#8CC4FF"/>
                <Setter Property="Foreground" Value="#EDEDF2"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Check" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="box" Width="20" Height="20" CornerRadius="6" BorderThickness="1.5" BorderBrush="#4A4A55" Background="Transparent">
              <Path x:Name="tick" Data="M4,10 L8,14 L16,6" Stroke="#0B0B0F" StrokeThickness="2.2" Visibility="Collapsed"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="box" Property="BorderBrush" Value="#8C80C0"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="#8CC4FF"/>
                <Setter TargetName="box" Property="BorderBrush" Value="#8CC4FF"/>
                <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Nav" TargetType="ListBoxItem">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="b" Background="Transparent" CornerRadius="8" Padding="10,7" Margin="0,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#1C1C24"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="#182536"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <!-- Todo el contenido se escala junto: el zoom (A−/A+, Ctrl + rueda) cambia texto, iconos y márgenes a la vez -->
  <Grid x:Name="Root">
    <Grid.LayoutTransform><ScaleTransform x:Name="Zoom" ScaleX="1" ScaleY="1"/></Grid.LayoutTransform>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Barra superior: secciones, nombre, búsqueda y tamaño del texto -->
    <Border Grid.Row="0" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="0,0,0,1" Padding="8,8,12,8">
      <DockPanel>
        <Button x:Name="NavToggle" DockPanel.Dock="Left" Style="{StaticResource Ghost}" Padding="9,6" ToolTip="Mostrar u ocultar las secciones">
          <TextBlock Text="&#xE700;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="15"/>
        </Button>
        <Image x:Name="Logo" DockPanel.Dock="Left" Width="26" Height="26" Margin="6,0,8,0" RenderOptions.BitmapScalingMode="HighQuality"/>
        <StackPanel DockPanel.Dock="Left" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,16,0">
          <TextBlock Text="iWinInstaller" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <TextBlock x:Name="VersionText" Foreground="{StaticResource Muted}" FontSize="12" Margin="8,1,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <Border DockPanel.Dock="Right" Background="{StaticResource Card}" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="8" Margin="10,0,0,0" VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal">
            <Button x:Name="ZoomOut" Style="{StaticResource Ghost}" Content="A−" FontSize="12" Padding="10,5" ToolTip="Texto más pequeño (Ctrl + −)"/>
            <Button x:Name="ZoomReset" Style="{StaticResource Ghost}" Padding="4,5" MinWidth="52" ToolTip="Tamaño normal (Ctrl + 0)">
              <TextBlock x:Name="ZoomText" Text="100 %" Foreground="{StaticResource Muted}" FontSize="12"/>
            </Button>
            <Button x:Name="ZoomIn" Style="{StaticResource Ghost}" Content="A+" FontSize="15" Padding="10,3" ToolTip="Texto más grande (Ctrl + +)"/>
          </StackPanel>
        </Border>
        <Border Background="{StaticResource Card}" CornerRadius="8" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="34" MaxWidth="560" HorizontalAlignment="Left" MinWidth="120">
          <Grid>
            <TextBlock Text="&#xE721;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{StaticResource Faint}" VerticalAlignment="Center" Margin="12,0,0,0" IsHitTestVisible="False"/>
            <TextBlock x:Name="SearchHint" Text="Buscar aplicaciones (Ctrl + F)" Foreground="{StaticResource Faint}" VerticalAlignment="Center" Margin="36,0,8,0" IsHitTestVisible="False" TextTrimming="CharacterEllipsis"/>
            <TextBox x:Name="Search" Background="Transparent" BorderThickness="0" Foreground="#EDEDF2" CaretBrush="#8CC4FF" VerticalContentAlignment="Center" Padding="32,0,10,0" FontSize="14">
              <TextBox.ContextMenu>
                <ContextMenu Style="{StaticResource TextMenu}">
                  <MenuItem Header="Cortar" Command="ApplicationCommands.Cut"/>
                  <MenuItem Header="Copiar" Command="ApplicationCommands.Copy"/>
                  <MenuItem Header="Pegar" Command="ApplicationCommands.Paste"/>
                  <Separator/>
                  <MenuItem Header="Seleccionar todo" Command="ApplicationCommands.SelectAll"/>
                </ContextMenu>
              </TextBox.ContextMenu>
            </TextBox>
          </Grid>
        </Border>
      </DockPanel>
    </Border>

    <Grid x:Name="CatalogPanel" Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition x:Name="NavColumn" Width="232"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Barra lateral: secciones y perfiles -->
      <Border x:Name="Sidebar" Grid.Column="0" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="0,0,1,0">
        <DockPanel Margin="10,12,10,12">
          <StackPanel DockPanel.Dock="Bottom" Margin="2,10,2,0">
            <TextBlock Text="PERFIL" Foreground="{StaticResource Muted}" FontSize="11" FontWeight="SemiBold" Margin="0,0,0,6"/>
            <ComboBox x:Name="Profile" Style="{StaticResource ProfileMenu}" Height="36" Margin="0,0,0,6"/>
            <Grid Margin="0,0,0,12">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <Button x:Name="ProfileSave" Grid.Column="0" Style="{StaticResource Btn}" Content="Guardar…" Padding="6,6" Margin="0,0,4,0" ToolTip="Guarda lo marcado como un perfil propio"/>
              <Button x:Name="ProfileImport" Grid.Column="1" Style="{StaticResource Btn}" Content="Importar…" Padding="6,6" Margin="0,0,4,0" ToolTip="Abre un perfil .iwin.json exportado en otro PC"/>
              <Button x:Name="ProfileMore" Grid.Column="2" Style="{StaticResource Btn}" Content="⋯" Padding="10,6" ToolTip="Exportar, eliminar o abrir la carpeta de perfiles">
                <Button.ContextMenu>
                  <ContextMenu Style="{StaticResource TextMenu}">
                    <MenuItem x:Name="ProfileExport" Header="Exportar a un archivo…"/>
                    <MenuItem x:Name="ProfileDelete" Header="Eliminar este perfil"/>
                    <MenuItem x:Name="ProfileFolder" Header="Abrir la carpeta de perfiles"/>
                  </ContextMenu>
                </Button.ContextMenu>
              </Button>
            </Grid>
            <TextBlock><Hyperlink x:Name="LogLink" Foreground="{StaticResource Muted}" TextDecorations="None">Abrir registro</Hyperlink></TextBlock>
            <TextBlock Margin="0,4,0,0"><Hyperlink x:Name="IgLink" Foreground="{StaticResource Muted}" TextDecorations="None">Instagram @_shun._05</Hyperlink></TextBlock>
          </StackPanel>
          <TextBlock DockPanel.Dock="Top" Text="SECCIONES" Foreground="{StaticResource Muted}" FontSize="11" FontWeight="SemiBold" Margin="4,0,0,6"/>
          <ListBox x:Name="Nav" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Nav}"
                   ScrollViewer.HorizontalScrollBarVisibility="Disabled">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <DockPanel x:Name="row">
                  <TextBlock DockPanel.Dock="Right" Text="{Binding Count}" Foreground="#7C7C88" FontSize="12" Margin="6,0,0,0"/>
                  <TextBlock x:Name="label" Text="{Binding Name}" Foreground="#EDEDF2" TextTrimming="CharacterEllipsis"/>
                </DockPanel>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding Kind}" Value="section">
                    <Setter TargetName="row" Property="Margin" Value="0,10,0,0"/>
                    <Setter TargetName="label" Property="Foreground" Value="#8CC4FF"/>
                    <Setter TargetName="label" Property="FontWeight" Value="SemiBold"/>
                    <Setter TargetName="label" Property="FontSize" Value="12"/>
                  </DataTrigger>
                  <DataTrigger Binding="{Binding Kind}" Value="group">
                    <Setter TargetName="label" Property="Margin" Value="10,0,0,0"/>
                  </DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
        </DockPanel>
      </Border>

      <!-- Zona principal -->
      <Grid Grid.Column="1">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="22,14,18,4">
          <DockPanel>
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="SelectVisible" Style="{StaticResource Ghost}" Content="Marcar visibles" ToolTip="Marca todo lo que se ve y aún no está instalado"/>
              <Button x:Name="ClearVisible" Style="{StaticResource Ghost}" Content="Desmarcar"/>
            </StackPanel>
            <TextBlock x:Name="Heading" Text="Todo el catálogo" FontSize="22" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
          </DockPanel>
          <TextBlock x:Name="Subheading" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,10"
                     Text="Marca lo que quieras instalar. Lo instalado no se reinstala; márcalo, o pulsa Desinstalar en su fila, para quitarlo."/>
          <WrapPanel>
            <RadioButton x:Name="FAll" GroupName="f" Style="{StaticResource Chip}" Content="Todas" IsChecked="True"/>
            <RadioButton x:Name="FChecked" GroupName="f" Style="{StaticResource Chip}" Content="Marcadas"/>
            <RadioButton x:Name="FMissing" GroupName="f" Style="{StaticResource Chip}" Content="No instaladas"/>
            <RadioButton x:Name="FInstalled" GroupName="f" Style="{StaticResource Chip}" Content="Instaladas"/>
            <RadioButton x:Name="FConfigure" GroupName="f" Style="{StaticResource Chip}" Content="Por configurar"/>
          </WrapPanel>
        </StackPanel>

        <ListBox Grid.Row="1" x:Name="List" Background="Transparent" BorderThickness="0" Margin="12,0,6,0"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.CanContentScroll="True"
                 VirtualizingPanel.IsVirtualizingWhenGrouping="True" VirtualizingPanel.ScrollUnit="Pixel">
          <ListBox.ContextMenu>
            <ContextMenu Style="{StaticResource TextMenu}">
              <MenuItem x:Name="MOpen" Header="Abrir"/>
              <MenuItem x:Name="MConfigured" Header="Marcar como configurada"/>
              <MenuItem x:Name="MUninstall" Header="Desinstalar…"/>
            </ContextMenu>
          </ListBox.ContextMenu>
          <ListBox.GroupStyle>
            <GroupStyle>
              <GroupStyle.HeaderTemplate>
                <DataTemplate>
                  <TextBlock Text="{Binding Name}" Foreground="#8CC4FF" FontSize="12" FontWeight="SemiBold" Margin="10,16,0,6"/>
                </DataTemplate>
              </GroupStyle.HeaderTemplate>
            </GroupStyle>
          </ListBox.GroupStyle>
          <ListBox.ItemContainerStyle>
            <Style TargetType="ListBoxItem">
              <Setter Property="Template">
                <Setter.Value>
                  <ControlTemplate TargetType="ListBoxItem">
                    <Border x:Name="card" Background="#19191C" CornerRadius="10" Padding="12,9" Margin="6,2" BorderThickness="1" BorderBrush="#29292E">
                      <ContentPresenter/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="card" Property="Background" Value="#222227"/></Trigger>
                      <Trigger Property="IsSelected" Value="True"><Setter TargetName="card" Property="BorderBrush" Value="#3A3A48"/></Trigger>
                      <DataTrigger Binding="{Binding Checked}" Value="True"><Setter TargetName="card" Property="BorderBrush" Value="#3D82C4"/></DataTrigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </Setter.Value>
              </Setter>
            </Style>
          </ListBox.ItemContainerStyle>
          <ListBox.ItemTemplate>
            <DataTemplate>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <CheckBox Grid.Column="0" Style="{StaticResource Check}" IsChecked="{Binding Checked, Mode=TwoWay}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                <Border Grid.Column="1" Width="36" Height="36" CornerRadius="9" Background="#182536" Margin="0,0,12,0" VerticalAlignment="Center">
                  <Grid>
                    <TextBlock x:Name="ini" Text="{Binding Initials}" Foreground="#8CC4FF" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    <TextBlock x:Name="gly" Text="{Binding Glyph}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="17" Foreground="#8CC4FF" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
                    <Border x:Name="pic" Width="28" Height="28" CornerRadius="7" Background="#F2F2F5" Visibility="Collapsed">
                      <Image Source="{Binding Image}" Width="20" Height="20" RenderOptions.BitmapScalingMode="HighQuality" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                  </Grid>
                </Border>
                <StackPanel Grid.Column="2" VerticalAlignment="Center" Margin="0,0,10,0">
                  <DockPanel LastChildFill="True">
                    <Border DockPanel.Dock="Right" CornerRadius="6" Padding="6,1" Margin="8,0,0,0" Background="#1E2A33" VerticalAlignment="Center" Visibility="{Binding IsCli, Converter={StaticResource Vis}}" ToolTip="Se usa desde la terminal (PowerShell, Windows Terminal…)">
                      <TextBlock Text="&gt;_ Terminal" FontFamily="Cascadia Mono, Consolas" FontSize="10.5" Foreground="#7FC8E8"/>
                    </Border>
                    <TextBlock Text="{Binding Name}" FontSize="14" FontWeight="SemiBold" Foreground="#EDEDF2" TextTrimming="CharacterEllipsis"/>
                  </DockPanel>
                  <TextBlock Text="{Binding Desc}" Foreground="#ADADB5" TextWrapping="Wrap" Margin="0,1,0,0"/>
                  <TextBlock x:Name="config" Text="{Binding Configuration}" Foreground="#8CC4FF" TextWrapping="Wrap" FontSize="11" Margin="0,3,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="3" Orientation="Vertical" VerticalAlignment="Center" MaxWidth="145">
                  <Border x:Name="badge" CornerRadius="10" Padding="10,3" VerticalAlignment="Center" Background="Transparent">
                    <TextBlock x:Name="badgeText" Text="{Binding Status}" FontSize="12" Foreground="#ADADB5"/>
                  </Border>
                  <Button Tag="setup" Style="{StaticResource Ghost}" Content="Pasos y notas" Visibility="{Binding NeedsConfiguration, Converter={StaticResource Vis}}" ToolTip="Qué falta configurar y cómo comprobarlo"/>
                  <Button Tag="open" Style="{StaticResource Ghost}" Content="{Binding OpenLabel}" Margin="4,0,0,0" Visibility="{Binding ShowOpen, Converter={StaticResource Vis}}" ToolTip="Abre la aplicación"/>
                  <Button Tag="uninstall" Style="{StaticResource GhostDanger}" Content="{Binding UninstallLabel}" Margin="2,0,0,0" Visibility="{Binding ShowUninstall, Converter={StaticResource Vis}}" ToolTip="Quitar de este PC (pide confirmación)"/>
                </StackPanel>
              </Grid>
              <DataTemplate.Triggers>
                <DataTrigger Binding="{Binding Configuration}" Value=""><Setter TargetName="config" Property="Visibility" Value="Collapsed"/></DataTrigger>
                <DataTrigger Binding="{Binding Status}" Value=""><Setter TargetName="badge" Property="Visibility" Value="Collapsed"/></DataTrigger>
                <DataTrigger Binding="{Binding HasGlyph}" Value="True">
                  <Setter TargetName="gly" Property="Visibility" Value="Visible"/>
                  <Setter TargetName="ini" Property="Visibility" Value="Collapsed"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding HasImage}" Value="True">
                  <Setter TargetName="pic" Property="Visibility" Value="Visible"/>
                  <Setter TargetName="ini" Property="Visibility" Value="Collapsed"/>
                  <Setter TargetName="gly" Property="Visibility" Value="Collapsed"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding StatusKind}" Value="ok">
                  <Setter TargetName="badge" Property="Background" Value="#1C3326"/>
                  <Setter TargetName="badgeText" Property="Foreground" Value="#78DC96"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding StatusKind}" Value="bad">
                  <Setter TargetName="badge" Property="Background" Value="#3A1E22"/>
                  <Setter TargetName="badgeText" Property="Foreground" Value="#FF7878"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding StatusKind}" Value="busy">
                  <Setter TargetName="badge" Property="Background" Value="#182536"/>
                  <Setter TargetName="badgeText" Property="Foreground" Value="#8CC4FF"/>
                </DataTrigger>
              </DataTemplate.Triggers>
            </DataTemplate>
          </ListBox.ItemTemplate>
        </ListBox>
      </Grid>
    </Grid>

    <Border x:Name="AfterPanel" Grid.Row="1" Grid.RowSpan="2" Panel.ZIndex="10" Background="#08080A" CornerRadius="18" Margin="12,4,12,8" BorderBrush="#303034" BorderThickness="1" Visibility="Collapsed">
      <Grid Margin="20,16">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <StackPanel Margin="0,0,0,14">
          <TextBlock Text="Después de instalar" FontSize="24" FontWeight="SemiBold" Foreground="#F5F5F7"/>
          <WrapPanel Margin="0,12,0,0">
            <Button x:Name="AfterCheckAll" Style="{StaticResource Primary}" Content="Comprobar todo" Margin="0,0,8,6"/>
            <Button x:Name="AfterBack" Style="{StaticResource Btn}" Content="Volver al catálogo" Margin="0,0,0,6"/>
          </WrapPanel>
        </StackPanel>
        <ScrollViewer x:Name="AfterScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel>
            <TextBlock x:Name="AfterSummary" TextWrapping="Wrap" Foreground="#ADADB5" Margin="0,0,0,16"/>
            <StackPanel x:Name="AfterRows"/>
          </StackPanel>
        </ScrollViewer>
      </Grid>
    </Border>

    <!-- Barra inferior: actividad, estado y acciones -->
    <Border x:Name="ActionPanel" Grid.Row="2" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0">
      <Grid Margin="16,10,16,12">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBox x:Name="Log" Grid.Row="0" Height="120" Visibility="Collapsed" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                 Background="#0F0F14" Foreground="#A0A0AA" BorderBrush="{StaticResource Line}" FontFamily="Segoe UI" FontSize="12" Margin="0,0,0,10" Padding="8"/>
        <StackPanel Grid.Row="1">
          <TextBlock x:Name="StatusText" Text="Elige las aplicaciones. Los accesos del escritorio se agrupan al terminar." Foreground="{StaticResource Muted}" TextWrapping="Wrap" TextTrimming="CharacterEllipsis" MaxHeight="36"
                     ToolTip="{Binding Text, RelativeSource={RelativeSource Self}}"/>
          <ProgressBar x:Name="Bar" Height="4" Margin="0,8,0,0" Background="#24242C" Foreground="#8CC4FF" BorderThickness="0"/>
        </StackPanel>
        <WrapPanel Grid.Row="2" HorizontalAlignment="Right" Margin="0,8,0,0">
          <!-- En ventanas pequeñas las acciones secundarias pasan a este menú -->
          <Button x:Name="BtnMore" Style="{StaticResource Btn}" Content="⋯" Padding="12,8" Margin="0,4,6,0" Visibility="Collapsed" ToolTip="Actividad, diagnóstico y actualizar">
            <Button.ContextMenu>
              <ContextMenu Style="{StaticResource TextMenu}">
                <MenuItem x:Name="MLog" Header="Mostrar actividad"/>
                <MenuItem x:Name="MExport" Header="Exportar diagnóstico"/>
                <MenuItem x:Name="MUpdate" Header="Actualizar todo"/>
                <MenuItem x:Name="MAppUpdate" Header="Buscar nueva versión de iWinInstaller"/>
                <MenuItem x:Name="MAutoUpdate" Header="Actualizar iWinInstaller automáticamente" IsCheckable="True" ToolTip="Comprueba GitHub al abrir, al iniciar sesión y cada día; no actualiza otras aplicaciones"/>
                <MenuItem x:Name="MAfter" Header="Después de instalar…"/>
                <MenuItem x:Name="MResume" Header="Reanudar lote pendiente…"/>
              </ContextMenu>
            </Button.ContextMenu>
          </Button>
          <Button x:Name="LogToggle" Style="{StaticResource Ghost}" Content="Mostrar actividad" Margin="0,4,6,0"/>
          <Button x:Name="BtnExport" Style="{StaticResource Btn}" Content="Exportar diagnóstico" Margin="0,4,6,0"/>
          <Button x:Name="BtnUpdate" Style="{StaticResource Btn}" Content="Actualizar todo" Margin="0,4,6,0"/>
          <Button x:Name="BtnResume" Style="{StaticResource Btn}" Content="Reanudar lote" Margin="0,4,6,0" Visibility="Collapsed"/>
          <Button x:Name="BtnCancel" Style="{StaticResource Btn}" Content="Pausar al terminar esta app" Margin="0,4,6,0" Visibility="Collapsed"/>
          <Button x:Name="BtnAfter" Style="{StaticResource Btn}" Content="Después de instalar" Margin="0,4,6,0"/>
          <Button x:Name="BtnVerify" Style="{StaticResource Btn}" Content="Verificar" Margin="0,4,6,0"/>
          <Button x:Name="BtnRemove" Style="{StaticResource Danger}" Content="Desinstalar" Margin="0,4,6,0" Visibility="Collapsed"/>
          <Button x:Name="BtnInstall" Style="{StaticResource Primary}" Content="Instalar" MinWidth="150" Margin="0,4,0,0"/>
        </WrapPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@.Replace('<!--BOTONES-->', $ButtonStyles)

# Diálogo propio (oscuro y con el mismo zoom): confirmaciones y nombre de perfil
$dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        SizeToContent="WidthAndHeight" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Foreground="#EDEDF2" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
<!--BOTONES-->
    <Style x:Key="CheckLabel" TargetType="CheckBox">
      <Setter Property="Foreground" Value="#C8C8D2"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="box" Width="18" Height="18" CornerRadius="5" BorderThickness="1.5" BorderBrush="#4A4A55" VerticalAlignment="Top" Margin="0,1,10,0">
                <Path x:Name="tick" Data="M3.5,9 L7,12.5 L14.5,5" Stroke="#0B0B0F" StrokeThickness="2" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="#8CC4FF"/>
                <Setter TargetName="box" Property="BorderBrush" Value="#8CC4FF"/>
                <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="Frame" Background="#18181B" BorderBrush="#3A3A45" BorderThickness="1" CornerRadius="12" Padding="22,18,22,18" Margin="12">
    <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="4" Opacity="0.6"/></Border.Effect>
    <StackPanel Width="420">
      <TextBlock x:Name="DTitle" FontSize="17" FontWeight="SemiBold" TextWrapping="Wrap"/>
      <ScrollViewer MaxHeight="260" VerticalScrollBarVisibility="Auto" Margin="0,8,0,0">
        <TextBlock x:Name="DText" Foreground="#A4A4B0" TextWrapping="Wrap"/>
      </ScrollViewer>
      <Border x:Name="DInputFrame" Background="#1E1E26" BorderBrush="#33333D" BorderThickness="1" CornerRadius="8" Height="36" Margin="0,14,0,0" Visibility="Collapsed">
        <TextBox x:Name="DInput" Background="Transparent" BorderThickness="0" Foreground="#EDEDF2" CaretBrush="#8CC4FF" VerticalContentAlignment="Center" Padding="8,0" FontSize="14"/>
      </Border>
      <CheckBox x:Name="DCheck" Style="{StaticResource CheckLabel}" Margin="0,12,0,0" Visibility="Collapsed"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
        <Button x:Name="DCancel" Style="{StaticResource Btn}" Content="Cancelar" IsCancel="True" Margin="0,0,8,0" MinWidth="96"/>
        <Button x:Name="DOk" Style="{StaticResource Primary}" Content="Aceptar" IsDefault="True" MinWidth="110"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@.Replace('<!--BOTONES-->', $ButtonStyles)

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
$byId = @{}
foreach ($app in $Apps) {
    $it = New-Object IwinApp
    $it.Id = $app.id; $it.Name = $app.name; $it.Desc = $app.desc; $it.Group = $app.group; $it.Section = $app.section
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
    $it.Search = "$($app.name) $($app.desc) $($app.group) $($app.section) $($app.winget)".ToLower()
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
    $remove = @($items | Where-Object { $_.Checked -and $_.Installed -and $_.CanUninstall }).Count
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
    $targets = @($targets | Where-Object { $_ -and $_.Installed -and $_.CanUninstall })
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
        if ($ok) { $it.Installed = if($it.IsTweak){Test-Tweak $a.id}else{$false}; $it.Checked = $false; $it.Status = $(if ($it.IsTweak) { 'Deshecho' } else { 'Desinstalada' }); $it.StatusKind = 'none' }
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
$ui.BtnRemove.Add_Click({ Start-Uninstall @($items | Where-Object { $_.Checked -and $_.Installed -and $_.CanUninstall }) })

# Teclado: Ctrl + F busca, Ctrl + +/−/0 cambia el tamaño, Espacio marca y Supr desinstala la fila
$win.Add_PreviewKeyDown({
    param($s, $e)
    $ctrl = [Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control
    if ($ctrl -and $e.Key -in @('OemPlus', 'Add')) { Set-Zoom ($ui.Zoom.ScaleX + 0.1); $e.Handled = $true }
    elseif ($ctrl -and $e.Key -in @('OemMinus', 'Subtract')) { Set-Zoom ($ui.Zoom.ScaleX - 0.1); $e.Handled = $true }
    elseif ($ctrl -and $e.Key -in @('D0', 'NumPad0')) { Set-Zoom 1; $e.Handled = $true }
    elseif ($ctrl -and $e.Key -eq 'F') { [void]$ui.Search.Focus(); $ui.Search.SelectAll(); $e.Handled = $true }
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
        $fail=if($pending){@(Resume-IwinBatch $pending $progress)}else{@(Invoke-Install $selection $progress)}
        $msg=if(Test-IwinStop){'Lote pausado. Reanuda cuando quieras; no se interrumpió la aplicación en curso.'}elseif($fail.Count){"Quedan $($fail.Count) elementos pendientes. Puedes reanudar y volver a comprobar."}else{'Instalación terminada. Abre «Después de instalar» para completar y comprobar la configuración.'}
        if (@(Get-IwinRebootPending).Count) { $msg += ' Hay cambios que requieren reiniciar Windows.' }
        Set-Status $msg
        Update-Nav; Update-Filter
    } catch { Write-Log "No se pudo completar: $($_.Exception.Message)"; Set-Status $_.Exception.Message }
    finally { Set-Busy $false }
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
