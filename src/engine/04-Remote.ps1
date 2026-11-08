# iWinInstaller — motor: Acceso remoto, SSH y pantalla virtual.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

# ---------- PC anfitrión de escritorio remoto (Sunshine + Tailscale) ----------
# Deja el PC disponible sin estar delante: no se suspende, los servicios arrancan solos y se reinician si fallan.
# Sunshine corre como servicio y transmite también la pantalla de inicio de sesión: tras un corte se entra desde Moonlight.
$RemoteServices = @('SunshineService', 'Tailscale')
$KdeRuleGroup = 'iWinInstaller KDE Connect'
$WinlogonKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$PasswordLessKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
# Valor de corriente alterna de un ajuste de energía del plan activo (powercfg muestra CA y después CC)
function Get-AcPowerValue([string]$sub, [string]$setting) {
    $hex = [regex]::Matches((& powercfg /query SCHEME_CURRENT $sub $setting 2>$null | Out-String), '0x[0-9a-fA-F]{8}')
    if ($hex.Count -lt 2) { return $null }
    [Convert]::ToInt64($hex[$hex.Count - 2].Value, 16)
}
function Get-TailscaleExe {
    $exe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path $exe) { return $exe }
    (Get-Command tailscale.exe -ErrorAction SilentlyContinue).Source
}
function Get-AutologonExe {
    $dirs = @((Join-Path $env:ProgramFiles 'WinGet\Links'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'))
    foreach ($name in 'Autologon64.exe', 'Autologon.exe') {
        foreach ($dir in $dirs) { $path = Join-Path $dir $name; if (Test-Path $path) { return $path } }
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $null
}
# Accesos web en el escritorio y el menú Inicio públicos (carpeta «Acceso remoto»; Organize-Desktop no mueve carpetas)
$RemoteLinks = [ordered]@{
    'Sunshine (panel)' = 'https://localhost:47990'
    'Tailscale (equipos)' = 'https://login.tailscale.com/admin/machines'
    'Escritorio remoto de Chrome' = 'https://remotedesktop.google.com/access'
}
function Get-RemoteLinkDirs {
    @([Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('CommonPrograms')) |
        Where-Object { $_ } | ForEach-Object { Join-Path $_ 'Acceso remoto' }
}
function Set-RemoteLinks {
    foreach ($dir in Get-RemoteLinkDirs) {
        New-Item $dir -ItemType Directory -Force | Out-Null
        foreach ($name in $RemoteLinks.Keys) {
            Set-Content (Join-Path $dir "$name.url") @('[InternetShortcut]', "URL=$($RemoteLinks[$name])") -Encoding ASCII
        }
        Write-Log "  Accesos directos en $dir"
    }
}
function Set-RemoteHost {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    $ok = $true
    # Energía: nunca suspender ni hibernar con corriente; sin hibernación tampoco hay inicio rápido,
    # que deja el equipo a medias tras un corte e impide Wake-on-LAN desde apagado
    & powercfg /change standby-timeout-ac 0
    & powercfg /change hibernate-timeout-ac 0
    & powercfg /hibernate off 2>$null
    if ((Get-AcPowerValue 'SUB_SLEEP' 'STANDBYIDLE') -ne 0) { Write-Log '  No se pudo desactivar la suspensión.'; $ok = $false }
    # Red: Wake-on-LAN y sin ahorro de energía en los adaptadores físicos
    foreach ($nic in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -ne 'Disabled')) {
        try {
            Set-NetAdapterPowerManagement -Name $nic.Name -WakeOnMagicPacket Enabled -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop
            Write-Log "  Wake-on-LAN activado en $($nic.Name)"
        } catch { Write-Log "  $($nic.Name): el adaptador no admite Wake-on-LAN o ahorro configurable." }
    }
    # Servicios: arranque automático y reinicio a los 10 s si se cierran
    foreach ($svc in $RemoteServices) {
        if (-not (Get-Service $svc -ErrorAction SilentlyContinue)) { Write-Log "  Falta el servicio ${svc}: instala Sunshine y Tailscale."; $ok = $false; continue }
        Set-Service $svc -StartupType Automatic
        & sc.exe failure $svc reset= 86400 actions= restart/10000/restart/10000/restart/60000 | Out-Null
        Start-Service $svc -ErrorAction SilentlyContinue
        Write-Log "  ${svc}: automático y con reinicio tras fallo"
    }
    # KDE Connect (portapapeles compartido): sus puertos solo desde la red de Tailscale, sea cual sea el perfil de red
    try {
        Remove-NetFirewallRule -Group $KdeRuleGroup -ErrorAction SilentlyContinue
        foreach ($proto in 'TCP', 'UDP') {
            New-NetFirewallRule -DisplayName "KDE Connect por Tailscale ($proto)" -Group $KdeRuleGroup -Direction Inbound -Action Allow -Protocol $proto -LocalPort '1714-1764' -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
        }
        Write-Log '  Firewall: KDE Connect permitido desde Tailscale (puertos 1714-1764).'
    } catch { Write-Log "  No se pudo abrir KDE Connect en el firewall: $($_.Exception.Message)" }
    # Tailscale sin sesión de Windows abierta (modo desatendido); requiere haber iniciado sesión en Tailscale
    $ts = Get-TailscaleExe
    if ($ts) {
        & $ts status *> $null
        if ($LASTEXITCODE -eq 0) {
            & $ts set --unattended=true 2>&1 | ForEach-Object { Write-Log "    $_" }
            if ($LASTEXITCODE -eq 0) { Write-Log '  Tailscale en modo desatendido.' } else { Write-Log '  Tailscale no aceptó el modo desatendido; actívalo en su menú (Preferences › Run unattended).' }
        } else {
            Write-Log '  Tailscale: abre la app, inicia sesión y vuelve a aplicar este ajuste para el modo desatendido.'
        }
        Write-Log '  En login.tailscale.com › Machines › este PC › «Disable key expiry» para que no caduque.'
    }
    # Inicio de sesión automático (opcional): Autologon guarda la contraseña cifrada como secreto LSA
    if ((Get-RegValue $WinlogonKey 'AutoAdminLogon') -ne '1') {
        $autologon = Get-AutologonExe
        if ($autologon) {
            # Con «solo Windows Hello» activado, Windows ignora el inicio automático
            Set-RegDword $PasswordLessKey 'DevicePasswordLessBuildVersion' 0
            Start-Process $autologon -ArgumentList '/accepteula'
            Write-Log '  Autologon abierto: escribe tu contraseña de Windows (no el PIN) y pulsa Enable.'
        } else {
            Write-Log '  Sin inicio automático: tras un reinicio, inicia sesión desde Moonlight en la pantalla de bloqueo.'
        }
    }
    try { Set-RemoteLinks } catch { Write-Log "  No se pudieron crear los accesos directos: $($_.Exception.Message)" }
    Write-Log '  Primera vez en casa: abre https://localhost:47990, crea el usuario de Sunshine y empareja Moonlight con su PIN.'
    if (Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object FriendlyName -match 'Virtual Display') {
        Write-Log '  Pantalla virtual presente: Sunshine transmite aunque apagues o desconectes los monitores. Con el monitor encendido, Win + P › Duplicar evita que el ratón se vaya a la pantalla virtual.'
    } else {
        Write-Log '  Sin pantalla virtual: al apagar o desconectar el monitor Sunshine se queda sin imagen. Instala «Pantalla virtual» o usa un adaptador HDMI fantasma.'
    }
    Write-Log '  BIOS/UEFI: «Restore on AC Power Loss» = Power On para que arranque solo tras un corte de luz.'
    return ($ok -and (Test-RemoteHost))
}
function Reset-RemoteHost { Restore-TweakSnapshot 'remotehost' }

function Test-RemoteHost {
    if ((Get-AcPowerValue 'SUB_SLEEP' 'STANDBYIDLE') -ne 0) { return $false }
    foreach ($svc in $RemoteServices) {
        $service=Get-Service $svc -ErrorAction SilentlyContinue
        if(-not $service -or $service.StartType -ne 'Automatic' -or $service.Status -ne 'Running'){return $false}
    }
    $ts=Get-TailscaleExe
    if(-not $ts){return $false}
    try{
        $status=Invoke-IwinProbe $ts 'status --json'
        if($status.Code -ne 0 -or ($status.Output | ConvertFrom-Json).BackendState -ne 'Running'){return $false}
        $prefs=Invoke-IwinProbe $ts 'debug prefs'
        if($prefs.Code -ne 0){return $false}
        return [bool]($prefs.Output | ConvertFrom-Json).ForceDaemon
    }catch{return $false}
}

# ---------- Control remoto por SSH (solo Tailscale y solo con clave) ----------
# Permite administrar el PC desde el Mac con PowerShell por SSH. El puerto 22 solo acepta la red de Tailscale
# y el servidor no admite contraseñas: hace falta una clave pública autorizada.
$SshDir = Join-Path $env:ProgramData 'ssh'
$SshConfig = Join-Path $SshDir 'sshd_config'
$SshAdminKeys = Join-Path $SshDir 'administrators_authorized_keys'
$SshRuleGroup = 'iWinInstaller SSH'
$SshShellKey = 'HKLM:\SOFTWARE\OpenSSH'
$SshMarker = '# iWinInstaller: solo claves'
$SshDirectives = @($SshMarker, 'PubkeyAuthentication yes', 'PasswordAuthentication no', 'PermitEmptyPasswords no', '# iWinInstaller: fin')
function Get-SshdExe { Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe' }
# Directivas al principio: sshd usa la primera aparición de cada opción, también antes de los bloques Match
function Set-SshKeyOnlyConfig {
    $lines = @(Get-Content $SshConfig -Encoding UTF8 -ErrorAction Stop)
    $start = [array]::IndexOf($lines, $SshMarker)
    if ($start -ge 0) {
        $end = [array]::IndexOf($lines, '# iWinInstaller: fin')
        if ($end -lt $start) { throw 'Bloque de iWinInstaller incompleto en sshd_config.' }
        $lines = @($lines[0..($start - 1)] | Where-Object { $start -gt 0 }) + @(if ($end + 1 -lt $lines.Count) { $lines[($end + 1)..($lines.Count - 1)] })
    }
    [IO.File]::WriteAllLines($SshConfig, [string[]](@($SshDirectives) + @($lines)), (New-Object Text.UTF8Encoding $false))
}
function Set-SshAdminKeysAcl {
    if (-not (Test-Path $SshAdminKeys)) { [IO.File]::WriteAllText($SshAdminKeys, '', (New-Object Text.UTF8Encoding $false)) }
    & icacls.exe $SshAdminKeys /inheritance:r /grant:r '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null
    if ($LASTEXITCODE) { throw 'No se pudieron proteger las claves autorizadas.' }
}
function Set-RemoteSsh {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
        $capability = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object Name -like 'OpenSSH.Server*' | Select-Object -First 1
        if (-not $capability) { throw 'Este Windows no ofrece el componente OpenSSH Server.' }
        Write-Log "  Instalando $($capability.Name)..."
        Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop | Out-Null
    }
    # El primer arranque genera las claves del equipo y sshd_config
    if (-not (Test-Path $SshConfig)) { Start-Service sshd -ErrorAction Stop; Start-Sleep -Seconds 2; Stop-Service sshd -ErrorAction SilentlyContinue }
    if (-not (Test-Path $SshConfig)) { throw 'OpenSSH no creó sshd_config.' }
    $backup = [IO.File]::ReadAllBytes($SshConfig)
    Set-SshKeyOnlyConfig
    # sshd -t escribe en stderr: con Stop, PowerShell 5.1 lo convertiría en excepción antes de restaurar
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & (Get-SshdExe) -t 2>&1 | ForEach-Object { Write-Log "    $_" }; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $previous }
    if ($code) { [IO.File]::WriteAllBytes($SshConfig, $backup); throw 'La configuración de SSH no es válida; se ha dejado como estaba.' }
    Set-SshAdminKeysAcl
    Set-RegString $SshShellKey 'DefaultShell' (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    # Firewall: la regla de Windows abre el 22 a cualquier red; se sustituye por una limitada a Tailscale
    Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
    Remove-NetFirewallRule -Group $SshRuleGroup -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'SSH por Tailscale' -Group $SshRuleGroup -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -RemoteAddress '100.64.0.0/10' -Profile Any -ErrorAction Stop | Out-Null
    Set-Service sshd -StartupType Automatic -ErrorAction Stop
    Restart-Service sshd -ErrorAction Stop
    $keys = @(Get-Content $SshAdminKeys -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(ssh-|ecdsa-|sk-)' })
    if ($keys.Count) { Write-Log "  SSH listo: $($keys.Count) clave(s) autorizada(s). Conecta con ssh <usuario>@<IP 100.x del PC>." }
    else {
        Write-Log "  Falta autorizar una clave: pega la clave pública del Mac (~/.ssh/id_ed25519.pub) en $SshAdminKeys y guarda."
        if (-not $Silent) { Start-Process notepad.exe -ArgumentList "`"$SshAdminKeys`"" }
    }
    return (Test-RemoteSsh)
}
function Test-RemoteSsh {
    $service = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $service -or $service.StartType -ne 'Automatic' -or $service.Status -ne 'Running') { return $false }
    if (-not (Get-NetFirewallRule -Group $SshRuleGroup -ErrorAction SilentlyContinue)) { return $false }
    $first = @(Get-Content $SshConfig -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*PasswordAuthentication\s' } | Select-Object -First 1)
    return ($first.Count -eq 1 -and $first[0] -match '\bno\s*$')
}

# ---------- Monitor virtual activo (Virtual Display Driver) ----------
# El paquete de WinGet solo deja los archivos: el monitor aparece al crear el dispositivo raíz Root\MttVDD con devcon.
$VddHardwareId = 'Root\MttVDD'
$VddSettingsDir = 'C:\VirtualDisplayDriver'
function Get-VddFiles {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $section = if ($arch -eq 'ARM64') { 'NTarm64' } else { 'NTamd64' }
    $devconArch = if ($arch -eq 'ARM64') { 'arm64' } else { 'x64|amd64' }
    $roots = @(Get-AllInstalledEntries | Where-Object { $_.DisplayName -match 'Virtual Display Driver' -and $_.InstallLocation } | ForEach-Object InstallLocation)
    $roots += @((Join-Path $env:ProgramFiles 'Virtual Display Driver'), $VddSettingsDir)
    $packages = @((Join-Path $env:ProgramFiles 'WinGet\Packages'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'))
    $packages += @(Get-ChildItem (Join-Path $env:SystemDrive 'Users') -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'AppData\Local\Microsoft\WinGet\Packages' })
    foreach ($base in $packages) { $roots += @(Get-ChildItem $base -Directory -Filter 'VirtualDrivers.Virtual-Display-Driver*' -ErrorAction SilentlyContinue | ForEach-Object FullName) }
    foreach ($root in @($roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
        # La carpeta puede llamarse x86 aunque el INF sea de 64 bits: se elige por la sección de arquitectura del INF
        $inf = Get-ChildItem $root -Recurse -Filter 'MttVDD.inf' -ErrorAction SilentlyContinue | Where-Object { (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match $section } | Select-Object -First 1
        $devcons = @(Get-ChildItem $root -Recurse -Filter 'devcon.exe' -ErrorAction SilentlyContinue)
        $devcon = @($devcons | Where-Object FullName -match $devconArch) + $devcons | Select-Object -First 1
        if ($inf -and $devcon) {
            $settings = Get-ChildItem $root -Recurse -Filter 'vdd_settings.xml' -ErrorAction SilentlyContinue | Select-Object -First 1
            return [pscustomobject]@{ Inf = $inf.FullName; Devcon = $devcon.FullName; Settings = $(if ($settings) { $settings.FullName }) }
        }
    }
    $null
}
function Get-VddDevices { @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.HardwareID -contains $VddHardwareId }) }
function Set-VirtualDisplay {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    if (Test-VirtualDisplay) { Write-Log '  El monitor virtual ya está activo.'; return $true }
    $files = Get-VddFiles
    if (-not $files) { Write-Log '  Falta Pantalla virtual (Virtual Display Driver) o no trae MttVDD.inf y devcon.exe: instálala desde Sistema › Acceso remoto.'; return $false }
    # El controlador lee su configuración (resoluciones, GPU) de esta carpeta fija
    New-Item $VddSettingsDir -ItemType Directory -Force | Out-Null
    $target = Join-Path $VddSettingsDir 'vdd_settings.xml'
    if ($files.Settings -and -not (Test-Path $target)) { Copy-Item $files.Settings $target }
    # Un dispositivo roto de un intento anterior impediría crear uno nuevo limpio
    foreach ($dev in Get-VddDevices) { $null = & pnputil.exe /remove-device $dev.PNPDeviceID }
    Write-Log "  Creando el monitor virtual con $($files.Inf)"
    $run = Start-Process $files.Devcon -ArgumentList "install `"$($files.Inf)`" $VddHardwareId" -WindowStyle Hidden -Wait -PassThru
    if ($run.ExitCode -notin 0, 1) { Write-Log "  devcon no pudo crear el dispositivo (código $($run.ExitCode))."; return $false }
    if ($run.ExitCode -eq 1) { Write-Log '  Reinicia Windows para terminar de activar el monitor virtual.' }
    Write-Log '  Monitor virtual creado: Sunshine puede transmitir con las pantallas apagadas o el HDMI desconectado.'
    return (Test-VirtualDisplay)
}
function Reset-VirtualDisplay {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    foreach ($dev in Get-VddDevices) { $null = & pnputil.exe /remove-device $dev.PNPDeviceID }
    Write-Log '  Monitor virtual quitado. El controlador sigue instalado para volver a activarlo.'
    return (-not (Get-VddDevices))
}
function Test-VirtualDisplay { [bool](Get-VddDevices | Where-Object ConfigManagerErrorCode -eq 0) }
