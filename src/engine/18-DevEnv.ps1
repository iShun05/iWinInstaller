# iWinInstaller — motor: entorno de desarrollo (Node, Python, Java) con plantillas de versiones fijadas.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
#
# Una plantilla es solo datos: ids del catálogo (apps.json, ya con su versión fijada: Python 3.13, Temurin 21…),
# la versión que se espera encontrar (pin) y pasos de configuración de una lista cerrada. Nunca se ejecuta texto
# de un archivo: los pasos son funciones de este archivo. La interfaz instala los ids con batch.run.

$IwinDevTemplates = [ordered]@{
    node = [ordered]@{
        name = 'Node.js'; desc = 'Node LTS, pnpm, Git y VS Code; activa Corepack.'
        ids = @('git', 'vscode', 'node', 'pnpm')
        pins = @([ordered]@{ app = 'node'; command = 'node'; args = @('--version'); minMajor = 22 })
        steps = @('corepack')
    }
    python = [ordered]@{
        name = 'Python'; desc = 'Python 3.13, Git y VS Code; actualiza pip.'
        ids = @('git', 'vscode', 'python')
        pins = @([ordered]@{ app = 'python'; command = 'python'; args = @('--version'); major = 3; minor = 13 })
        steps = @('pip')
    }
    java = [ordered]@{
        name = 'Java'; desc = 'JDK 21 (Temurin), Git y VS Code; fija JAVA_HOME.'
        ids = @('git', 'vscode', 'java')
        pins = @([ordered]@{ app = 'java'; command = 'java'; args = @('-version'); major = 21 })
        steps = @('javahome')
    }
}

# Versión que informa una herramienta, o $null si no está o no se puede leer
function Get-IwinToolVersion([string]$command, [string[]]$arguments) {
    if (-not (Test-Cmd $command)) { return $null }
    try {
        # java -version escribe en stderr: con «Stop» eso sería un error terminante
        $ErrorActionPreference = 'Continue'
        $text = (& $command @arguments 2>&1 | Out-String)
        # «version "21.0.5"» (o «"21"») de java manda sobre cualquier otra cifra, como las líneas «Picked up…»
        if ($text -match 'version\s+"(\d+)(?:\.(\d+))?(?:\.(\d+))?') { return [version]("$($Matches[1]).$(if ($Matches[2]) { $Matches[2] } else { 0 }).$(if ($Matches[3]) { $Matches[3] } else { 0 })") }
        if ($text -match '(\d+)\.(\d+)(?:\.(\d+))?') { return [version]("$($Matches[1]).$($Matches[2]).$(if ($Matches[3]) { $Matches[3] } else { 0 })") }
    } catch { Write-Log "  No se pudo leer la versión de ${command}: $($_.Exception.Message)" }
    $null
}

function Test-IwinDevPin($pin, $version) {
    if (-not $version) { return $false }
    if ($null -ne $pin.minMajor) { return $version.Major -ge [int]$pin.minMajor }
    if ($version.Major -ne [int]$pin.major) { return $false }
    if ($null -ne $pin.minor) { return $version.Minor -eq [int]$pin.minor }
    $true
}

function Get-IwinJdkHome {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs')) | Where-Object { $_ }) {
        $found = Get-ChildItem -LiteralPath (Join-Path $base 'Eclipse Adoptium') -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($found -and (Test-Path -LiteralPath (Join-Path $found.FullName 'bin\java.exe'))) { return $found.FullName }
    }
    $null
}

# Pasos de configuración (lista cerrada). Cada uno devuelve una línea de resumen y no falla si falta la herramienta.
$IwinDevSteps = @{
    corepack = {
        if (-not (Test-Cmd corepack)) {
            if (-not (Test-Cmd node)) { return 'Corepack: omitido (Node no está instalado todavía)' }
            # Node 25 dejó de incluir Corepack; pnpm ya viene en la plantilla como app aparte
            return 'Corepack: no viene con este Node (25 o posterior); pnpm está instalado aparte'
        }
        $out = (& corepack enable 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0) { 'Corepack activado (pnpm y yarn por proyecto)' } else { "Corepack: no se pudo activar ($out)" }
    }
    pip = {
        if (-not (Test-Cmd python)) { return 'pip: omitido (Python no está instalado todavía)' }
        $out = (& python -m pip install --user --upgrade pip 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0) { 'pip actualizado (instalación del usuario)' } else { "pip: no se pudo actualizar ($out)" }
    }
    javahome = {
        $jdk = Get-IwinJdkHome
        if (-not $jdk) { return 'JAVA_HOME: omitido (no se encuentra el JDK 21 todavía)' }
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk, 'User')
        $env:JAVA_HOME = $jdk
        "JAVA_HOME = $jdk (usuario; abre una terminal nueva)"
    }
}

function Get-IwinDevTemplate([string]$name) {
    $key = ([string]$name).ToLowerInvariant()
    if (-not $IwinDevTemplates.Contains($key)) { throw [ArgumentException]"Plantilla desconocida: $name (disponibles: $($IwinDevTemplates.Keys -join ', '))" }
    $IwinDevTemplates[$key]
}

# Estado de una plantilla: apps que faltan, versión fijada comprobada y pasos pendientes
function Get-IwinDevStatus([string]$key) {
    $template = Get-IwinDevTemplate $key
    Update-EnvPath
    $items = foreach ($id in $template.ids) {
        $app = $Apps | Where-Object id -eq $id | Select-Object -First 1
        $installed = $false
        if ($app) { try { $installed = [bool](Test-AppInstalled $app) } catch { Write-Log "  No se pudo comprobar $($app.name): $($_.Exception.Message)" } }
        [ordered]@{ id = $id; name = $(if ($app) { [string]$app.name } else { $id }); installed = $installed }
    }
    $pins = foreach ($pin in $template.pins) {
        $version = Get-IwinToolVersion $pin.command $pin.args
        $expected = if ($null -ne $pin.minMajor) { ">= $($pin.minMajor)" } elseif ($null -ne $pin.minor) { "$($pin.major).$($pin.minor)" } else { "$($pin.major)" }
        [ordered]@{ app = $pin.app; expected = $expected; found = $(if ($version) { $version.ToString() } else { $null }); ok = [bool](Test-IwinDevPin $pin $version) }
    }
    [ordered]@{
        template = $key; name = $template.name; desc = $template.desc
        items = @($items); missing = @($items | Where-Object { -not $_.installed } | ForEach-Object id)
        pins = @($pins); steps = @($template.steps)
        ready = (-not @($items | Where-Object { -not $_.installed }).Count) -and (-not @($pins | Where-Object { -not $_.ok }).Count)
    }
}

# Ejecuta los pasos de configuración de la plantilla (sin instalar nada)
function Invoke-IwinDevConfigure([string]$key) {
    $template = Get-IwinDevTemplate $key
    Update-EnvPath
    $lines = @()
    foreach ($step in $template.steps) { $lines += [string](@(& $IwinDevSteps[$step])[-1]) }
    $lines
}

Register-IwinEngineCommand 'devenv.list' {
    param($request)
    @{ templates = @($IwinDevTemplates.Keys | ForEach-Object { Get-IwinDevStatus $_ }) }
}

# Devuelve qué falta; la interfaz instala «missing» con batch.run y luego llama a devenv.configure
Register-IwinEngineCommand 'devenv.status' {
    param($request)
    Get-IwinDevStatus ([string]$request.template)
}

Register-IwinEngineCommand 'devenv.configure' {
    param($request)
    $key = ([string]$request.template).ToLowerInvariant()
    $lines = @(Invoke-IwinDevConfigure $key)
    @{ template = $key; lines = $lines; status = (Get-IwinDevStatus $key) }
}
