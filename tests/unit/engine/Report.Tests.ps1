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
        @(Select-IwinKeyLines $segment)[0] | Should -Be 'The current system configuration does not support the installation of this package.'
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

Describe 'Descargas caducadas del fabricante (v5.5)' {
    It 'reconoce la huella desfasada y los errores HTTP 4xx como descarga caducada' {
        Test-IwinStaleDownloadCode -1978335215 | Should -BeTrue
        Test-IwinStaleDownloadCode -2145844844 | Should -BeTrue   # 0x80190194, HTTP 404 (HWiNFO)
        Test-IwinStaleDownloadCode -2145844746 | Should -BeFalse  # 0x801901F6, HTTP 502: es del servidor, no caducada
        Test-IwinStaleDownloadCode 0 | Should -BeFalse
    }

    It 'trata el HTTP 5xx como fallo del servidor y se puede reintentar' {
        Test-IwinServerErrorCode -2145844746 | Should -BeTrue    # HxD, 502
        Test-IwinServerErrorCode -2147012867 | Should -BeFalse
        (Get-IwinCodeHint -2145844746)[0] | Should -Match 'servidor'
        (Get-IwinCodeHint -2145844844)[0] | Should -Match 'ya no está'
    }

    It 'una app con web propia y descarga caducada pasa a acción manual, no a fallo' {
        $app = [pscustomobject]@{ id = 'hwinfo'; name = 'HWiNFO'; type = 'winget'; page = 'https://www.hwinfo.com/download/' }
        $info = Get-IwinFailureInfo $app ([pscustomobject]@{ code = -2145844844; ok = $false; stopped = $false }) @('12:00:00  Instalando HWiNFO...')
        $info.kind | Should -Be 'manual'
        $info.hint | Should -Match 'web del proveedor'
    }

    It 'sin web propia sigue siendo un fallo' {
        $app = [pscustomobject]@{ id = 'x'; name = 'X'; type = 'winget' }
        (Get-IwinFailureInfo $app ([pscustomobject]@{ code = -1978335215; ok = $false; stopped = $false }) @('12:00:00  Instalando X...')).kind | Should -Be 'fallo'
    }

    It 'pide cerrar Brave en el informe de Brave limpio' {
        $app = [pscustomobject]@{ id = 'braveclean'; name = 'Brave limpio'; type = 'tweak' }
        $lines = @('12:00:00  Instalando Brave limpio...', '12:00:00    Cierra Brave (incluidos sus procesos en segundo plano) y vuelve a aplicar.', '12:00:00    FALLÓ: Brave limpio')
        (Get-IwinFailureInfo $app ([pscustomobject]@{ code = 0; ok = $false; stopped = $false }) $lines).hint | Should -Match 'Cierra la aplicación'
    }
}
