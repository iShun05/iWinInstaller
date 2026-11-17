# iWinInstaller — motor: ordenar las apps instaladas en carpetas por categoría (sin publicar).
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
#
# Windows 11 no ofrece una API soportada para crear carpetas de anclados en Inicio. Lo que sí se puede es crear
# subcarpetas en «Programas» del menú Inicio (se ven en «Todo» con la vista Lista) y una carpeta en el escritorio.
# Reglas de seguridad:
#  - Opcional: nada se mueve hasta que el usuario lo pide (botón «Ordenar») o activa el orden automático.
#  - Solo se mueven accesos .lnk que están directamente en «Programas» (nunca las carpetas de cada fabricante).
#  - Todo lo que se mueve o copia queda en %LOCALAPPDATA%\iWinInstaller\carpetas.json, así «Deshacer» lo devuelve.
#  - Los accesos del escritorio son copias del acceso de Inicio; los que Organize-Desktop dejó en «Aplicaciones» se
#    adoptan (se mueven a su categoría) y al deshacer vuelven a «Aplicaciones».
#  - Si una actualización recrea el acceso original, «Reordenar» lo vuelve a colocar.

$IwinFoldersDesktopName = 'Aplicaciones'
$IwinFoldersSkipPattern = '(?i)uninstall|desinstal|readme|léeme|leeme|\bhelp\b|ayuda|documentaci|manual|release notes|notas de la versi'

function Get-IwinFoldersPath { Join-Path $LogDir 'carpetas.json' }

# Estado guardado: preferencias y lo que se movió o copió. Si el archivo está dañado no se toca (se avisa).
function Read-IwinFoldersState {
    $state = @{ auto = $false; startMenu = $true; desktop = $true; moves = @(); copies = @() }
    $path = Get-IwinFoldersPath
    if (-not (Test-Path -LiteralPath $path)) { return $state }
    try { $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'El registro de carpetas está dañado; no se modifica para no perder lo que se movió.' }
    if ($null -ne $data.auto) { $state.auto = [bool]$data.auto }
    if ($null -ne $data.startMenu) { $state.startMenu = [bool]$data.startMenu }
    if ($null -ne $data.desktop) { $state.desktop = [bool]$data.desktop }
    $state.moves = @($data.moves | Where-Object { $_ } | ForEach-Object { @{ id = [string]$_.id; from = [string]$_.from; to = [string]$_.to } })
    $state.copies = @($data.copies | Where-Object { $_ } | ForEach-Object { @{ id = [string]$_.id; path = [string]$_.path; adoptedFrom = [string]$_.adoptedFrom } })
    $state
}

function Save-IwinFoldersState($state) {
    Write-IwinJson (Get-IwinFoldersPath) ([ordered]@{
        version = 1; auto = [bool]$state.auto; startMenu = [bool]$state.startMenu; desktop = [bool]$state.desktop
        moves = @($state.moves); copies = @($state.copies)
    })
}

function Get-IwinFolderName([string]$group) {
    $name = ($group -replace '[\\/:*?"<>|]', '-').Trim().TrimEnd('.')
    if ($name) { $name } else { 'Otras apps' }
}

# Carpetas «Programas» del menú Inicio: del usuario y del equipo
function Get-IwinProgramsRoots {
    $roots = [ordered]@{}
    $user = [Environment]::GetFolderPath('Programs'); if ($user) { $roots['user'] = $user }
    $machine = [Environment]::GetFolderPath('CommonPrograms'); if ($machine) { $roots['machine'] = $machine }
    $roots
}

# Plan: a qué categoría va el acceso de cada app. Solo apps con un acceso .lnk en «Programas» (o en una carpeta que
# se llama igual que la app). Primero coincidencia exacta de nombre; luego, solo para apps instaladas, por prefijo.
# «Direct» es $true si el .lnk está directamente en «Programas» (único caso en que se mueve).
function Get-IwinFolderPlan($apps, $roots, [scriptblock]$isInstalled) {
    $candidates = @()
    foreach ($scope in @($roots.Keys)) {
        $root = $roots[$scope]
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter *.lnk -File -ErrorAction SilentlyContinue)) {
            $candidates += [pscustomobject]@{ Scope = $scope; Root = $root; Path = $file.FullName; Base = $file.BaseName; Direct = $true }
        }
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            foreach ($file in @(Get-ChildItem -LiteralPath $dir.FullName -Filter *.lnk -File -ErrorAction SilentlyContinue)) {
                $candidates += [pscustomobject]@{ Scope = $scope; Root = $root; Path = $file.FullName; Base = $file.BaseName; Direct = $false; Folder = $dir.Name }
            }
        }
    }
    # Un acceso que ya está en una carpeta de categoría de iWinInstaller no es candidato (ya está ordenado)
    $candidates = @($candidates | Where-Object { $_.Base -notmatch $IwinFoldersSkipPattern })
    $claimed = @{}
    $plan = @()
    $pending = @($apps | Where-Object { $_.type -ne 'tweak' -and $_.group })
    $rest = @()
    foreach ($app in $pending) {
        $names = @($app.name) + @($app.detectNames) | Where-Object { $_ }
        $hit = $null
        foreach ($candidate in $candidates) {
            if ($claimed.ContainsKey($candidate.Path)) { continue }
            if ($candidate.Direct -and @($names | Where-Object { $_ -eq $candidate.Base }).Count) { $hit = $candidate; break }
        }
        if (-not $hit) {
            foreach ($candidate in $candidates) {
                if ($claimed.ContainsKey($candidate.Path) -or $candidate.Direct) { continue }
                if (@($names | Where-Object { $_ -eq $candidate.Base -or $_ -eq $candidate.Folder }).Count) { $hit = $candidate; break }
            }
        }
        if ($hit) { $claimed[$hit.Path] = $true; $plan += [pscustomobject]@{ Id = [string]$app.id; Name = [string]$app.name; Category = (Get-IwinFolderName $app.group); Source = $hit.Path; Scope = $hit.Scope; Root = $hit.Root; Direct = $hit.Direct } }
        else { $rest += $app }
    }
    foreach ($app in $rest) {
        $installed = $false
        if ($isInstalled) { try { $installed = [bool](& $isInstalled $app) } catch { } }
        if (-not $installed) { continue }
        $hit = $candidates | Where-Object { -not $claimed.ContainsKey($_.Path) -and ($_.Base.StartsWith($app.name, [StringComparison]::OrdinalIgnoreCase) -or $app.name.StartsWith($_.Base + ' ', [StringComparison]::OrdinalIgnoreCase)) } |
            Sort-Object { $_.Base.Length } | Select-Object -First 1
        if ($hit) { $claimed[$hit.Path] = $true; $plan += [pscustomobject]@{ Id = [string]$app.id; Name = [string]$app.name; Category = (Get-IwinFolderName $app.group); Source = $hit.Path; Scope = $hit.Scope; Root = $hit.Root; Direct = $hit.Direct } }
    }
    $plan
}

function Get-IwinDesktopFoldersRoot { Join-Path ([Environment]::GetFolderPath('Desktop')) $IwinFoldersDesktopName }

# Ejecuta el plan. $options: StartMenu, Desktop, Scope ('all' o 'machine'), DesktopRoot. Devuelve contadores.
function Invoke-IwinFolderApply($plan, $options, $state) {
    $result = @{ moved = 0; copied = 0; adopted = 0; skipped = 0; needsAdmin = 0 }
    $admin = Test-Administrator
    $scopeOnly = if ($options.Scope -eq 'machine') { 'machine' } else { '' }
    foreach ($entry in $plan) {
        if ($scopeOnly -and $entry.Scope -ne $scopeOnly) { continue }
        $current = $entry.Source
        if ($options.StartMenu -and $entry.Direct) {
            if ($entry.Scope -eq 'machine' -and -not $admin) { $result.needsAdmin++ }
            else {
                try {
                    $folder = Join-Path $entry.Root $entry.Category
                    New-Item $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    $target = Join-Path $folder (Split-Path -Leaf $entry.Source)
                    Move-Item -LiteralPath $entry.Source -Destination $target -Force -ErrorAction Stop
                    $state.moves = @($state.moves | Where-Object { $_.to -ne $target }) + @(@{ id = $entry.Id; from = $entry.Source; to = $target })
                    $current = $target
                    $result.moved++
                } catch { $result.skipped++; Write-Log "  Acceso conservado en Inicio ($($entry.Name)): $($_.Exception.Message)" }
            }
        }
        if ($options.Desktop -and $options.DesktopRoot -and $scopeOnly -ne 'machine') {
            try {
                $folder = Join-Path $options.DesktopRoot $entry.Category
                $target = Join-Path $folder (Split-Path -Leaf $entry.Source)
                $flat = Join-Path $options.DesktopRoot (Split-Path -Leaf $entry.Source)
                New-Item $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                if (Test-Path -LiteralPath $target) { continue }
                $known = @($state.copies | Where-Object { $_.path -eq $target })
                if (Test-Path -LiteralPath $flat) {
                    # Lo dejó Organize-Desktop: se adopta (se mueve a su categoría) y al deshacer vuelve aquí
                    Move-Item -LiteralPath $flat -Destination $target -ErrorAction Stop
                    $state.copies = @($state.copies | Where-Object { $_.path -ne $target }) + @(@{ id = $entry.Id; path = $target; adoptedFrom = $flat })
                    $result.adopted++
                } elseif (Test-Path -LiteralPath $current) {
                    Copy-Item -LiteralPath $current -Destination $target -ErrorAction Stop
                    $state.copies = @($state.copies | Where-Object { $_.path -ne $target }) + @(@{ id = $entry.Id; path = $target; adoptedFrom = '' })
                    $result.copied++
                }
            } catch { $result.skipped++; Write-Log "  Acceso no copiado al escritorio ($($entry.Name)): $($_.Exception.Message)" }
        }
    }
    $result
}

function Remove-IwinEmptyFolder([string]$path) {
    if ($path -and (Test-Path -LiteralPath $path) -and -not @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue).Count) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

# Devuelve todo a su sitio según el registro; nunca toca lo que no movió o copió iWinInstaller.
function Invoke-IwinFolderRevert($state, [string]$scope = 'all') {
    $result = @{ restored = 0; removed = 0; skipped = 0; needsAdmin = 0 }
    $admin = Test-Administrator
    $keep = @()
    foreach ($move in @($state.moves)) {
        $machine = $move.from -like ((Get-IwinMachineProgramsPattern))
        if ($scope -eq 'machine' -and -not $machine) { $keep += $move; continue }
        if ($machine -and -not $admin) { $result.needsAdmin++; $keep += $move; continue }
        try {
            if (-not (Test-Path -LiteralPath $move.to)) { continue }
            if (Test-Path -LiteralPath $move.from) { Remove-Item -LiteralPath $move.to -Force -ErrorAction Stop }
            else { Move-Item -LiteralPath $move.to -Destination $move.from -ErrorAction Stop }
            $result.restored++
            Remove-IwinEmptyFolder (Split-Path -Parent $move.to)
        } catch { $result.skipped++; $keep += $move; Write-Log "  No se pudo devolver $($move.to): $($_.Exception.Message)" }
    }
    $state.moves = @($keep)
    if ($scope -ne 'machine') {
        $desktopKeep = @()
        foreach ($copy in @($state.copies)) {
            try {
                if (Test-Path -LiteralPath $copy.path) {
                    if ($copy.adoptedFrom) {
                        New-Item (Split-Path -Parent $copy.adoptedFrom) -ItemType Directory -Force | Out-Null
                        if (-not (Test-Path -LiteralPath $copy.adoptedFrom)) { Move-Item -LiteralPath $copy.path -Destination $copy.adoptedFrom -ErrorAction Stop; $result.restored++ }
                        else { Remove-Item -LiteralPath $copy.path -Force -ErrorAction Stop; $result.removed++ }
                    } else { Remove-Item -LiteralPath $copy.path -Force -ErrorAction Stop; $result.removed++ }
                }
                Remove-IwinEmptyFolder (Split-Path -Parent $copy.path)
            } catch { $result.skipped++; $desktopKeep += $copy; Write-Log "  No se pudo quitar $($copy.path): $($_.Exception.Message)" }
        }
        $state.copies = @($desktopKeep)
    }
    $result
}

function Get-IwinMachineProgramsPattern {
    $machine = [Environment]::GetFolderPath('CommonPrograms')
    if ($machine) { ($machine.TrimEnd('\', '/') -replace '([\[\]\*\?])', '`$1') + '*' } else { '\0never\0' }
}

# Una sola solicitud de administrador para lo que vive en «Programas» del equipo (mismo patrón que la limpieza)
function Invoke-IwinFoldersElevated([string]$command, [hashtable]$body) {
    $work = Join-Path $LogDir ('carpetas-' + [guid]::NewGuid().ToString('N'))
    New-Item $work -ItemType Directory -Force | Out-Null
    $req = Join-Path $work 'request.json'; $res = Join-Path $work 'response.json'
    $body['contract'] = 1; $body['scope'] = 'machine'
    [IO.File]::WriteAllText($req, (ConvertTo-Json $body), (New-Object Text.UTF8Encoding $false))
    try {
        $p = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $Root 'iWinInstaller.ps1')`"", '-EngineCommand', $command, '-EngineRequest', "`"$req`"", '-EngineResponse', "`"$res`"")
        $p.ExitCode -eq 0 -and (Test-Path $res)
    } catch { $false } finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-IwinFoldersSummary($result) {
    $parts = @()
    if ($result.moved) { $parts += "$($result.moved) accesos de Inicio ordenados" }
    if ($result.copied) { $parts += "$($result.copied) copiados al escritorio" }
    if ($result.adopted) { $parts += "$($result.adopted) del escritorio recolocados" }
    if ($result.skipped) { $parts += "$($result.skipped) omitidos" }
    if ($parts) { $parts -join ' · ' } else { 'Nada que ordenar: no hay accesos nuevos.' }
}

function Invoke-IwinFoldersOrganize($request) {
    $state = Read-IwinFoldersState
    $startMenu = if ($null -ne $request.startMenu) { [bool]$request.startMenu } else { [bool]$state.startMenu }
    $desktop = if ($null -ne $request.desktop) { [bool]$request.desktop } else { [bool]$state.desktop }
    $scope = if ($request.scope -eq 'machine') { 'machine' } else { 'all' }
    $options = @{ StartMenu = $startMenu; Desktop = $desktop; Scope = $scope; DesktopRoot = (Get-IwinDesktopFoldersRoot) }
    $plan = @(Get-IwinFolderPlan $Apps (Get-IwinProgramsRoots) { param($app) Test-AppInstalled $app })
    $denied = $false
    # Accesos del equipo: si no hay permiso, un proceso elevado los mueve y luego se relee el registro
    if ($scope -eq 'all' -and $startMenu -and -not (Test-Administrator) -and @($plan | Where-Object { $_.Scope -eq 'machine' -and $_.Direct }).Count) {
        if (Invoke-IwinFoldersElevated 'folders.apply' @{ startMenu = $true; desktop = $false }) { $state = Read-IwinFoldersState } else { $denied = $true }
        $plan = @(Get-IwinFolderPlan $Apps (Get-IwinProgramsRoots) { param($app) Test-AppInstalled $app })
    }
    $result = Invoke-IwinFolderApply $plan $options $state
    Save-IwinFoldersState $state
    $summary = Get-IwinFoldersSummary $result
    if ($denied) { $summary += ' · No se aceptó el permiso: los accesos del equipo siguen donde estaban.' }
    $result.denied = $denied; $result.summary = $summary
    $result
}

# Tras instalar: si el orden automático está activo, coloca los accesos nuevos. Nunca interrumpe la instalación.
function Invoke-IwinFoldersAuto {
    if ($WorkerMode) { return }
    try {
        $state = Read-IwinFoldersState
        if (-not $state.auto) { return }
        $result = Invoke-IwinFoldersOrganize ([pscustomobject]@{ contract = 1 })
        Write-Log "Carpetas por categoría: $($result.summary)"
    } catch { Write-Log "  No se pudo ordenar en carpetas: $($_.Exception.Message)" }
}

# ---------- Comandos del contrato ----------

Register-IwinEngineCommand 'folders.status' {
    param($request)
    $state = Read-IwinFoldersState
    $plan = @(Get-IwinFolderPlan $Apps (Get-IwinProgramsRoots) { param($app) Test-AppInstalled $app })
    $categories = @($plan | Group-Object Category | Sort-Object Name | ForEach-Object { [ordered]@{ name = $_.Name; count = $_.Count } })
    @{
        auto = [bool]$state.auto; startMenu = [bool]$state.startMenu; desktop = [bool]$state.desktop
        moved = @($state.moves).Count; copied = @($state.copies).Count
        pending = @($plan).Count
        categories = $categories; desktopFolder = (Get-IwinDesktopFoldersRoot)
    }
}

Register-IwinEngineCommand 'folders.set' {
    param($request)
    $state = Read-IwinFoldersState
    if ($null -ne $request.auto) { $state.auto = [bool]$request.auto }
    if ($null -ne $request.startMenu) { $state.startMenu = [bool]$request.startMenu }
    if ($null -ne $request.desktop) { $state.desktop = [bool]$request.desktop }
    Save-IwinFoldersState $state
    @{ auto = $state.auto; startMenu = $state.startMenu; desktop = $state.desktop }
}

# «Ordenar» y «Reordenar» son el mismo comando: vuelve a colocar lo que una actualización haya recreado
Register-IwinEngineCommand 'folders.apply' {
    param($request)
    $r = Invoke-IwinFoldersOrganize $request
    @{ moved = $r.moved; copied = $r.copied; adopted = $r.adopted; skipped = $r.skipped; needsAdmin = $r.needsAdmin; denied = [bool]$r.denied; summary = $r.summary }
}

Register-IwinEngineCommand 'folders.revert' {
    param($request)
    $state = Read-IwinFoldersState
    $scope = if ($request.scope -eq 'machine') { 'machine' } else { 'all' }
    $denied = $false
    if ($scope -eq 'all' -and -not (Test-Administrator) -and @($state.moves | Where-Object { $_.from -like (Get-IwinMachineProgramsPattern) }).Count) {
        if (Invoke-IwinFoldersElevated 'folders.revert' @{}) { $state = Read-IwinFoldersState } else { $denied = $true }
    }
    $r = Invoke-IwinFolderRevert $state $scope
    Save-IwinFoldersState $state
    $summary = "$($r.restored) accesos devueltos a su sitio · $($r.removed) copias quitadas" + $(if ($r.skipped) { " · $($r.skipped) sin poder deshacer" } else { '' }) + $(if ($denied) { ' · No se aceptó el permiso: los accesos del equipo siguen ordenados.' } else { '' })
    @{ restored = $r.restored; removed = $r.removed; skipped = $r.skipped; denied = $denied; summary = $summary }
}
