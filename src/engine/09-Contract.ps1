# iWinInstaller — motor: contrato interfaz ↔ motor (specs/001-centro-de-control/contracts/engine.md).
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
# La interfaz escribe un Request JSON, lanza el motor con -EngineCommand y lee Response y Events.

$IwinContractVersion = 1
$IwinEngineCommands = [ordered]@{}

# Registra un comando del contrato: nombre → bloque que recibe el Request y devuelve el Response
function Register-IwinEngineCommand([string]$name, [scriptblock]$handler) { $IwinEngineCommands[$name] = $handler }

function Write-IwinEngineEvent([hashtable]$data) {
    if (-not $script:EngineEventsPath) { return }
    $event = [ordered]@{ t = (Get-Date).ToUniversalTime().ToString('o') }
    foreach ($key in $data.Keys) { $event[$key] = $data[$key] }
    $line = (ConvertTo-Json -InputObject $event -Compress -Depth 6) + "`n"
    # UTF-8 sin BOM y con reintentos: la interfaz lee el archivo mientras se escribe
    for ($try = 0; $try -lt 5; $try++) {
        try { [IO.File]::AppendAllText($script:EngineEventsPath, $line, (New-Object Text.UTF8Encoding $false)); return }
        catch { Start-Sleep -Milliseconds 50 }
    }
}

function Write-IwinEngineResponse([string]$path, $response) {
    $document = [ordered]@{ contract = $IwinContractVersion }
    foreach ($key in $response.Keys) { $document[$key] = $response[$key] }
    $temporary = "$path.tmp"
    [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $document -Depth 8), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

# Ejecuta un comando y devuelve el código de salida del contrato (0, 2, 3, 4 o 10)
function Invoke-IwinEngineCommand([string]$command, [string]$requestPath, [string]$responsePath, [string]$eventsPath) {
    $script:EngineEventsPath = $eventsPath
    $code = 10; $outcome = 'failed'
    try {
        if (-not $responsePath) { throw [ArgumentException]'Falta -Response.' }
        if (-not $IwinEngineCommands.Contains($command)) { throw [ArgumentException]"Comando desconocido: $command" }
        $request = [pscustomobject]@{ contract = $IwinContractVersion }
        if ($requestPath) {
            if (-not (Test-Path -LiteralPath $requestPath)) { throw [ArgumentException]'No existe el archivo de Request.' }
            $request = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        }
        if ($null -eq $request.contract -or [int]$request.contract -gt $IwinContractVersion) {
            throw [ArgumentException]"Versión de contrato no admitida: $($request.contract)"
        }
        $response = & $IwinEngineCommands[$command] $request
        Write-IwinEngineResponse $responsePath $response
        $code = 0; $outcome = 'success'
    } catch [ArgumentException] {
        $code = 2
        Write-IwinEngineEvent @{ type = 'log'; level = 'error'; text = $_.Exception.Message }
    } catch [Management.Automation.RuntimeException] {
        # ConvertFrom-Json con JSON roto también es un Request inválido
        $code = if ($_.FullyQualifiedErrorId -match 'ConvertFromJson') { 2 } else { 10 }
        Write-IwinEngineEvent @{ type = 'log'; level = 'error'; text = $_.Exception.Message }
    } catch {
        Write-IwinEngineEvent @{ type = 'log'; level = 'error'; text = $_.Exception.Message }
    } finally {
        # «done» es siempre el último evento
        Write-IwinEngineEvent @{ type = 'done'; outcome = $outcome; exitCode = $code }
    }
    $code
}

# ---------- Comandos disponibles ----------

Register-IwinEngineCommand 'catalog.inventory' {
    param($request)
    $wanted = @($request.ids | Where-Object { $_ })
    $selection = if ($wanted) { @($Apps | Where-Object { $wanted -contains $_.id }) } else { $Apps }
    if (Test-Cmd winget) { Update-WingetCache }
    $items = foreach ($app in $selection) {
        Write-IwinEngineEvent @{ type = 'progress'; id = $app.id; phase = 'check' }
        $installed = $null; $checkable = $true
        try { $installed = [bool](Test-AppInstalled $app) } catch { $checkable = $false }
        [ordered]@{ id = $app.id; installed = $installed; checkable = $checkable }
    }
    @{ items = @($items) }
}

Register-IwinEngineCommand 'batch.pending' {
    param($request)
    $batches = foreach ($pending in @(Get-IwinPendingBatches)) {
        $data = $pending.Data
        [ordered]@{
            path = $pending.Path
            operation = $data.operation
            pending = @($data.items | Where-Object state -ne 'done' | ForEach-Object id)
            done = @($data.items | Where-Object state -eq 'done' | ForEach-Object id)
        }
    }
    @{ batches = @($batches) }
}

Register-IwinEngineCommand 'report.last' {
    param($request)
    $report = Get-IwinLastReport
    if (-not $report) { return @{ report = $null; summary = $null } }
    @{ report = $report; summary = (Get-IwinReportSummary $report); text = (Format-IwinReportText $report) }
}
