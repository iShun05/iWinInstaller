# iWinInstaller — motor: ordenar las apps del menú Inicio y del escritorio en carpetas por categoría.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
#
# Windows 11 no ofrece una API soportada para crear carpetas de anclados en Inicio. Lo que sí se puede es crear
# subcarpetas en «Programas» del menú Inicio (se ven en «Todo» con la vista Lista o Cuadrícula) y una carpeta en el
# escritorio. Comprobado en Windows 11 (build 26300):
#  - Inicio solo muestra un nivel de carpetas: lo que hay en subcarpetas aparece dentro de la carpeta de primer nivel,
#    así que la carpeta de cada fabricante se puede meter entera dentro de su categoría.
#  - Una carpeta con un solo acceso se muestra como app suelta; las carpetas del usuario y del equipo con el mismo
#    nombre se juntan.
#  - Las apps de la Tienda (MSIX) salen siempre sueltas: un acceso a ellas en una carpeta solo crea un duplicado.
#    Por eso en Inicio no se tocan, y en el escritorio sí se crea su acceso dentro de su categoría.
# Reglas de seguridad:
#  - Nada se mueve hasta que el usuario lo pide («Comprobar y organizar») o deja activo el orden automático.
#  - Nunca se tocan las carpetas de Windows (Accesibilidad, Inicio automático, Herramientas…) ni los accesos que
#    apuntan a Windows. Se mueven los accesos sueltos y las carpetas de cada fabricante, del usuario y del equipo.
#  - Desinstaladores, ayudas y webs se guardan aparte (fuera de Inicio), no se borran.
#  - Todo queda en %LOCALAPPDATA%\iWinInstaller\carpetas.json, así «Deshacer» lo devuelve a su sitio.
#  - Si una actualización recrea un acceso, «Comprobar y organizar» lo vuelve a colocar y quita la copia vieja.

$IwinFoldersDesktopName = 'Aplicaciones'
$IwinFoldersOthersName = 'Otras apps'
# Accesos que no son la app: desinstaladores, ayuda, documentación y webs
$IwinFoldersSkipPattern = '(?i)^(uninstall|desinstalar|remove|quitar)\b|\b(readme|léeme|leeme|help|ayuda|documentaci[oó]n|documentation|docs?|manuals?|faqs?|license|licencia|release notes|notas de la versi[oó]n|website|sitio web|web site|support center)\b|^visit\b|\ben la web$'
$IwinFoldersSecondary = '(?i)\b(reset|config\w*|command line|command prompt|prompt|cmd|skinned|spy|shell|settings|installer|tools?|debug\w*|depurador)\b'
$IwinFoldersExtraTargets ='(?i)\\(unins\d*|uninst|uninstall|uninstaller)\.exe$|\.(html?|pdf|chm|txt|rtf|md|ini|log)$'
# Carpetas propias de Windows en «Programas» (nombre en disco, sin traducir)
$IwinFoldersSystem = @('Accessibility', 'Accessories', 'Administrative Tools', 'Maintenance', 'Startup', 'System Tools',
    'Windows PowerShell', 'Windows Accessories', 'Windows Administrative Tools', 'Windows Ease of Access', 'Windows System',
    'Windows Tools', 'Tablet PC', 'Immersive Control Panel')
# Accesos de Windows sueltos en «Programas» que se dejan donde están
$IwinFoldersSystemLinks = @('File Explorer', 'Explorador de archivos', 'Administrative Tools', 'Herramientas de Windows', 'Windows Tools',
    'Control Panel', 'Panel de control', 'Run', 'Ejecutar', 'Command Prompt', 'Símbolo del sistema', 'Task Manager', 'Administrador de tareas')
# Apps que no son del catálogo: categoría por palabras clave (nombre de la carpeta, del acceso y ruta del programa)
$IwinFoldersGuesses = @(
    @('IA', '(?i)\b(chatgpt|copilot|claude|gemini|codex|ollama|lm studio|perplexity)\b'),
    @('Navegadores', '(?i)\b(brave|chrome|chromium|firefox|microsoft edge|opera|vivaldi|zen browser|librewolf|tor browser|browser|navegador)\b'),
    @('Juegos', '(?i)\b(steam|epic games|riot|league of legends|valorant|fortnite|epicgames|hoyoplay|honkai|genshin|battle\.net|ubisoft|ea app|gog galaxy|xbox|minecraft|wallpaper engine|games?)\b'),
    @('Drivers y componentes', '(?i)\b(driver|nvidia|geforce|radeon|amd software|intel.*(graphics|driver)|nvcleanstall|redistributable|runtime)\b'),
    @('Mantenimiento y hardware', '(?i)\b(cpu-z|gpu-z|hwinfo|hwmonitor|crystaldisk\w*|wiztree|treesize|memtest|occt|afterburner|disk|benchmark)\b'),
    @('Bases de datos', '(?i)\b(mysql|postgres\w*|pgadmin|mongodb|sqlite|dbeaver|sql server)\b'),
    @('Desarrollo', '(?i)\b(visual studio|android studio|jetbrains|intellij|pycharm|docker|github|gitkraken|sdk|postman|mobaxterm|putty|winscp|sublime|notepad\+\+|cursor|antigravity)\b'),
    @('Consola y shells', '(?i)\b(powershell|terminal|wsl|ubuntu|debian|kali|clink|git bash|cmder)\b'),
    @('Lenguajes y entornos', '(?i)\b(python|idle|node\.js|nodejs|java|jdk|ruby|golang|rust|dotnet|\.net)\b'),
    @('Virtualización', '(?i)\b(virtualbox|vmware|hyper-v|virt-manager|sandboxie)\b'),
    @('Seguridad y redes', '(?i)\b(vpn|wireshark|tailscale|nmap|firewall|bitwarden|keepass|malwarebytes|defender)\b'),
    @('Comunicación', '(?i)\b(whatsapp|telegram|teams|discord|zoom|slack|signal|skype|outlook|thunderbird|mail)\b'),
    @('Multimedia', '(?i)\b(vlc|spotify|media player|reproductor|music|obs studio|audacity|handbrake|plex|kodi|foobar)\b'),
    @('Diseño y foto', '(?i)\b(photoshop|gimp|krita|inkscape|blender|figma|paint\.net|lightroom|affinity|canva)\b'),
    @('Ofimática y estudio', '(?i)\b(office|word|excel|powerpoint|libreoffice|onlyoffice|acrobat|pdf|autofirma|zotero|anki)\b'),
    @('Almacenamiento y nube', '(?i)\b(icloud|google drive|dropbox|onedrive|mega|nextcloud|syncthing|backup)\b'),
    @('Utilidades', '(?i)\b(autohotkey|powertoys|everything|7-zip|winrar|sharex|bulk rename|utility|tools?)\b'))

function Get-IwinFoldersPath { Join-Path $LogDir 'carpetas.json' }

# Estado guardado: preferencias y lo que se movió o copió. Si el archivo está dañado no se toca (se avisa).
function Read-IwinFoldersState {
    # Sin registro previo el orden automático viene activo (v5.5): era lo pedido y antes nunca llegaba a ejecutarse.
    # Sigue siendo reversible y se apaga en Mantenimiento; con registro, manda lo que el usuario guardó.
    $state = @{ auto = $true; startMenu = $true; desktop = $true; others = $true; extras = $true; moves = @(); copies = @() }
    $path = Get-IwinFoldersPath
    if (-not (Test-Path -LiteralPath $path)) { return $state }
    try { $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'El registro de carpetas está dañado; no se modifica para no perder lo que se movió.' }
    foreach ($flag in 'auto', 'startMenu', 'desktop', 'others', 'extras') { if ($null -ne $data.$flag) { $state[$flag] = [bool]$data.$flag } }
    $state.moves = @($data.moves | Where-Object { $_ } | ForEach-Object {
            $kind = if ($_.kind) { [string]$_.kind } else { 'file' }
            @{ id = [string]$_.id; kind = $kind; from = [string]$_.from; to = [string]$_.to } })
    $state.copies = @($data.copies | Where-Object { $_ } | ForEach-Object { @{ id = [string]$_.id; path = [string]$_.path; adoptedFrom = [string]$_.adoptedFrom } })
    $state
}

function Save-IwinFoldersState($state) {
    Write-IwinJson (Get-IwinFoldersPath) ([ordered]@{
            version = 2; auto = [bool]$state.auto; startMenu = [bool]$state.startMenu; desktop = [bool]$state.desktop
            others = [bool]$state.others; extras = [bool]$state.extras
            moves = @($state.moves); copies = @($state.copies)
        })
}

function Get-IwinFolderName([string]$group) {
    $name = ($group -replace '[\\/:*?"<>|]', '-').Trim().TrimEnd('.')
    if ($name) { $name } else { $IwinFoldersOthersName }
}

# Carpetas «Programas» del menú Inicio: del usuario y del equipo (la del equipo la ven todos los usuarios)
function Get-IwinProgramsRoots {
    $roots = [ordered]@{}
    $user = [Environment]::GetFolderPath('Programs'); if ($user) { $roots['user'] = $user }
    $machine = [Environment]::GetFolderPath('CommonPrograms'); if ($machine) { $roots['machine'] = $machine }
    $roots
}

# Accesos sueltos dentro de la carpeta «Aplicaciones» del escritorio (los deja ahí Organize-Desktop o el usuario).
# El resto del escritorio no se toca: lo que el usuario deja a mano en él es decisión suya.
function Get-IwinDesktopSources { [ordered]@{ user = (Get-IwinDesktopFoldersRoot) } }

$script:IwinShell = $null
function Get-IwinShortcutTarget([string]$path) {
    try {
        if ($path -match '(?i)\.url$') {
            $line = Select-String -LiteralPath $path -Pattern '^URL=(.+)$' -ErrorAction Stop | Select-Object -First 1
            if ($line) { return $line.Matches[0].Groups[1].Value.Trim() }
            return ''
        }
        if (-not $script:IwinShell) { $script:IwinShell = New-Object -ComObject WScript.Shell }
        [string]$script:IwinShell.CreateShortcut($path).TargetPath
    } catch { '' }
}

# Identidad de un acceso para detectar duplicados: programa y argumentos (un lanzador abre varios juegos)
function Get-IwinShortcutKey([string]$path) {
    $target = Get-IwinShortcutTarget $path
    if (-not $target) { return '' }
    $arguments = ''
    if ($path -match '(?i)\.lnk$') { try { $arguments = [string]$script:IwinShell.CreateShortcut($path).Arguments } catch { } }
    # Chrome, Brave y Edge marcan de dónde sale el acceso: no cambia el programa que abre
    ("$target " + ($arguments -replace '--source-shortcut-location=\S+', '')).Trim().ToLowerInvariant()
}

# ¿Es un acceso que no es la app (desinstalador, ayuda, web)? Un .url solo es app si abre un lanzador (steam://…).
function Test-IwinFolderExtra([string]$path) {
    $base = [IO.Path]::GetFileNameWithoutExtension($path)
    if ($base -match $IwinFoldersSkipPattern) { return $true }
    $target = Get-IwinShortcutTarget $path
    if ($path -match '(?i)\.url$') { return -not ($target -match '^(steam|com\.epicgames\.launcher|uplay|origin|battlenet|riotclient)://') }
    [bool]($target -and $target -match $IwinFoldersExtraTargets)
}

function Get-IwinNormName([string]$text) { ($text.ToLowerInvariant() -replace '[^a-z0-9]', '') }

function Get-IwinFolderGuess([string]$text) {
    foreach ($guess in $IwinFoldersGuesses) { if ($text -match $guess[1]) { return $guess[0] } }
    ''
}

# Unidades que se pueden ordenar en una carpeta «Programas»: cada acceso suelto y cada carpeta de fabricante.
function Get-IwinFolderUnits([string]$scope, [string]$root, $categoryNames) {
    $units = @()
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { return $units }
    $windows = $env:WINDIR
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^(?i)\.(lnk|url)$' })) {
        if ($file.BaseName -match '(?i)^iWinInstaller' -or $IwinFoldersSystemLinks -contains $file.BaseName) { continue }
        $target = Get-IwinShortcutTarget $file.FullName
        if ($windows -and $target -and $target.StartsWith($windows, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $extra = Test-IwinFolderExtra $file.FullName
        $units += [pscustomobject]@{ Scope = $scope; Root = $root; Kind = $(if ($extra) { 'extra' } else { 'file' }); Path = $file.FullName; Name = $file.BaseName; Items = @($file.FullName); Extras = @(); Target = $target }
    }
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        if ($IwinFoldersSystem -contains $dir.Name) { continue }
        if ($categoryNames -contains $dir.Name) {
            # Ya está en su categoría: solo cuenta para el escritorio y para guardar aparte lo que no es la app
            foreach ($file in @(Get-ChildItem -LiteralPath $dir.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^(?i)\.(lnk|url)$' })) {
                $extra = Test-IwinFolderExtra $file.FullName
                $units += [pscustomobject]@{ Scope = $scope; Root = $root; Kind = $(if ($extra) { 'extra' } else { 'placed' }); Path = $file.FullName; Name = $file.BaseName; Items = @($file.FullName); Extras = @(); Target = ''; Category = $dir.Name; Leaf = $true }
            }
            foreach ($sub in @(Get-ChildItem -LiteralPath $dir.FullName -Directory -ErrorAction SilentlyContinue)) {
                $unit = Get-IwinFolderUnit $scope $root $sub
                if ($unit) { $unit.Kind = 'placed'; $unit | Add-Member Category $dir.Name; $unit | Add-Member Leaf $false; $units += $unit }
            }
            continue
        }
        $unit = Get-IwinFolderUnit $scope $root $dir
        if ($unit) { $units += $unit }
    }
    $units
}

function Get-IwinFolderUnit([string]$scope, [string]$root, $dir) {
    $files = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^(?i)\.(lnk|url)$' })
    if (-not $files.Count) { return $null }
    $items = @(); $extras = @()
    foreach ($f in $files) { if (Test-IwinFolderExtra $f.FullName) { $extras += $f.FullName } else { $items += $f.FullName } }
    if (-not $items.Count) { return $null }
    $targets = @($items | ForEach-Object { Get-IwinShortcutTarget $_ }) -join ' '
    [pscustomobject]@{ Scope = $scope; Root = $root; Kind = 'folder'; Path = $dir.FullName; Name = $dir.Name; Items = $items; Extras = $extras; Target = $targets }
}

function Get-IwinUnitBases($unit) { @($unit.Items | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }) }

# Acceso principal de una unidad (el que se copia al escritorio)
function Get-IwinUnitMain($unit, $names) {
    if ($unit.Kind -eq 'file' -or $unit.Leaf) { return $unit.Path }
    # Antes la app que sus herramientas secundarias (consola, configuración, «reset»…); luego la de nombre más corto
    $byBase = @($unit.Items | Sort-Object { [IO.Path]::GetFileNameWithoutExtension($_) -match $IwinFoldersSecondary }, { ([IO.Path]::GetFileNameWithoutExtension($_)).Length })
    foreach ($n in @($names) + @($unit.Name)) {
        $hit = $byBase | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_) -eq $n } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    foreach ($n in @($names) + @($unit.Name)) {
        $norm = Get-IwinNormName $n
        if ($norm.Length -lt 3) { continue }
        $hit = $byBase | Where-Object { (Get-IwinNormName ([IO.Path]::GetFileNameWithoutExtension($_))).StartsWith($norm) } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    $byBase | Select-Object -First 1
}

# Plan: a qué categoría va cada acceso suelto o carpeta de fabricante. Primero por nombre exacto con el catálogo;
# luego, solo para apps instaladas, por nombre parecido; y si $others, el resto por palabras clave u «Otras apps».
# Kind: 'file' (acceso suelto), 'folder' (carpeta de fabricante) o 'extra' (desinstalador/ayuda suelto).
function Get-IwinFolderPlan($apps, $roots, [scriptblock]$isInstalled, [bool]$others = $true) {
    $catalog = @($apps | Where-Object { $_.type -ne 'tweak' -and $_.group })
    $categoryNames = @($catalog | ForEach-Object { Get-IwinFolderName $_.group } | Select-Object -Unique) + @($IwinFoldersOthersName)
    $units = @()
    foreach ($scope in @($roots.Keys)) { $units += @(Get-IwinFolderUnits $scope $roots[$scope] $categoryNames) }
    $plan = @()
    foreach ($unit in @($units | Where-Object { $_.Kind -eq 'extra' })) {
        $plan += [pscustomobject]@{ Id = ''; Name = $unit.Name; Category = ''; Source = $unit.Path; Scope = $unit.Scope; Root = $unit.Root; Kind = 'extra'; Direct = $true; Main = ''; Extras = @($unit.Path); Known = $false }
    }
    foreach ($unit in @($units | Where-Object { $_.Kind -eq 'placed' })) {
        $bases = @(Get-IwinUnitBases $unit) + @($unit.Name)
        $app = $catalog | Where-Object { $n = @($_.name) + @($_.detectNames); @($bases | Where-Object { $n -contains $_ }).Count } | Select-Object -First 1
        $names = if ($app) { @($app.name) + @($app.detectNames) | Where-Object { $_ } } else { @() }
        $plan += [pscustomobject]@{ Id = $(if ($app) { [string]$app.id } else { '' }); Name = $unit.Name; Category = $unit.Category; Source = $unit.Path; Scope = $unit.Scope; Root = $unit.Root; Kind = 'placed'; Direct = $false; Main = (Get-IwinUnitMain $unit $names); Extras = @($unit.Extras); Known = [bool]$app }
    }
    $units = @($units | Where-Object { $_.Kind -ne 'extra' -and $_.Kind -ne 'placed' })
    $claimed = @{}
    $add = {
        param($unit, $app, $category, $known)
        $claimed[$unit.Path] = $true
        $names = if ($app) { @($app.name) + @($app.detectNames) | Where-Object { $_ } } else { @() }
        $script:IwinPlanOut += [pscustomobject]@{
            Id = $(if ($app) { [string]$app.id } else { '' }); Name = $(if ($app) { [string]$app.name } else { $unit.Name })
            Category = $category; Source = $unit.Path; Scope = $unit.Scope; Root = $unit.Root; Kind = $unit.Kind
            Direct = ($unit.Kind -eq 'file'); Main = (Get-IwinUnitMain $unit $names); Extras = @($unit.Extras); Known = $known
        }
    }
    $script:IwinPlanOut = @()
    $rest = @()
    foreach ($app in $catalog) {
        $names = @($app.name) + @($app.detectNames) | Where-Object { $_ }
        $hit = $units | Where-Object { -not $claimed.ContainsKey($_.Path) -and $_.Kind -eq 'file' -and $names -contains $_.Name } | Select-Object -First 1
        if (-not $hit) {
            $hit = $units | Where-Object { -not $claimed.ContainsKey($_.Path) -and $_.Kind -eq 'folder' -and ($names -contains $_.Name -or @(Get-IwinUnitBases $_ | Where-Object { $names -contains $_ }).Count) } | Select-Object -First 1
        }
        if ($hit) { & $add $hit $app (Get-IwinFolderName $app.group) $true } else { $rest += $app }
    }
    foreach ($app in $rest) {
        $installed = $false
        if ($isInstalled) { try { $installed = [bool](& $isInstalled $app) } catch { } }
        if (-not $installed) { continue }
        $raw = @(@($app.name) + @($app.detectNames) | Where-Object { $_ })
        $norms = @($raw | ForEach-Object { Get-IwinNormName $_ } | Where-Object { $_.Length -ge 4 })
        $hit = $units | Where-Object { -not $claimed.ContainsKey($_.Path) } | Where-Object {
            $labels = @($_.Name) + @(Get-IwinUnitBases $_)
            # «Brave» para «Brave normal»: el acceso se llama como el principio del nombre de la app
            if (@($labels | Where-Object { $l = $_; @($raw | Where-Object { $_.StartsWith($l + ' ', [StringComparison]::OrdinalIgnoreCase) }).Count }).Count) { return $true }
            $keys = @($labels | ForEach-Object { Get-IwinNormName $_ })
            @($keys | Where-Object { $k = $_; @($norms | Where-Object { $k.StartsWith($_) -or ($_.Length -ge 6 -and $k.EndsWith($_)) }).Count }).Count
        } | Sort-Object { $_.Name.Length } | Select-Object -First 1
        if ($hit) { & $add $hit $app (Get-IwinFolderName $app.group) $true }
    }
    if ($others) {
        foreach ($unit in @($units | Where-Object { -not $claimed.ContainsKey($_.Path) })) {
            $category = Get-IwinFolderGuess ("$($unit.Name) $((Get-IwinUnitBases $unit) -join ' ') $($unit.Target)")
            if (-not $category) { $category = $IwinFoldersOthersName }
            & $add $unit $null $category $false
        }
    }
    $plan + @($script:IwinPlanOut)
}

# Apps de la Tienda (MSIX): solo para el escritorio. Se incluyen las del catálogo y las que no son de Windows.
function Get-IwinPackagedApps {
    $list = @()
    try {
        $folder = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder')
        foreach ($item in @($folder.Items())) {
            $aumid = [string]$item.Path
            if ($aumid -notmatch '^[^\\!]+_[a-z0-9]{13}![^\\]+$') { continue }
            $list += [pscustomobject]@{ Name = [string]$item.Name; Aumid = $aumid; Family = $aumid.Split('!')[0] }
        }
    } catch { Write-Log "  No se pudieron leer las apps de la Tienda: $($_.Exception.Message)" }
    $list
}

function Get-IwinPackagedPlan($apps, $packaged, [bool]$others = $true) {
    $catalog = @($apps | Where-Object { $_.type -ne 'tweak' -and $_.group })
    $plan = @()
    foreach ($pkg in @($packaged)) {
        $app = $catalog | Where-Object { @($_.families) -contains $pkg.Family -or $_.name -eq $pkg.Name -or @($_.detectNames) -contains $pkg.Name } | Select-Object -First 1
        $category = ''
        if ($app) { $category = Get-IwinFolderName $app.group }
        elseif ($others -and $pkg.Family -notmatch '^(?i)(Microsoft|MicrosoftWindows|MicrosoftCorporationII|Windows|MSTeams|Clipchamp)\b') {
            $category = Get-IwinFolderGuess $pkg.Name
            if (-not $category) { $category = $IwinFoldersOthersName }
        }
        if (-not $category) { continue }
        $plan += [pscustomobject]@{ Id = $(if ($app) { [string]$app.id } else { '' }); Name = $pkg.Name; Category = $category; Aumid = $pkg.Aumid; Known = [bool]$app }
    }
    $plan
}

# Accesos sueltos del escritorio (del usuario y público) que abren una app: se recolocan en su categoría
function Get-IwinDesktopLoosePlan($apps, $sources, [bool]$others = $true) {
    $catalog = @($apps | Where-Object { $_.type -ne 'tweak' -and $_.group })
    $plan = @()
    foreach ($scope in @($sources.Keys)) {
        $root = $sources[$scope]
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^(?i)\.(lnk|url)$' })) {
            $target = Get-IwinShortcutTarget $file.FullName
            $isApp = if ($file.Extension -eq '.url') { $target -match '^(steam|com\.epicgames\.launcher)://' } else { $target -match '(?i)\.(exe|com)$|^shell:AppsFolder' -or -not $target }
            if (-not $isApp -or (Test-IwinFolderExtra $file.FullName) -or $file.BaseName -match '(?i)^iWinInstaller') { continue }
            # «Brave (1)» es un duplicado que dejó un instalador al recrear su acceso
            $base = $file.BaseName -replace '\s\(\d+\)$', ''
            $app = $catalog | Where-Object { $_.name -eq $base -or @($_.detectNames) -contains $base } | Select-Object -First 1
            $category = if ($app) { Get-IwinFolderName $app.group } elseif ($others) { $g = Get-IwinFolderGuess "$base $target"; if ($g) { $g } else { $IwinFoldersOthersName } } else { '' }
            if ($category) { $plan += [pscustomobject]@{ Id = $(if ($app) { [string]$app.id } else { '' }); Name = $base; Category = $category; Source = $file.FullName; Scope = $scope; Duplicate = ($base -ne $file.BaseName); Target = $target } }
        }
    }
    # Primero los originales («Brave») y luego las copias numeradas («Brave (1)»)
    @($plan | Sort-Object Duplicate, Name)
}

function Get-IwinDesktopFoldersRoot { Join-Path ([Environment]::GetFolderPath('Desktop')) $IwinFoldersDesktopName }

# Donde se guardan los desinstaladores y ayudas que se quitan de Inicio (fuera del menú, para poder devolverlos)
function Get-IwinExtrasRoot([string]$scope) {
    if ($scope -eq 'machine' -and $env:ProgramData) { Join-Path $env:ProgramData 'iWinInstaller\accesos-guardados' }
    else { Join-Path $LogDir 'accesos-guardados' }
}

# Acceso a una app de la Tienda (shell:AppsFolder\<AUMID>) con su identidad, para que muestre su icono
function New-IwinPackagedShortcut([string]$path, [string]$aumid) {
    if (-not ('IwinFolders.PackagedLink' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
namespace IwinFolders {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")] internal class CShellLink { }
    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
    internal interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f, int c, IntPtr d, uint fl);
        void GetIDList(out IntPtr p); void SetIDList(IntPtr p);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int c); void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int c); void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int c); void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetHotkey(out short h); void SetHotkey(short h); void GetShowCmd(out int i); void SetShowCmd(int i);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int c, out int i); void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string s, int i);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string s, uint r); void Resolve(IntPtr h, uint f); void SetPath([MarshalAs(UnmanagedType.LPWStr)] string s);
    }
    [StructLayout(LayoutKind.Sequential, Pack = 4)] public struct PropKey { public Guid fmtid; public uint pid; }
    [StructLayout(LayoutKind.Explicit)] public struct PropVar { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; [FieldOffset(16)] public IntPtr p2; }
    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    internal interface IPropStore { void GetCount(out uint c); void GetAt(uint i, out PropKey k); void GetValue(ref PropKey k, out PropVar v); void SetValue(ref PropKey k, ref PropVar v); void Commit(); }
    public static class PackagedLink {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SHParseDisplayName(string name, IntPtr bindCtx, out IntPtr pidl, uint sfgao, out uint attrs);
        public static void Create(string lnk, string aumid) {
            var link = (IShellLinkW)new CShellLink();
            IntPtr pidl; uint attrs;
            SHParseDisplayName("shell:AppsFolder\\" + aumid, IntPtr.Zero, out pidl, 0, out attrs);
            try { link.SetIDList(pidl); } finally { Marshal.FreeCoTaskMem(pidl); }
            var key = new PropKey(); key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); key.pid = 5;
            var value = new PropVar(); value.vt = 31; value.p = Marshal.StringToCoTaskMemUni(aumid);
            var store = (IPropStore)link;
            try { store.SetValue(ref key, ref value); store.Commit(); } finally { Marshal.FreeCoTaskMem(value.p); }
            ((IPersistFile)link).Save(lnk, true);
        }
    }
}
'@
    }
    [IwinFolders.PackagedLink]::Create($path, $aumid)
}

function Move-IwinFolderMerge([string]$source, [string]$target) {
    if (-not (Test-Path -LiteralPath $target)) { Move-Item -LiteralPath $source -Destination $target -ErrorAction Stop; return }
    # Ya existe (una actualización recreó la carpeta): se juntan los archivos y se quita la carpeta vacía
    foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)) {
        $dest = Join-Path $target $file.FullName.Substring($source.Length).TrimStart('\')
        New-Item (Split-Path -Parent $dest) -ItemType Directory -Force | Out-Null
        Move-Item -LiteralPath $file.FullName -Destination $dest -Force -ErrorAction Stop
    }
    Remove-Item -LiteralPath $source -Recurse -Force -ErrorAction SilentlyContinue
}

# Guarda fuera de Inicio un desinstalador o una ayuda (se devuelve con «Deshacer»)
function Move-IwinFolderExtra([string]$path, $entry, $state) {
    $rel = $path.Substring($entry.Root.TrimEnd('\').Length).TrimStart('\')
    $dest = Join-Path (Join-Path (Get-IwinExtrasRoot $entry.Scope) $entry.Scope) $rel
    New-Item (Split-Path -Parent $dest) -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Move-Item -LiteralPath $path -Destination $dest -Force -ErrorAction Stop
    $state.moves = @($state.moves | Where-Object { $_.to -ne $dest }) + @(@{ id = $entry.Id; kind = 'extra'; from = $path; to = $dest })
}

# Una actualización recreó el acceso en su sitio: se quita la copia vieja que movió iWinInstaller a la categoría
function Remove-IwinStaleMoves([string]$folder, $unit, $state) {
    if (-not (Test-Path -LiteralPath $folder)) { return }
    $leaves = @($unit.Items | ForEach-Object { Split-Path -Leaf $_ })
    foreach ($move in @($state.moves | Where-Object { $_.kind -eq 'file' -and $_.to -and $_.to.StartsWith($folder + '\', [StringComparison]::OrdinalIgnoreCase) })) {
        if ($leaves -notcontains (Split-Path -Leaf $move.to) -or -not (Test-Path -LiteralPath $move.to)) { continue }
        $new = $unit.Items | Where-Object { (Split-Path -Leaf $_) -eq (Split-Path -Leaf $move.to) } | Select-Object -First 1
        $old = Get-IwinShortcutTarget $move.to; $now = Get-IwinShortcutTarget $new
        if ($old -and $now -and $old -ne $now) { continue }
        Remove-Item -LiteralPath $move.to -Force -ErrorAction Stop
        $state.moves = @($state.moves | Where-Object { $_.to -ne $move.to })
    }
}

# Ejecuta el plan. $options: StartMenu, Desktop, Extras, Scope ('all' o 'machine'), DesktopRoot, Packaged, DesktopLoose.
function Invoke-IwinFolderApply($plan, $options, $state) {
    $result = @{ moved = 0; copied = 0; adopted = 0; extras = 0; skipped = 0; needsAdmin = 0; removed = 0 }
    $script:IwinDesktopIndex = @{}
    $admin = Test-Administrator
    $scopeOnly = if ($options.Scope -eq 'machine') { 'machine' } else { '' }
    foreach ($entry in $plan) {
        if ($scopeOnly -and $entry.Scope -ne $scopeOnly) { continue }
        $needs = $entry.Scope -eq 'machine' -and -not $admin
        if ($entry.Kind -eq 'extra') {
            if (-not ($options.StartMenu -and $options.Extras)) { continue }
            if ($needs) { $result.needsAdmin++; continue }
            try { Move-IwinFolderExtra $entry.Source $entry $state; $result.extras++ }
            catch { $result.skipped++; Write-Log "  Acceso conservado en Inicio ($($entry.Name)): $($_.Exception.Message)" }
            continue
        }
        $current = $entry.Main
        if ($entry.Kind -eq 'placed') {
            # Ya ordenado: solo se guardan aparte los desinstaladores que una actualización haya añadido
            if ($options.StartMenu -and $options.Extras -and @($entry.Extras).Count) {
                if ($needs) { $result.needsAdmin++ }
                else { foreach ($extra in @($entry.Extras)) { try { Move-IwinFolderExtra $extra $entry $state; $result.extras++ } catch { $result.skipped++ } } }
            }
        } elseif ($options.StartMenu) {
            if ($needs) { $result.needsAdmin++ }
            else {
                try {
                    $folder = Join-Path $entry.Root $entry.Category
                    if ($options.Extras) { foreach ($extra in @($entry.Extras)) { if (Test-Path -LiteralPath $extra) { Move-IwinFolderExtra $extra $entry $state; $result.extras++ } } }
                    New-Item $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    Remove-IwinStaleMoves $folder ([pscustomobject]@{ Items = @(Get-ChildItem -LiteralPath $entry.Source -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object FullName) }) $state
                    $target = Join-Path $folder (Split-Path -Leaf $entry.Source)
                    if ($entry.Kind -eq 'folder') {
                        Move-IwinFolderMerge $entry.Source $target
                        if ($current) { $current = Join-Path $target $current.Substring($entry.Source.Length).TrimStart('\') }
                    } else {
                        Move-Item -LiteralPath $entry.Source -Destination $target -Force -ErrorAction Stop
                        $current = $target
                    }
                    $kind = if ($entry.Kind -eq 'folder') { 'folder' } else { 'file' }
                    $state.moves = @($state.moves | Where-Object { $_.to -ne $target }) + @(@{ id = $entry.Id; kind = $kind; from = $entry.Source; to = $target })
                    $result.moved++
                } catch { $result.skipped++; Write-Log "  Acceso conservado en Inicio ($($entry.Name)): $($_.Exception.Message)" }
            }
        }
        if ($options.Desktop -and $options.DesktopRoot -and $scopeOnly -ne 'machine' -and $current) {
            try { Add-IwinDesktopCopy $options.DesktopRoot $entry.Category $current $entry $state $result } catch { $result.skipped++; Write-Log "  Acceso no copiado al escritorio ($($entry.Name)): $($_.Exception.Message)" }
        }
    }
    if ($options.Desktop -and $options.DesktopRoot) {
        # Accesos sueltos del escritorio (el público solo con permiso) y apps de la Tienda
        foreach ($loose in @($options.DesktopLoose | Where-Object { $_ })) {
            if ($scopeOnly -and $loose.Scope -ne $scopeOnly) { continue }
            if ($loose.Scope -eq 'machine' -and -not $admin) { $result.needsAdmin++; continue }
            try {
                if (-not (Test-Path -LiteralPath $loose.Source)) { continue }
                $folder = Join-Path $options.DesktopRoot $loose.Category
                New-Item $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                $key = Get-IwinShortcutKey $loose.Source
                $index = Get-IwinDesktopIndex $options.DesktopRoot
                if ($key -and @($index[$key] | Where-Object { $_ -and $_ -ne $loose.Source -and (Split-Path -Parent $_) -ne $options.DesktopRoot.TrimEnd('\') -and (Test-Path -LiteralPath $_) }).Count) {
                    # Ya hay otro acceso a la misma app en una categoría: el duplicado se guarda aparte (vuelve con «Deshacer»)
                    Move-IwinFolderExtra $loose.Source ([pscustomobject]@{ Root = $options.DesktopRoot; Scope = 'escritorio'; Id = $loose.Id }) $state
                    $index[$key] = @(@($index[$key]) | Where-Object { $_ -ne $loose.Source })
                    $result.extras++
                    continue
                }
                $target = Join-Path $folder (Split-Path -Leaf $loose.Source)
                $clean = Join-Path $folder ($loose.Name + [IO.Path]::GetExtension($loose.Source))
                if ($loose.Duplicate -and -not (Test-Path -LiteralPath $clean)) { $target = $clean }
                if (Test-Path -LiteralPath $target) { continue }
                Move-Item -LiteralPath $loose.Source -Destination $target -ErrorAction Stop
                if ($key) { $index[$key] = @(@($index[$key]) | Where-Object { $_ -ne $loose.Source }) + @($target) }
                $state.copies = @($state.copies | Where-Object { $_.path -ne $target }) + @(@{ id = $loose.Id; path = $target; adoptedFrom = $loose.Source })
                $result.adopted++
            } catch { $result.skipped++; Write-Log "  Acceso conservado en el escritorio ($($loose.Name)): $($_.Exception.Message)" }
        }
        if ($scopeOnly -ne 'machine') {
            foreach ($pkg in @($options.Packaged | Where-Object { $_ })) {
                try {
                    $folder = Join-Path $options.DesktopRoot $pkg.Category
                    $target = Join-Path $folder ((($pkg.Name -replace '[\\/:*?"<>|]', '-').Trim()) + '.lnk')
                    if (Test-Path -LiteralPath $target) { continue }
                    New-Item $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    New-IwinPackagedShortcut $target $pkg.Aumid
                    $state.copies = @($state.copies | Where-Object { $_.path -ne $target }) + @(@{ id = $pkg.Id; path = $target; adoptedFrom = '' })
                    $result.copied++
                } catch { $result.skipped++; Write-Log "  Acceso de la Tienda no creado ($($pkg.Name)): $($_.Exception.Message)" }
            }
            # Categorías que se han quedado vacías (la app se desinstaló o su acceso era un duplicado)
            foreach ($dir in @(Get-ChildItem -LiteralPath $options.DesktopRoot -Directory -ErrorAction SilentlyContinue)) { Remove-IwinEmptyFolder $dir.FullName }
        }
    }
    $result
}

# Índice destino → accesos de la carpeta Aplicaciones, para no repetir una app con dos nombres («Riot Client» y
# «Cliente de Riot», «Brave (1)»…). Se construye una vez por carpeta y se actualiza al copiar o mover.
$script:IwinDesktopIndex = @{}
function Get-IwinDesktopIndex([string]$desktopRoot) {
    if (-not $script:IwinDesktopIndex.ContainsKey($desktopRoot)) {
        $index = @{}
        if (Test-Path -LiteralPath $desktopRoot) {
            foreach ($file in @(Get-ChildItem -LiteralPath $desktopRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^(?i)\.(lnk|url)$' })) {
                $key = Get-IwinShortcutKey $file.FullName
                if ($key) { $index[$key] = @($index[$key] | Where-Object { $_ }) + @($file.FullName) }
            }
        }
        $script:IwinDesktopIndex[$desktopRoot] = $index
    }
    $script:IwinDesktopIndex[$desktopRoot]
}

function Add-IwinDesktopCopy([string]$desktopRoot, [string]$category, [string]$current, $entry, $state, $result) {
    $folder = Join-Path $desktopRoot $category
    $leaf = Split-Path -Leaf $current
    $target = Join-Path $folder $leaf
    $flat = Join-Path $desktopRoot $leaf
    if (Test-Path -LiteralPath $target) { return }
    # La app ya tiene su acceso en el escritorio (otro nombre u otro acceso suyo): no se duplica.
    # Las que no son del catálogo se identifican por el nombre de su acceso o carpeta.
    $copyId = if ($entry.Id) { $entry.Id } else { '~' + $entry.Name }
    if (@($state.copies | Where-Object { $_.id -eq $copyId -and (Test-Path -LiteralPath $_.path) }).Count) { return }
    $key = Get-IwinShortcutKey $current
    $index = Get-IwinDesktopIndex $desktopRoot
    # Solo cuentan los que ya están en una categoría: los sueltos de Aplicaciones se recolocan después
    if ($key -and $index.ContainsKey($key) -and @($index[$key] | Where-Object { $_ -and (Split-Path -Parent $_) -ne $desktopRoot.TrimEnd('\') -and (Test-Path -LiteralPath $_) }).Count) { return }
    New-Item $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    if (Test-Path -LiteralPath $flat) {
        # Lo dejó Organize-Desktop: se adopta (se mueve a su categoría) y al deshacer vuelve aquí
        Move-Item -LiteralPath $flat -Destination $target -ErrorAction Stop
        $state.copies = @($state.copies | Where-Object { $_.path -ne $target }) + @(@{ id = $copyId; path = $target; adoptedFrom = $flat })
        $result.adopted++
    } elseif (Test-Path -LiteralPath $current) {
        Copy-Item -LiteralPath $current -Destination $target -ErrorAction Stop
        $state.copies = @($state.copies | Where-Object { $_.path -ne $target }) + @(@{ id = $copyId; path = $target; adoptedFrom = '' })
        $result.copied++
    }
    # Se indexa el acceso que ha quedado en la categoría (el adoptado puede llevar otros argumentos que el de Inicio)
    $placed = Get-IwinShortcutKey $target
    if ($placed) { $index[$placed] = @(@($index[$placed]) | Where-Object { $_ -and $_ -ne $flat }) + @($target) }
}

# Limpieza: quita del registro lo que ya no existe, borra accesos movidos cuya app se desinstaló y copias del
# escritorio que eran desinstaladores o ayudas (versiones anteriores las copiaban).
function Invoke-IwinFolderPrune($state, [string]$scope = 'all') {
    $removed = 0
    $admin = Test-Administrator
    $machinePattern = Get-IwinMachineProgramsPattern
    $keep = @()
    foreach ($move in @($state.moves)) {
        if (-not (Test-Path -LiteralPath $move.to)) { continue }
        $machine = $move.from -like $machinePattern
        if ($move.kind -eq 'file' -and $move.to -match '(?i)\.lnk$' -and ($admin -or -not $machine) -and ($scope -ne 'machine' -or $machine)) {
            $target = Get-IwinShortcutTarget $move.to
            if ($target -match '^[A-Za-z]:\\' -and (Test-Path -LiteralPath (Split-Path -Qualifier $target)) -and -not (Test-Path -LiteralPath $target)) {
                try { Remove-Item -LiteralPath $move.to -Force -ErrorAction Stop; Remove-IwinEmptyFolder (Split-Path -Parent $move.to); $removed++; continue } catch { }
            }
        }
        $keep += $move
    }
    $state.moves = @($keep)
    if ($scope -ne 'machine') {
        $copies = @()
        foreach ($copy in @($state.copies)) {
            if (-not (Test-Path -LiteralPath $copy.path)) { continue }
            if (-not $copy.adoptedFrom -and (Test-IwinFolderExtra $copy.path)) {
                try { Remove-Item -LiteralPath $copy.path -Force -ErrorAction Stop; Remove-IwinEmptyFolder (Split-Path -Parent $copy.path); $removed++; continue } catch { }
            }
            $copies += $copy
        }
        $state.copies = @($copies)
    }
    $removed
}

function Remove-IwinEmptyFolder([string]$path) {
    if ($path -and (Test-Path -LiteralPath $path) -and -not @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue).Count) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

# Devuelve todo a su sitio según el registro; nunca toca lo que no movió o copió iWinInstaller.
# Orden: primero accesos y carpetas (al revés de como se movieron), luego desinstaladores y ayudas guardados.
function Invoke-IwinFolderRevert($state, [string]$scope = 'all') {
    $result = @{ restored = 0; removed = 0; skipped = 0; needsAdmin = 0 }
    $admin = Test-Administrator
    $machinePattern = Get-IwinMachineProgramsPattern
    $keep = @()
    $moves = @($state.moves)
    [array]::Reverse($moves)
    $ordered = @($moves | Where-Object { $_.kind -ne 'extra' }) + @($moves | Where-Object { $_.kind -eq 'extra' })
    $folders = @($moves | Where-Object { $_.kind -eq 'folder' })
    foreach ($move in $ordered) {
        if ($move.kind -eq 'extra') {
            # Se guardó desde una carpeta que ya volvió a su sitio: se devuelve allí
            foreach ($f in $folders) {
                if ($move.from.StartsWith($f.to + '\', [StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath $f.to)) {
                    $move = @{ id = $move.id; kind = 'extra'; from = $f.from + $move.from.Substring($f.to.Length); to = $move.to }
                }
            }
        }
        $machine = $move.from -like $machinePattern
        if ($scope -eq 'machine' -and -not $machine) { $keep += $move; continue }
        if ($machine -and -not $admin) { $result.needsAdmin++; $keep += $move; continue }
        try {
            if (-not (Test-Path -LiteralPath $move.to)) { continue }
            if ($move.kind -eq 'folder') {
                Move-IwinFolderMerge $move.to $move.from
            } else {
                New-Item (Split-Path -Parent $move.from) -ItemType Directory -Force -ErrorAction Stop | Out-Null
                if (Test-Path -LiteralPath $move.from) { Remove-Item -LiteralPath $move.to -Force -ErrorAction Stop }
                else { Move-Item -LiteralPath $move.to -Destination $move.from -ErrorAction Stop }
            }
            $result.restored++
            $parent = Split-Path -Parent $move.to
            Remove-IwinEmptyFolder $parent
            if ($move.kind -eq 'extra') { Remove-IwinEmptyFolder (Split-Path -Parent $parent) }
        } catch { $result.skipped++; $keep += $move; Write-Log "  No se pudo devolver $($move.to): $($_.Exception.Message)" }
    }
    [array]::Reverse($keep)
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

# Una sola solicitud de administrador para lo que vive en «Programas» del equipo y el escritorio público
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
    if ($result.moved) { $parts += "$($result.moved) apps de Inicio ordenadas" }
    if ($result.extras) { $parts += "$($result.extras) desinstaladores y ayudas guardados aparte" }
    if ($result.copied) { $parts += "$($result.copied) copiadas al escritorio" }
    if ($result.adopted) { $parts += "$($result.adopted) del escritorio recolocadas" }
    if ($result.removed) { $parts += "$($result.removed) accesos viejos o rotos quitados" }
    if ($result.skipped) { $parts += "$($result.skipped) omitidas" }
    if ($parts) { $parts -join ' · ' } else { 'Nada que ordenar: no hay accesos nuevos.' }
}

function Get-IwinFoldersFullPlan($state) {
    @(Get-IwinFolderPlan $Apps (Get-IwinProgramsRoots) { param($app) Test-AppInstalled $app } ([bool]$state.others))
}

function Invoke-IwinFoldersOrganize($request) {
    $state = Read-IwinFoldersState
    foreach ($flag in 'startMenu', 'desktop', 'others', 'extras') { if ($null -ne $request.$flag) { $state[$flag] = [bool]$request.$flag } }
    $scope = if ($request.scope -eq 'machine') { 'machine' } else { 'all' }
    $admin = Test-Administrator
    $plan = Get-IwinFoldersFullPlan $state
    $loose = if ($state.desktop) { @(Get-IwinDesktopLoosePlan $Apps (Get-IwinDesktopSources) ([bool]$state.others)) } else { @() }
    $denied = $false
    # Lo del Inicio de todos los usuarios: un proceso elevado lo ordena y luego se relee el registro
    $machineWork = $state.startMenu -and @($plan | Where-Object {
            $_.Scope -eq 'machine' -and (($_.Kind -in 'file', 'folder') -or ($state.extras -and ($_.Kind -eq 'extra' -or ($_.Kind -eq 'placed' -and @($_.Extras).Count)))) }).Count
    if ($scope -eq 'all' -and -not $admin -and $machineWork) {
        Save-IwinFoldersState $state
        if (Invoke-IwinFoldersElevated 'folders.apply' @{ startMenu = [bool]$state.startMenu; desktop = [bool]$state.desktop; others = [bool]$state.others; extras = [bool]$state.extras }) {
            $prefs = $state; $state = Read-IwinFoldersState
            foreach ($flag in 'startMenu', 'desktop', 'others', 'extras') { $state[$flag] = $prefs[$flag] }
        } else { $denied = $true }
        $plan = Get-IwinFoldersFullPlan $state
        $loose = if ($state.desktop) { @(Get-IwinDesktopLoosePlan $Apps (Get-IwinDesktopSources) ([bool]$state.others)) } else { @() }
    }
    $removed = Invoke-IwinFolderPrune $state $scope
    $packaged = if ($state.desktop -and $scope -ne 'machine') { @(Get-IwinPackagedPlan $Apps (Get-IwinPackagedApps) ([bool]$state.others)) } else { @() }
    $options = @{ StartMenu = [bool]$state.startMenu; Desktop = [bool]$state.desktop; Extras = [bool]$state.extras; Scope = $scope
        DesktopRoot = (Get-IwinDesktopFoldersRoot); Packaged = $packaged; DesktopLoose = $loose }
    $result = Invoke-IwinFolderApply $plan $options $state
    $result.removed += $removed
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
    $plan = @(Get-IwinFoldersFullPlan $state | Where-Object { $_.Kind -ne 'extra' })
    $categories = @($plan | Group-Object Category | Sort-Object Name | ForEach-Object { [ordered]@{ name = $_.Name; count = $_.Count } })
    @{
        auto = [bool]$state.auto; startMenu = [bool]$state.startMenu; desktop = [bool]$state.desktop
        others = [bool]$state.others; extras = [bool]$state.extras
        moved = @($state.moves | Where-Object { $_.kind -ne 'extra' }).Count; copied = @($state.copies).Count
        saved = @($state.moves | Where-Object { $_.kind -eq 'extra' }).Count
        pending = @($plan).Count; pendingKnown = @($plan | Where-Object { $_.Known }).Count
        categories = $categories; desktopFolder = (Get-IwinDesktopFoldersRoot)
    }
}

Register-IwinEngineCommand 'folders.set' {
    param($request)
    $state = Read-IwinFoldersState
    foreach ($flag in 'auto', 'startMenu', 'desktop', 'others', 'extras') { if ($null -ne $request.$flag) { $state[$flag] = [bool]$request.$flag } }
    Save-IwinFoldersState $state
    @{ auto = $state.auto; startMenu = $state.startMenu; desktop = $state.desktop; others = $state.others; extras = $state.extras }
}

# «Comprobar y organizar» y «Reordenar» son el mismo comando: vuelve a colocar lo que una actualización haya recreado
Register-IwinEngineCommand 'folders.apply' {
    param($request)
    $r = Invoke-IwinFoldersOrganize $request
    @{ moved = $r.moved; copied = $r.copied; adopted = $r.adopted; extras = $r.extras; removed = $r.removed; skipped = $r.skipped; needsAdmin = $r.needsAdmin; denied = [bool]$r.denied; summary = $r.summary }
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
