# iWinInstaller — motor: energía, seguridad, vincular equipos y ajustes de la app (interfaz nueva, v4.7).
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
# Las funciones de Vincular equipos (Get-LinkCommands…) vienen de la ventana clásica y viven aquí desde v4.7.

# ---------- Energía: apagado de pantalla, suspensión e hibernación del plan activo ----------
function Get-IwinHibernateEnabled { try { [bool](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' HibernateEnabled -ErrorAction Stop) } catch { $false } }

function ConvertTo-IwinMinutes($seconds) { if ($null -eq $seconds) { $null } else { [int][math]::Ceiling($seconds / 60) } }

Register-IwinEngineCommand 'power.get' {
    param($request)
    $plan = (& powercfg /getactivescheme 2>$null | Out-String) -replace '^.*?:\s*', '' -replace '\s+$', ''
    @{
        monitor = ConvertTo-IwinMinutes (Get-AcPowerValue SUB_VIDEO VIDEOIDLE)
        sleep = ConvertTo-IwinMinutes (Get-AcPowerValue SUB_SLEEP STANDBYIDLE)
        hibernateAfter = ConvertTo-IwinMinutes (Get-AcPowerValue SUB_SLEEP HIBERNATEIDLE)
        hibernate = Get-IwinHibernateEnabled
        plan = $plan
    }
}

# Aplica los tiempos a corriente y batería por igual; la hibernación necesita administrador
Register-IwinEngineCommand 'power.set' {
    param($request)
    $values = @{}
    foreach ($name in 'monitor', 'sleep', 'hibernateAfter') {
        $value = $request.$name
        if ($null -eq $value -or [int]$value -lt 0 -or [int]$value -gt 1440) { throw [ArgumentException]"Valor no válido para $name." }
        $values[$name] = [int]$value
    }
    foreach ($pair in @(@('monitor-timeout', $values.monitor), @('standby-timeout', $values.sleep), @('hibernate-timeout', $values.hibernateAfter))) {
        foreach ($side in 'ac', 'dc') { & powercfg /change "$($pair[0])-$side" $pair[1] 2>$null | Out-Null }
    }
    $hibernateFailed = $false
    $wanted = [bool]$request.hibernate
    if ($wanted -ne (Get-IwinHibernateEnabled)) {
        $argument = if ($wanted) { '/hibernate on' } else { '/hibernate off' }
        try {
            if (Test-Administrator) { & powercfg $argument.Split(' ') | Out-Null; $hibernateFailed = $LASTEXITCODE -ne 0 }
            else { $p = Start-Process powercfg -ArgumentList $argument -Verb RunAs -WindowStyle Hidden -Wait -PassThru; $hibernateFailed = $p.ExitCode -ne 0 }
        } catch { $hibernateFailed = $true }
    }
    Write-Log "Energía: pantalla $($values.monitor) min, suspensión $($values.sleep) min, hibernar tras $($values.hibernateAfter) min, hibernación $wanted"
    @{ hibernateFailed = $hibernateFailed; hibernate = Get-IwinHibernateEnabled }
}

# ---------- Seguridad: Microsoft Defender ----------
Register-IwinEngineCommand 'security.status' {
    param($request)
    $others = @()
    try { $others = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object { $_.displayName -notmatch 'Defender' } | ForEach-Object displayName) } catch { }
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { $mp = $null }
    if (-not $mp) { return @{ available = $false; others = @($others) } }
    $date = { param($value) if (-not $value -or $value.Year -lt 2000) { $null } else { $value.ToString('o') } }
    $threats = @(); $threatsVisible = $true
    try {
        $names = @{}; foreach ($t in @(Get-MpThreat -ErrorAction Stop)) { $names[[string]$t.ThreatID] = $t.ThreatName }
        $threats = @(Get-MpThreatDetection -ErrorAction Stop | Sort-Object InitialDetectionTime -Descending | Select-Object -First 5 | ForEach-Object {
            [ordered]@{ when = $_.InitialDetectionTime.ToString('o'); name = $(if ($names.ContainsKey([string]$_.ThreatID)) { $names[[string]$_.ThreatID] } else { "Amenaza $($_.ThreatID)" }); resolved = [bool]$_.ActionSuccess }
        })
    } catch { $threatsVisible = $false }
    @{
        available = $true; others = @($others)
        realtime = [bool]$mp.RealTimeProtectionEnabled; antivirus = [bool]$mp.AntivirusEnabled
        passive = [string]$mp.AMRunningMode -notin @('Normal', ''); mode = [string]$mp.AMRunningMode
        tamper = [bool]$mp.IsTamperProtected
        signatureVersion = [string]$mp.AntivirusSignatureVersion; signatureAge = [int]$mp.AntivirusSignatureAge
        signatureUpdated = & $date $mp.AntivirusSignatureLastUpdated
        quickScan = & $date $mp.QuickScanEndTime; fullScan = & $date $mp.FullScanEndTime
        threats = @($threats); threatsVisible = $threatsVisible
    }
}

# Análisis o firmas en este proceso del motor: puede durar horas sin bloquear la ventana
Register-IwinEngineCommand 'security.run' {
    param($request)
    $action = [string]$request.action
    switch ($action) {
        'quick' { Start-MpScan -ScanType QuickScan -ErrorAction Stop }
        'full' { Start-MpScan -ScanType FullScan -ErrorAction Stop }
        'update' { Update-MpSignature -ErrorAction Stop }
        'folder' {
            $path = [string]$request.path
            if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Container)) { throw [ArgumentException]'Esa carpeta no existe.' }
            Start-MpScan -ScanType CustomScan -ScanPath $path -ErrorAction Stop
        }
        default { throw [ArgumentException]"Acción no válida: $action" }
    }
    Write-Log "Seguridad: $action terminado."
    @{ action = $action; done = $true }
}

# ---------- Vincular equipos: SSH con clave desde un Mac u otro Windows ----------
# ---- Vincular equipos: SSH con clave desde un Mac u otro Windows ----
$SshLanGroup = 'iWinInstaller SSH red local'
function Get-LinkAddresses {
    $tail = $null
    $exe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path $exe) { try { $tail = @(& $exe ip -4 2>$null | Where-Object { $_ -match '^100\.' })[0] } catch {} }
    if (-not $tail) { $tail = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '100.*' -and $_.InterfaceAlias -like '*Tailscale*' } | ForEach-Object IPAddress)[0] }
    $lan = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | ForEach-Object { $_.IPv4Address.IPAddress } | Where-Object { $_ -notlike '100.*' -and $_ -notlike '169.254.*' })[0]
    [pscustomobject]@{ Tailscale = $tail; Lan = $lan }
}
function Get-LinkAlias { $a = ($env:COMPUTERNAME.ToLowerInvariant() -replace '[^a-z0-9-]', ''); if ($a) { $a } else { 'pc-windows' } }
function Test-UserIsAdminGroup { [bool]([Security.Principal.WindowsIdentity]::GetCurrent().Groups | Where-Object { $_.Value -eq 'S-1-5-32-544' }) }
function Get-LinkKeysPath { if (Test-UserIsAdminGroup) { $SshAdminKeys } else { Join-Path $env:USERPROFILE '.ssh\authorized_keys' } }
function Get-LinkCommands {
    $addr = Get-LinkAddresses
    $ip = if ($addr.Tailscale) { $addr.Tailscale } elseif ($addr.Lan) { $addr.Lan } else { '<IP del PC>' }
    $alias = Get-LinkAlias; $user = $env:USERNAME
    $mac = "H='$alias'; IP='$ip'; U='$user'; mkdir -p ~/.ssh && chmod 700 ~/.ssh; [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C `"`$(whoami)@`$(hostname -s)`"; grep -q `"^Host `$H`$`" ~/.ssh/config 2>/dev/null || printf '\nHost %s\n  HostName %s\n  User %s\n  IdentityFile ~/.ssh/id_ed25519\n  ServerAliveInterval 30\n' `"`$H`" `"`$IP`" `"`$U`" >> ~/.ssh/config; pbcopy < ~/.ssh/id_ed25519.pub; echo 'Clave copiada: pegala en iWinInstaller > Vincular equipos'; cat ~/.ssh/id_ed25519.pub"
    $win = "`$H='$alias'; `$IP='$ip'; `$U='$user'; `$d=Join-Path `$HOME '.ssh'; New-Item -ItemType Directory -Force `$d | Out-Null; if (-not (Test-Path `"`$d\id_ed25519`")) { Start-Process ssh-keygen -Wait -NoNewWindow -ArgumentList (`"-q -t ed25519 -N ```"```" -f ```"`$d\id_ed25519```" -C `$env:USERNAME@`$env:COMPUTERNAME`") }; `$c=`"`$d\config`"; if (-not (Select-String -Path `$c -Pattern `"^Host `$H`$`" -Quiet -ErrorAction SilentlyContinue)) { Add-Content `$c `"``nHost `$H``n  HostName `$IP``n  User `$U``n  IdentityFile ~/.ssh/id_ed25519``n  ServerAliveInterval 30`" }; Get-Content `"`$d\id_ed25519.pub`" | Set-Clipboard; 'Clave copiada: pegala en iWinInstaller > Vincular equipos'; Get-Content `"`$d\id_ed25519.pub`""
    [pscustomobject]@{ Mac = $mac; Windows = $win; Alias = $alias; Ip = $ip; User = $user; Addresses = $addr }
}
function Invoke-LinkElevated([string]$script, [string]$label) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$ErrorActionPreference='Stop'`n" + $script))
    try { $p = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -Verb RunAs -WindowStyle Hidden -Wait -PassThru }
    catch { Write-Log "$label`: hace falta aceptar el permiso de administrador."; return $false }
    if ($p.ExitCode) { Write-Log "$label no se completó (código $($p.ExitCode))."; return $false }
    return $true
}

Register-IwinEngineCommand 'link.status' {
    param($request)
    $info = Get-LinkCommands
    $ready = $false; try { $ready = [bool](Test-RemoteSsh) } catch { }
    $keys = @(Get-Content (Get-LinkKeysPath) -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(ssh-|ecdsa-|sk-)' })
    @{
        ready = $ready; tailscale = [string]$info.Addresses.Tailscale; lan = [string]$info.Addresses.Lan
        lanAllowed = [bool](Get-NetFirewallRule -Group $SshLanGroup -ErrorAction SilentlyContinue)
        user = [string]$info.User; alias = [string]$info.Alias; ip = [string]$info.Ip; authorized = $keys.Count
        macCommand = [string]$info.Mac; windowsCommand = [string]$info.Windows
    }
}

Register-IwinEngineCommand 'link.prepare' {
    param($request)
    $app = $Apps | Where-Object id -eq 'remotessh' | Select-Object -First 1
    if (-not $app) { throw 'El catálogo no incluye el control remoto por SSH.' }
    $failed = @(Invoke-InstallWorker @($app) $null)
    if ($failed) { throw 'No se pudo preparar el servidor SSH: revisa la actividad.' }
    @{ ready = $true }
}

Register-IwinEngineCommand 'link.lan' {
    param($request)
    $on = [bool]$request.enabled
    $script = if ($on) { "Remove-NetFirewallRule -Group '$SshLanGroup' -ErrorAction SilentlyContinue; New-NetFirewallRule -DisplayName 'SSH en red local' -Group '$SshLanGroup' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -RemoteAddress LocalSubnet -Profile Private,Domain | Out-Null" } else { "Remove-NetFirewallRule -Group '$SshLanGroup' -ErrorAction SilentlyContinue" }
    if (-not (Invoke-LinkElevated $script 'Red local')) { throw 'Hace falta aceptar el permiso de administrador.' }
    Write-Log "Vincular: SSH en red local $(if ($on) { 'permitido (solo redes privadas)' } else { 'cerrado' })."
    @{ lanAllowed = [bool](Get-NetFirewallRule -Group $SshLanGroup -ErrorAction SilentlyContinue) }
}

Register-IwinEngineCommand 'link.authorize' {
    param($request)
    $key = ([string]$request.key -replace '\s+', ' ').Trim()
    if ($key -match 'PRIVATE KEY') { throw [ArgumentException]'Eso es una clave privada: no la compartas. Pega la línea que empieza por ssh-ed25519.' }
    if ($key -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com) [A-Za-z0-9+/=]{40,}( [^\r\n]{0,200})?$') { throw [ArgumentException]'La clave no tiene el formato esperado (ssh-ed25519 AAAA… usuario@equipo).' }
    $path = Get-LinkKeysPath
    if (@(Get-Content $path -ErrorAction SilentlyContinue) -contains $key) { return @{ added = $false; message = 'Ese equipo ya estaba autorizado.' } }
    if ($path -eq $SshAdminKeys) {
        # El archivo de administradores solo lo pueden escribir administradores y SYSTEM
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($key))
        $script = "`$k=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')); `$f='$SshAdminKeys'; if(-not (Test-Path `$f)){New-Item `$f -ItemType File -Force | Out-Null}; `$t=[IO.File]::ReadAllText(`$f); if(`$t -and -not `$t.EndsWith(`"``n`")){`$t+=`"``r``n`"}; [IO.File]::WriteAllText(`$f, `$t + `$k + `"``r``n`", (New-Object Text.UTF8Encoding `$false)); icacls.exe `$f /inheritance:r /grant:r '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null; if(`$LASTEXITCODE){exit 3}"
        if (-not (Invoke-LinkElevated $script 'Autorizar equipo')) { throw 'Hace falta aceptar el permiso de administrador.' }
    } else {
        New-Item (Split-Path $path) -ItemType Directory -Force | Out-Null
        Add-Content $path $key -Encoding ASCII
    }
    $comment = ($key -split ' ', 3)[2]
    Write-Log "Vincular: equipo autorizado $(if ($comment) { "($comment)" })."
    @{ added = $true; message = "Equipo autorizado. Desde él: ssh $(Get-LinkAlias)" }
}

Register-IwinEngineCommand 'link.keys' {
    param($request)
    $path = Get-LinkKeysPath
    $keys = @(Get-Content $path -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(ssh-|ecdsa-|sk-)' } | ForEach-Object {
        $p = $_ -split ' ', 3
        if ($p.Count -ge 3) { $p[2] } else { $p[0] + ' …' + $p[1].Substring([math]::Max(0, $p[1].Length - 12)) }
    })
    @{ keys = @($keys); path = $path }
}

# ---------- Ajustes de la app ----------
Register-IwinEngineCommand 'app.info' {
    param($request)
    $task = Get-ScheduledTask -TaskName 'iWinInstaller actualizaciones' -ErrorAction SilentlyContinue
    @{ version = $Version; autoUpdate = [bool]$task; logDir = $LogDir; installDir = (Get-IwinInstallDir) }
}

Register-IwinEngineCommand 'app.autoupdate' {
    param($request)
    Set-IwinAutoUpdate ([bool]$request.enabled)
    @{ autoUpdate = [bool](Get-ScheduledTask -TaskName 'iWinInstaller actualizaciones' -ErrorAction SilentlyContinue) }
}

Register-IwinEngineCommand 'app.selfupdate' {
    param($request)
    # Como la ventana: si la app está abierta, la versión nueva se aplica al cerrarla
    $script:AutoUpdate = $true
    Clear-IwinUpdateDownloads
    $ok = Update-Self
    @{ ok = [bool]$ok }
}

Register-IwinEngineCommand 'app.diagnostic' {
    param($request)
    @{ path = [string](Export-Diagnostic) }
}
