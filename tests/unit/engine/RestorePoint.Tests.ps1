# Punto de restauración automático: la regla de 24 horas, sin tocar el sistema.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    function Write-Log($msg) { }
    . (Join-Path $root 'src\engine\06-Tweaks.ps1')
}

Describe 'Punto de restauración automático' {
    It 'se crea si nunca hubo uno' {
        Test-IwinRestorePointDue $null (Get-Date) | Should -BeTrue
    }

    It 'no se repite antes de 24 horas' {
        $now = Get-Date '2026-11-17 12:00'
        Test-IwinRestorePointDue $now.AddHours(-23) $now | Should -BeFalse
    }

    It 'vuelve a poder crearse a las 24 horas' {
        $now = Get-Date '2026-11-17 12:00'
        Test-IwinRestorePointDue $now.AddHours(-24) $now | Should -BeTrue
    }
}
