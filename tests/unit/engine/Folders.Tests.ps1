# Carpetas por categoría: en carpetas de prueba, nunca toca el menú Inicio ni el escritorio reales.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('iwin-folders-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:LogDir -ItemType Directory | Out-Null
    $script:WorkerMode = ''
    function Write-Log($msg) { }
    function Test-Administrator { $true }
    function Write-IwinJson($path, $value) { ConvertTo-Json $value -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8 }
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\17-Folders.ps1')
    # Nada fuera de la carpeta de prueba: ni ProgramData ni el Inicio real
    function Get-IwinExtrasRoot([string]$scope) { Join-Path $script:LogDir "guardados-$scope" }
    $script:Apps = @(
        [pscustomobject]@{ id = 'vscode'; name = 'Visual Studio Code'; group = 'Desarrollo'; type = 'winget' },
        [pscustomobject]@{ id = 'vlc'; name = 'VLC media player'; group = 'Multimedia'; type = 'winget' },
        [pscustomobject]@{ id = 'git'; name = 'Git Bash'; group = 'Desarrollo'; type = 'winget' },
        [pscustomobject]@{ id = 'tweak'; name = 'Ajuste'; group = 'Ajustes'; type = 'tweak' })
    function script:Get-Ids($plan) { (@($plan | Where-Object { $_.Kind -ne 'extra' } | ForEach-Object Id | Where-Object { $_ }) | Sort-Object) -join ',' }
}

AfterAll { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Carpetas por categoría' {
    BeforeEach {
        $script:T = Join-Path $script:LogDir ([guid]::NewGuid().ToString('N'))
        $script:U = Join-Path $script:T 'user'; $script:M = Join-Path $script:T 'machine'; $script:D = Join-Path $script:T 'desk\Aplicaciones'
        New-Item $script:U, $script:M, $script:D, (Join-Path $script:M 'Git'), (Join-Path $script:U 'Startup'), (Join-Path $script:U 'Accessibility') -ItemType Directory | Out-Null
        Set-Content (Join-Path $script:U 'Visual Studio Code.lnk') 'a'
        Set-Content (Join-Path $script:M 'VLC media player.lnk') 'b'
        Set-Content (Join-Path $script:M 'Git\Git Bash.lnk') 'c'
        Set-Content (Join-Path $script:M 'Git\Git Release Notes.lnk') 'notas'
        Set-Content (Join-Path $script:M 'Uninstall VLC.lnk') 'u'
        Set-Content (Join-Path $script:U 'Startup\Arranque.lnk') 's'
        Set-Content (Join-Path $script:U 'Accessibility\Lupa.lnk') 'l'
        Set-Content (Join-Path $script:D 'VLC media player.lnk') 'plano'
        $script:Roots = [ordered]@{ user = $script:U; machine = $script:M }
        $script:Options = @{ StartMenu = $true; Desktop = $true; Extras = $true; Scope = 'all'; DesktopRoot = $script:D }
        Remove-Item (Get-IwinFoldersPath) -ErrorAction SilentlyContinue
    }

    It 'casa por nombre, incluye la carpeta del fabricante y no toca las de Windows' {
        $plan = @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true })
        Get-Ids $plan | Should -Be 'git,vlc,vscode'
        ($plan | Where-Object Id -eq 'git').Kind | Should -Be 'folder'
        ($plan | Where-Object Id -eq 'git').Extras | Should -HaveCount 1
        @($plan | Where-Object Kind -eq 'extra').Count | Should -Be 1
        @($plan | Where-Object { $_.Source -match 'Startup|Accessibility' }).Count | Should -Be 0
    }

    It 'ordena las apps que no son del catálogo por palabras clave o en «Otras apps»' {
        New-Item (Join-Path $script:U 'Riot Games') -ItemType Directory | Out-Null
        Set-Content (Join-Path $script:U 'Riot Games\League of Legends.lnk') 'g'
        Set-Content (Join-Path $script:U 'Zeta Qwerty.lnk') 'z'
        $plan = @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true })
        ($plan | Where-Object Name -eq 'Riot Games').Category | Should -Be 'Juegos'
        ($plan | Where-Object Name -eq 'Zeta Qwerty').Category | Should -Be 'Otras apps'
        $only = @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true } $false)
        @($only | Where-Object Name -in 'Riot Games', 'Zeta Qwerty').Count | Should -Be 0
    }

    It 'mueve accesos y carpetas de fabricante, guarda aparte los desinstaladores y copia al escritorio' {
        $plan = @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true })
        $state = Read-IwinFoldersState
        $r = Invoke-IwinFolderApply $plan $script:Options $state
        $r.moved | Should -Be 3
        $r.extras | Should -Be 2
        Test-Path (Join-Path $script:U 'Desarrollo\Visual Studio Code.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Multimedia\VLC media player.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Desarrollo\Git\Git Bash.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Git') | Should -BeFalse
        Test-Path (Join-Path $script:M 'Uninstall VLC.lnk') | Should -BeFalse
        Test-Path (Join-Path $script:M 'Desarrollo\Git\Git Release Notes.lnk') | Should -BeFalse
        Test-Path (Join-Path $script:U 'Startup\Arranque.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:D 'Multimedia\VLC media player.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:D 'VLC media player.lnk') | Should -BeFalse
        Test-Path (Join-Path $script:D 'Desarrollo\Git Bash.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:D 'Desarrollo\Visual Studio Code.lnk') | Should -BeTrue
    }

    It 'sin «guardar aparte» deja los desinstaladores donde estaban' {
        $options = $script:Options.Clone(); $options.Extras = $false
        $r = Invoke-IwinFolderApply @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true }) $options (Read-IwinFoldersState)
        $r.extras | Should -Be 0
        Test-Path (Join-Path $script:M 'Uninstall VLC.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Desarrollo\Git\Git Release Notes.lnk') | Should -BeTrue
    }

    It 'sin permiso de administrador no toca los accesos del equipo' {
        function Test-Administrator { $false }
        $plan = @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true })
        $r = Invoke-IwinFolderApply $plan $script:Options (Read-IwinFoldersState)
        $r.needsAdmin | Should -Be 3
        Test-Path (Join-Path $script:M 'VLC media player.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Git\Git Bash.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Uninstall VLC.lnk') | Should -BeTrue
        function Test-Administrator { $true }
    }

    It 'repetir no duplica y deshacer lo devuelve todo a su sitio' {
        function Get-IwinMachineProgramsPattern { "$($script:M)*" }
        $state = Read-IwinFoldersState
        [void](Invoke-IwinFolderApply @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true }) $script:Options $state)
        Save-IwinFoldersState $state
        $state = Read-IwinFoldersState
        $again = Invoke-IwinFolderApply @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true }) $script:Options $state
        $again.moved | Should -Be 0
        $again.copied | Should -Be 0
        $again.extras | Should -Be 0
        [void](Invoke-IwinFolderRevert $state)
        Test-Path (Join-Path $script:U 'Visual Studio Code.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'VLC media player.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Git\Git Bash.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Git\Git Release Notes.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Uninstall VLC.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:D 'VLC media player.lnk') | Should -BeTrue
        foreach ($gone in (Join-Path $script:D 'Desarrollo'), (Join-Path $script:U 'Desarrollo'), (Join-Path $script:M 'Desarrollo'), (Join-Path $script:M 'Multimedia')) { Test-Path $gone | Should -BeFalse }
        @($state.moves).Count | Should -Be 0
        @($state.copies).Count | Should -Be 0
    }

    It 'recoloca un acceso o una carpeta que una actualización recreó, sin duplicados' {
        $state = Read-IwinFoldersState
        [void](Invoke-IwinFolderApply @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true }) $script:Options $state)
        Set-Content (Join-Path $script:U 'Visual Studio Code.lnk') 'nuevo'
        New-Item (Join-Path $script:M 'Git') -ItemType Directory | Out-Null
        Set-Content (Join-Path $script:M 'Git\Git Bash.lnk') 'git nuevo'
        $r = Invoke-IwinFolderApply @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true }) $script:Options $state
        $r.moved | Should -Be 2
        Test-Path (Join-Path $script:U 'Visual Studio Code.lnk') | Should -BeFalse
        Get-Content (Join-Path $script:U 'Desarrollo\Visual Studio Code.lnk') | Should -Be 'nuevo'
        Get-Content (Join-Path $script:M 'Desarrollo\Git\Git Bash.lnk') | Should -Be 'git nuevo'
        Test-Path (Join-Path $script:M 'Git') | Should -BeFalse
    }

    It 'quita una copia vieja que movió iWinInstaller cuando el fabricante crea su carpeta' {
        $state = Read-IwinFoldersState
        New-Item (Join-Path $script:U 'Desarrollo') -ItemType Directory | Out-Null
        Set-Content (Join-Path $script:U 'Desarrollo\Visual Studio Code.lnk') 'viejo'
        $state.moves = @(@{ id = 'vscode'; kind = 'file'; from = (Join-Path $script:U 'Visual Studio Code.lnk'); to = (Join-Path $script:U 'Desarrollo\Visual Studio Code.lnk') })
        Remove-Item (Join-Path $script:U 'Visual Studio Code.lnk')
        New-Item (Join-Path $script:U 'Microsoft VS Code') -ItemType Directory | Out-Null
        Set-Content (Join-Path $script:U 'Microsoft VS Code\Visual Studio Code.lnk') 'nuevo'
        [void](Invoke-IwinFolderApply @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true }) $script:Options $state)
        Test-Path (Join-Path $script:U 'Desarrollo\Visual Studio Code.lnk') | Should -BeFalse
        Get-Content (Join-Path $script:U 'Desarrollo\Microsoft VS Code\Visual Studio Code.lnk') | Should -Be 'nuevo'
    }

    It 'la limpieza retira copias del escritorio que eran ayudas de versiones anteriores' {
        function Get-IwinMachineProgramsPattern { "$($script:M)*" }
        $state = Read-IwinFoldersState
        New-Item (Join-Path $script:D 'Consola y shells') -ItemType Directory | Out-Null
        $doc = Join-Path $script:D 'Consola y shells\Clink Documentation.lnk'
        Set-Content $doc 'doc'
        $state.copies = @(@{ id = 'clink'; path = $doc; adoptedFrom = '' })
        Invoke-IwinFolderPrune $state | Should -Be 1
        Test-Path $doc | Should -BeFalse
        @($state.copies).Count | Should -Be 0
    }

    It 'recoloca en su categoría los accesos sueltos de la carpeta Aplicaciones' {
        Set-Content (Join-Path $script:D 'Zeta Qwerty.lnk') 'z'
        $loose = @(Get-IwinDesktopLoosePlan $script:Apps ([ordered]@{ user = $script:D }))
        ($loose | Where-Object Name -eq 'Zeta Qwerty').Category | Should -Be 'Otras apps'
        $options = $script:Options.Clone(); $options.StartMenu = $false; $options.DesktopLoose = $loose
        $state = Read-IwinFoldersState
        [void](Invoke-IwinFolderApply @() $options $state)
        Test-Path (Join-Path $script:D 'Otras apps\Zeta Qwerty.lnk') | Should -BeTrue
        [void](Invoke-IwinFolderRevert $state)
        Test-Path (Join-Path $script:D 'Zeta Qwerty.lnk') | Should -BeTrue
    }

    It 'no repite en Aplicaciones una app que ya tiene otro acceso al mismo programa' {
        $shell = New-Object -ComObject WScript.Shell
        New-Item (Join-Path $script:D 'Utilidades') -ItemType Directory | Out-Null
        foreach ($p in (Join-Path $script:D 'Utilidades\Bloc.lnk'), (Join-Path $script:D 'Bloc (1).lnk')) { $l = $shell.CreateShortcut($p); $l.TargetPath = "$env:WINDIR\System32\notepad.exe"; $l.Save() }
        $loose = @(Get-IwinDesktopLoosePlan $script:Apps ([ordered]@{ user = $script:D }))
        $options = $script:Options.Clone(); $options.StartMenu = $false; $options.DesktopLoose = $loose
        $state = Read-IwinFoldersState
        $r = Invoke-IwinFolderApply @() $options $state
        $r.extras | Should -Be 1
        Test-Path (Join-Path $script:D 'Bloc (1).lnk') | Should -BeFalse
        @(Get-ChildItem $script:D -Recurse -Filter 'Bloc*').Count | Should -Be 1
        [void](Invoke-IwinFolderRevert $state)
        Test-Path (Join-Path $script:D 'Bloc (1).lnk') | Should -BeTrue
    }

    It 'de dos accesos sueltos al mismo programa conserva uno en su categoría' {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($p in (Join-Path $script:D 'Brave.lnk'), (Join-Path $script:D 'Brave (1).lnk')) { $l = $shell.CreateShortcut($p); $l.TargetPath = "$env:WINDIR\System32\notepad.exe"; $l.Save() }
        $loose = @(Get-IwinDesktopLoosePlan $script:Apps ([ordered]@{ user = $script:D }))
        $options = $script:Options.Clone(); $options.StartMenu = $false; $options.DesktopLoose = $loose
        [void](Invoke-IwinFolderApply @() $options (Read-IwinFoldersState))
        Test-Path (Join-Path $script:D 'Navegadores\Brave.lnk') | Should -BeTrue
        @(Get-ChildItem $script:D -Recurse -Filter 'Brave*').Count | Should -Be 1
    }

    It 'casa «Brave» con la app «Brave normal» del catálogo' {
        Set-Content (Join-Path $script:M 'Brave.lnk') 'b'
        $apps = @($script:Apps) + @([pscustomobject]@{ id = 'brave'; name = 'Brave normal'; group = 'Navegadores'; type = 'winget' })
        (@(Get-IwinFolderPlan $apps $script:Roots { param($a) $true }) | Where-Object Name -eq 'Brave normal').Category | Should -Be 'Navegadores'
    }

    It 'lee el registro antiguo (v1) sin tipo de movimiento' {
        Set-Content (Get-IwinFoldersPath) '{"version":1,"auto":false,"moves":[{"id":"a","from":"x","to":"y"}],"copies":[]}'
        $state = Read-IwinFoldersState
        $state.auto | Should -BeFalse
        $state.others | Should -BeTrue
        $state.moves[0].kind | Should -Be 'file'
    }

    It 'rechaza un registro dañado sin sobrescribirlo' {
        Set-Content (Get-IwinFoldersPath) '{no json'
        { Read-IwinFoldersState } | Should -Throw '*dañado*'
        Remove-Item (Get-IwinFoldersPath)
    }

    It 'registra los comandos del contrato' {
        foreach ($name in 'folders.status', 'folders.set', 'folders.apply', 'folders.revert') { $IwinEngineCommands.Contains($name) | Should -BeTrue }
    }
}
