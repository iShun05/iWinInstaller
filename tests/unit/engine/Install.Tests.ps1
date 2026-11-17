# Pruebas de los comandos de Instalar del motor (v4.6) sin instalar nada.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('iwin-install-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:LogDir -ItemType Directory | Out-Null
    $script:Apps = @(
        [pscustomobject]@{ id = 'git'; name = 'Git'; type = 'winget'; winget = 'Git.Git'; section = 'Terminal' },
        [pscustomobject]@{ id = 'demo'; name = 'Demo App'; type = 'winget'; winget = 'Demo.App'; section = 'Aplicaciones'; configure = $true; configNote = 'Inicia sesión.' },
        [pscustomobject]@{ id = 'oscuro'; name = 'Tema oscuro'; type = 'tweak'; section = 'Sistema'; restart = $true; postInstall = [pscustomobject]@{ steps = @('Uno', 'Dos'); note = 'Nota' } }
    )
    function Write-Log($msg) { }
    function Get-IwinPreflight($plan) { [pscustomobject]@{ Ok = $true; Text = 'Espacio suficiente.' } }
    . (Join-Path $root 'lifecycle.ps1')
    . (Join-Path $root 'src\engine\02-Packages.ps1')
    function Get-InstallContext($app) { if ($app.type -eq 'tweak') { 'user' } else { 'machine' } }
    # El inventario real (02-Packages) lee el registro y Appx: aquí se sustituyen por datos de prueba
    # 02-Packages declara $RegistryApps/$AppxApps en este ámbito; se quitan para que Update-LocalInventory (que escribe en $script:) y la lectura coincidan
    Remove-Variable RegistryApps, AppxApps -ErrorAction SilentlyContinue
    $script:RegistryApps = @(); $script:AppxApps = @()
    $global:IwinFakeRegistry = @()
    function Get-ItemProperty { $global:IwinFakeRegistry }
    function Get-AppxPackage { @() }
    function Update-EnvPath { }
    function Update-WingetCache { }
    function Test-Cmd($name) { $false }
    function Get-NormName($s) { ($s -replace '[^A-Za-z0-9]', '').ToLower() }
    function Test-AppInstalled($app) { $true }
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\12-Install.ps1')
}

AfterAll { Remove-Variable IwinFakeRegistry -Scope Global -ErrorAction SilentlyContinue; Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }

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

    It 'Por configurar: el check se quita solo cuando cambia la versión instalada' {
        $global:IwinFakeRegistry = @([pscustomobject]@{ DisplayName = 'Demo App'; DisplayVersion = '1.0' })
        $set = & $IwinEngineCommands['postinstall.set'] ([pscustomobject]@{ contract = 1; id = 'demo'; steps = @(0, 1) })
        $set.configured | Should -BeTrue
        $first = & $IwinEngineCommands['configure.list'] ([pscustomobject]@{ contract = 1 })
        $item = $first.items | Where-Object id -eq 'demo'
        $item.configured | Should -BeTrue
        $item.version | Should -Be '1.0'
        $global:IwinFakeRegistry = @([pscustomobject]@{ DisplayName = 'Demo App'; DisplayVersion = '1.1' })
        $second = & $IwinEngineCommands['configure.list'] ([pscustomobject]@{ contract = 1 })
        $item = $second.items | Where-Object id -eq 'demo'
        $item.configured | Should -BeFalse
        $item.reopenedFrom | Should -Be '1.0'
        $again = & $IwinEngineCommands['configure.list'] ([pscustomobject]@{ contract = 1 })
        ($again.items | Where-Object id -eq 'demo').configured | Should -BeFalse
        $done = & $IwinEngineCommands['postinstall.set'] ([pscustomobject]@{ contract = 1; id = 'demo'; steps = @(0, 1) })
        $done.configured | Should -BeTrue
        $last = & $IwinEngineCommands['configure.list'] ([pscustomobject]@{ contract = 1 })
        ($last.items | Where-Object id -eq 'demo').reopenedFrom | Should -Be ''
    }

    It 'postinstall.set sin nota conserva la nota guardada' {
        & $IwinEngineCommands['postinstall.set'] ([pscustomobject]@{ contract = 1; id = 'oscuro'; steps = @(0); note = 'mi nota' }) | Out-Null
        & $IwinEngineCommands['postinstall.set'] ([pscustomobject]@{ contract = 1; id = 'oscuro'; steps = @(0, 1) }) | Out-Null
        (& $IwinEngineCommands['postinstall.get'] ([pscustomobject]@{ contract = 1; ids = @('oscuro') })).guides[0].userNote | Should -Be 'mi nota'
    }

    It 'el archivo de pausa del contrato se deriva del Request' {
        $script:EngineRequest = Join-Path $script:LogDir 'op\request.json'
        Get-IwinEngineCancelFile | Should -Be (Join-Path $script:LogDir 'op\cancel')
    }
}
