# iWinInstaller — motor: actualizaciones disponibles de WinGet (tarjeta del Inicio y, desde v4.5, su módulo).
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

# Convierte la tabla de «winget upgrade» en objetos. Las columnas se localizan por la posición de
# los títulos (que cambian con el idioma de Windows); el nombre puede contener espacios, el id no.
function ConvertFrom-WingetTable([string[]]$lines) {
    # La animación de progreso de winget escribe varios trozos separados por «\r»: vale el último
    $clean = @($lines | ForEach-Object { $parts = @($_ -split "`r" | Where-Object { $_.Trim() }); if ($parts) { $parts[-1] } else { '' } })
    $separator = -1
    for ($i = 1; $i -lt $clean.Count; $i++) { if ($clean[$i] -match '^-{10,}\s*$') { $separator = $i; break } }
    if ($separator -lt 1) { return @() }
    $header = $clean[$separator - 1]
    $starts = @([regex]::Matches($header, '\S+') | ForEach-Object Index)
    if ($starts.Count -lt 4) { return @() }
    foreach ($line in $clean[($separator + 1)..($clean.Count - 1)]) {
        if ($line.Length -le $starts[1] -or $line -match '^\s*$') { continue }
        # Las líneas de resumen («3 upgrades available.», «3 actualizaciones disponibles.») no tienen id
        $cells = for ($c = 0; $c -lt $starts.Count; $c++) {
            $from = $starts[$c]
            if ($from -ge $line.Length) { ''; continue }
            $to = if ($c + 1 -lt $starts.Count) { [Math]::Min($starts[$c + 1], $line.Length) } else { $line.Length }
            $line.Substring($from, $to - $from).Trim()
        }
        $cells = @($cells)
        if ($cells.Count -lt 4 -or $cells[1] -notmatch '^[A-Za-z0-9][\w.+-]*\.[\w.+-]+$|^9[A-Z0-9]{11}$|^XP[A-Z0-9]{10}$') { continue }
        if (-not $cells[3]) { continue }
        [pscustomobject]@{
            Name = $cells[0] -replace '…$', ''
            Id = $cells[1]
            Version = $cells[2]
            Available = $cells[3]
            Source = if ($cells.Count -gt 4) { $cells[4] } else { '' }
        }
    }
}

# Lista las actualizaciones que ofrece WinGet. Devuelve $null si no se pudo comprobar.
function Get-IwinAvailableUpdates([int]$timeoutSec = 180) {
    if (-not (Test-Cmd winget)) { return $null }
    $out = Join-Path $env:TEMP ('iwin_upgrade_' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $p = Start-Process winget -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -ArgumentList @('upgrade', '--accept-source-agreements', '--disable-interactivity')
        $null = $p.Handle
        if (-not $p.WaitForExit($timeoutSec * 1000)) { try { $p.Kill() } catch { }; return $null }
        if (-not (Test-Path $out)) { return $null }
        $lines = [IO.File]::ReadAllLines($out, [Text.Encoding]::UTF8)
        # Sin actualizaciones winget no imprime tabla: es un resultado válido (lista vacía).
        # La coma conserva la lista vacía: sin ella PowerShell devolvería $null («no se pudo comprobar»)
        return ,@(ConvertFrom-WingetTable $lines)
    } catch { $null }
    finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
}

# ---------- Exclusiones (v4.5): apps que el usuario mantiene en su versión actual ----------
$IwinExclusionsFormat = 'iWinInstaller-exclusiones'

function Get-IwinExclusionsPath { Join-Path $LogDir 'exclusiones.json' }

function Get-IwinExclusions {
    $path = Get-IwinExclusionsPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($data.format -ne $IwinExclusionsFormat) { return @() }
        @($data.items | ForEach-Object { [string]$_.id } | Where-Object { $_ -match '^[\w.+-]{1,200}$' } | Select-Object -Unique)
    } catch { Write-Log "  Exclusiones ilegibles: se ignoran ($($_.Exception.Message))."; @() }
}

# Añade o quita una exclusión por id de WinGet. Escritura atómica: un corte no deja el archivo a medias.
function Set-IwinExclusion([string]$id, [bool]$excluded) {
    if ($id -notmatch '^[\w.+-]{1,200}$') { throw [ArgumentException]"Id no válido: $id" }
    $path = Get-IwinExclusionsPath
    $current = @()
    if (Test-Path -LiteralPath $path) {
        try { $current = @((Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop).items) } catch { $current = @() }
    }
    $items = @($current | Where-Object { $_.id -and $_.id -ne $id } | ForEach-Object { [ordered]@{ id = [string]$_.id; since = [string]$_.since } })
    if ($excluded) { $items += [ordered]@{ id = $id; since = (Get-Date -Format 'yyyy-MM-dd') } }
    $document = [ordered]@{ format = $IwinExclusionsFormat; version = 1; items = @($items) }
    New-Item (Split-Path $path) -ItemType Directory -Force | Out-Null
    $temporary = "$path.tmp"
    [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $document -Depth 5), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

# Entrada del catálogo para un id de WinGet (las apps del catálogo usan su lote, contexto y avisos)
function Get-IwinCatalogAppByWingetId([string]$id) {
    @($Apps | Where-Object { $_.type -in @('winget', 'wingetall') -and @($_.winget) -contains $id }) | Select-Object -First 1
}

# Lista para el módulo Actualizaciones: lo que ofrece WinGet, con exclusiones y avisos del catálogo
function Get-IwinUpdateList {
    $updates = Get-IwinAvailableUpdates
    if ($null -eq $updates) { return $null }
    $excluded = @(Get-IwinExclusions)
    $list = @(foreach ($update in $updates) {
        $app = Get-IwinCatalogAppByWingetId $update.Id
        [ordered]@{
            id = $update.Id
            name = $update.Name
            installedVersion = $update.Version
            availableVersion = $update.Available
            source = $update.Source
            catalogId = if ($app) { $app.id } else { $null }
            interactive = [bool]($app -and $app.interactive)
            excluded = $excluded -contains $update.Id
        }
    })
    # La coma conserva la lista vacía («todo al día»), distinta de $null («no se pudo comprobar»)
    return ,$list
}

# Actualiza los ids indicados. Las apps del catálogo usan su lote (contexto, elevación, informe);
# el resto, «winget upgrade» con el usuario. En modo programado se omiten los asistentes interactivos.
# Devuelve un resultado por id: success, failed, skipped (excluida o interactiva programada).
function Invoke-IwinUpgradeIds([string[]]$ids, [switch]$Scheduled) {
    $excluded = @(Get-IwinExclusions)
    $results = [ordered]@{}
    $catalog = @()
    foreach ($id in @($ids | Where-Object { $_ } | Select-Object -Unique)) {
        if ($excluded -contains $id) { $results[$id] = 'skipped'; Write-Log "  $id · excluida: no se actualiza."; continue }
        $app = Get-IwinCatalogAppByWingetId $id
        if ($app -and $Scheduled -and $app.interactive) { $results[$id] = 'skipped'; Write-Log "  $($app.name) · necesita su asistente: se deja para una actualización manual."; continue }
        if ($app) { $catalog += $app; continue }
        Write-IwinEngineEvent @{ type = 'progress'; id = $id; phase = 'upgrade' }
        $code = Invoke-Winget @('upgrade', '-e', '--id', $id, '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements') $id
        $results[$id] = if ($code -in $wingetOk) { 'success' } else { 'failed' }
        Write-IwinEngineEvent @{ type = 'item'; id = $id; outcome = $results[$id] }
    }
    if ($catalog) {
        $previous = $UpgradePackages
        $script:UpgradePackages = $true
        try {
            $report = { param($app, $ok) Write-IwinEngineEvent @{ type = 'item'; id = @($app.winget)[0]; outcome = $(if ($ok) { 'success' } else { 'failed' }) } }
            $failed = @(Invoke-Install $catalog $report | ForEach-Object id)
        } finally { $script:UpgradePackages = $previous }
        foreach ($app in $catalog) { $results[@($app.winget)[0]] = if ($failed -contains $app.id) { 'failed' } else { 'success' } }
    }
    $results
}

# ---------- Actualización programada de apps (opcional, con el usuario, sin reiniciar) ----------
$IwinAppUpdateTask = 'iWinInstaller actualizar aplicaciones'

function Get-IwinAppUpdateSchedule {
    $task = Get-ScheduledTask -TaskName $IwinAppUpdateTask -ErrorAction SilentlyContinue
    if (-not $task) { return [ordered]@{ enabled = $false; frequency = 'weekly'; time = '12:00' } }
    $trigger = @($task.Triggers)[0]
    $frequency = if ($trigger.DaysInterval) { 'daily' } else { 'weekly' }
    $time = try { ([datetime]$trigger.StartBoundary).ToString('HH:mm') } catch { '12:00' }
    [ordered]@{ enabled = $true; frequency = $frequency; time = $time }
}

function Set-IwinAppUpdateSchedule([bool]$enabled, [string]$frequency = 'weekly', [string]$time = '12:00') {
    if (-not $enabled) { Unregister-ScheduledTask -TaskName $IwinAppUpdateTask -Confirm:$false -ErrorAction SilentlyContinue; return }
    if ($frequency -notin @('daily', 'weekly')) { throw [ArgumentException]'La frecuencia debe ser daily o weekly.' }
    if ($time -notmatch '^([01]\d|2[0-3]):[0-5]\d$') { throw [ArgumentException]'La hora debe tener el formato HH:mm.' }
    $at = [datetime]::Today.Add([timespan]::Parse($time))
    $trigger = if ($frequency -eq 'daily') { New-ScheduledTaskTrigger -Daily -At $at } else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $at }
    $script = Join-Path $Root 'iWinInstaller.ps1'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $powershell -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Update -Scheduled"
    # Con el usuario: las apps por usuario se actualizan en su perfil; las de equipo piden permiso como siempre
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2) -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $IwinAppUpdateTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Actualiza las aplicaciones con versión nueva, salvo las excluidas y las que necesitan asistente. No reinicia Windows.' -Force -ErrorAction Stop | Out-Null
}

# ---------- Comandos del contrato ----------
Register-IwinEngineCommand 'updates.list' {
    param($request)
    $items = Get-IwinUpdateList
    if ($null -eq $items) { throw 'No se pudieron comprobar las actualizaciones: WinGet no respondió o no está instalado.' }
    @{ items = @($items); schedule = (Get-IwinAppUpdateSchedule) }
}

Register-IwinEngineCommand 'updates.exclude' {
    param($request)
    if (-not $request.id) { throw [ArgumentException]'Falta el id.' }
    Set-IwinExclusion ([string]$request.id) ([bool]$request.excluded)
    @{ excluded = @(Get-IwinExclusions) }
}

Register-IwinEngineCommand 'updates.apply' {
    param($request)
    $ids = @($request.ids | Where-Object { $_ })
    if (-not $ids) { throw [ArgumentException]'No hay aplicaciones seleccionadas.' }
    if (-not (Ensure-Winget)) { throw 'WinGet no está disponible.' }
    Update-WingetCache
    $results = Invoke-IwinUpgradeIds $ids
    @{ results = @($results.Keys | ForEach-Object { [ordered]@{ id = $_; outcome = $results[$_] } }) }
}

Register-IwinEngineCommand 'updates.schedule' {
    param($request)
    Set-IwinAppUpdateSchedule ([bool]$request.enabled) ([string]$(if ($request.frequency) { $request.frequency } else { 'weekly' })) ([string]$(if ($request.time) { $request.time } else { '12:00' }))
    @{ schedule = (Get-IwinAppUpdateSchedule) }
}
