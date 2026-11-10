# iWinInstaller — motor: Entradas opcionales, Guest Additions de VirtualBox y ayudas de registro.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

# Entradas opcionales (optin o extra, catálogo ampliado). No se marcan solas ni cuentan como falta.
function Test-Optional($app) { [bool]($app.optin -or $app.extra) }

# ---------- VirtualBox Guest Additions: el ISO viene con VirtualBox; si falta, se descarga el de la última versión ----------
$VBoxISO = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxGuestAdditions.iso'
$VBoxDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'VirtualBox'

function Install-VBoxGA {
    if (Test-Path $VBoxISO) { Write-Log "  Incluidas con VirtualBox: $VBoxISO"; return $true }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $v = ([string](Invoke-WebRequest 'https://download.virtualbox.org/virtualbox/LATEST.TXT' -UseBasicParsing).Content).Trim()
        New-Item $VBoxDir -ItemType Directory -Force | Out-Null
        $dest = Join-Path $VBoxDir "VBoxGuestAdditions_$v.iso"
        Write-Log "  Descargando Guest Additions $v..."
        if ($v -notmatch '^\d+(\.\d+){1,3}$') { throw "versión no válida: $v" }
        $base = "https://download.virtualbox.org/virtualbox/$v"
        $sums = [string](Invoke-WebRequest "$base/SHA256SUMS" -UseBasicParsing).Content
        $match = [regex]::Match($sums, "(?m)^([a-fA-F0-9]{64}) \*?VBoxGuestAdditions_$([regex]::Escape($v))\.iso\r?$")
        if (-not $match.Success) { throw 'Oracle no publica el hash SHA256 de esta versión.' }
        $expected = $match.Groups[1].Value
        Invoke-WebRequest "$base/VBoxGuestAdditions_$v.iso" -OutFile $dest -UseBasicParsing
        if ((Get-FileHash $dest -Algorithm SHA256).Hash -ne $expected) { Remove-Item $dest -Force; throw 'El ISO no supera la comprobación SHA256.' }
        Write-Log "  Guardado en $dest (SHA256 comprobado)"
        return $true
    } catch {
        Write-Log "  Descarga fallida ($($_.Exception.Message))."
        return $false
    }
}

function Test-VBoxGA {
    (Test-Path $VBoxISO) -or [bool](Get-ChildItem $VBoxDir -Filter 'VBoxGuestAdditions_*.iso' -ErrorAction SilentlyContinue)
}

# WSL instala una plataforma de aplicaciones; no modifica preferencias personales.
# Ajustes de Windows. Los de HKCU van en el lote de usuario y los de equipo en el de administrador.
$ExplorerAdv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$Personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$AppModelUnlock = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$HighPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
# Menú contextual clásico de Windows 11: una clave vacía de usuario; borrarla lo deshace
$ClassicMenu = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$SearchPolicy = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
$MouseKey = 'HKCU:\Control Panel\Mouse'
$FileSystemKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$DevSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'
function Get-RegValue($path, $name) { (Get-ItemProperty $path -Name $name -ErrorAction SilentlyContinue).$name }
function Set-RegDword($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path -Name $name -Value $value -Type DWord -Force
}
# HKCU\Software\Policies es de solo lectura para usuarios sin elevar: se reintenta con UNA solicitud
# de administrador que escribe en la rama del usuario actual (HKEY_USERS\<SID>), tambien si el administrador es otra cuenta.
function Invoke-UserPolicyElevated([object[]]$operations) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $lines = @('$ErrorActionPreference=''Stop''')
    foreach ($op in $operations) {
        if ($op.path -notmatch '^HKCU:\\Software\\Policies\\[A-Za-z0-9 ._\\-]+$' -or $op.name -notmatch '^[A-Za-z0-9_]+$') { throw 'Destino de directiva no permitido.' }
        $key = 'Registry::HKEY_USERS\' + $sid + '\' + $op.path.Substring(6)
        if ($null -eq $op.value) { $lines += "Remove-ItemProperty -LiteralPath '$key' -Name '$($op.name)' -ErrorAction SilentlyContinue" }
        else { $lines += "if(-not (Test-Path -LiteralPath '$key')){New-Item -Path '$key' -Force | Out-Null}"; $lines += "Set-ItemProperty -LiteralPath '$key' -Name '$($op.name)' -Value $([int]$op.value) -Type DWord -Force" }
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($lines -join "`n")))
    Write-Log '  Las directivas de usuario necesitan permiso de administrador: se pide una sola vez.'
    try { $process = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -Verb RunAs -WindowStyle Hidden -Wait -PassThru }
    catch { throw 'Se necesita aceptar el permiso de administrador para aplicar esta directiva.' }
    if ($process.ExitCode -ne 0) { throw "No se pudo escribir la directiva como administrador (codigo $($process.ExitCode))." }
}
function Set-PolicyDwords([string]$path, [System.Collections.IDictionary]$values) {
    $ErrorActionPreference = 'Stop'
    try { foreach ($name in $values.Keys) { Set-RegDword $path $name $values[$name] } }
    catch {
        if ($path -notlike 'HKCU:\Software\Policies\*') { throw }
        Invoke-UserPolicyElevated @($values.Keys | ForEach-Object { @{ path = $path; name = $_; value = $values[$_] } })
    }
}
function Set-RegString($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path -Name $name -Value $value -Type String -Force
}
# Ajustes de equipo: directamente si ya hay permisos, si no con una solicitud de administrador
function Invoke-MachineTweak($cmd) {
    if (Test-Administrator) { Invoke-Expression $cmd; return $true }
    Invoke-Elevated $cmd
}
