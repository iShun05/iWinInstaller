# iWinInstaller — motor: exportar e importar la configuración (plantilla para varios PC).
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
#
# Un archivo de configuración es un JSON de datos (nunca se evalúa como órdenes) con este esquema:
#   { "formato": "iWinInstaller-config", "version": 1, "nombre": "…", "creado": "AAAA-MM-DD", "app": "v5.4",
#     "secciones": { "perfil": {…}, "seguimiento": {…}, "exclusiones": {…}, "interfaz": {…} } }
# Es extensible: cada «sección» se registra con Register-IwinConfigSection (exportar + importar).
# Reglas de compatibilidad: una sección desconocida se ignora y se avisa; campos desconocidos dentro de
# una sección se ignoran; solo un «version» mayor que el soportado se rechaza. Cambios que rompen una
# sección se resuelven añadiendo una sección nueva, no subiendo «version».

$IwinConfigFormat = 'iWinInstaller-config'
$IwinConfigVersion = 1
$IwinConfigSections = [ordered]@{}

# Registra una sección. «export» recibe el contexto y devuelve sus datos (o $null si no hay nada que
# guardar); «import» recibe (datos, contexto), valida todo, solo escribe si $ctx.Apply y devuelve una línea
# de resumen. Contexto: Apply, IncludePersonal, ExportIds (al exportar) y Ids (apps que pide instalar).
function Register-IwinConfigSection([string]$name, [scriptblock]$export, [scriptblock]$import) {
    if ($name -notmatch '^[a-z][a-z0-9_-]{0,31}$') { throw [ArgumentException]"Nombre de sección no válido: $name" }
    $IwinConfigSections[$name] = [pscustomobject]@{ Name = $name; Export = $export; Import = $import }
}

function New-IwinConfigContext([bool]$apply, [bool]$includePersonal, $exportIds) {
    @{ Apply = $apply; IncludePersonal = $includePersonal; ExportIds = @($exportIds); Ids = (New-Object 'Collections.Generic.List[string]') }
}

# Ids del catálogo que están instalados o aplicados en este PC (apps y ajustes)
function Get-IwinInstalledIds {
    if (Test-Cmd winget) { Update-WingetCache }
    $ids = @()
    foreach ($app in $Apps) {
        try { if (Test-AppInstalled $app) { $ids += [string]$app.id } }
        catch { Write-Log "  No se pudo comprobar $($app.name): $($_.Exception.Message)" }
    }
    $ids
}

function Read-IwinConfigFile([string]$path) {
    $file = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($file.Length -gt 4MB) { throw 'El archivo es demasiado grande para ser una configuración.' }
    try { $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { throw 'El archivo no es un JSON válido.' }
    $name = Get-SafeProfileName ([string]$data.nombre)
    if (-not $name) { $name = Get-SafeProfileName ([IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '\.iwin(-config)?$', '') }
    if (-not $name) { $name = 'Configuración importada' }
    $sections = [ordered]@{}
    # Un perfil exportado con la versión anterior también se acepta: es una configuración con solo «perfil»
    if ($data.formato -eq $ProfileFormat -and $null -ne $data.apps) {
        $sections['perfil'] = [pscustomobject]@{ apps = @($data.apps | ForEach-Object { $_ }) }
        return [pscustomobject]@{ Name = $name; Version = 1; Sections = $sections; Unknown = @() }
    }
    if ($data.formato -ne $IwinConfigFormat) { throw 'No es una configuración de iWinInstaller.' }
    $version = 0
    if (-not [int]::TryParse([string]$data.version, [ref]$version) -or $version -lt 1) { throw 'La versión de la configuración no es válida.' }
    if ($version -gt $IwinConfigVersion) { throw "La configuración es de una versión más nueva ($version) que la que entiende esta app ($IwinConfigVersion). Actualiza iWinInstaller." }
    $unknown = @()
    if ($null -ne $data.secciones) {
        foreach ($property in @($data.secciones.PSObject.Properties)) {
            if ($IwinConfigSections.Contains($property.Name)) { $sections[$property.Name] = $property.Value } else { $unknown += $property.Name }
        }
    }
    [pscustomobject]@{ Name = $name; Version = $version; Sections = $sections; Unknown = @($unknown) }
}

# Crea el documento con todas las secciones; una sección que falla se omite sin perder las demás
function New-IwinConfigDocument([string]$name, $ctx) {
    $sections = [ordered]@{}
    $failed = @()
    foreach ($section in @($IwinConfigSections.Values)) {
        try { $data = & $section.Export $ctx; if ($null -ne $data) { $sections[$section.Name] = $data } }
        catch { $failed += $section.Name; Write-Log "  Sección «$($section.Name)» no exportada: $($_.Exception.Message)" }
    }
    $document = [ordered]@{ formato = $IwinConfigFormat; version = $IwinConfigVersion; nombre = $name; creado = (Get-Date -Format 'yyyy-MM-dd'); app = [string]$Version; secciones = $sections }
    [pscustomobject]@{ Document = $document; Failed = @($failed) }
}

# Aplica (o solo describe, con $apply = $false) las secciones de una configuración leída con Read-IwinConfigFile
function Invoke-IwinConfigImport($config, [bool]$apply, [string[]]$only) {
    $ctx = New-IwinConfigContext $apply $true @()
    $lines = @(); $errors = @()
    foreach ($key in @($config.Sections.Keys)) {
        if ($only -and $only -notcontains $key) { continue }
        try { $out = @(& $IwinConfigSections[$key].Import $config.Sections[$key] $ctx); $lines += [string]$out[-1] }
        catch { $errors += "${key}: $($_.Exception.Message)" }
    }
    [pscustomobject]@{ Lines = @($lines); Errors = @($errors); Ids = @($ctx.Ids); Ignored = @($config.Unknown) }
}

# ---------- Secciones ----------

# perfil: ids del catálogo (apps y ajustes). Se omiten los de otro hardware; solo lo marca para instalar.
Register-IwinConfigSection 'perfil' {
    param($ctx)
    [ordered]@{ apps = @($ctx.ExportIds | Select-Object -Unique) }
} {
    param($data, $ctx)
    $known = @{}; foreach ($app in $Apps) { $known[$app.id] = $app }
    $listed = @($data.apps | ForEach-Object { $_ })
    $ids = @($listed | Where-Object { $_ -is [string] -and $known.ContainsKey($_) } | Select-Object -Unique)
    $hardware = @(Get-HardwareText)
    $other = @($ids | Where-Object { $known[$_].hardware -and -not ($hardware -match $known[$_].hardware) })
    foreach ($id in $ids) { if ($other -notcontains $id) { $ctx.Ids.Add($id) } }
    $text = "Apps y ajustes: $($ctx.Ids.Count)"
    if ($listed.Count -ne $ids.Count) { $text += " · $($listed.Count - $ids.Count) no existen en este catálogo" }
    if ($other.Count) { $text += " · $($other.Count) omitidas por ser de otro hardware" }
    $text
}

# exclusiones: apps (id de WinGet) que se mantienen en su versión. Se suman a las de este PC.
Register-IwinConfigSection 'exclusiones' {
    param($ctx)
    $ids = @(Get-IwinExclusions)
    if (-not $ids.Count) { return $null }
    [ordered]@{ ids = $ids }
} {
    param($data, $ctx)
    $ids = @($data.ids | ForEach-Object { $_ } | Where-Object { $_ -is [string] -and $_ -match '^[\w.+-]{1,200}$' } | Select-Object -Unique)
    if ($ctx.Apply) { foreach ($id in $ids) { Set-IwinExclusion $id $true } }
    "Exclusiones de actualización: $($ids.Count)"
}

# seguimiento: pasos marcados de «Por configurar» (y notas solo con IncludePersonal). Se unen a los de este PC.
Register-IwinConfigSection 'seguimiento' {
    param($ctx)
    $state = Get-PostInstallState
    $out = [ordered]@{}
    foreach ($id in @($state.Keys | Sort-Object)) {
        if (-not ($Apps | Where-Object id -eq $id)) { continue }
        $entry = $state[$id]
        $note = [string]$entry.note
        if (-not @($entry.steps).Count -and -not ($ctx.IncludePersonal -and $note)) { continue }
        $row = [ordered]@{ pasos = @($entry.steps); guia = [string]$entry.guideHash }
        if ($ctx.IncludePersonal -and $note) { $row['nota'] = $note }
        $out[$id] = $row
    }
    if (-not $out.Count) { return $null }
    $out
} {
    param($data, $ctx)
    $script:PostInstallReadOnly = $false
    $state = try { Get-PostInstallState } catch { $script:PostInstallReadOnly = $true; throw 'El seguimiento de este PC está dañado; no se modifica para no perder tus notas.' }
    $configured = Get-IwinConfiguredApps
    $applied = 0; $skipped = 0
    foreach ($property in @($data.PSObject.Properties)) {
        $app = $Apps | Where-Object id -eq $property.Name | Select-Object -First 1
        # La guía cambió entre versiones: los números de paso ya no significan lo mismo
        if (-not $app -or $property.Name -notmatch '^[a-z0-9_-]{1,80}$' -or [string]$property.Value.guia -ne (Get-IwinGuideHash $app)) { $skipped++; continue }
        $count = @((Get-PostInstallGuide $app).steps).Count
        $incoming = @($property.Value.pasos | ForEach-Object { $_ } | Where-Object { ($_ -is [int] -or $_ -is [long]) -and $_ -ge 0 -and $_ -lt $count })
        $current = $state[$app.id]
        $steps = @(@($current.steps) + $incoming | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ } | Select-Object -Unique | Sort-Object)
        $note = [string]$current.note
        if (-not $note) { $note = [string]$property.Value.nota }
        if ($note.Length -gt 2000) { $note = $note.Substring(0, 2000) }
        $state[$app.id] = @{ steps = @($steps); guideHash = (Get-IwinGuideHash $app); note = $note }
        $configured[$app.id] = ($steps.Count -eq $count)
        $applied++
    }
    if ($ctx.Apply -and $applied) {
        $script:PostInstallState = $state
        Save-PostInstallState
        Write-IwinJson (Join-Path $LogDir 'configuracion.json') $configured
    }
    $text = "Seguimiento de configuración: $applied apps"
    if ($skipped) { $text += " · $skipped omitidas (guía distinta o app desconocida)" }
    $text
}

# interfaz: zoom (y servidor del juego solo con IncludePersonal). La app lo lee al abrirse.
function Get-IwinInterfacePath { Join-Path $LogDir 'interfaz.json' }
function Read-IwinInterface {
    $path = Get-IwinInterfacePath
    $result = [ordered]@{}
    if (Test-Path -LiteralPath $path) {
        try { foreach ($property in @((Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties)) { $result[$property.Name] = $property.Value } }
        catch { Write-Log '  Preferencias de la interfaz ilegibles: se ignoran.' }
    }
    $result
}
Register-IwinConfigSection 'interfaz' {
    param($ctx)
    $current = Read-IwinInterface
    $out = [ordered]@{}
    if ($null -ne $current['zoom']) { $out['zoom'] = $current['zoom'] }
    if ($ctx.IncludePersonal -and $current['gameServer']) { $out['servidorJuego'] = [string]$current['gameServer'] }
    if (-not $out.Count) { return $null }
    $out
} {
    param($data, $ctx)
    $change = [ordered]@{}
    if ($null -ne $data.zoom) {
        $zoom = 0.0
        if ([double]::TryParse([string]$data.zoom, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$zoom) -and -not [double]::IsNaN($zoom) -and -not [double]::IsInfinity($zoom)) {
            $change['zoom'] = [math]::Round([math]::Min(2.0, [math]::Max(0.7, $zoom)) * 10) / 10
        }
    }
    $server = [string]$data.servidorJuego
    if ($server -and $server.Length -le 253 -and $server -match '^[A-Za-z0-9._:\[\]-]+$') { $change['gameServer'] = $server }
    if ($ctx.Apply -and $change.Count) {
        $current = Read-IwinInterface
        $current['format'] = 'iWinInstaller-interfaz'
        if (-not $current['version']) { $current['version'] = 1 }
        foreach ($key in $change.Keys) { $current[$key] = $change[$key] }
        Write-IwinJson (Get-IwinInterfacePath) $current
    }
    "Interfaz: $($change.Count) valores (se ven al abrir la app)"
}

# ---------- Comandos del contrato ----------

Register-IwinEngineCommand 'config.export' {
    param($request)
    $path = [string]$request.path
    if (-not $path) { throw [ArgumentException]'Falta la ruta.' }
    $ids = if ($request.ids) { @(Get-IwinSelection @($request.ids) | ForEach-Object id) } else { @(Get-IwinInstalledIds) }
    $name = Get-SafeProfileName ([string]$request.name)
    if (-not $name) { $name = Get-SafeProfileName ([IO.Path]::GetFileNameWithoutExtension($path) -replace '\.iwin(-config)?$', '') }
    if (-not $name) { $name = 'Configuración' }
    $ctx = New-IwinConfigContext $false ([bool]$request.includePersonal) $ids
    $built = New-IwinConfigDocument $name $ctx
    Write-IwinJson $path $built.Document
    @{ path = $path; name = $name; count = $ids.Count; sections = @($built.Document.secciones.Keys); failed = @($built.Failed) }
}

# Describe qué haría una configuración sin cambiar nada
Register-IwinEngineCommand 'config.inspect' {
    param($request)
    if (-not (Test-Path -LiteralPath ([string]$request.path))) { throw [ArgumentException]'No existe ese archivo.' }
    $config = try { Read-IwinConfigFile ([string]$request.path) } catch { throw [ArgumentException]$_.Exception.Message }
    $plan = Invoke-IwinConfigImport $config $false $null
    @{ name = $config.Name; version = $config.Version; sections = @($config.Sections.Keys); ignored = $plan.Ignored; lines = $plan.Lines; errors = $plan.Errors; ids = $plan.Ids }
}

# Aplica las secciones que no instalan; devuelve los ids para que la interfaz los instale con batch.run
Register-IwinEngineCommand 'config.import' {
    param($request)
    if (-not (Test-Path -LiteralPath ([string]$request.path))) { throw [ArgumentException]'No existe ese archivo.' }
    $config = try { Read-IwinConfigFile ([string]$request.path) } catch { throw [ArgumentException]$_.Exception.Message }
    $plan = Invoke-IwinConfigImport $config $true @($request.sections | Where-Object { $_ })
    @{ name = $config.Name; ignored = $plan.Ignored; lines = $plan.Lines; errors = $plan.Errors; ids = $plan.Ids }
}
