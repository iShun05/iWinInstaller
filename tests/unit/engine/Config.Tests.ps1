# Pruebas de exportar/importar configuración y de la plantilla multi-PC (v5.4) sin instalar nada.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:Root = $root
    $script:Base = Join-Path ([IO.Path]::GetTempPath()) ('iwin-config-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:Base -ItemType Directory | Out-Null
    $script:LogDir = Join-Path $script:Base 'a'
    $script:Version = 'v5.4'
    $script:Installed = @('git', 'oscuro')
    $script:Apps = @(
        [pscustomobject]@{ id = 'git'; name = 'Git'; type = 'winget'; winget = 'Git.Git'; section = 'Terminal' },
        [pscustomobject]@{ id = 'oscuro'; name = 'Tema oscuro'; type = 'tweak'; section = 'Sistema'; postInstall = [pscustomobject]@{ steps = @('Uno', 'Dos'); note = 'Nota' } },
        [pscustomobject]@{ id = 'nvapp'; name = 'App NVIDIA'; type = 'winget'; winget = 'Nvidia.App'; section = 'Aplicaciones'; hardware = 'NVIDIA' },
        [pscustomobject]@{ id = 'amdapp'; name = 'App AMD'; type = 'winget'; winget = 'Amd.App'; section = 'Aplicaciones'; hardware = 'AMD' }
    )
    function Write-Log($msg) { }
    function Test-Cmd($name) { $false }
    function Update-WingetCache { }
    function Test-AppInstalled($app) { $script:Installed -contains $app.id }
    function Get-InstallContext($app) { 'user' }
    function Get-IwinPreflight($plan) { [pscustomobject]@{ Ok = $true; Text = '' } }
    . (Join-Path $root 'lifecycle.ps1')
    . (Join-Path $root 'src\engine\07-Profiles.ps1')
    function Get-HardwareText { @('GPU: AMD Radeon RX 7800') }
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\10-Updates.ps1')
    . (Join-Path $root 'src\engine\12-Install.ps1')
    . (Join-Path $root 'src\engine\16-Config.ps1')

    function New-Pc([string]$name) {
        $script:LogDir = Join-Path $script:Base $name
        New-Item $script:LogDir -ItemType Directory -Force | Out-Null
    }
    function Export-Config($extra = @{}) {
        $request = @{ contract = 1; path = (Join-Path $script:Base ([guid]::NewGuid().ToString('N') + '.iwin-config.json')) } + $extra
        $response = & $IwinEngineCommands['config.export'] ([pscustomobject]$request)
        [pscustomobject]@{ Path = $response.path; Response = $response; Json = (Get-Content $response.path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    }
}

AfterAll { Remove-Item $script:Base -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Exportar' {
    BeforeEach { New-Pc 'origen'; $script:Installed = @('git', 'oscuro') }

    It 'escribe el esquema versionado con lo instalado y los ajustes aplicados' {
        $export = Export-Config
        $export.Json.formato | Should -Be 'iWinInstaller-config'
        $export.Json.version | Should -Be 1
        $export.Json.app | Should -Be 'v5.4'
        @($export.Json.secciones.perfil.apps) | Should -Be @('git', 'oscuro')
    }

    It 'con ids explícitos exporta solo esos' {
        $export = Export-Config @{ ids = @('git') }
        @($export.Json.secciones.perfil.apps) | Should -Be @('git')
    }

    It 'rechaza ids desconocidos' {
        { Export-Config @{ ids = @('noexiste') } } | Should -Throw '*noexiste*'
    }

    It 'las notas y el servidor del juego solo van con includePersonal' {
        & $IwinEngineCommands['postinstall.set'] ([pscustomobject]@{ contract = 1; id = 'oscuro'; steps = @(0); note = 'secreto' }) | Out-Null
        Write-IwinJson (Join-Path $script:LogDir 'interfaz.json') ([ordered]@{ format = 'iWinInstaller-interfaz'; version = 1; zoom = 1.2; gameServer = '203.0.113.7' })
        $plain = Export-Config
        $plain.Json.secciones.seguimiento.oscuro.nota | Should -BeNullOrEmpty
        @($plain.Json.secciones.seguimiento.oscuro.pasos) | Should -Be @(0)
        $plain.Json.secciones.interfaz.servidorJuego | Should -BeNullOrEmpty
        (Get-Content $plain.Path -Raw) | Should -Not -Match 'secreto|203\.0\.113\.7'
        $personal = Export-Config @{ includePersonal = $true }
        $personal.Json.secciones.seguimiento.oscuro.nota | Should -Be 'secreto'
        $personal.Json.secciones.interfaz.servidorJuego | Should -Be '203.0.113.7'
    }
}

Describe 'Importar en otro PC' {
    BeforeAll {
        New-Pc 'origen'
        $script:Installed = @('git', 'oscuro')
        & $IwinEngineCommands['postinstall.set'] ([pscustomobject]@{ contract = 1; id = 'oscuro'; steps = @(0, 1); note = 'hecho' }) | Out-Null
        Set-IwinExclusion 'Git.Git' $true
        Write-IwinJson (Join-Path $script:LogDir 'interfaz.json') ([ordered]@{ format = 'iWinInstaller-interfaz'; version = 1; zoom = 1.3; gameServer = '' })
        $script:Template = (Export-Config @{ includePersonal = $true }).Path
    }
    BeforeEach { New-Pc ('destino-' + [guid]::NewGuid().ToString('N')) }

    It 'config.inspect describe sin escribir nada' {
        $plan = & $IwinEngineCommands['config.inspect'] ([pscustomobject]@{ contract = 1; path = $script:Template })
        @($plan.ids) | Should -Be @('git', 'oscuro')
        @($plan.sections) | Should -Contain 'seguimiento'
        @(Get-ChildItem $script:LogDir -File).Count | Should -Be 0
    }

    It 'config.import aplica exclusiones, seguimiento e interfaz y devuelve los ids a instalar' {
        $result = & $IwinEngineCommands['config.import'] ([pscustomobject]@{ contract = 1; path = $script:Template })
        @($result.errors).Count | Should -Be 0
        @($result.ids) | Should -Be @('git', 'oscuro')
        @(Get-IwinExclusions) | Should -Be @('Git.Git')
        $state = Get-PostInstallState
        @($state['oscuro'].steps) | Should -Be @(0, 1)
        $state['oscuro'].note | Should -Be 'hecho'
        (Get-IwinConfiguredApps)['oscuro'] | Should -BeTrue
        (Read-IwinInterface)['zoom'] | Should -Be 1.3
    }

    It 'une los pasos con los que ya había y conserva la nota local' {
        & $IwinEngineCommands['postinstall.set'] ([pscustomobject]@{ contract = 1; id = 'oscuro'; steps = @(1); note = 'mía' }) | Out-Null
        & $IwinEngineCommands['config.import'] ([pscustomobject]@{ contract = 1; path = $script:Template; sections = @('seguimiento') }) | Out-Null
        $state = Get-PostInstallState
        @($state['oscuro'].steps) | Should -Be @(0, 1)
        $state['oscuro'].note | Should -Be 'mía'
    }

    It 'solo aplica las secciones pedidas' {
        & $IwinEngineCommands['config.import'] ([pscustomobject]@{ contract = 1; path = $script:Template; sections = @('exclusiones') }) | Out-Null
        @(Get-IwinExclusions) | Should -Be @('Git.Git')
        Test-Path (Join-Path $script:LogDir 'postinstalacion.json') | Should -BeFalse
    }

    It 'omite las apps de otro hardware y los ids que no existen' {
        $path = Join-Path $script:Base 'hw.iwin-config.json'
        Set-Content $path '{"formato":"iWinInstaller-config","version":1,"secciones":{"perfil":{"apps":["git","nvapp","amdapp","fantasma",7]}}}' -Encoding UTF8
        $plan = & $IwinEngineCommands['config.inspect'] ([pscustomobject]@{ contract = 1; path = $path })
        @($plan.ids) | Should -Be @('git', 'amdapp')
        ($plan.lines -join ' ') | Should -Match 'otro hardware'
    }

    It 'ignora un paso de una guía distinta' {
        $path = Join-Path $script:Base 'guia.iwin-config.json'
        Set-Content $path '{"formato":"iWinInstaller-config","version":1,"secciones":{"seguimiento":{"oscuro":{"pasos":[0],"guia":"OTRA"}}}}' -Encoding UTF8
        & $IwinEngineCommands['config.import'] ([pscustomobject]@{ contract = 1; path = $path }) | Out-Null
        Test-Path (Join-Path $script:LogDir 'postinstalacion.json') | Should -BeFalse
    }

    It 'limita el zoom y rechaza servidores con caracteres raros' {
        $path = Join-Path $script:Base 'ui.iwin-config.json'
        Set-Content $path '{"formato":"iWinInstaller-config","version":1,"secciones":{"interfaz":{"zoom":9,"servidorJuego":"a b;rm"}}}' -Encoding UTF8
        & $IwinEngineCommands['config.import'] ([pscustomobject]@{ contract = 1; path = $path }) | Out-Null
        $ui = Read-IwinInterface
        $ui['zoom'] | Should -Be 2.0
        $ui.Contains('gameServer') | Should -BeFalse
    }

    It 'las exclusiones con ids raros se descartan' {
        $path = Join-Path $script:Base 'ex.iwin-config.json'
        Set-Content $path '{"formato":"iWinInstaller-config","version":1,"secciones":{"exclusiones":{"ids":["A.B","a b;rm",5]}}}' -Encoding UTF8
        & $IwinEngineCommands['config.import'] ([pscustomobject]@{ contract = 1; path = $path }) | Out-Null
        @(Get-IwinExclusions) | Should -Be @('A.B')
    }
}

Describe 'Compatibilidad del formato' {
    BeforeEach { New-Pc 'compat' }

    It 'rechaza una versión de esquema más nueva' {
        $path = Join-Path $script:Base 'nueva.json'
        Set-Content $path '{"formato":"iWinInstaller-config","version":2,"secciones":{}}' -Encoding UTF8
        { & $IwinEngineCommands['config.inspect'] ([pscustomobject]@{ contract = 1; path = $path }) } | Should -Throw '*más nueva*'
    }

    It 'rechaza otros formatos y JSON roto' {
        $path = Join-Path $script:Base 'otro.json'
        Set-Content $path '{"formato":"otra-cosa","version":1}' -Encoding UTF8
        { Read-IwinConfigFile $path } | Should -Throw '*No es una configuración*'
        Set-Content $path '{roto' -Encoding UTF8
        { Read-IwinConfigFile $path } | Should -Throw '*JSON*'
    }

    It 'las secciones desconocidas se ignoran y se avisan; los campos nuevos no estorban' {
        $path = Join-Path $script:Base 'futuro.json'
        Set-Content $path '{"formato":"iWinInstaller-config","version":1,"campoNuevo":1,"secciones":{"perfil":{"apps":["git"],"extra":true},"rgb":{"x":1}}}' -Encoding UTF8
        $plan = & $IwinEngineCommands['config.inspect'] ([pscustomobject]@{ contract = 1; path = $path })
        @($plan.ignored) | Should -Be @('rgb')
        @($plan.ids) | Should -Be @('git')
    }

    It 'acepta un perfil exportado con el formato anterior' {
        $path = Join-Path $script:Base 'viejo.iwin.json'
        Set-Content $path '{"formato":"iWinInstaller-perfil","version":1,"nombre":"Viejo","apps":["git","oscuro"]}' -Encoding UTF8
        $plan = & $IwinEngineCommands['config.inspect'] ([pscustomobject]@{ contract = 1; path = $path })
        $plan.name | Should -Be 'Viejo'
        @($plan.ids) | Should -Be @('git', 'oscuro')
    }

    It 'otras funciones pueden registrar su propia sección' {
        Register-IwinConfigSection 'prueba' { param($ctx) [ordered]@{ valor = 42 } } { param($data, $ctx) "Prueba: $($data.valor)" }
        try {
            $export = Export-Config
            $export.Json.secciones.prueba.valor | Should -Be 42
            $plan = & $IwinEngineCommands['config.inspect'] ([pscustomobject]@{ contract = 1; path = $export.Path })
            $plan.lines | Should -Contain 'Prueba: 42'
        } finally { $IwinConfigSections.Remove('prueba') }
    }

    It 'rechaza nombres de sección no válidos' {
        { Register-IwinConfigSection 'Mal Nombre' {} {} } | Should -Throw
    }

    It 'una sección que falla al importar no impide las demás' {
        Register-IwinConfigSection 'rota' { param($ctx) $null } { param($data, $ctx) throw 'fallo' }
        try {
            $path = Join-Path $script:Base 'rota.json'
            Set-Content $path '{"formato":"iWinInstaller-config","version":1,"secciones":{"rota":{},"perfil":{"apps":["git"]}}}' -Encoding UTF8
            $plan = & $IwinEngineCommands['config.inspect'] ([pscustomobject]@{ contract = 1; path = $path })
            @($plan.errors).Count | Should -Be 1
            @($plan.ids) | Should -Be @('git')
        } finally { $IwinConfigSections.Remove('rota') }
    }
}
