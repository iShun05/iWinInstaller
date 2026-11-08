# Explicación de fallos del informe con líneas reales de un diagnóstico (2026-11-08, Windows 11 26300).

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    . (Join-Path $root 'lifecycle.ps1')
}

Describe 'Códigos de error' {
    It 'explica 0x8A150113 (este Windows no admite el instalador)' {
        (Get-IwinCodeHint -1978334957)[0] | Should -Match 'no admite'
        Get-IwinCodeText -1978334957 | Should -Be '0x8A150113'
    }

    It 'explica 0x80072EFD como un fallo de conexión' {
        (Get-IwinCodeHint -2147012867)[0] | Should -Match 'conectar'
        Get-IwinCodeText -2147012867 | Should -Be '0x80072EFD'
    }
}

Describe 'Motivo del informe' {
    It 'prefiere el mensaje del instalador a la línea de resumen interna' {
        $segment = @(
            'Found PowerShell [Microsoft.PowerShell] Version 7.6.9.0',
            'Successfully verified installer hash',
            'The current system configuration does not support the installation of this package.',
            'pwsh · codigo -1978334957 · 2.5 s'
        )
        (Select-IwinKeyLines $segment)[0] | Should -Be 'The current system configuration does not support the installation of this package.'
    }

    It 'salta la frase genérica de WinGet y deja el detalle' {
        $segment = @(
            'An unexpected error occurred while executing the command:',
            'InternetOpenUrl() failed.',
            '0x80072efd : unknown error',
            'eartrumpet · codigo -2147012867 · 242.1 s'
        )
        $lines = @(Select-IwinKeyLines $segment)
        $lines | Should -Not -Contain 'An unexpected error occurred while executing the command:'
        $lines | Should -Contain '0x80072efd : unknown error'
    }
}
