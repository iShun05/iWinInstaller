# Validaciones de los comandos de Sistema, Seguridad y Vincular equipos (v4.7) sin cambiar el equipo.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('iwin-tools-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:LogDir -ItemType Directory | Out-Null
    $script:SshAdminKeys = Join-Path $script:LogDir 'administrators_authorized_keys'
    function Write-Log($msg) { }
    function Test-UserIsAdminGroup { $false }
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\13-Tools.ps1')
    # Las claves del usuario de prueba van a una carpeta temporal
    function Get-LinkKeysPath { Join-Path $script:LogDir 'authorized_keys' }
}

AfterAll { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Energía' {
    It 'rechaza tiempos negativos o de más de un día' {
        { & $IwinEngineCommands['power.set'] ([pscustomobject]@{ contract = 1; monitor = -1; sleep = 0; hibernateAfter = 0; hibernate = $false }) } | Should -Throw
        { & $IwinEngineCommands['power.set'] ([pscustomobject]@{ contract = 1; monitor = 10; sleep = 5000; hibernateAfter = 0; hibernate = $false }) } | Should -Throw
    }
}

Describe 'Vincular equipos' {
    It 'rechaza una clave privada' {
        { & $IwinEngineCommands['link.authorize'] ([pscustomobject]@{ contract = 1; key = '-----BEGIN OPENSSH PRIVATE KEY----- abc' }) } | Should -Throw '*privada*'
    }

    It 'rechaza texto que no es una clave pública' {
        { & $IwinEngineCommands['link.authorize'] ([pscustomobject]@{ contract = 1; key = 'hola mundo' }) } | Should -Throw '*formato*'
    }

    It 'autoriza una clave pública una sola vez' {
        $key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGzX8fLsT0d2iNjbYk8zR6pQ1v3mW9cU4hE7aB2nK5xY mac@prueba'
        (& $IwinEngineCommands['link.authorize'] ([pscustomobject]@{ contract = 1; key = $key })).added | Should -BeTrue
        (& $IwinEngineCommands['link.authorize'] ([pscustomobject]@{ contract = 1; key = $key })).added | Should -BeFalse
        @(Get-Content (Get-LinkKeysPath)) | Should -Be @($key)
        @((& $IwinEngineCommands['link.keys'] ([pscustomobject]@{ contract = 1 })).keys) | Should -Be @('mac@prueba')
    }
}

Describe 'Seguridad' {
    It 'rechaza acciones desconocidas' {
        { & $IwinEngineCommands['security.run'] ([pscustomobject]@{ contract = 1; action = 'borrar' }) } | Should -Throw
    }
}
