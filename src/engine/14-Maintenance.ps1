# iWinInstaller — motor: mantenimiento y salud (v4.9): limpieza segura, reparación e informe del equipo.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
# La limpieza solo toca una lista cerrada de ubicaciones temporales y de caché; nunca documentos.

function Get-IwinCleanupCategories {
    $local = $env:LOCALAPPDATA
    $windows = $env:SystemRoot
    [ordered]@{
        userTemp = @{ label = 'Temporales de tu usuario'; admin = $false; paths = @($env:TEMP) }
        systemTemp = @{ label = 'Temporales de Windows'; admin = $true; paths = @(Join-Path $windows 'Temp') }
        wuCache = @{ label = 'Descargas de Windows Update ya instaladas'; admin = $true; paths = @(Join-Path $windows 'SoftwareDistribution\Download') }
        deliveryOptimization = @{ label = 'Caché de Optimización de distribución'; admin = $true; paths = @(Join-Path $windows 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache') }
        thumbnails = @{ label = 'Miniaturas del Explorador'; admin = $false; paths = @(Join-Path $local 'Microsoft\Windows\Explorer'); filter = 'thumbcache_*.db' }
        crashDumps = @{ label = 'Volcados de errores de apps'; admin = $false; paths = @(Join-Path $local 'CrashDumps') }
        recycleBin = @{ label = 'Papelera de reciclaje'; admin = $false; paths = @() }
        iwinDownloads = @{ label = 'Descargas antiguas de iWinInstaller'; admin = $false; paths = @(Join-Path $LogDir 'actualizacion') }
    }
}

# Archivos de una categoría con más de un día (lo reciente puede estar en uso)
function Get-IwinCleanupFiles($category) {
    $limit = (Get-Date).AddDays(-1)
    foreach ($path in @($category.paths)) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        $filter = if ($category.filter) { $category.filter } else { '*' }
        Get-ChildItem -LiteralPath $path -Filter $filter -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limit -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }
    }
}

function Get-IwinRecycleBinSize {
    try {
        $shell = New-Object -ComObject Shell.Application
        $bin = $shell.NameSpace(10)
        [long](@($bin.Items() | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum)
    } catch { 0 }
}

Register-IwinEngineCommand 'maintenance.estimate' {
    param($request)
    $categories = Get-IwinCleanupCategories
    $result = foreach ($key in $categories.Keys) {
        $category = $categories[$key]
        Write-IwinEngineEvent @{ type = 'progress'; id = $key; phase = 'estimate' }
        $bytes = if ($key -eq 'recycleBin') { Get-IwinRecycleBinSize } else { [long](@(Get-IwinCleanupFiles $category | Measure-Object Length -Sum).Sum) }
        [ordered]@{ id = $key; label = $category.label; admin = [bool]$category.admin; estimatedBytes = $bytes }
    }
    @{ categories = @($result) }
}

# Limpia las categorías indicadas. Las que necesitan administrador se agrupan en una sola solicitud.
Register-IwinEngineCommand 'maintenance.clean' {
    param($request)
    $categories = Get-IwinCleanupCategories
    $wanted = @($request.categories | Where-Object { $_ })
    $unknown = @($wanted | Where-Object { -not $categories.Contains($_) })
    if ($unknown) { throw [ArgumentException]"Categorías desconocidas: $($unknown -join ', ')" }
    $results = @()
    $elevated = @($wanted | Where-Object { $categories[$_].admin })
    if ($elevated -and -not (Test-Administrator)) {
        # Un único proceso de administrador limpia las del sistema con el mismo motor
        $work = Join-Path $LogDir ('limpieza-' + [guid]::NewGuid().ToString('N'))
        New-Item $work -ItemType Directory -Force | Out-Null
        $req = Join-Path $work 'request.json'; $res = Join-Path $work 'response.json'
        [IO.File]::WriteAllText($req, (ConvertTo-Json @{ contract = 1; categories = $elevated }), (New-Object Text.UTF8Encoding $false))
        try {
            $p = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $Root 'iWinInstaller.ps1')`"", '-EngineCommand', 'maintenance.clean', '-EngineRequest', "`"$req`"", '-EngineResponse', "`"$res`"")
            if ($p.ExitCode -eq 0 -and (Test-Path $res)) { $results += @((Get-Content $res -Raw -Encoding UTF8 | ConvertFrom-Json).categories | ForEach-Object { [ordered]@{ id = $_.id; freedBytes = [long]$_.freedBytes; skippedFiles = [int]$_.skippedFiles; denied = $false } }) }
            else { $results += @($elevated | ForEach-Object { [ordered]@{ id = $_; freedBytes = 0; skippedFiles = 0; denied = $true } }) }
        } catch { $results += @($elevated | ForEach-Object { [ordered]@{ id = $_; freedBytes = 0; skippedFiles = 0; denied = $true } }) }
        finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
        $wanted = @($wanted | Where-Object { $elevated -notcontains $_ })
    }
    foreach ($key in $wanted) {
        Write-IwinEngineEvent @{ type = 'progress'; id = $key; phase = 'clean' }
        $freed = [long]0; $skipped = 0
        if ($key -eq 'recycleBin') {
            $before = Get-IwinRecycleBinSize
            try { Clear-RecycleBin -Force -ErrorAction Stop } catch { $skipped++ }
            $freed = [math]::Max(0, $before - (Get-IwinRecycleBinSize))
        } else {
            foreach ($file in @(Get-IwinCleanupFiles $categories[$key])) {
                try { $size = $file.Length; Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop; $freed += $size } catch { $skipped++ }
            }
        }
        Write-Log "Limpieza: $($categories[$key].label) · $([math]::Round($freed / 1MB, 1)) MB liberados · $skipped omitidos"
        $results += [ordered]@{ id = $key; freedBytes = $freed; skippedFiles = $skipped; denied = $false }
    }
    @{ categories = @($results) }
}

# Reparación de archivos de sistema: DISM y después SFC, con permiso de administrador
Register-IwinEngineCommand 'maintenance.repair' {
    param($request)
    $script = '$ErrorActionPreference=''Continue''; & DISM.exe /Online /Cleanup-Image /RestoreHealth | Out-Null; $d=$LASTEXITCODE; & sfc.exe /scannow | Out-Null; $s=$LASTEXITCODE; exit ([int]($d -ne 0) * 10 + [int]($s -ne 0))'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    Write-IwinEngineEvent @{ type = 'progress'; id = 'repair'; phase = 'run' }
    try {
        $start = @{ FilePath = 'powershell.exe'; ArgumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded); WindowStyle = 'Hidden'; Wait = $true; PassThru = $true }
        if (-not (Test-Administrator)) { $start.Verb = 'RunAs' }
        $p = Start-Process @start
    } catch { throw 'Hace falta aceptar el permiso de administrador para reparar Windows.' }
    $code = $p.ExitCode
    $text = switch ($code) {
        0 { 'Reparación terminada: DISM y SFC no encontraron problemas o los corrigieron.' }
        1 { 'DISM terminó bien; SFC encontró archivos que no pudo reparar. Reinicia y repítelo.' }
        10 { 'DISM no pudo completar la reparación (necesita conexión o Windows Update); SFC terminó.' }
        default { "La reparación no terminó (código $code). Reinicia Windows y repítela." }
    }
    Write-Log "Reparación: $text"
    @{ code = $code; text = $text; ok = $code -eq 0 }
}

# Informe del equipo: sin números de serie, nombre del equipo ni usuario salvo que se pidan
Register-IwinEngineCommand 'report.machine' {
    param($request)
    $sensitive = [bool]$request.includeSensitive
    $path = [string]$request.path
    if (-not $path) { throw [ArgumentException]'Falta la ruta del informe.' }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $disks = @(Get-CimInstance -Namespace root/Microsoft/Windows/Storage -ClassName MSFT_PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
        $entry = [ordered]@{ name = $_.FriendlyName; media = [string]$_.MediaType; sizeGB = [math]::Round($_.Size / 1GB); health = [string]$_.HealthStatus }
        if ($sensitive) { $entry.serial = [string]$_.SerialNumber }
        $entry
    })
    $document = [ordered]@{
        format = 'iWinInstaller-informe-equipo'; version = 1; createdAt = (Get-Date).ToString('o'); includeSensitive = $sensitive; app = $Version
        system = [ordered]@{ edition = [string]$os.Caption; build = [string]$os.BuildNumber; version = [string]$os.Version; architecture = [string]$env:PROCESSOR_ARCHITECTURE }
        hardware = [ordered]@{
            manufacturer = [string]$cs.Manufacturer; model = [string]$cs.Model
            cpu = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | ForEach-Object Name)
            gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object Name)
            ramGB = [math]::Round([double]$cs.TotalPhysicalMemory / 1GB)
            board = "$($board.Manufacturer) $($board.Product)".Trim(); bios = "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)".Trim()
            disks = @($disks)
        }
    }
    if ($sensitive) {
        $document.computerName = $env:COMPUTERNAME; $document.user = $env:USERNAME
        $document.hardware.serial = [string]$bios.SerialNumber; $document.hardware.boardSerial = [string]$board.SerialNumber
    }
    New-Item (Split-Path $path) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $document -Depth 6), (New-Object Text.UTF8Encoding $false))
    @{ path = $path }
}
