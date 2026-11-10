# iWinInstaller — motor: Ajustes, actualización de la app e instalación de cada app.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

function Install-Tweak($id) {
    try {
        $ErrorActionPreference = 'Stop'
        Save-TweakSnapshot $id
        switch ($id) {
            'braveclean' { return (Set-BraveClean) }
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
            'nobing' { Set-PolicyDwords $SearchPolicy @{ DisableSearchBoxSuggestions = 1 }; Write-Log '  Se aplica al reiniciar la sesión.'; return $true }
            'taskbarleft' { Set-RegDword $ExplorerAdv 'TaskbarAl' 0; return $true }
            'clockseconds' { Set-RegDword $ExplorerAdv 'ShowSecondsInSystemClock' 1; return $true }
            'thispc' { Set-RegDword $ExplorerAdv 'LaunchTo' 1; return $true }
            'endtask' { Set-RegDword $DevSettings 'TaskbarEndTask' 1; return $true }
            'remotehost' { return (Set-RemoteHost) }
            'remotessh' { return (Set-RemoteSsh) }
            'virtualdisplayon' { return (Set-VirtualDisplay) }
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
        'braveclean' { return (Test-BraveClean) }
        'wsl' {
            if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
            & wsl.exe --status 2>&1 | Out-Null
            return ($LASTEXITCODE -eq 0)
        }
        # Se crea en cada instalación; nunca cuenta como hecho de antemano
        'restorepoint' { return $false }
        'showext' { return ((Get-RegValue $ExplorerAdv 'HideFileExt') -eq 0) }
        'showhidden' { return ((Get-RegValue $ExplorerAdv 'Hidden') -eq 1) }
        'darkmode' { return ((Get-RegValue $Personalize 'AppsUseLightTheme') -eq 0 -and (Get-RegValue $Personalize 'SystemUsesLightTheme') -eq 0) }
        'power' { return ((& powercfg /getactivescheme 2>$null | Out-String) -match $HighPerf) }
        'devmode' { return ((Get-RegValue $AppModelUnlock 'AllowDevelopmentWithoutDevLicense') -eq 1) }
        'longpaths' { return ((Get-RegValue $FileSystemKey 'LongPathsEnabled') -eq 1) }
        'classicmenu' { return (Test-Path "$ClassicMenu\InprocServer32") }
        'nobing' { return ((Get-RegValue $SearchPolicy 'DisableSearchBoxSuggestions') -eq 1) }
        'taskbarleft' { return ((Get-RegValue $ExplorerAdv 'TaskbarAl') -eq 0) }
        'clockseconds' { return ((Get-RegValue $ExplorerAdv 'ShowSecondsInSystemClock') -eq 1) }
        'thispc' { return ((Get-RegValue $ExplorerAdv 'LaunchTo') -eq 1) }
        'endtask' { return ((Get-RegValue $DevSettings 'TaskbarEndTask') -eq 1) }
        'mouseaccel' { return ((Get-RegValue $MouseKey 'MouseSpeed') -eq '0' -and (Get-RegValue $MouseKey 'MouseThreshold1') -eq '0' -and (Get-RegValue $MouseKey 'MouseThreshold2') -eq '0') }
        'remotehost' { return (Test-RemoteHost) }
        'remotessh' { return (Test-RemoteSsh) }
        'virtualdisplayon' { return (Test-VirtualDisplay) }
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
                    # GitHub responde a veces 502/504: hasta tres intentos (una pausa cancela)
                    for ($attempt = 1; ; $attempt++) {
                        try { [void](Invoke-IwinWebTransfer $asset.browser_download_url $download 600); break }
                        catch { if ($attempt -ge 3 -or (Test-IwinStop)) { throw }; Write-Log "  Descarga fallida; reintento $attempt."; Start-Sleep -Seconds (10 * $attempt) }
                    }
                    if((Get-FileHash $download).Hash -ne $expected){throw 'La actualización no supera la comprobación SHA256.'}
                    Move-Item $download $setup -Force -ErrorAction Stop
                }finally{Remove-Item $download -Force -ErrorAction SilentlyContinue}
            }
            foreach($running in @(Get-Process -Name iWinInstaller-Setup -ErrorAction SilentlyContinue)){try{if($running.Path -eq $setup){Write-Log '  La nueva versión ya está preparada para aplicarse al cerrar.';return $true}}catch{}}
            $p=Start-Process $setup -ArgumentList '--silent' -PassThru
            $null=$p.Handle
            if (($UI -or $AutoUpdate) -and $env:IWIN_HOST_PID -match '^\d+$') {
                Write-Log '  Versión verificada. Se aplica cuando cierre iWinInstaller; conserva notas, perfiles y lotes.'
                return $true
            }
        } else {
            $p=Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Root 'install.ps1')`" -Silent"
            $null=$p.Handle
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
    # Las apps excluidas en Actualizaciones (v4.5) se mantienen en su versión
    $excluded = @(Get-IwinExclusions)
    $kept = @($installed | Where-Object { @($_.winget | Where-Object { $excluded -contains $_ }).Count })
    if ($kept) { Write-Log "  Se mantienen en su versión (excluidas): $(($kept | ForEach-Object name) -join ', ')" }
    $installed = @($installed | Where-Object { $kept -notcontains $_ })
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
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
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
