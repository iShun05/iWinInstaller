# iWinInstaller — motor: Apagado de luces RGB con OpenRGB.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

# ---------- Luces RGB apagadas (OpenRGB) ----------
# Muchas placas, memorias, gráficas y controladoras vuelven a su efecto de serie al quitarles la corriente:
# una tarea del sistema vuelve a apagarlas en cada arranque, sin necesidad de iniciar sesión.
$RgbDir = Join-Path $env:ProgramData 'iWinInstaller\OpenRGB'
$RgbScript = Join-Path $RgbDir 'apagar-rgb.ps1'
$RgbTaskPath = '\iWinInstaller\'
$RgbTaskName = 'Apagar luces RGB'
# Software del fabricante que reescribe los colores y compite con OpenRGB por el mismo controlador
$RgbVendorApps = 'Armoury Crate|Aura Sync|LightingService|iCUE|Mystic Light|MSI Center|RGB Fusion|GIGABYTE Control Center|NZXT CAM|SignalRGB|Razer Synapse|Logitech G HUB|L-Connect|Polychrome|MasterPlus|TT RGB Plus|SteelSeries GG|FURY CTRL|HyperX NGENUITY|Corsair'
# Fabricantes USB habituales de controladoras RGB (VID)
$RgbUsbVendors = @{ '1B1C' = 'Corsair'; '1E71' = 'NZXT'; '0B05' = 'ASUS Aura'; '1462' = 'MSI Mystic Light'; '048D' = 'ITE (Gigabyte RGB Fusion)'; '26CE' = 'ASRock Polychrome'; '0CF2' = 'Lian Li (ENE)'; '2516' = 'Cooler Master'; '264A' = 'Thermaltake'; '3633' = 'DeepCool'; '1532' = 'Razer'; '046D' = 'Logitech'; '1038' = 'SteelSeries'; '0951' = 'HyperX'; '03F0' = 'HyperX (HP)' }
function Get-OpenRgbExe {
    $exe = Join-Path $env:ProgramFiles 'OpenRGB\OpenRGB.exe'
    if (Test-Path $exe) { return $exe }
    foreach ($key in Get-AllInstalledEntries) {
        if ($key.DisplayName -like 'OpenRGB*' -and $key.InstallLocation) {
            $exe = Join-Path $key.InstallLocation 'OpenRGB.exe'
            if (Test-Path $exe) { return $exe }
        }
    }
    $null
}
function Get-AllInstalledEntries {
    $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    @(Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object DisplayName)
}
# Elige, por dispositivo de «OpenRGB --list-detailed», el modo que deja los LED apagados: Off, Direct o Static en negro.
# OpenRGB 1.1 marca el modo activo entre corchetes y entrecomilla con ' los nombres con espacios: [Direct] Pulse 'Double Flash'
function Get-RgbTokens {
    param([string]$Text)
    @([regex]::Matches($Text, "\[?'[^']*'\]?|\[?""[^""]*""\]?|\S+") | ForEach-Object { $_.Value.Trim('[', ']').Trim("'", '"') })
}
function Get-RgbOffArguments {
    param([string[]]$Lines)
    $result = @(); $device = $null
    foreach ($line in $Lines) {
        if ($line -match '^(\d+): ') { $device = $Matches[1]; continue }
        if ($null -eq $device -or $line -notmatch '^\s+Modes:(.*)$') { continue }
        $modes = Get-RgbTokens $Matches[1]
        $pick = $null
        foreach ($want in 'Off', 'Direct', 'Static') { if ($modes -contains $want) { $pick = $want; break } }
        $result += @('-d', $device)
        if ($pick -eq 'Off') { $result += @('-m', 'Off') }
        elseif ($pick) { $result += @('-m', $pick, '-c', '000000', '-b', '0') }
        else { $result += @('-c', '000000', '-b', '0') }  # sin modo conocido: negro en el modo actual
        $device = $null
    }
    , $result
}
# Zonas direccionables (JRAINBOW, ARGB…) que OpenRGB crea con 0 LED: sin tamaño, el negro no llega a la tira.
# Devuelve un comando por zona porque un tamaño fuera de rango hace que OpenRGB descarte toda la orden.
function Get-RgbResizeArguments {
    param([string[]]$Lines, [int]$Size = 60)
    $result = @(); $device = $null; $zones = @()
    foreach ($line in @($Lines) + @('999999: fin')) {
        if ($line -match '^(\d+): ') {
            if ($null -ne $device) {
                for ($z = 0; $z -lt $zones.Count; $z++) {
                    if ($zones[$z] -match '(?i)rainbow|argb|addressable') { $result += , @('-d', $device, '-z', "$z", '-sz', "$Size") }
                }
            }
            $device = $Matches[1]; $zones = @(); continue
        }
        if ($null -ne $device -and $line -match '^\s+Zones:(.*)$') { $zones = Get-RgbTokens $Matches[1] }
    }
    $result
}
# Script que ejecuta la tarea como SYSTEM; registra la última ejecución en apagar-rgb.log
function Get-RgbBootScript([string]$exe) {
    @"
# Generado por iWinInstaller. Apaga las luces RGB que detecta OpenRGB; lo ejecuta la tarea «$RgbTaskName».
param([switch]`$Once)
`$ErrorActionPreference = 'Continue'
`$exe = '$($exe -replace "'", "''")'
`$config = Split-Path -Parent `$MyInvocation.MyCommand.Path
# OpenRGB escribe en la consola del proceso padre si la hay: sin consola, su salida llega por la tubería
Add-Type -Namespace IwinRgb -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool FreeConsole();'
[void][IwinRgb.Native]::FreeConsole()
function Invoke-OpenRgb([string[]]`$ArgumentList, [int]`$TimeoutMs = 300000) {
    `$psi = New-Object Diagnostics.ProcessStartInfo `$exe
    `$psi.Arguments = (@('--config', ('"' + `$config + '"')) + `$script:baseArgs + `$ArgumentList) -join ' '
    `$psi.UseShellExecute = `$false; `$psi.CreateNoWindow = `$true
    `$psi.RedirectStandardOutput = `$true; `$psi.RedirectStandardError = `$true
    `$p = [Diagnostics.Process]::Start(`$psi)
    try {
        # Leer ambas tuberías sin bloquear permite aplicar el límite aunque OpenRGB no cierre stdout.
        `$stderr = `$p.StandardError.ReadToEndAsync()
        `$stdout = `$p.StandardOutput.ReadToEndAsync()
        if (-not `$p.WaitForExit(`$TimeoutMs)) {
            `$p.Kill()
            [void]`$p.WaitForExit(5000)
            throw 'OpenRGB superó el tiempo de espera.'
        }
        `$script:code = `$p.ExitCode
        @((`$stdout.Result + "``n" + `$stderr.Result) -split "``r?``n" | Where-Object { `$_ })
    } finally { `$p.Dispose() }
}
function Get-RgbTokens {
$(${function:Get-RgbTokens}.ToString())
}
function Get-RgbOffArguments {
$(${function:Get-RgbOffArguments}.ToString())
}
function Get-RgbResizeArguments {
$(${function:Get-RgbResizeArguments}.ToString())
}
# Si el servicio OpenRGB está instalado, es él quien tiene el hardware: se le envían las órdenes como cliente
# (conexión automática a 127.0.0.1:6742, sin detectar por segunda vez). Sin servicio, OpenRGB detecta por su cuenta.
`$service = Get-Service OpenRGB -ErrorAction SilentlyContinue
if (`$service) {
    if (`$service.Status -ne 'Running') { Start-Service OpenRGB -ErrorAction SilentlyContinue }
    `$script:baseArgs = @('--nodetect')
} else { `$script:baseArgs = @('--noautoconnect') }
`$out = @("`$(Get-Date -Format s) Inicio")
`$passes = if (`$Once) { 1 } else { 2 }
`$failed = `$false
try {
for (`$pass = 1; `$pass -le `$passes; `$pass++) {
    # Las controladoras USB pueden reiniciarse al cargar sus drivers: una segunda pasada al minuto las vuelve a apagar
    if (`$pass -gt 1) { Start-Sleep -Seconds 60 }
    # Al arrancar, el servicio tarda en detectar: se reintenta hasta tener dispositivos
    for (`$try = 1; `$try -le 8; `$try++) {
        `$list = Invoke-OpenRgb @('--list-detailed')
        `$devices = @(`$list | Where-Object { `$_ -match '^\d+: ' })
        if (`$code -eq 0 -and `$devices.Count) { break }
        Start-Sleep -Seconds 15
    }
    if (`$code -ne 0) { throw "OpenRGB no pudo enumerar dispositivos (código `$code)." }
    if (`$service) { `$out += "Servicio OpenRGB: `$((Get-Service OpenRGB).Status)" }
    foreach (`$resize in Get-RgbResizeArguments `$list) {
        `$res = Invoke-OpenRgb `$resize
        `$out += "  Tamaño `$(`$resize -join ' '): código `$code"
        `$out += `$res | Where-Object { `$_ -match '(?i)error' } | ForEach-Object { "    `$_" }
    }
    `$out += "Pasada `${pass}: `$(`$devices.Count) dispositivos"
    `$out += `$devices | ForEach-Object { "  `$_" }
    `$offArgs = Get-RgbOffArguments `$list
    if (`$offArgs.Count) {
        `$res = Invoke-OpenRgb `$offArgs
        `$out += "  Código `$code"
        `$errors = @(`$res | Where-Object { `$_ -match '(?i)error|wrong|failed' })
        `$out += `$errors | ForEach-Object { "  `$_" }
        if (`$code -ne 0 -or `$errors.Count) { throw "OpenRGB no pudo aplicar el apagado (código `$code)." }
        `$out += "Apagado aplicado: `$(`$devices.Count) dispositivos"
    }
}
} catch { `$failed = `$true; `$out += "ERROR: `$(`$_.Exception.Message)" }
finally { `$out | Set-Content (Join-Path `$config 'apagar-rgb.log') -Encoding UTF8 }
if (`$failed) { exit 1 }
"@
}
# Solo lectura: componentes, posibles controladoras USB y software RGB que hay que cerrar o quitar
function Write-RgbInventory {
    try {
        $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        Write-Log "    Placa base: $($board.Manufacturer) $($board.Product)"
        foreach ($ram in @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)) { Write-Log "    RAM: $($ram.Manufacturer) $(([string]$ram.PartNumber).Trim()) ($($ram.DeviceLocator))" }
        foreach ($gpu in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) { Write-Log "    Gráfica: $($gpu.Name)" }
    } catch { Write-Log "    Inventario incompleto: $($_.Exception.Message)" }
    $usb = @{}
    foreach ($dev in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
        if ($dev.InstanceId -match 'VID_([0-9A-F]{4})' -and $RgbUsbVendors.ContainsKey($Matches[1].ToUpper())) { $usb[$RgbUsbVendors[$Matches[1].ToUpper()]] = $true }
    }
    if ($usb.Count) { Write-Log "    USB con posible RGB: $(@($usb.Keys | Sort-Object) -join ', ')" }
    $vendor = @(Get-AllInstalledEntries | Where-Object { $_.DisplayName -match $RgbVendorApps } | ForEach-Object DisplayName | Sort-Object -Unique)
    if ($vendor) {
        Write-Log "  Software RGB del fabricante: $($vendor -join ', ')."
        Write-Log '  Puede volver a encender las luces: desinstálalo o quítalo del inicio (si controla ventiladores, configúralos antes en la BIOS).'
    }
}
function Set-RgbOff {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    $exe = Get-OpenRgbExe
    if (-not $exe) { Write-Log '  Falta OpenRGB: instálalo desde Sistema › Iluminación RGB.'; return $false }
    if (-not (Get-AllInstalledEntries | Where-Object DisplayName -like 'PawnIO*')) { Write-Log '  Falta PawnIO: sin él OpenRGB no llega a la placa base ni a la RAM.' }
    Write-RgbInventory
    # El servicio de OpenRGB, si existe, es quien controla el hardware: debe arrancar siempre con Windows
    if (Get-Service OpenRGB -ErrorAction SilentlyContinue) {
        Set-Service OpenRGB -StartupType Automatic
        Start-Service OpenRGB -ErrorAction SilentlyContinue
        Write-Log '  Servicio OpenRGB: automático; las órdenes se le envían como cliente.'
    }
    # Carpeta solo para SYSTEM y administradores: la tarea corre como SYSTEM y OpenRGB carga plugins de su configuración
    New-Item $RgbDir -ItemType Directory -Force | Out-Null
    & icacls.exe $RgbDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log '  No se pudieron proteger los permisos de la carpeta.'; return $false }
    Set-Content $RgbScript (Get-RgbBootScript $exe) -Encoding UTF8
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$RgbScript`""
    # Al arrancar (sin sesión) y al iniciar sesión, que es cuando algunos drivers reinician sus LED
    $boot = New-ScheduledTaskTrigger -AtStartup; $boot.Delay = 'PT30S'
    $logon = New-ScheduledTaskTrigger -AtLogOn; $logon.Delay = 'PT20S'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskPath $RgbTaskPath -TaskName $RgbTaskName -Action $action -Trigger $boot, $logon -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log "  Tarea «$RgbTaskName» creada: apaga las luces en cada arranque, también sin sesión."
    # Primera aplicación ahora, para ver qué detecta OpenRGB
    # Un informe de una ejecución anterior no prueba el resultado de esta pasada.
    $reportPath = Join-Path $RgbDir 'apagar-rgb.log'
    Remove-Item $reportPath -Force -ErrorAction SilentlyContinue
    $run = Start-Process $ps -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$RgbScript`" -Once" -WindowStyle Hidden -Wait -PassThru
    $report = @(Get-Content (Join-Path $RgbDir 'apagar-rgb.log') -Encoding UTF8 -ErrorAction SilentlyContinue)
    $report | Select-Object -Skip 1 | ForEach-Object { Write-Log "    $_" }
    if ($run.ExitCode -ne 0) { Write-Log "  OpenRGB no completó el apagado (código $($run.ExitCode)). Consulta el diagnóstico de la tarea."; return $false }
    $found = $report | Where-Object { $_ -match '^Apagado aplicado: (\d+) dispositivos$' } | ForEach-Object { [int]$Matches[1] }
    if (-not $found) {
        Write-Log '  OpenRGB no detectó ningún dispositivo. Reinicia (PawnIO se carga al arrancar) y vuelve a aplicar.'
        return $false
    }
    Write-Log "  $found dispositivos con orden de apagado aplicada. Si algo sigue encendido, no es compatible con OpenRGB: apágalo desde la BIOS o el botón/cable de su controladora."
    Write-Log '  BIOS/UEFI: desactiva también el LED de la placa al arrancar y apagado (ASUS «LED lighting», MSI «EZ LED Control», Gigabyte «RGB Fusion», ASRock «RGB LED»).'
    return $true
}
function Reset-RgbOff {
    if (-not (Test-Administrator)) { Write-Log '  Necesita permiso de administrador.'; return $false }
    Unregister-ScheduledTask -TaskPath $RgbTaskPath -TaskName $RgbTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $RgbDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log '  Las luces vuelven a su efecto de serie tras apagar el PC, o configúralas desde OpenRGB.'
    return (-not (Get-ScheduledTask -TaskPath $RgbTaskPath -TaskName $RgbTaskName -ErrorAction SilentlyContinue))
}
function Test-RgbOff {
    if (-not (Test-Path $RgbScript)) { return $false }
    $report = @(Get-Content (Join-Path $RgbDir 'apagar-rgb.log') -Encoding UTF8 -ErrorAction SilentlyContinue)
    if (-not ($report -match '^Apagado aplicado: [1-9][0-9]* dispositivos$') -or ($report -match '^ERROR:')) { return $false }
    # Sin administrador no se ven las tareas de SYSTEM: basta con el script, que solo puede escribir un administrador
    if (-not (Test-Administrator)) { return $true }
    [bool](Get-ScheduledTask -TaskPath $RgbTaskPath -TaskName $RgbTaskName -ErrorAction SilentlyContinue)
}
