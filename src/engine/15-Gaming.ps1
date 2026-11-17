# iWinInstaller — motor: juego competitivo (v5.2). DNS más rápido por red y Wi-Fi sin ahorro de energía con corriente.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
# Diseño: specs/002-juego-competitivo/design.md

$GameDnsSource = Join-Path $Root 'src\engine\gaming\dns-rapido.ps1'
$GameDnsDir = Join-Path $env:ProgramData 'iWinInstaller\Latencia'
$GameDnsScript = Join-Path $GameDnsDir 'dns-rapido.ps1'
$GameDnsTaskPath = '\iWinInstaller\'
$GameDnsTaskName = 'DNS más rápido'
# powercfg: «Configuración del adaptador inalámbrico › Modo de ahorro de energía» (0 = máximo rendimiento)
$WifiPowerSub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
$WifiPowerSetting = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
$GuidPattern = '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'

# Select-GameDns y el resto de funciones puras del script de la tarea (una sola fuente)
if (Test-Path -LiteralPath $GameDnsSource) { . $GameDnsSource -Library }

# ---------- DNS más rápido ----------
function Get-GameDnsTaskXml([string]$ScriptPath) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = [Security.SecurityElement]::Escape("-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`"")
    # Disparador por evento: PowerShell 5.1 no lo crea con New-ScheduledTaskTrigger. 10000 = red conectada.
    $query = [Security.SecurityElement]::Escape('<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[EventID=10000]]</Select></Query></QueryList>')
    @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Author>iWinInstaller</Author><Description>Mide el DNS de la red y tres públicos al conectar y deja el más rápido. Deshacer desde iWinInstaller.</Description></RegistrationInfo>
  <Triggers>
    <BootTrigger><Enabled>true</Enabled><Delay>PT30S</Delay></BootTrigger>
    <LogonTrigger><Enabled>true</Enabled><Delay>PT20S</Delay></LogonTrigger>
    <EventTrigger><Enabled>true</Enabled><Subscription>$query</Subscription><Delay>PT10S</Delay></EventTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>Queue</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT2M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author"><Exec><Command>$ps</Command><Arguments>$arguments</Arguments></Exec></Actions>
</Task>
"@
}

function Test-GameDnsTask {
    if (-not (Test-Path -LiteralPath $GameDnsScript) -or -not (Test-Path -LiteralPath $GameDnsSource)) { return $false }
    # El script que ejecuta SYSTEM debe ser exactamente el del motor
    if ((Get-FileHash -LiteralPath $GameDnsScript).Hash -ne (Get-FileHash -LiteralPath $GameDnsSource).Hash) { return $false }
    # Sin administrador no se ven las tareas de SYSTEM: basta con el script, que solo puede escribir un administrador
    if (-not (Test-Administrator)) { return $true }
    [bool](Get-ScheduledTask -TaskPath $GameDnsTaskPath -TaskName $GameDnsTaskName -ErrorAction SilentlyContinue)
}
function Test-GameDns { Test-GameDnsTask }

function Set-GameDns {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    if ((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain) {
        Write-Log '  Equipo unido a un dominio: el DNS lo gestiona tu organización y no se cambia.'
        return $false
    }
    foreach ($directory in @((Join-Path $env:ProgramData 'iWinInstaller'), $GameDnsDir)) { Protect-IwinProgramDataDir $directory }
    Copy-Item -LiteralPath $GameDnsSource -Destination $GameDnsScript -Force -ErrorAction Stop
    Register-ScheduledTask -TaskPath $GameDnsTaskPath -TaskName $GameDnsTaskName -Xml (Get-GameDnsTaskXml $GameDnsScript) -Force -ErrorAction Stop | Out-Null
    Write-Log "  Tarea «$GameDnsTaskName» creada: mide el DNS al arrancar, al iniciar sesión y en cada red nueva."
    Start-ScheduledTask -TaskPath $GameDnsTaskPath -TaskName $GameDnsTaskName -ErrorAction SilentlyContinue
    $result = Join-Path $GameDnsDir 'dns.json'
    for ($i = 0; $i -lt 90 -and -not (Test-Path $result); $i++) { Start-Sleep -Seconds 1 }
    try {
        $data = Get-Content $result -Raw -Encoding UTF8 | ConvertFrom-Json
        $times = @($data.results | ForEach-Object { if ($_.failed) { "$($_.provider) sin respuesta" } else { "$($_.provider) $($_.ms) ms" } }) -join ' · '
        Write-Log "  Elegido: $($data.chosen) ($times)."
    } catch { Write-Log '  La primera medición aún no ha terminado; se completará en segundo plano.' }
    Write-Log '  El DNS acelera conectar con lanzadores y matchmaking; no cambia el ping dentro de la partida.'
    return (Test-GameDnsTask)
}

function Reset-GameDns {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    Stop-ScheduledTask -TaskPath $GameDnsTaskPath -TaskName $GameDnsTaskName -ErrorAction SilentlyContinue
    # Espera a que termine una medición en curso para que no vuelva a aplicar el DNS
    $mutex = New-Object Threading.Mutex($false, 'Global\iWinInstaller-dns')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(120)) } catch [Threading.AbandonedMutexException] { $locked = $true }
        Unregister-ScheduledTask -TaskPath $GameDnsTaskPath -TaskName $GameDnsTaskName -Confirm:$false -ErrorAction SilentlyContinue
        $applied = @()
        try { $applied = @((Get-Content (Join-Path $GameDnsDir 'aplicado.json') -Raw -Encoding UTF8 | ConvertFrom-Json).adapters) } catch { }
        foreach ($adapter in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $applied -contains $_.InterfaceGuid })) {
            $servers = @(Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses })
            # Solo vuelve a automático si sigue el DNS que puso iWinInstaller: si el usuario lo cambió, se respeta
            if (Get-GameDnsOwner $servers) { Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue }
        }
        Remove-Item -LiteralPath $GameDnsDir -Recurse -Force -ErrorAction SilentlyContinue
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
    Write-Log '  DNS automático restaurado en los adaptadores que había cambiado.'
    return (-not (Get-ScheduledTask -TaskPath $GameDnsTaskPath -TaskName $GameDnsTaskName -ErrorAction SilentlyContinue))
}

# ---------- Wi-Fi sin ahorro de energía (con corriente) ----------
# Valor de «powercfg /query» de corriente alterna (ac) o batería (dc), independiente del idioma:
# la línea AC contiene «AC» o «alterna» y la DC «DC» o «continua»; en otros idiomas, son las dos últimas líneas con valor.
function Get-PowercfgIndex([string]$Text, [ValidateSet('ac', 'dc')][string]$Kind = 'ac') {
    $pattern = if ($Kind -eq 'ac') { '\bAC\b|alterna' } else { '\bDC\b|continua' }
    $values = @()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -notmatch '0x([0-9a-fA-F]{8})\s*$') { continue }
        $value = [Convert]::ToInt32($Matches[1], 16)
        if ($line -match $pattern) { return $value }
        $values += $value
    }
    # Otros idiomas: powercfg siempre termina con el índice AC y después el DC
    if ($values.Count -ge 2) { return $values[$(if ($Kind -eq 'ac') { -2 } else { -1 })] }
    $null
}

# Planes que tienen el ajuste de Wi-Fi, con su valor actual con corriente
function Get-WifiPerfPlans {
    $list = (& powercfg /list 2>$null | Out-String)
    foreach ($match in [regex]::Matches($list, $GuidPattern)) {
        $text = (& powercfg /query $match.Value $WifiPowerSub $WifiPowerSetting 2>$null | Out-String)
        if ($LASTEXITCODE -ne 0) { continue }
        $ac = Get-PowercfgIndex $text 'ac'
        if ($null -ne $ac) { [pscustomobject]@{ plan = $match.Value.ToLowerInvariant(); ac = $ac } }
    }
}

function Set-WifiPerf {
    $plans = @(Get-WifiPerfPlans)
    if (-not $plans) { Write-Log '  Este equipo no tiene ajuste de energía de Wi-Fi (sin adaptador inalámbrico o sin esa opción).'; return $false }
    foreach ($p in $plans) { & powercfg /setacvalueindex $p.plan $WifiPowerSub $WifiPowerSetting 0 | Out-Null }
    & powercfg /setactive SCHEME_CURRENT | Out-Null
    Write-Log "  Wi-Fi a máximo rendimiento con corriente en $($plans.Count) planes; con batería se mantiene el ahorro."
    Write-Log '  Más estable aún: cable, o Wi-Fi de 5/6 GHz cerca del router. En el driver (Administrador de dispositivos) puedes revisar «Roaming aggressiveness» y «MIMO power save».'
    return (Test-WifiPerf)
}

function Test-WifiPerf {
    $text = (& powercfg /query SCHEME_CURRENT $WifiPowerSub $WifiPowerSetting 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) { return $false }
    return ((Get-PowercfgIndex $text 'ac') -eq 0)
}

# Repone el valor guardado en cada plan sin cambiar el plan activo
function Restore-WifiPerf($Wifi) {
    foreach ($p in @($Wifi)) {
        if ([string]$p.plan -notmatch "^$GuidPattern$") { throw 'Plan de energía no válido.' }
        $value = [int]$p.ac
        if ($value -lt 0 -or $value -gt 5) { throw 'Valor de energía de Wi-Fi no válido.' }
        & powercfg /setacvalueindex $p.plan $WifiPowerSub $WifiPowerSetting $value | Out-Null
    }
    & powercfg /setactive SCHEME_CURRENT | Out-Null
}
