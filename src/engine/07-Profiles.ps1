# iWinInstaller — motor: Perfiles, hardware detectado y escritorio.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

# Entradas de un perfil (profiles.json agrupa por «group»)
# Un perfil lista grupos (sus apps principales) o ids concretos (también del catálogo ampliado).
# ---------- Perfiles propios ----------
# Un perfil es un JSON con ids del catálogo; nunca contiene órdenes, rutas ni datos del equipo.
$ProfileDir = Join-Path $LogDir 'perfiles'
$ProfileFormat = 'iWinInstaller-perfil'
$CustomMark = '★ '
function Get-SafeProfileName([string]$name) {
    $clean = (($name -replace '[^\p{L}\p{N} ._()+-]', '') -replace '\s+', ' ').Trim(' .')
    if ($clean.Length -gt 60) { $clean = $clean.Substring(0, 60).Trim() }
    $clean
}
function Read-ProfileFile([string]$path) {
    $file = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($file.Length -gt 1MB) { throw 'El archivo es demasiado grande para ser un perfil.' }
    try { $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { throw 'El archivo no es un JSON válido.' }
    if ($data.formato -ne $ProfileFormat -or $null -eq $data.apps) { throw 'No es un perfil de iWinInstaller.' }
    $known = @{}; foreach ($a in $Apps) { $known[$a.id] = $true }
    $listed = @($data.apps | ForEach-Object { $_ })
    $ids = @($listed | Where-Object { $_ -is [string] -and $known.ContainsKey($_) } | Select-Object -Unique)
    $name = Get-SafeProfileName ([string]$data.nombre)
    if (-not $name) { $name = Get-SafeProfileName ([IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '\.iwin$', '') }
    if (-not $name) { $name = 'Perfil importado' }
    [pscustomobject]@{ Name = $name; Apps = $ids; Ignored = $listed.Count - $ids.Count }
}
function Write-ProfileFile([string]$path, [string]$name, $ids) {
    $data = [ordered]@{ formato = $ProfileFormat; version = 1; nombre = (Get-SafeProfileName $name); creado = (Get-Date -Format 'yyyy-MM-dd'); apps = @($ids | Select-Object -Unique) }
    $temporary = $path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($data | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}
function Get-CustomProfilePath([string]$name) { Join-Path $ProfileDir ((Get-SafeProfileName $name) + '.iwin.json') }
# Perfiles guardados en este equipo: nombre -> ids. Un archivo dañado se ignora sin cerrar la app.
function Get-CustomProfiles {
    $result = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $ProfileDir -Filter '*.iwin.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $entry = Read-ProfileFile $file.FullName; $result[$entry.Name] = $entry.Apps } catch { Write-Log "  Perfil ignorado ($($file.Name)): $($_.Exception.Message)" }
    }
    $result
}

# Marcas del hardware de este PC en líneas «Placa: …», «GPU: …», «GPUVEN_xxxx», «VID_xxxx»… para los «hardware» de apps.json
function Get-HardwareText {
    if ($null -ne $script:HardwareText) { return $script:HardwareText }
    $lines = @()
    try {
        foreach ($b in @(Get-CimInstance Win32_BaseBoard -ErrorAction Stop)) { $lines += "Placa: $($b.Manufacturer) $($b.Product)" }
        foreach ($c in @(Get-CimInstance Win32_Processor -ErrorAction Stop)) { $lines += "CPU: $($c.Name)" }
        foreach ($g in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) {
            $lines += "GPU: $($g.Name)"
            # Fabricante de la tarjeta (ASUS, MSI, Gigabyte…): subsistema del identificador PCI
            if ($g.PNPDeviceID -match 'SUBSYS_[0-9A-F]{4}([0-9A-F]{4})') { $lines += "GPUVEN_$($Matches[1].ToUpper())" }
        }
        foreach ($r in @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)) { $lines += "RAM: $($r.Manufacturer) $(([string]$r.PartNumber).Trim())" }
        foreach ($d in @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop)) { $lines += "Disco: $($d.Model)" }
    } catch { Write-Log "  Inventario de hardware incompleto: $($_.Exception.Message)" }
    foreach ($dev in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
        if ($dev.InstanceId -match 'VID_([0-9A-F]{4})') { $lines += "VID_$($Matches[1].ToUpper())" }
    }
    $script:HardwareText = @($lines | Select-Object -Unique)
    $script:HardwareText
}
# Apps del fabricante que corresponden a este PC; con las luces apagadas se omiten las que vuelven a encenderlas
function Get-HardwareApps {
    $text = Get-HardwareText
    $rgbOff = Test-RgbOff
    @($Apps | Where-Object { $_.hardware -and ($text -match $_.hardware) -and -not ($rgbOff -and $_.rgb) })
}
function Get-ProfileApps($name) {
    # Perfil exportado (archivo) o guardado en este equipo: exactamente los ids que contiene
    $ids = $null
    if ($name -match '\.json$' -and (Test-Path -LiteralPath $name -PathType Leaf)) { $ids = (Read-ProfileFile $name).Apps }
    else {
        $plain = $name -replace ('^' + [regex]::Escape($CustomMark)), ''
        $path = Get-CustomProfilePath $plain
        if (($name.StartsWith($CustomMark) -or -not ($Profiles.PSObject.Properties.Name -contains $name)) -and $plain -and (Test-Path -LiteralPath $path)) { $ids = (Read-ProfileFile $path).Apps }
    }
    if ($null -ne $ids) { return @($Apps | Where-Object { $ids -contains $_.id }) }
    # Desde la consola los acentos pueden llegar mal codificados: se compara solo con las letras ASCII
    $key = $name -replace '[^A-Za-z]', ''
    $match = $Profiles.PSObject.Properties.Name | Where-Object { ($_ -replace '[^A-Za-z]', '') -eq $key } | Select-Object -First 1
    if ($match) { $name = $match }
    $groups = @($Profiles.$name)
    if (-not $groups) { return @() }
    if ($groups -contains '@hardware') { return (Get-HardwareApps) }
    if ($groups -contains '*') { return @($Apps | Where-Object { -not (Test-Optional $_) }) }
    # «@Sistema», «@Terminal» o «@Aplicaciones» incluyen toda esa sección
    @($Apps | Where-Object { ($groups -contains $_.id -and -not $_.optin) -or (($groups -contains $_.group -or $groups -contains "@$($_.section)") -and -not (Test-Optional $_)) })
}

function Get-DesktopPaths {
    @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')) | Where-Object { $_ } | Select-Object -Unique
}

function Organize-Desktop([string]$destinationFolder = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Aplicaciones')) {
    $shell = New-Object -ComObject WScript.Shell
    $moved = 0
    foreach ($desktop in Get-DesktopPaths) {
        if (-not (Test-Path $desktop)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $desktop -File) {
            try {
                $isApplication = $false
                if ($file.Extension -eq '.lnk') {
                    $target = $shell.CreateShortcut($file.FullName).TargetPath
                    $isApplication = $target -match '(?i)\.(exe|com)$|^shell:AppsFolder'
                } elseif ($file.Extension -eq '.url') {
                    $isApplication = [bool](Select-String -LiteralPath $file.FullName -Pattern '^URL=(steam|com\.epicgames\.launcher)://' -Quiet)
                }
                if (-not $isApplication) { continue }
                $folder = $destinationFolder
                New-Item $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                $destination = Join-Path $folder $file.Name
                $suffix = 1
                while (Test-Path -LiteralPath $destination) {
                    $destination = Join-Path $folder ($file.BaseName + " ($suffix)" + $file.Extension)
                    $suffix++
                }
                [IO.File]::Move($file.FullName, $destination)
                $moved++
            } catch { Write-Log "  Acceso conservado en el escritorio ($($file.Name)): $($_.Exception.Message)" }
        }
    }
    Write-Log "Escritorio organizado: $moved accesos movidos a Aplicaciones."
}
