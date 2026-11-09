# Pruebas de los comandos de Instalar del motor (v4.6) sin instalar nada.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('iwin-install-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:LogDir -ItemType Directory | Out-Null
    $script:Apps = @(
        [pscustomobject]@{ id = 'git'; name = 'Git'; type = 'winget'; winget = 'Git.Git'; section = 'Terminal' },
        [pscustomobject]@{ id = 'oscuro'; name = 'Tema oscuro'; type = 'tweak'; section = 'Sistema'; restart = $true; postInstall = [pscustomobject]@{ steps = @('Uno', 'Dos'); note = 'Nota' } }
    )
    function Write-Log($msg) { }
    function Get-InstallContext($app) { if ($app.type -eq 'tweak') { 'user' } else { 'machine' } }
    function Get-IwinPreflight($plan) { [pscustomobject]@{ Ok = $true; Text = 'Espacio suficiente.' } }
    . (Join-Path $root 'lifecycle.ps1')
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\12-Install.ps1')
}

AfterAll { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Comandos de Instalar' {
    It 'rechaza ids desconocidos' {
        { Get-IwinSelection @('git', 'noexiste') } | Should -Throw '*noexiste*'
    }

    It 'install.preflight devuelve el plan con contexto, ajuste y reinicio' {
        $response = & $IwinEngineCommands['install.preflight'] ([pscustomobject]@{ contract = 1; operation = 'install'; ids = @('git', 'oscuro') })
        $response.ok | Should -BeTrue
        ($response.plan | Where-Object id -eq 'git').context | Should -Be 'machine'
        ($response.plan | Where-Object id -eq 'oscuro').tweak | Should -BeTrue
        ($response.plan | Where-Object id -eq 'oscuro').restart | Should -BeTrue
    }

    It 'install.preflight rechaza operaciones desconocidas' {
        { & $IwinEngineCommands['install.preflight'] ([pscustomobject]@{ contract = 1; operation = 'borrar'; ids = @('git') }) } | Should -Throw
    }

    It 'los pasos marcados se guardan y la opción queda configurada al completarlos' {
        $set = & $IwinEngineCommands['postinstall.set'] ([pscustomobject]@{ contract = 1; id = 'oscuro'; steps = @(0, 1, 7); note = 'hecho' })
        $set.configured | Should -BeTrue
        $get = & $IwinEngineCommands['postinstall.get'] ([pscustomobject]@{ contract = 1; ids = @('oscuro') })
        @($get.guides[0].done) | Should -Be @(0, 1)
        $get.guides[0].userNote | Should -Be 'hecho'
    }

    It 'el archivo de pausa del contrato se deriva del Request' {
        $script:EngineRequest = Join-Path $script:LogDir 'op\request.json'
        Get-IwinEngineCancelFile | Should -Be (Join-Path $script:LogDir 'op\cancel')
    }
}
