# Carpetas por categoría (sin publicar): en carpetas de prueba, nunca toca el menú Inicio ni el escritorio reales.

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
    $script:Apps = @(
        [pscustomobject]@{ id = 'vscode'; name = 'Visual Studio Code'; group = 'Desarrollo'; type = 'winget' },
        [pscustomobject]@{ id = 'vlc'; name = 'VLC media player'; group = 'Multimedia'; type = 'winget' },
        [pscustomobject]@{ id = 'git'; name = 'Git Bash'; group = 'Desarrollo'; type = 'winget' },
        [pscustomobject]@{ id = 'tweak'; name = 'Ajuste'; group = 'Ajustes'; type = 'tweak' })
}

AfterAll { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Carpetas por categoría' {
    BeforeEach {
        $script:T = Join-Path $script:LogDir ([guid]::NewGuid().ToString('N'))
        $script:U = Join-Path $script:T 'user'; $script:M = Join-Path $script:T 'machine'; $script:D = Join-Path $script:T 'desk\Aplicaciones'
        New-Item $script:U, $script:M, $script:D, (Join-Path $script:M 'Git') -ItemType Directory | Out-Null
        Set-Content (Join-Path $script:U 'Visual Studio Code.lnk') 'a'
        Set-Content (Join-Path $script:M 'VLC media player.lnk') 'b'
        Set-Content (Join-Path $script:M 'Git\Git Bash.lnk') 'c'
        Set-Content (Join-Path $script:M 'Uninstall VLC.lnk') 'u'
        Set-Content (Join-Path $script:D 'VLC media player.lnk') 'plano'
        $script:Roots = [ordered]@{ user = $script:U; machine = $script:M }
        $script:Options = @{ StartMenu = $true; Desktop = $true; Scope = 'all'; DesktopRoot = $script:D }
    }

    It 'casa por nombre, ignora desinstaladores y ajustes' {
        $plan = @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true })
        ($plan | ForEach-Object Id | Sort-Object) -join ',' | Should -Be 'git,vlc,vscode'
        ($plan | Where-Object Id -eq 'git').Direct | Should -BeFalse
    }

    It 'mueve solo los accesos directos de Programas y copia o adopta en el escritorio' {
        $plan = @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true })
        $state = Read-IwinFoldersState
        $r = Invoke-IwinFolderApply $plan $script:Options $state
        $r.moved | Should -Be 2
        Test-Path (Join-Path $script:U 'Desarrollo\Visual Studio Code.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Multimedia\VLC media player.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Git\Git Bash.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'Uninstall VLC.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:D 'Multimedia\VLC media player.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:D 'VLC media player.lnk') | Should -BeFalse
        Test-Path (Join-Path $script:D 'Desarrollo\Git Bash.lnk') | Should -BeTrue
    }

    It 'sin permiso de administrador no toca los accesos del equipo' {
        function Test-Administrator { $false }
        $plan = @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true })
        $r = Invoke-IwinFolderApply $plan $script:Options (Read-IwinFoldersState)
        $r.needsAdmin | Should -Be 1
        Test-Path (Join-Path $script:M 'VLC media player.lnk') | Should -BeTrue
        function Test-Administrator { $true }
    }

    It 'repetir no duplica y deshacer lo devuelve todo a su sitio' {
        function Get-IwinMachineProgramsPattern { "$($script:M)*" }
        $plan = @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true })
        $state = Read-IwinFoldersState
        [void](Invoke-IwinFolderApply $plan $script:Options $state)
        Save-IwinFoldersState $state
        $state = Read-IwinFoldersState
        $again = Invoke-IwinFolderApply @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true }) $script:Options $state
        $again.moved | Should -Be 0
        $again.copied | Should -Be 0
        [void](Invoke-IwinFolderRevert $state)
        Test-Path (Join-Path $script:U 'Visual Studio Code.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:M 'VLC media player.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:D 'VLC media player.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:D 'Desarrollo') | Should -BeFalse
        Test-Path (Join-Path $script:U 'Desarrollo') | Should -BeFalse
    }

    It 'Reordenar recoloca un acceso que una actualización recreó' {
        $state = Read-IwinFoldersState
        [void](Invoke-IwinFolderApply @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true }) $script:Options $state)
        Set-Content (Join-Path $script:U 'Visual Studio Code.lnk') 'nuevo'
        $r = Invoke-IwinFolderApply @(Get-IwinFolderPlan $script:Apps $script:Roots { param($a) $true }) $script:Options $state
        $r.moved | Should -Be 1
        Test-Path (Join-Path $script:U 'Visual Studio Code.lnk') | Should -BeFalse
        Get-Content (Join-Path $script:U 'Desarrollo\Visual Studio Code.lnk') | Should -Be 'nuevo'
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
