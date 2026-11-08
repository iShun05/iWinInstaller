# iWinInstaller — motor: Registro, espera de procesos, WinGet incluido y elevación.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

# ---------- Utilidades comunes ----------
$log = $null
function Write-Log($msg) {
    $line = "$(Get-Date -Format HH:mm:ss)  $msg"
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
    $detail = $msg -match '^    '
    if ($WorkerMode -and $ResultFile -and -not $detail) { Write-WorkerEvent @{message=[string]$msg} }
    if ($detail) { return }
    if ($log) { $log.AppendText("$line`r`n"); $log.ScrollToEnd(); Invoke-UiPump }
    elseif ($Check -or $Updates -or $Status) { if (-not $Json) { Write-Host $msg } }  # con -Json la salida estándar es solo el documento
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
        $null = $p.Handle
        Wait-Proc $p
        return ($p.HasExited -and $p.ExitCode -eq 0)
    } catch {
        Write-Log '  Permiso de administrador denegado.'
        return $false
    }
}
