# iWinInstaller — motor: instalar, desinstalar, perfiles y pasos de después de instalar para la interfaz nueva.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

# Archivo de pausa de la operación en curso: la interfaz lo crea junto al Request y el lote para
# al terminar la aplicación actual (nunca a mitad de un instalador).
function Get-IwinEngineCancelFile {
    if ($EngineRequest) { return (Join-Path (Split-Path -Parent $EngineRequest) 'cancel') }
    $null
}

# Estado manual de configuración (configuracion.json): solo ids y booleanos
function Get-IwinConfiguredApps {
    $path = Join-Path $LogDir 'configuracion.json'
    $configured = @{}
    if (Test-Path $path) {
        try {
            $saved = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($property in $saved.PSObject.Properties) { if ($property.Value -is [bool]) { $configured[$property.Name] = $property.Value } }
        } catch { Write-Log 'No se pudo leer el seguimiento de configuración anterior.' }
    }
    $configured
}

function ConvertTo-IwinPlanItem($app) {
    [ordered]@{
        id = $app.id
        name = $app.name
        context = $(if ((Get-InstallContext $app) -eq 'machine') { 'machine' } else { 'user' })
        tweak = $app.type -eq 'tweak'
        restart = [bool]$app.restart
        interactive = [bool]$app.interactive
    }
}

function Get-IwinSelection([string[]]$ids) {
    $wanted = @($ids | Where-Object { $_ } | Select-Object -Unique)
    $selection = @($Apps | Where-Object { $wanted -contains $_.id })
    $unknown = @($wanted | Where-Object { $_ -notin $selection.id })
    if ($unknown) { throw [ArgumentException]"Ids desconocidos: $($unknown -join ', ')" }
    $selection
}

Register-IwinEngineCommand 'install.preflight' {
    param($request)
    $operation = if ($request.operation) { [string]$request.operation } else { 'install' }
    if ($operation -notin @('install', 'uninstall', 'upgrade')) { throw [ArgumentException]"Operación no válida: $operation" }
    $selection = Get-IwinSelection @($request.ids)
    $plan = if ($operation -eq 'uninstall') { $selection } else { @(Get-InstallPlan $selection) }
    $preflight = if ($operation -eq 'uninstall') { [pscustomobject]@{ Ok = $true; Text = 'Se usará el desinstalador oficial o el estado anterior guardado.' } } else { Get-IwinPreflight $plan }
    @{ ok = [bool]$preflight.Ok; text = [string]$preflight.Text; plan = @($plan | ForEach-Object { ConvertTo-IwinPlanItem $_ }) }
}

# Ejecuta un lote completo. Emite un evento «item» por aplicación con su resultado y su estado nuevo.
Register-IwinEngineCommand 'batch.run' {
    param($request)
    $operation = if ($request.operation) { [string]$request.operation } else { 'install' }
    if ($operation -notin @('install', 'uninstall', 'upgrade')) { throw [ArgumentException]"Operación no válida: $operation" }
    $script:EngineCancelFile = Get-IwinEngineCancelFile
    $script:StopRequested = $false
    $removing = $operation -eq 'uninstall'
    $progress = {
        param($app, $ok)
        $reboot = (Test-IwinRebootCode $script:LastInstallCode) -or ($ok -and [bool]$app.restart)
        $installed = if ($removing) { [bool](Test-AppInstalled $app) } else { [bool]$ok }
        $outcome = if ($ok) { if ($reboot) { 'rebootRequired' } else { 'success' } } elseif (Test-IwinStop) { 'pending' } else { 'failed' }
        Write-IwinEngineEvent @{ type = 'item'; id = $app.id; outcome = $outcome; installed = $installed; previousState = [bool](Test-IwinPreviousState $app); code = $script:LastInstallCode }
    }
    if (-not $removing -and -not (Ensure-Winget)) { throw 'WinGet no está disponible.' }
    $script:LastReport = $null
    $fail = @()
    if ($request.resume) {
        $pending = @(Get-IwinPendingBatches | Where-Object { $_.Path -eq [string]$request.resume }) | Select-Object -First 1
        if (-not $pending) { throw [ArgumentException]'Ese lote ya no está pendiente.' }
        $fail = @(Resume-IwinBatch $pending $progress)
    } else {
        $selection = Get-IwinSelection @($request.ids)
        if (-not $selection) { throw [ArgumentException]'No hay aplicaciones seleccionadas.' }
        $previous = $UpgradePackages
        $script:UpgradePackages = $operation -eq 'upgrade'
        try { $fail = if ($removing) { @(Invoke-Uninstall $selection $progress) } else { @(Invoke-Install $selection $progress) } }
        finally { $script:UpgradePackages = $previous }
    }
    @{
        failed = @($fail | Where-Object { $_ -and $_.id } | ForEach-Object id | Select-Object -Unique)
        paused = [bool](Test-IwinStop)
        rebootPending = @(Get-IwinRebootPending)
        hasReport = [bool]($script:LastReport -and @($script:LastReport.items).Count)
    }
}

# ---------- Perfiles ----------
Register-IwinEngineCommand 'profiles.list' {
    param($request)
    @{ builtIn = @($Profiles.PSObject.Properties.Name); custom = @((Get-CustomProfiles).Keys | Sort-Object) }
}

Register-IwinEngineCommand 'profiles.resolve' {
    param($request)
    $name = [string]$request.name
    if (-not $name) { throw [ArgumentException]'Falta el nombre del perfil.' }
    $custom = Get-CustomProfiles
    $ids = if ($request.custom -and $custom.ContainsKey($name)) { @((Read-ProfileFile $custom[$name]).Apps) } else { @(Get-ProfileApps $name | ForEach-Object id) }
    @{ ids = @($ids) }
}

Register-IwinEngineCommand 'profiles.save' {
    param($request)
    $name = Get-SafeProfileName ([string]$request.name)
    if (-not $name) { throw [ArgumentException]'El nombre del perfil no es válido.' }
    $ids = @(Get-IwinSelection @($request.ids) | ForEach-Object id)
    New-Item $ProfileDir -ItemType Directory -Force | Out-Null
    Write-ProfileFile (Get-CustomProfilePath $name) $name $ids
    @{ name = $name; count = $ids.Count }
}

Register-IwinEngineCommand 'profiles.delete' {
    param($request)
    $name = Get-SafeProfileName ([string]$request.name)
    if (-not $name -or -not (Get-CustomProfiles).ContainsKey($name)) { throw [ArgumentException]'Ese perfil no existe.' }
    Remove-Item -LiteralPath (Get-CustomProfilePath $name) -Force
    @{ name = $name }
}

Register-IwinEngineCommand 'profiles.import' {
    param($request)
    $path = [string]$request.path
    if (-not (Test-Path -LiteralPath $path)) { throw [ArgumentException]'No existe ese archivo.' }
    $profile = Read-ProfileFile $path
    $known = @($Apps.id)
    @{ name = [string]$profile.Name; ids = @($profile.Apps | Where-Object { $known -contains $_ }) }
}

Register-IwinEngineCommand 'profiles.export' {
    param($request)
    $path = [string]$request.path
    if (-not $path) { throw [ArgumentException]'Falta la ruta.' }
    $ids = @(Get-IwinSelection @($request.ids) | ForEach-Object id)
    Write-ProfileFile $path ([string]$request.name) $ids
    @{ path = $path; count = $ids.Count }
}

# ---------- Después de instalar ----------
Register-IwinEngineCommand 'postinstall.get' {
    param($request)
    $state = try { Get-PostInstallState } catch { throw 'El seguimiento de pasos está dañado; no se modifica para no perder tus notas.' }
    $configured = Get-IwinConfiguredApps
    $wanted = @($request.ids | Where-Object { $_ })
    $guides = foreach ($app in $Apps) {
        if (-not ($app.postInstall -or $app.configure)) { continue }
        if ($wanted -and $wanted -notcontains $app.id) { continue }
        $guide = Get-PostInstallGuide $app
        $entry = $state[$app.id]
        $count = @($guide.steps).Count
        $done = @($entry.steps | Where-Object { $_ -ge 0 -and $_ -lt $count } | Select-Object -Unique)
        [ordered]@{
            id = $app.id; name = $app.name
            steps = @($guide.steps); note = [string]$guide.note; link = [string]$guide.link; linkLabel = [string]$guide.linkLabel
            done = @($done); userNote = [string]$entry.note
            configured = [bool]$(if ($state.ContainsKey($app.id)) { $done.Count -eq $count } else { $configured[$app.id] })
        }
    }
    @{ guides = @($guides); rebootPending = @(Get-IwinRebootPending) }
}

Register-IwinEngineCommand 'postinstall.set' {
    param($request)
    $app = @(Get-IwinSelection @([string]$request.id))[0]
    $script:PostInstallReadOnly = $false
    $script:PostInstallState = try { Get-PostInstallState } catch { $script:PostInstallReadOnly = $true; throw 'El seguimiento de pasos está dañado; no se modifica para no perder tus notas.' }
    $count = @((Get-PostInstallGuide $app).steps).Count
    $steps = @($request.steps | ForEach-Object { [int]$_ } | Where-Object { $_ -ge 0 -and $_ -lt $count } | Select-Object -Unique)
    $note = [string]$request.note
    if ($note.Length -gt 2000) { $note = $note.Substring(0, 2000) }
    $script:PostInstallState[$app.id] = @{ steps = @($steps); guideHash = (Get-IwinGuideHash $app); note = $note }
    Save-PostInstallState
    $configured = Get-IwinConfiguredApps
    $configured[$app.id] = $steps.Count -eq $count
    Write-IwinJson (Join-Path $LogDir 'configuracion.json') $configured
    @{ id = $app.id; configured = $configured[$app.id] }
}

Register-IwinEngineCommand 'postinstall.check' {
    param($request)
    $app = @(Get-IwinSelection @([string]$request.id))[0]
    $result = Test-PostInstall $app
    @{ id = $app.id; ok = [bool]$result.Ok; text = [string]$result.Text }
}

# ---------- Abrir una app instalada (misma lógica que la ventana clásica) ----------
Register-IwinEngineCommand 'app.open' {
    param($request)
    $app = @(Get-IwinSelection @([string]$request.id))[0]
    $console = $app.section -eq 'Terminal' -and -not $app.gui
    # Acceso del menú Inicio: nombre exacto o, si no, el más corto que empiece igual (p. ej. «7-Zip File Manager»)
    $shell = New-Object -ComObject Shell.Application
    $entries = @($shell.NameSpace('shell:AppsFolder').Items() | Where-Object { $_.Name -notmatch '(?i)uninstall|desinstal' })
    $found = @($entries | Where-Object { $_.Name -eq $app.name })
    if (-not $found -and -not $console) {
        $found = @($entries | Where-Object { $_.Name.StartsWith($app.name, [StringComparison]::OrdinalIgnoreCase) -or $app.name.StartsWith($_.Name + ' ', [StringComparison]::OrdinalIgnoreCase) } | Sort-Object { $_.Name.Length })
    }
    if ($found) { $found[0].InvokeVerb(); return @{ message = "Abriendo $($app.name)…" } }
    if ($console) {
        $cmd = @($app.commands)[0]
        $hint = if ($cmd) { "Escribe $cmd para usar $($app.name)." } else { "$($app.name) está disponible en esta terminal." }
        $script = "`$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User'); Write-Host '$($hint -replace "'", "''")' -ForegroundColor Cyan"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
        $shellExe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
        $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
        if ($wt) { Start-Process $wt.Source -ArgumentList @('new-tab', '--title', "`"$($app.name)`"", $shellExe, '-NoExit', '-EncodedCommand', $encoded) }
        else { Start-Process $shellExe -ArgumentList @('-NoExit', '-EncodedCommand', $encoded) }
        return @{ message = "Terminal abierta para $($app.name)." }
    }
    Start-Process explorer.exe 'shell:AppsFolder'
    @{ message = "Elige $($app.name) en la lista de aplicaciones." }
}
