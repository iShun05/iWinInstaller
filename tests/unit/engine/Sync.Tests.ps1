# Pruebas de la sincronización con un repo privado (src/engine/19-Sync.ps1) sin red ni git.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:Base = Join-Path ([IO.Path]::GetTempPath()) ('iwin-sync-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:Base -ItemType Directory | Out-Null
    $script:LogDir = $script:Base
    $script:Public = $false
    function Write-Log($msg) { }
    function Test-Cmd($name) { $false }
    . (Join-Path $root 'lifecycle.ps1')
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\19-Sync.ps1')
    function Test-IwinSyncRepoPublic($repo) { $script:Public }
}

AfterAll { Remove-Item $script:Base -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Dirección del repo' {
    It 'acepta https://github.com/usuario/repo con o sin .git' {
        (ConvertTo-IwinSyncRepo 'https://github.com/iShun05/mi-config').Url | Should -Be 'https://github.com/iShun05/mi-config.git'
        (ConvertTo-IwinSyncRepo 'https://github.com/iShun05/mi-config.git/').Name | Should -Be 'mi-config'
    }
    It 'rechaza rutas locales, ssh, otros servidores y opciones de git' {
        foreach ($bad in @('C:\repo', 'git@github.com:a/b.git', 'https://gitlab.com/a/b', 'https://github.com/a/b/../c', '--upload-pack=calc', 'file:///x', '', 'http://github.com/a/b')) {
            ConvertTo-IwinSyncRepo $bad | Should -BeNullOrEmpty -Because $bad
        }
    }
}

Describe 'Conectar' {
    BeforeEach { Remove-Item (Get-IwinSyncDir) -Recurse -Force -ErrorAction SilentlyContinue }
    It 'sin conectar el estado lo dice' {
        (& $IwinEngineCommands['sync.status'] ([pscustomobject]@{ contract = 1 })).connected | Should -BeFalse
    }
    It 'conecta un repo privado y lo recuerda' {
        $script:Public = $false
        $out = & $IwinEngineCommands['sync.connect'] ([pscustomobject]@{ contract = 1; repo = 'https://github.com/iShun05/mi-config' })
        $out.privateChecked | Should -BeTrue
        (& $IwinEngineCommands['sync.status'] ([pscustomobject]@{ contract = 1 })).repo | Should -Be 'iShun05/mi-config'
    }
    It 'se niega a usar un repo público' {
        $script:Public = $true
        { & $IwinEngineCommands['sync.connect'] ([pscustomobject]@{ contract = 1; repo = 'https://github.com/iShun05/publico' }) } | Should -Throw '*público*'
        (& $IwinEngineCommands['sync.status'] ([pscustomobject]@{ contract = 1 })).connected | Should -BeFalse
    }
    It 'rechaza una dirección que no es de GitHub' {
        { & $IwinEngineCommands['sync.connect'] ([pscustomobject]@{ contract = 1; repo = 'https://example.com/a/b' }) } | Should -Throw '*https://github.com*'
    }
    It 'subir sin conectar da un error de uso y sin Git no ejecuta nada' {
        { & $IwinEngineCommands['sync.push'] ([pscustomobject]@{ contract = 1 }) } | Should -Throw '*conecta*'
    }
    It 'desconectar borra el estado local' {
        $script:Public = $false
        & $IwinEngineCommands['sync.connect'] ([pscustomobject]@{ contract = 1; repo = 'https://github.com/iShun05/mi-config' }) | Out-Null
        & $IwinEngineCommands['sync.disconnect'] ([pscustomobject]@{ contract = 1 }) | Out-Null
        (& $IwinEngineCommands['sync.status'] ([pscustomobject]@{ contract = 1 })).connected | Should -BeFalse
    }
}
