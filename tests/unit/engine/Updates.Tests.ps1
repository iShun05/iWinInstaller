# Pruebas de la lectura de «winget upgrade» y de las tarjetas de estado, sin ejecutar winget.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    function Write-Log($msg) { }
    $script:IwinEngineCommands = [ordered]@{}
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\10-Updates.ps1')
    . (Join-Path $root 'src\engine\11-Status.ps1')
}

Describe 'ConvertFrom-WingetTable' {
    It 'lee la tabla en inglés con nombres con espacios e ignora el resumen' {
        $lines = @(
            "   - `r   \ `rName                       Id                    Version     Available   Source",
            '-----------------------------------------------------------------------------------------',
            'Mozilla Firefox (x64 es-ES) Mozilla.Firefox.es-ES 131.0       132.0.1     winget',
            'Git                        Git.Git               2.46.0      2.47.0      winget',
            '2 upgrades available.'
        )
        $rows = @(ConvertFrom-WingetTable $lines)
        $rows.Count | Should -Be 2
        $rows[0].Name | Should -Be 'Mozilla Firefox (x64 es-ES)'
        $rows[0].Id | Should -Be 'Mozilla.Firefox.es-ES'
        $rows[0].Available | Should -Be '132.0.1'
        $rows[1].Id | Should -Be 'Git.Git'
    }

    It 'lee la tabla en español' {
        $lines = @(
            'Nombre           Id                            Versión   Disponible Origen',
            '--------------------------------------------------------------------------',
            'Visual C++ 2015+ Microsoft.VCRedist.2015+.x64  14.38.0   14.40.0    winget',
            '1 actualizaciones disponibles.'
        )
        $rows = @(ConvertFrom-WingetTable $lines)
        $rows.Count | Should -Be 1
        $rows[0].Id | Should -Be 'Microsoft.VCRedist.2015+.x64'
        $rows[0].Version | Should -Be '14.38.0'
    }

    It 'sin tabla devuelve una lista vacía' {
        @(ConvertFrom-WingetTable @('No installed package found matching input criteria.')).Count | Should -Be 0
    }
}

Describe 'Tarjeta de actualizaciones' {
    It 'no se puede comprobar se muestra como unknown con motivo, nunca como correcta' {
        function Test-Cmd($name) { $true }
        function Get-IwinAvailableUpdates { $null }
        $card = Get-IwinUpdatesCard
        $card.state | Should -Be 'unknown'
        $card.reason | Should -Not -BeNullOrEmpty
    }

    It 'cuenta las actualizaciones disponibles' {
        function Get-IwinAvailableUpdates { @([pscustomobject]@{ Name = 'Git'; Id = 'Git.Git' }, [pscustomobject]@{ Name = 'VLC'; Id = 'VideoLAN.VLC' }) }
        $card = Get-IwinUpdatesCard
        $card.state | Should -Be 'attention'
        $card.summary | Should -Match '^2 actualizaciones'
    }

    It 'sin actualizaciones queda al día' {
        function Get-IwinAvailableUpdates { @() }
        (Get-IwinUpdatesCard).state | Should -Be 'ok'
    }
}

Describe 'status.collect' {
    It 'una comprobación que lanza error queda como unknown' {
        function Get-IwinUpdatesCard { throw 'fallo simulado' }
        $response = & $IwinEngineCommands['status.collect'] ([pscustomobject]@{ contract = 1; areas = @('appUpdates') })
        @($response.cards).Count | Should -Be 1
        $response.cards[0].state | Should -Be 'unknown'
        $response.cards[0].reason | Should -Match 'fallo simulado'
    }
}
