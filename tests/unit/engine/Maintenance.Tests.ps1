# Limpieza e informe del equipo (v4.9) en carpetas de prueba: nunca toca el sistema real.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('iwin-mant-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:LogDir -ItemType Directory | Out-Null
    $script:Version = 'v0.0'
    function Write-Log($msg) { }
    function Test-Administrator { $true }
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\14-Maintenance.ps1')
    # Una sola categoría apuntando a una carpeta de prueba
    $script:Fixture = Join-Path $script:LogDir 'temp'
    New-Item $script:Fixture -ItemType Directory | Out-Null
    function Get-IwinCleanupCategories { [ordered]@{ prueba = @{ label = 'Prueba'; admin = $false; paths = @($script:Fixture) } } }
}

AfterAll { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Limpieza' {
    It 'solo borra lo que tiene más de un día y lo cuenta' {
        $old = Join-Path $script:Fixture 'viejo.tmp'; $new = Join-Path $script:Fixture 'nuevo.tmp'
        Set-Content $old ('x' * 4096); Set-Content $new ('y' * 4096)
        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-3)
        $estimate = & $IwinEngineCommands['maintenance.estimate'] ([pscustomobject]@{ contract = 1 })
        $estimate.categories[0].estimatedBytes | Should -BeGreaterThan 4000
        $done = & $IwinEngineCommands['maintenance.clean'] ([pscustomobject]@{ contract = 1; categories = @('prueba') })
        $done.categories[0].freedBytes | Should -BeGreaterThan 4000
        Test-Path $old | Should -BeFalse
        Test-Path $new | Should -BeTrue
    }

    It 'no entra en uniones ni enlaces: nunca borra fuera de la carpeta de la categoría' {
        $outside = Join-Path $script:LogDir 'fuera'
        New-Item $outside -ItemType Directory | Out-Null
        $precious = Join-Path $outside 'documento.txt'
        Set-Content $precious ('z' * 4096)
        (Get-Item $precious).LastWriteTime = (Get-Date).AddDays(-30)
        $junction = Join-Path $script:Fixture 'enlace'
        & cmd.exe /c mklink /J "$junction" "$outside" | Out-Null
        try {
            & $IwinEngineCommands['maintenance.clean'] ([pscustomobject]@{ contract = 1; categories = @('prueba') }) | Out-Null
            Test-Path $precious | Should -BeTrue
        } finally { & cmd.exe /c rmdir "$junction" | Out-Null }
    }

    It 'borra los archivos antiguos de subcarpetas normales' {
        $sub = Join-Path $script:Fixture 'sub\hondo'
        New-Item $sub -ItemType Directory -Force | Out-Null
        $old = Join-Path $sub 'viejo.tmp'
        Set-Content $old ('x' * 100)
        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-3)
        & $IwinEngineCommands['maintenance.clean'] ([pscustomobject]@{ contract = 1; categories = @('prueba') }) | Out-Null
        Test-Path $old | Should -BeFalse
    }

    It 'rechaza categorías desconocidas' {
        { & $IwinEngineCommands['maintenance.clean'] ([pscustomobject]@{ contract = 1; categories = @('documentos') }) } | Should -Throw '*desconocidas*'
    }
}

Describe 'Informe del equipo' {
    It 'sin marcarlo no incluye número de serie, equipo ni usuario' {
        $path = Join-Path $script:LogDir 'informe.json'
        & $IwinEngineCommands['report.machine'] ([pscustomobject]@{ contract = 1; path = $path; includeSensitive = $false }) | Out-Null
        $text = Get-Content $path -Raw
        $text | Should -Not -Match '"serial"'
        $text | Should -Not -Match ([regex]::Escape($env:COMPUTERNAME))
        (ConvertFrom-Json $text).format | Should -Be 'iWinInstaller-informe-equipo'
    }
}
