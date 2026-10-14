# iWinInstaller — Autoinstalador con interfaz gráfica para Windows 10 / 11
# Lee el catálogo de apps.json (y los perfiles de profiles.json); añadir una app = una entrada nueva.
# Uso:
#   Iniciar.bat                                   ventana
#   iWinInstaller.ps1 -Check                      informe ✓/✗ en consola
#   iWinInstaller.ps1 -Silent [-Perfil Gaming]    instala un perfil sin ventana
#   iWinInstaller.ps1 -Update                     actualiza las aplicaciones instaladas
param(
    [switch]$Check,
    [switch]$Silent,
    [switch]$Update,
    [string]$Perfil = 'Todo',
    [string]$WorkerMode,
    [string]$PlanFile,
    [string]$ResultFile,
    [string]$SharedLog,
    [switch]$UpgradePackages
)
$ProgressPreference = 'SilentlyContinue'
# Salida de herramientas en UTF-8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'

$Version = 'v2.0'
$Instagram = 'https://www.instagram.com/_shun._05/'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
# PowerShell 5.1 devuelve un array JSON como un solo objeto: «ForEach-Object { $_ }» lo desenrolla
$Apps = @(Get-Content (Join-Path $Root 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
$Profiles = Get-Content (Join-Path $Root 'profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ReleaseApi = 'https://api.github.com/repos/iShun05/iWinInstaller/releases/latest'
$UI = -not ($Check -or $Silent -or $Update -or $WorkerMode)

# Registro en archivo: %LOCALAPPDATA%\iWinInstaller\iWinInstaller_AAAA-MM-DD.log
$LogDir = Join-Path $env:LOCALAPPDATA 'iWinInstaller'
New-Item $LogDir -ItemType Directory -Force | Out-Null
$LogFile = Join-Path $LogDir ('iWinInstaller_{0:yyyy-MM-dd_HH-mm-ss-fff}.log' -f (Get-Date))
if ($WorkerMode -and $SharedLog) { $LogFile = $SharedLog }

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
        $dependencies=@(Get-ChildItem (Join-Path $temporary $folder) -Recurse -File | Where-Object Extension -in @('.appx','.msix') | ForEach-Object FullName)
        if (-not $dependencies.Count) { throw 'Faltan las dependencias de la arquitectura actual.' }
        Add-AppxPackage -Path (Join-Path $dir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle') -DependencyPath $dependencies -ErrorAction Stop
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
$wingetOk = @(0, 3010, -1978335135, -1978335189)

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
    if ($app.type -eq 'tweak') { return 'machine' }
    if ($app.context) { return $app.context }
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
        $nextPhase = if ($tail -match '(?i)Starting.*install|Installing|Instalando|Starting package') { 'Instalando' } elseif ($tail -match '(?i)verified|verificado|hash') { 'Verificando' } elseif ($tail -match '(?i)Downloading|Descargando') { 'Descargando' } else { $phase }
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
    $script:LastInstallCode = $code
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
        $download.GetAwaiter().GetResult()
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
function Invoke-InstallWorker($selection, [scriptblock]$onProgress, [switch]$AsUser) {
    $stem = Join-Path $env:TEMP ('iwin-batch-' + [Guid]::NewGuid().ToString('N'))
    $plan = "$stem.plan.json"; $result = "$stem.result.jsonl"
    @($selection | ForEach-Object id) | ConvertTo-Json -Compress | Set-Content $plan -Encoding UTF8
    New-Item $result -ItemType File -Force | Out-Null
    $mode = if ($AsUser) { 'user' } else { 'machine' }
    $args0 = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Root 'iWinInstaller.ps1')`" -WorkerMode $mode -PlanFile `"$plan`" -ResultFile `"$result`" -SharedLog `"$LogFile`""
    if ($UpgradePackages) { $args0 += ' -UpgradePackages' }
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
                if ($event.current -and $UI -and $byId -and $byId.ContainsKey($event.current)) {
                    $byId[$event.current].Status = 'Instalando…'; $byId[$event.current].StatusKind = 'busy'
                    if ($event.phase -in @('Descargando','Instalando','Verificando')) { $byId[$event.current].Status=$event.phase+'…'; Set-Status "$($byId[$event.current].Name) · $($event.phase)…" } else { Set-Status "Instalando $($byId[$event.current].Name)…" }
                }
                if ($event.id -and $event.ok -is [bool]) {
                    $app = $selection | Where-Object id -eq $event.id | Select-Object -First 1
                    if ($app -and -not $reported.ContainsKey($event.id)) {
                        $reported[$event.id] = [bool]$event.ok
                        if ($onProgress) { & $onProgress $app ([bool]$event.ok) }
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
    finally { Remove-Item $plan, $result -Force -ErrorAction SilentlyContinue }
    foreach ($app in $selection) {
        if (-not $reported.ContainsKey($app.id)) { if ($onProgress) { & $onProgress $app $false }; $app }
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
        Invoke-WebRequest "https://download.virtualbox.org/virtualbox/$v/VBoxGuestAdditions_$v.iso" -OutFile $dest -UseBasicParsing
        Write-Log "  Guardado en $dest"
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
function Get-RegValue($path, $name) { (Get-ItemProperty $path -Name $name -ErrorAction SilentlyContinue).$name }
function Install-Tweak($id) {
    if ($id -ne 'wsl') { return $false }
    $ok = Invoke-Elevated 'wsl.exe --install --no-launch'
    if ($ok) { Write-Log '  Reinicia Windows para terminar de instalar WSL.' }
    return $ok
}
function Test-Tweak($id) {
    if ($id -ne 'wsl') { return $false }
    & wsl.exe --status *> $null
    return ($LASTEXITCODE -eq 0)
}

function Update-Self {
    if (-not (Test-Path (Join-Path $Root 'instalado.txt'))) { return $true }
    $release = Invoke-RestMethod $ReleaseApi
    $tag = $release.tag_name
    if (-not $tag) { throw 'No se pudo consultar la última versión.' }
    if ($tag -eq $Version) { Write-Log "  iWinInstaller ya está en la última versión ($Version)."; return $true }
    Write-Log "  iWinInstaller: actualizando de $Version a $tag"
    if (Test-Path (Join-Path $Root 'iWinInstaller.exe')) {
        $updateDir=Join-Path $LogDir 'actualizacion'
        New-Item $updateDir -ItemType Directory -Force | Out-Null
        $asset = $release.assets | Where-Object name -eq 'iWinInstaller-Setup.exe' | Select-Object -First 1
        if (-not $asset -or $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw 'Falta la descarga con su hash SHA256.' }
        $expected = $Matches[1]
        $setup=Join-Path $updateDir 'iWinInstaller-Setup.exe'
        Invoke-WebRequest $asset.browser_download_url -OutFile $setup -UseBasicParsing
        if ((Get-FileHash $setup).Hash -ne $expected) { throw 'La actualización no supera la comprobación SHA256.' }
        $p=Start-Process $setup -ArgumentList '--silent' -PassThru
        if ($UI -and $env:IWIN_HOST_PID -match '^\d+$') {
            Write-Log '  La nueva version se instalara al cerrar la app; no interrumpe la sesion actual.'
            return $true
        }
    } else {
        $p = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Root 'install.ps1')`" -Silent"
    }
    Wait-Proc $p 600
    $p.HasExited -and $p.ExitCode -eq 0
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
        'manual' { Write-Log '  Necesita instalarse desde la cuenta del proveedor; no se marca como instalada.'; if (-not $Silent) { Start-Process $app.page }; return $false }
    }
    # type = download: instalador oficial con asistente (HoYoPlay y Riot no ofrecen instalación silenciosa)
    if ($Silent) { Write-Log '  Necesita su asistente: se omite en modo sin ventana.'; return $false }
    $tmp = Join-Path $env:TEMP ('iwin-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest $app.url -OutFile $tmp -UseBasicParsing
        $bytes = [IO.File]::ReadAllBytes($tmp)
        if ($bytes.Length -lt 1MB -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw 'la descarga no es un ejecutable de Windows' }
        if ((Get-AuthenticodeSignature $tmp).Status -ne 'Valid') { throw 'el instalador no tiene una firma digital válida' }
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
function Get-ProfileApps($name) {
    # Desde la consola los acentos pueden llegar mal codificados: se compara solo con las letras ASCII
    $key = $name -replace '[^A-Za-z]', ''
    $match = $Profiles.PSObject.Properties.Name | Where-Object { ($_ -replace '[^A-Za-z]', '') -eq $key } | Select-Object -First 1
    if ($match) { $name = $match }
    $groups = @($Profiles.$name)
    if (-not $groups) { return @() }
    if ($groups -contains '*') { return @($Apps | Where-Object { -not (Test-Optional $_) }) }
    @($Apps | Where-Object { ($groups -contains $_.id -and -not $_.optin) -or ($groups -contains $_.group -and -not (Test-Optional $_)) })
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
    $required = @($sel | ForEach-Object { $_.requires })
    foreach ($app in $sel) {
        switch ($app.type) {
            'vboxga' { $required += 'virtualbox' }
        }
    }
    $deps = @($Apps | Where-Object { $required -contains $_.id })
    $sel = $deps + @($sel | Where-Object { $required -notcontains $_.id })
    $sel = @($sel | Where-Object type -ne 'download') + @($sel | Where-Object type -eq 'download')
    if (($sel | Where-Object { $_.type -in @('winget', 'wingetall') }) -and -not (Ensure-Winget)) {
        foreach ($app in $sel) { if ($onProgress) { & $onProgress $app $false } }
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
        # Lo que ya está instalado no se vuelve a instalar
        try { $alreadyInstalled = (Test-AppInstalled $app) } catch {
            Write-Log "  No se pudo comprobar $($app.name): $($_.Exception.Message)"
            $fail += $app
            if ($onProgress) { & $onProgress $app $false }
            continue
        }
        if ($alreadyInstalled -and -not $UpgradePackages) {
            Write-Log "Ya instalada, se omite: $($app.name)"
            if ($onProgress) { & $onProgress $app $true }
            continue
        }
        Write-Log "Instalando $($app.name)..."
        if ($WorkerMode -and $ResultFile) { Write-WorkerEvent @{current=$app.id} }
        elseif ($UI -and $byId -and $byId.ContainsKey($app.id)) { $byId[$app.id].Status='Instalando…'; $byId[$app.id].StatusKind='busy'; Set-Status "Instalando $($app.name)…" }
        $ok = $false
        try {
            $ok = Install-App $app
            if (-not $ok -and $app.type -in @('winget','wingetall') -and $LastInstallCode -in @(-1978335224,-1978335173,-1978335123)) {
                Write-Log '  Reintentando...'
                Start-Sleep -Seconds 1
                $ok = Install-App $app
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
        if ($onProgress) { & $onProgress $app $ok }
    }
    Organize-Desktop
    if ($fail) {
        Write-Log "Terminado con fallos en: $(($fail | ForEach-Object name) -join ', ')"
        if (-not $WorkerMode -and $LogFile) { try { $report = Export-Diagnostic; Write-Log "Diagnostico guardado en $report" } catch { Write-Log "No se pudo exportar el diagnostico: $($_.Exception.Message)" } }
    } else { Write-Log 'Todo instalado correctamente.' }
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
        $fail = @(Invoke-Install $selection { param($app,$ok) Write-WorkerEvent @{id=$app.id; ok=[bool]$ok} })
        $exitCode = $fail.Count
    } catch { Write-Log "Error del lote: $($_.Exception.Message)"; $exitCode=1 }
    Write-WorkerEvent @{done=$true; exitCode=$exitCode}
    exit $exitCode
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
    $sel = Get-ProfileApps $Perfil
    if (-not $sel) { Write-Log "Perfil desconocido: $Perfil (disponibles: $(($Profiles.PSObject.Properties.Name) -join ', '))"; exit 1 }
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
    public string Initials { get; set; }
    public string IconSpec { get; set; }
    public string Glyph { get; set; }
    public bool HasGlyph { get { return !string.IsNullOrEmpty(Glyph); } }
    ImageSource im; public ImageSource Image { get { return im; } set { im = value; N("Image"); N("HasImage"); } }
    public bool HasImage { get { return im != null; } }
    public string Search { get; set; }
    public bool Optional { get; set; }
    bool c; public bool Checked { get { return c; } set { if (c != value) { c = value; N("Checked"); } } }
    bool i; public bool Installed { get { return i; } set { i = value; N("Installed"); N("Configuration"); } }
    public bool NeedsConfiguration { get; set; }
    bool configured; public bool Configured { get { return configured; } set { configured = value; N("Configured"); N("Configuration"); } }
    public string Configuration { get { return !Installed || !NeedsConfiguration ? "" : configured ? "Configuración confirmada por ti" : "Por configurar · sesión sin comprobar"; } }
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


[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="iWinInstaller" Width="1180" Height="780" MinWidth="900" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="#000000" Foreground="#ECECF0"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Panel" Color="#0C0C10"/>
    <SolidColorBrush x:Key="Card" Color="#141418"/>
    <SolidColorBrush x:Key="CardHover" Color="#1F1F28"/>
    <SolidColorBrush x:Key="Line" Color="#2A2A33"/>
    <SolidColorBrush x:Key="Muted" Color="#8C8C96"/>
    <SolidColorBrush x:Key="Accent" Color="#BEACFF"/>
    <SolidColorBrush x:Key="Ok" Color="#78DC96"/>
    <SolidColorBrush x:Key="Bad" Color="#FF7878"/>

    <!-- Desplegable de perfiles: superficie oscura, foco visible y selección por teclado. -->
    <Style x:Key="ProfileItem" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#ECECF0"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="row" CornerRadius="6" Padding="12,9" Margin="2" Background="Transparent">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="22"/></Grid.ColumnDefinitions>
                <ContentPresenter/>
                <TextBlock x:Name="mark" Grid.Column="1" Text="✓" Foreground="#BEACFF" Visibility="Hidden" HorizontalAlignment="Right"/>
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
      <Setter Property="Foreground" Value="#ECECF0"/>
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
                    <Border x:Name="surface" Background="#17171D" BorderBrush="#373740" BorderThickness="1" CornerRadius="8">
                      <Path Data="M0,0 L4,4 L8,0" Stroke="#C8C8D0" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,14,0"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="surface" Property="Background" Value="#22222A"/></Trigger>
                      <Trigger Property="IsPressed" Value="True"><Setter TargetName="surface" Property="Background" Value="#2C263D"/></Trigger>
                      <Trigger Property="IsChecked" Value="True"><Setter TargetName="surface" Property="BorderBrush" Value="#BEACFF"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}" Margin="13,0,34,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
              <Border x:Name="focus" BorderBrush="#BEACFF" BorderThickness="2" CornerRadius="8" Visibility="Collapsed" IsHitTestVisible="False"/>
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
      <Setter Property="Foreground" Value="#ECECF0"/>
      <Setter Property="Template">
        <Setter.Value><ControlTemplate TargetType="ContextMenu">
          <Border Background="#111115" BorderBrush="#41414B" BorderThickness="1" CornerRadius="10" Padding="5"><StackPanel IsItemsHost="True"/></Border>
        </ControlTemplate></Setter.Value>
      </Setter>
      <Setter Property="ItemContainerStyle">
        <Setter.Value><Style TargetType="MenuItem">
          <Setter Property="Foreground" Value="#ECECF0"/>
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
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#ECECF0"/>
      <Setter Property="Background" Value="#1F1F28"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.9"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.72"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#BEACFF"/>
      <Setter Property="Foreground" Value="#0B0B0F"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Chip" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#8C8C96"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" Background="Transparent" BorderBrush="#2A2A33" BorderThickness="1" CornerRadius="14" Padding="12,5">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="#2A2440"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#BEACFF"/>
                <Setter Property="Foreground" Value="#ECECF0"/>
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
              <Path x:Name="tick" Data="M4,10 L8,14 L16,6" Stroke="#0B0B0F" StrokeThickness="2.2" Visibility="Collapsed" Margin="0,0,0,0"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="#BEACFF"/>
                <Setter TargetName="box" Property="BorderBrush" Value="#BEACFF"/>
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
            <Border x:Name="b" Background="Transparent" CornerRadius="8" Padding="12,8" Margin="0,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#1A1A22"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="#2A2440"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="250"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Barra lateral -->
    <Border Grid.Column="0" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="0,0,1,0">
      <DockPanel Margin="16,20,16,16">
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="4,0,0,22">
          <Image x:Name="Logo" Width="40" Height="40" RenderOptions.BitmapScalingMode="HighQuality"/>
          <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="iWinInstaller" FontSize="18" FontWeight="SemiBold"/>
            <TextBlock x:Name="VersionText" Foreground="{StaticResource Muted}" FontSize="12"/>
          </StackPanel>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom" Margin="4,12,0,0">
          <TextBlock Text="PERFIL" Foreground="{StaticResource Muted}" FontSize="11" FontWeight="SemiBold" Margin="0,0,0,6"/>
          <ComboBox x:Name="Profile" Style="{StaticResource ProfileMenu}" Height="40" Margin="0,0,0,16"/>
          <TextBlock Margin="0,0,0,4"><Hyperlink x:Name="LogLink" Foreground="{StaticResource Muted}" TextDecorations="None">Abrir registro</Hyperlink></TextBlock>
          <TextBlock><Hyperlink x:Name="IgLink" Foreground="{StaticResource Muted}" TextDecorations="None">Instagram @_shun._05</Hyperlink></TextBlock>
        </StackPanel>
        <TextBlock DockPanel.Dock="Top" Text="SECCIONES" Foreground="{StaticResource Muted}" FontSize="11" FontWeight="SemiBold" Margin="4,0,0,6"/>
        <ListBox x:Name="Nav" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Nav}"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled">
          <ListBox.ItemTemplate>
            <DataTemplate>
              <DockPanel>
                <TextBlock DockPanel.Dock="Right" Text="{Binding Count}" Foreground="#8C8C96" FontSize="12"/>
                <TextBlock Text="{Binding Name}" Foreground="#ECECF0" TextTrimming="CharacterEllipsis"/>
              </DockPanel>
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
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0" Margin="28,22,28,10">
        <TextBlock x:Name="Heading" Text="Todas las apps" FontSize="28" FontWeight="SemiBold"/>
        <TextBlock x:Name="Subheading" Foreground="{StaticResource Muted}" Margin="0,4,0,14"
                   Text="Marca lo que quieras instalar. Lo que ya tienes aparece como instalado y no se vuelve a instalar."/>
        <DockPanel>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
            <Button x:Name="SelectVisible" Style="{StaticResource Btn}" Content="Marcar visibles" Padding="12,6" Margin="0,0,6,0"/>
            <Button x:Name="ClearVisible" Style="{StaticResource Btn}" Content="Desmarcar visibles" Padding="12,6"/>
          </StackPanel>
          <Border Background="{StaticResource Card}" CornerRadius="10" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="38" Margin="0,0,16,0">
            <Grid>
              <TextBlock x:Name="SearchHint" Text="Buscar aplicaciones…" Foreground="#5E5E68" VerticalAlignment="Center" Margin="14,0" IsHitTestVisible="False"/>
              <TextBox x:Name="Search" Background="Transparent" BorderThickness="0" Foreground="#ECECF0" CaretBrush="#BEACFF" VerticalContentAlignment="Center" Padding="10,0" FontSize="14">
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
        <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
          <RadioButton x:Name="FAll" GroupName="f" Style="{StaticResource Chip}" Content="Todas" IsChecked="True"/>
          <RadioButton x:Name="FChecked" GroupName="f" Style="{StaticResource Chip}" Content="Marcadas"/>
          <RadioButton x:Name="FMissing" GroupName="f" Style="{StaticResource Chip}" Content="No instaladas"/>
          <RadioButton x:Name="FInstalled" GroupName="f" Style="{StaticResource Chip}" Content="Instaladas"/>
          <RadioButton x:Name="FConfigure" GroupName="f" Style="{StaticResource Chip}" Content="Por configurar"/>
        </StackPanel>
      </StackPanel>

      <ListBox Grid.Row="1" x:Name="List" Background="Transparent" BorderThickness="0" Margin="20,0,20,0"
               ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.IsVirtualizingWhenGrouping="True"
               VirtualizingPanel.ScrollUnit="Pixel">
        <ListBox.GroupStyle>
          <GroupStyle>
            <GroupStyle.HeaderTemplate>
              <DataTemplate>
                <TextBlock Text="{Binding Name}" Foreground="#BEACFF" FontSize="12" FontWeight="SemiBold" Margin="10,18,0,8"/>
              </DataTemplate>
            </GroupStyle.HeaderTemplate>
          </GroupStyle>
        </ListBox.GroupStyle>
        <ListBox.ItemContainerStyle>
          <Style TargetType="ListBoxItem">
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ListBoxItem">
                  <Border x:Name="card" Background="#18181F" CornerRadius="10" Padding="14,11" Margin="8,3" BorderThickness="1" BorderBrush="Transparent">
                    <ContentPresenter/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="card" Property="Background" Value="#1F1F28"/></Trigger>
                    <DataTrigger Binding="{Binding Checked}" Value="True"><Setter TargetName="card" Property="BorderBrush" Value="#4B3F7A"/></DataTrigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
        </ListBox.ItemContainerStyle>
        <ListBox.ItemTemplate>
          <DataTemplate>
            <DockPanel>
              <CheckBox DockPanel.Dock="Left" Style="{StaticResource Check}" IsChecked="{Binding Checked, Mode=TwoWay}" VerticalAlignment="Center" Margin="0,0,14,0"/>
              <Border DockPanel.Dock="Left" Width="40" Height="40" CornerRadius="10" Background="#2A2440" Margin="0,0,14,0" VerticalAlignment="Center">
                <Grid>
                  <TextBlock x:Name="ini" Text="{Binding Initials}" Foreground="#BEACFF" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  <TextBlock x:Name="gly" Text="{Binding Glyph}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" Foreground="#BEACFF" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
                  <Border x:Name="pic" Width="30" Height="30" CornerRadius="7" Background="#F2F2F5" Visibility="Collapsed">
                    <Image Source="{Binding Image}" Width="22" Height="22" RenderOptions.BitmapScalingMode="HighQuality" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                </Grid>
              </Border>
              <Border DockPanel.Dock="Right" x:Name="badge" CornerRadius="10" Padding="10,3" VerticalAlignment="Center" Background="Transparent">
                <TextBlock x:Name="badgeText" Text="{Binding Status}" FontSize="12" Foreground="#8C8C96"/>
              </Border>
              <StackPanel VerticalAlignment="Center">
                <TextBlock Text="{Binding Name}" FontSize="14" FontWeight="SemiBold" Foreground="#ECECF0"/>
                <TextBlock Text="{Binding Desc}" Foreground="#8C8C96" TextWrapping="Wrap" Margin="0,2,0,0"/>
                <TextBlock Text="{Binding Configuration}" Foreground="#BEACFF" TextWrapping="Wrap" FontSize="11" Margin="0,3,0,0"/>
              </StackPanel>
            </DockPanel>
            <DataTemplate.Triggers>
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
                <Setter TargetName="badge" Property="Background" Value="#2A2440"/>
                <Setter TargetName="badgeText" Property="Foreground" Value="#BEACFF"/>
              </DataTrigger>
            </DataTemplate.Triggers>
          </DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>

      <!-- Barra inferior -->
      <Border Grid.Row="2" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0">
        <StackPanel Margin="28,14,28,16">
          <WrapPanel Margin="0,0,0,10">
            <Button x:Name="BtnOpen" Style="{StaticResource Btn}" Content="Abrir aplicación" IsEnabled="False" Margin="0,0,8,0"/>
            <Button x:Name="BtnConfigured" Style="{StaticResource Btn}" Content="Confirmar configuración" IsEnabled="False"/>
            <TextBlock Text="Selecciona una app de la lista" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="12,0,0,0"/>
          </WrapPanel>
          <Expander x:Name="LogExpander" Header="Actividad de instalación" IsExpanded="True" Foreground="{StaticResource Muted}" Margin="0,0,0,10">
            <TextBox x:Name="Log" Height="120" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                     Background="#0F0F14" Foreground="#A0A0AA" BorderBrush="{StaticResource Line}" FontFamily="Segoe UI" FontSize="12" Margin="0,8,0,0" Padding="8"/>
          </Expander>
          <TextBlock x:Name="StatusText" Text="Elige las aplicaciones. Los accesos del escritorio se agrupan al terminar." Foreground="{StaticResource Muted}" TextWrapping="Wrap"/>
          <ProgressBar x:Name="Bar" Height="6" Margin="0,10,0,14" Background="#24242C" Foreground="#BEACFF" BorderThickness="0"/>
          <WrapPanel HorizontalAlignment="Right">
            <Button x:Name="BtnExport" Style="{StaticResource Btn}" Content="Exportar diagnóstico" Margin="0,0,8,0"/>
            <Button x:Name="BtnUpdate" Style="{StaticResource Btn}" Content="Actualizar todo" Margin="0,0,8,0"/>
            <Button x:Name="BtnVerify" Style="{StaticResource Btn}" Content="Verificar" Margin="0,0,8,0"/>
            <Button x:Name="BtnInstall" Style="{StaticResource Primary}" Content="Instalar" MinWidth="160"/>
          </WrapPanel>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

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

$win.Title = "iWinInstaller $Version"
$ui.VersionText.Text = "$Version · Windows 10/11"
$iconPng = Join-Path $Root 'assets\icon-128.png'
if (Test-Path $iconPng) { $ui.Logo.Source = New-Object Windows.Media.Imaging.BitmapImage ([Uri]$iconPng) }
$iconIco = Join-Path $Root 'assets\icon.ico'
if (Test-Path $iconIco) { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconIco) }
$win.Add_SourceInitialized({ try { [IwinDwm]::Dark((New-Object Windows.Interop.WindowInteropHelper $win).Handle) } catch { } })

# Registro: la ventana sustituye al TextBox de WinForms; Write-Log solo necesita AppendText
$log = $ui.Log
function Set-Status($text) { $ui.StatusText.Text = $text; Invoke-UiPump }

# Estado manual de configuracion: solo IDs y booleanos, sin credenciales.
$ConfigFile = Join-Path $LogDir 'configuracion.json'
$ConfiguredApps = @{}
if (Test-Path $ConfigFile) {
    try {
        $saved = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $saved.PSObject.Properties) { if ($property.Value -is [bool]) { $ConfiguredApps[$property.Name] = $property.Value } }
    } catch { Write-Log 'No se pudo leer el seguimiento de configuracion anterior.' }
}
# ---- Catálogo ----
$items = New-Object 'System.Collections.ObjectModel.ObservableCollection[IwinApp]'
$byId = @{}
foreach ($app in $Apps) {
    $it = New-Object IwinApp
    $it.Id = $app.id; $it.Name = $app.name; $it.Desc = $app.desc; $it.Group = $app.group
    $words = @($app.name -split '[\s\.\-]+' | Where-Object { $_ -match '^[\p{L}\d]' })
    $it.Initials = if ($words.Count -ge 2) { ($words[0].Substring(0, 1) + $words[1].Substring(0, 1)).ToUpper() } else { $app.name.Substring(0, [Math]::Min(2, $app.name.Length)) }
    $it.IconSpec = $app.icon
    if ("$($app.icon)" -match '^glyph:([0-9A-Fa-f]{4})$') { $it.Glyph = [string][char][Convert]::ToInt32($Matches[1], 16) }
    $it.NeedsConfiguration = [bool]$app.configure
    $it.Configured = [bool]$ConfiguredApps[$app.id]
    $it.Optional = Test-Optional $app
    $it.Search = "$($app.name) $($app.desc) $($app.group)".ToLower()
    $it.Checked = -not $it.Optional
    $items.Add($it); $byId[$app.id] = $it
}
$view = [Windows.Data.CollectionViewSource]::GetDefaultView($items)
$view.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'Group'))
$ui.List.ItemsSource = $view

$navAll = 'Todas las apps'
function Update-Nav {
    $sel = if ($ui.Nav.SelectedItem) { $ui.Nav.SelectedItem.Name } else { $navAll }
    $groups = @($Apps | ForEach-Object group | Select-Object -Unique)
    $rows = @([pscustomobject]@{ Name = $navAll; Count = "$(@($items | Where-Object Installed).Count)/$($items.Count)" })
    foreach ($g in $groups) {
        $gi = @($items | Where-Object Group -eq $g)
        $rows += [pscustomobject]@{ Name = $g; Count = "$(@($gi | Where-Object Installed).Count)/$($gi.Count)" }
    }
    $ui.Nav.ItemsSource = $rows
    $ui.Nav.SelectedItem = $rows | Where-Object Name -eq $sel | Select-Object -First 1
}
Update-Nav
$ui.Nav.SelectedIndex = 0

$view.Filter = [Predicate[object]]{
    param($o)
    $q = $ui.Search.Text.Trim().ToLower()
    $g = if ($ui.Nav.SelectedItem) { $ui.Nav.SelectedItem.Name } else { $navAll }
    if ($g -ne $navAll -and $o.Group -ne $g) { return $false }
    if ($q -and -not $o.Search.Contains($q)) { return $false }
    if ($ui.FChecked.IsChecked -and -not $o.Checked) { return $false }
    if ($ui.FMissing.IsChecked -and $o.Installed) { return $false }
    if ($ui.FInstalled.IsChecked -and -not $o.Installed) { return $false }
    if ($ui.FConfigure.IsChecked -and (-not $o.Installed -or -not $o.NeedsConfiguration -or $o.Configured)) { return $false }
    $true
}
function Update-Filter { $view.Refresh() }
function Update-Count {
    $n = @($items | Where-Object Checked).Count
    $ui.BtnInstall.Content = if ($n) { "Instalar $n seleccionada$(if ($n -ne 1) { 's' })" } else { 'Nada seleccionado' }
    $ui.BtnInstall.IsEnabled = $n -gt 0 -and -not $script:Busy
}
foreach ($it in $items) { $it.add_PropertyChanged({ param($s, $e) if ($e.PropertyName -eq 'Checked') { Update-Count } }) }
Update-Count

$ui.Search.Add_TextChanged({ $ui.SearchHint.Visibility = if ($ui.Search.Text) { 'Collapsed' } else { 'Visible' }; Update-Filter })
foreach ($f in 'FAll', 'FChecked', 'FMissing', 'FInstalled', 'FConfigure') { $ui[$f].Add_Checked({ Update-Filter }) }
$ui.Nav.Add_SelectionChanged({
    if ($ui.Nav.SelectedItem) { $ui.Heading.Text = $ui.Nav.SelectedItem.Name }
    Update-Filter
})
$ui.SelectVisible.Add_Click({ foreach ($o in $view) { if (-not $o.Installed) { $o.Checked = $true } } })
$ui.ClearVisible.Add_Click({ foreach ($o in $view) { $o.Checked = $false } })

# ---- Perfiles ----
$Profiles.PSObject.Properties.Name | ForEach-Object { [void]$ui.Profile.Items.Add($_) }
$ui.Profile.SelectedItem = 'Todo'
$ui.Profile.Add_SelectionChanged({
    $ids = @(Get-ProfileApps $ui.Profile.SelectedItem | ForEach-Object id)
    foreach ($it in $items) { $it.Checked = ($ids -contains $it.Id) -and -not $it.Installed }
})

$ui.LogLink.Add_Click({ if (Test-Path $LogFile) { Start-Process notepad.exe $LogFile } else { Start-Process $LogDir } })
$ui.IgLink.Add_Click({ Start-Process $Instagram })
function Update-ConfigurationActions {
    $selected = $ui.List.SelectedItem
    $ui.BtnOpen.IsEnabled = [bool]($selected -and $selected.Installed -and -not $script:Busy)
    $ui.BtnConfigured.IsEnabled = [bool]($selected -and $selected.Installed -and $selected.NeedsConfiguration -and -not $script:Busy)
    $ui.BtnConfigured.Content = if ($selected -and $selected.Configured) { 'Marcar pendiente' } else { 'Confirmar configuración' }
}
$ui.List.Add_SelectionChanged({ Update-ConfigurationActions })
$ui.BtnExport.Add_Click({
    try { $report = Export-Diagnostic; Set-Status "Diagnóstico guardado en Descargas: $([IO.Path]::GetFileName($report))"; Start-Process explorer.exe -ArgumentList ('/select,"' + $report + '"') }
    catch { Write-Log "No se pudo exportar: $($_.Exception.Message)"; Set-Status 'No se pudo guardar el diagnóstico. Consulta el registro.' }
})
$ui.BtnConfigured.Add_Click({
    $selected = $ui.List.SelectedItem
    if (-not $selected -or -not $selected.Installed) { return }
    $selected.Configured = -not $selected.Configured
    $ConfiguredApps[$selected.Id] = $selected.Configured
    $temporary = $ConfigFile + '.tmp'
    $ConfiguredApps | ConvertTo-Json | Set-Content $temporary -Encoding UTF8
    Move-Item $temporary $ConfigFile -Force
    Update-ConfigurationActions; Update-Filter
})
$ui.BtnOpen.Add_Click({
    $selected = $ui.List.SelectedItem
    if (-not $selected) { return }
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.NameSpace('shell:AppsFolder')
        $matches = @($folder.Items() | Where-Object { $_.Name -eq $selected.Name })
        if ($matches.Count -eq 1) { $matches[0].InvokeVerb() }
        else { Start-Process explorer.exe 'shell:AppsFolder'; Set-Status "Elige $($selected.Name) en la lista de aplicaciones." }
    } catch { Write-Log "No se pudo abrir $($selected.Name): $($_.Exception.Message)" }
})


function Set-Busy($busy) {
    $script:Busy = $busy
    Update-ConfigurationActions
    foreach ($b in 'BtnInstall', 'BtnVerify', 'BtnUpdate', 'Profile') { $ui[$b].IsEnabled = -not $busy }
    $win.Cursor = if ($busy) { [Windows.Input.Cursors]::AppStarting } else { $null }
    if (-not $busy) { Update-Count }
}

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
    if (-not $Quiet) { Write-Log "Verificación: $msg" }
    Set-Status $msg
    Update-Nav; Update-Filter
    Set-Busy $false
}

$ui.BtnVerify.Add_Click({ Invoke-Verify })
$ui.BtnUpdate.Add_Click({
    Set-Busy $true; $ui.LogExpander.IsExpanded = $true
    Set-Status 'Actualizando aplicaciones…'
    $ok = Invoke-Update
    Set-Status $(if ($ok) { 'Actualización terminada.' } else { 'Actualización incompleta. Consulta el registro.' })
    Set-Busy $false
})
$ui.BtnInstall.Add_Click({
    if ($script:Busy) { return }
    $sel = @($Apps | Where-Object { $byId[$_.id].Checked })
    if (-not $sel) { return }
    Set-Busy $true; $ui.LogExpander.IsExpanded = $true
    $ui.Bar.Maximum = $sel.Count; $ui.Bar.Value = 0
    foreach ($a in $sel) { $byId[$a.id].Status = 'En cola'; $byId[$a.id].StatusKind = 'busy' }
    $fail = @(Invoke-Install $sel {
        param($a, $ok)
        $it = $byId[$a.id]
        if ($ok) { $it.Status = 'Instalada'; $it.StatusKind = 'ok'; $it.Installed = $true; $it.Checked = $false }
        else { $it.Status = 'Falló'; $it.StatusKind = 'bad'; $it.Checked = $true }
        if ($ui.Bar.Value -ge $ui.Bar.Maximum) { $ui.Bar.Maximum++ }
        $ui.Bar.Value++
        Set-Status "$($a.name) · $(if ($ok) {'Completada'} else {'Falló'}) · $($ui.Bar.Value)/$($ui.Bar.Maximum)"
    })
    # Quedan marcadas solo las que fallaron: pulsar otra vez reintenta solo esas
    Set-Status $(if ($fail) { "Terminado con $($fail.Count) fallo(s): siguen marcadas para reintentar." } else { 'Instalación terminada. Revisa «Por configurar» para completar tus sesiones.' })
    Update-Nav
    Set-Busy $false
})

# Iconos en segundo plano (la lista no espera a internet; sin red quedan las iniciales)
$IconDir = Join-Path $LogDir 'iconos'
try { [IwinIcons]::Start($items, $IconDir, $win.Dispatcher) } catch { }

# Al abrirse, comprueba lo instalado sin que haya que pulsar nada
$win.Add_ContentRendered({
    if ([Windows.SystemParameters]::ClientAreaAnimation) {
        $animation = New-Object Windows.Media.Animation.DoubleAnimation(0, 1, [TimeSpan]::FromMilliseconds(180))
        $win.BeginAnimation([Windows.UIElement]::OpacityProperty, $animation)
    }
    Invoke-Verify -Quiet
})

# Prueba automática (GitHub Actions): construye la ventana y sale sin mostrarla
if ($env:IWIN_PRUEBA_GUI) {
    # Muestra y despacha eventos reales: construir XAML no ejecuta el arranque de la ventana.
    $win.Show()
    for ($pass=0; $pass -lt 10; $pass++) { Invoke-UiPump; Start-Sleep -Milliseconds 100 }
    foreach ($profileName in @('Base','Gaming','Todo')) { $ui.Profile.SelectedItem=$profileName; Invoke-UiPump }
    Set-Busy $true
    $probe=$items | Select-Object -First 1
    $probe.Checked=-not $probe.Checked
    if ($ui.BtnInstall.IsEnabled) { throw 'No se puede iniciar otro lote mientras la app esta ocupada.' }
    Set-Busy $false

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
