# Caché de shaders (sin publicar): comprueba que la categoría solo apunta a cachés de controlador.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('iwin-shader-' + [guid]::NewGuid().ToString('N'))
    $script:Version = 'v0.0'
    function Write-Log($msg) { }
    function Test-Administrator { $true }
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\14-Maintenance.ps1')
    $script:Categories = Get-IwinCleanupCategories
}

Describe 'Caché de shaders' {
    It 'existe, no pide administrador y tiene rutas' {
        $script:Categories.Contains('shaderCache') | Should -BeTrue
        $script:Categories['shaderCache'].admin | Should -BeFalse
        @($script:Categories['shaderCache'].paths).Count | Should -BeGreaterThan 0
    }

    It 'nunca apunta a carpetas de juegos ni de anticheat' {
        foreach ($path in @($script:Categories['shaderCache'].paths)) {
            $path | Should -Not -Match '(?i)steam|epic|games|riot|vanguard|easyanticheat|battleye|hoyoplay|fortnite'
        }
    }
}
