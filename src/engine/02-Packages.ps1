# iWinInstaller — motor: Argumentos de WinGet, inventario, instalación de paquetes y proceso de trabajo.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

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
    # Kits portátiles sin entrada en Programas (p. ej. Emsisoft Emergency Kit en C:\EEK).
    foreach ($path in @($app.detectPaths)) {
        if ($path -and (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables([string]$path)))) { return $true }
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
    # Algunos fabricantes solo publican un asistente sin modo silencioso: se muestra y se espera a que lo completes.
    $mode = if ($app.interactive) { '--interactive' } else { '--silent' }
    $timeout = if ($app.interactive) { 3600 } else { 900 }
    if ($app.interactive) { Write-Log "  Se abrirá el asistente de $($app.name): complétalo para continuar." }
    $arguments = @($operation, '-e', '--id', $id, '--source', $source, $mode, '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')
    if ($app.scope) { $arguments += @('--scope', $app.scope) }
    if ($app.architecture) { $arguments += @('--architecture', $app.architecture) }
    $code = Invoke-Winget $arguments $app.id $timeout
    # Errores de red puntuales (0x80072EFD, 0x80072EE2, 0x80072EFE…): un reintento tras una pausa breve
    if ($code -in @(-2147012867, -2147012894, -2147012866, -2147012889)) {
        Write-Log '  Fallo de conexión al descargar: se reintenta una vez en 15 s.'
        for ($wait = 0; $wait -lt 75 -and -not (Test-IwinStop); $wait++) { Invoke-UiPump; Start-Sleep -Milliseconds 200 }
        if (-not (Test-IwinStop)) { $code = Invoke-Winget $arguments ($app.id + '-reintento') $timeout }
    }
    $usedMsix = $false
    # 0x80070005: el MSI no pudo escribir (antivirus, carpeta protegida o proceso abierto).
    # 0x8A150113: «la configuración del sistema no admite» ese instalador. En ambos casos el paquete MSIX oficial suele funcionar.
    if ($code -in @(-2147024891, -1978334957) -and $app.families -and $operation -eq 'install') {
        Write-Log '  El instalador clasico no se pudo usar: se prueba el paquete MSIX oficial.'
        $retry = @($arguments | Where-Object { $_ -ne '--scope' -and $_ -ne $app.scope }) + @('--installer-type', 'msix')
        $code = Invoke-Winget $retry ($app.id + '-msix')
        $usedMsix = $true
    }
    if ($code -notin $wingetOk) { return $false }
    if (Test-IwinRebootCode $code) { Write-Log '  Requiere reiniciar Windows y volver a verificar.'; return $true }
    # Un paquete MSIX solo aparece en el inventario de Appx: se relee también en ese caso.
    Update-LocalInventory -Appx:((Get-InstallContext $app) -eq 'user' -or $usedMsix)
    # El codigo de exito no basta: debe aparecer en el inventario o en winget list.
    if ($app.type -ne 'wingetall' -and (Test-LocalApp $app)) { $script:WingetIds += $id; return $true }
    if ($app.architecture -and $app.families) { Write-Log '  No se confirma la arquitectura requerida del paquete.'; return $false }
    $check = Invoke-Winget @('list', '-e', '--id', $id, '--source', $source, '--disable-interactivity', '--accept-source-agreements') ($app.id + '-verificar') 45
    if ($check -eq 0) { $script:WingetIds += $id; return $true }
    return $false
}

function Write-WorkerEvent($event) {
    # La ventana principal lee este archivo cada 250 ms: un evento perdido marcaba como fallida una app instalada.
    $line = ($event | ConvertTo-Json -Compress) + "`r`n"
    for ($attempt = 1; ; $attempt++) {
        try { $stream = [IO.File]::Open($ResultFile, 'Append', 'Write', 'ReadWrite'); try { $bytes = [Text.Encoding]::UTF8.GetBytes($line); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }; return }
        catch { if ($attempt -ge 40) { throw }; Start-Sleep -Milliseconds 50 }
    }
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
    if (@($selection | Where-Object { -not $reported.ContainsKey($_.id) }).Count) { Update-LocalInventory -Appx; $script:WingetIds = $null }
    foreach ($app in $selection) {
        if (-not $reported.ContainsKey($app.id)) {
            $present = $false
            if (-not $Remove) { try { $present = [bool](Test-AppInstalled $app) } catch {} }
            if ($present) { Write-Log "  Comprobado en el equipo: $($app.name)"; $script:LastInstallCode=0; Complete-IwinItem $app $true $onProgress; continue }
            $script:LastInstallCode=0; Complete-IwinItem $app $false $onProgress; $app
        }
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
    # El resumen de fallos va primero: se lee sin recorrer todo el registro.
    $lastReport = if ($script:LastReport) { $script:LastReport } else { try { Get-IwinLastReport } catch { $null } }
    if ($lastReport) { $header += (Format-IwinReportText $lastReport) + "`r`n`r`n=== REGISTRO COMPLETO ===`r`n" }
    $text = $header + $body
    if ($env:USERPROFILE) { $text = $text.Replace($env:USERPROFILE, '%USERPROFILE%') }
    $text = $text -replace '(?i)(https?://)[^/\s@]+@', '$1[OCULTO]@'
    $text = $text -replace 'gh[pousr]_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]+', '[SECRETO OCULTO]'
    $text = $text -replace '(?i)(Authorization\s*:\s*(?:Bearer|token)\s+)\S+', '$1[OCULTO]' -replace '(?i)([?&](?:token|access_token|key|signature|sig)=)[^&\s]+', '$1[OCULTO]'
    $text = $text -replace '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[CORREO OCULTO]'
    [IO.File]::WriteAllText($destination, $text, [Text.Encoding]::UTF8)
    return $destination
}
