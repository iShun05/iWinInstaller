# iWinInstaller — motor: Instalar, desinstalar y reanudar lotes.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

# Instala dependencias y apps antes de la configuracion; devuelve los fallos confirmados.
function Invoke-Install($sel, [scriptblock]$onProgress) {
    $sel = @(Get-InstallPlan $sel)
    if ($script:ResumingBatch -and $script:Batch) { $done=@($script:Batch.items | Where-Object state -eq 'done' | ForEach-Object id); $sel=@($sel | Where-Object { $done -notcontains $_.id }) }
    if (-not $WorkerMode -and -not $script:ResumingBatch) { Start-IwinBatch $sel $(if($UpgradePackages){'upgrade'}else{'install'}) }
    $script:LastInstallCode = 0
    # Punto de partida del informe final: resultados de esta pasada y registro desde aquí.
    $reportPlan = @($sel); $script:RunResults = @{}
    $reportOffset = 0; try { $reportOffset = Get-IwinLogLength } catch { }
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
    if (-not $WorkerMode -and $LogDir) {
        # Informe con el motivo de cada fallo: panel al terminar, portapapeles y cabecera del diagnóstico.
        try {
            $script:LastReport = New-IwinInstallReport $reportPlan $fail $reportOffset $(if ($UpgradePackages) { 'upgrade' } else { 'install' })
            Save-IwinInstallReport $script:LastReport
            if (@($script:LastReport.items).Count) {
                Write-Log "Informe: $(Get-IwinReportSummary $script:LastReport)"
                foreach ($item in @($script:LastReport.items)) { Write-Log "  ✗ $($item.name): $($item.reason)$(if ($item.codeText) { ' (código ' + $item.codeText + ')' })" }
            }
        } catch { $script:LastReport = $null; Write-Log "No se pudo preparar el informe: $($_.Exception.Message)" }
    }
    if ($fail) {
        Write-Log "Terminado con fallos en: $(($fail | ForEach-Object name | Select-Object -Unique) -join ', ')"
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
        try { $present = (Test-AppInstalled $app) -or (Test-IwinPreviousState $app) } catch { $present = $true }
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
