# iWinInstaller — motor: tarjetas de estado del Inicio que necesitan PowerShell (contrato status.collect).
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
# El espacio en disco, la salud de los discos, la batería y el reinicio pendiente los lee la interfaz.

function New-IwinStatusCard([string]$area, [string]$state, [string]$summary, [string]$reason = '', [string]$action = '') {
    [ordered]@{ area = $area; state = $state; summary = $summary; reason = $reason; action = $action; checkedAt = (Get-Date).ToUniversalTime().ToString('o') }
}

function Get-IwinUpdatesCard {
    $updates = Get-IwinAvailableUpdates
    if ($null -eq $updates) {
        $why = if (Test-Cmd winget) { 'WinGet no respondió (sin conexión o su origen no está disponible).' } else { 'WinGet no está instalado.' }
        return New-IwinStatusCard 'appUpdates' 'unknown' 'No se pudieron comprobar las actualizaciones' $why 'updates.open'
    }
    $count = @($updates).Count
    if ($count -eq 0) { return New-IwinStatusCard 'appUpdates' 'ok' 'Aplicaciones al día' '' 'updates.open' }
    $names = (@($updates | Select-Object -First 3 | ForEach-Object Name) -join ', ')
    New-IwinStatusCard 'appUpdates' 'attention' "$count $(if ($count -eq 1) { 'actualización disponible' } else { 'actualizaciones disponibles' })" $names 'updates.open'
}

function Get-IwinWindowsUpdateCard {
    try {
        $results = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results
        $last = $results.LastSearchSuccessDate
    } catch { return New-IwinStatusCard 'windowsUpdate' 'unknown' 'No se pudo leer Windows Update' $_.Exception.Message 'windowsupdate.open' }
    if (-not $last -or $last.Year -lt 2000) { return New-IwinStatusCard 'windowsUpdate' 'attention' 'Windows Update no ha buscado actualizaciones' 'Abre Windows Update y pulsa «Buscar actualizaciones».' 'windowsupdate.open' }
    $days = [int]((Get-Date).ToUniversalTime() - $last.ToUniversalTime()).TotalDays
    $when = if ($days -le 0) { 'hoy' } elseif ($days -eq 1) { 'ayer' } else { "hace $days días" }
    if ($days -le 7) { return New-IwinStatusCard 'windowsUpdate' 'ok' 'Windows Update al día' "Última búsqueda: $when." 'windowsupdate.open' }
    New-IwinStatusCard 'windowsUpdate' 'attention' "Windows Update lleva $days días sin buscar" 'Abre Windows Update y busca actualizaciones.' 'windowsupdate.open'
}

function Get-IwinAntivirusCard {
    $others = @()
    try { $others = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object { $_.displayName -notmatch 'Defender' } | ForEach-Object displayName) } catch { }
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { $mp = $null }
    if (-not $mp) {
        if ($others) { return New-IwinStatusCard 'antivirus' 'ok' "Protección a cargo de $($others -join ', ')" '' 'security.open' }
        return New-IwinStatusCard 'antivirus' 'unknown' 'No se pudo leer la protección antivirus' 'Microsoft Defender no responde en este equipo.' 'security.open'
    }
    $passive = [string]$mp.AMRunningMode -notin @('Normal', '')
    if ($passive -and $others) { return New-IwinStatusCard 'antivirus' 'ok' "Protección a cargo de $($others -join ', ')" '' 'security.open' }
    if (-not ($mp.RealTimeProtectionEnabled -and $mp.AntivirusEnabled)) { return New-IwinStatusCard 'antivirus' 'attention' 'Protección en tiempo real desactivada' 'Actívala en Seguridad de Windows.' 'security.open' }
    $age = [int]$mp.AntivirusSignatureAge
    if ($age -gt 3) { return New-IwinStatusCard 'antivirus' 'attention' "Firmas del antivirus de hace $age días" 'Actualiza las firmas desde Seguridad.' 'security.open' }
    New-IwinStatusCard 'antivirus' 'ok' 'Protegido: tiempo real activado y firmas al día' '' 'security.open'
}

function Get-IwinPendingBatchCard {
    $pending = @(Get-IwinPendingBatches)
    if (-not $pending) { return New-IwinStatusCard 'pendingBatch' 'ok' 'Sin lotes pendientes' '' 'install.open' }
    $items = @($pending[0].Data.items | Where-Object state -ne 'done').Count
    New-IwinStatusCard 'pendingBatch' 'attention' "Lote sin terminar: $items aplicación(es)" 'Puedes reanudarlo desde Instalar.' 'install.resume'
}

Register-IwinEngineCommand 'status.collect' {
    param($request)
    $all = [ordered]@{
        appUpdates = { Get-IwinUpdatesCard }
        windowsUpdate = { Get-IwinWindowsUpdateCard }
        antivirus = { Get-IwinAntivirusCard }
        pendingBatch = { Get-IwinPendingBatchCard }
    }
    $wanted = @($request.areas | Where-Object { $_ })
    $cards = foreach ($area in $all.Keys) {
        if ($wanted -and $wanted -notcontains $area) { continue }
        Write-IwinEngineEvent @{ type = 'progress'; id = $area; phase = 'check' }
        # Una comprobación que falla nunca se presenta como correcta
        try { $card = & $all[$area] } catch { $card = New-IwinStatusCard $area 'unknown' 'No se pudo comprobar' $_.Exception.Message }
        Write-IwinEngineEvent @{ type = 'item'; id = $area; outcome = $card.state }
        $card
    }
    @{ cards = @($cards) }
}
