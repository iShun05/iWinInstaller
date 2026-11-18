# Pruebas del entorno de desarrollo (plantillas Node, Python, Java) sin instalar nada.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:Catalog = @(Get-Content (Join-Path $root 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
    $script:Apps = $script:Catalog
    $script:Installed = @()
    $script:Versions = @{}
    function Write-Log($msg) { }
    function Update-EnvPath { }
    function Test-Cmd($name) { $script:Versions.ContainsKey($name) }
    function Test-AppInstalled($app) { $script:Installed -contains $app.id }
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\18-DevEnv.ps1')
    # Después de cargar el motor, para sustituir la lectura real de versiones
    function Get-IwinToolVersion([string]$command, [string[]]$arguments) { $script:Versions[$command] }
}

Describe 'Plantillas' {
    It 'cada plantilla solo usa ids que existen en el catálogo' {
        foreach ($key in $IwinDevTemplates.Keys) {
            foreach ($id in $IwinDevTemplates[$key].ids) { ($script:Catalog.id -contains $id) | Should -BeTrue -Because "$key usa $id" }
            foreach ($pin in $IwinDevTemplates[$key].pins) { ($script:Catalog.id -contains $pin.app) | Should -BeTrue }
        }
    }
    It 'solo usa pasos de la lista cerrada' {
        foreach ($key in $IwinDevTemplates.Keys) { foreach ($step in $IwinDevTemplates[$key].steps) { $IwinDevSteps.ContainsKey($step) | Should -BeTrue } }
    }
    It 'las versiones fijadas del catálogo coinciden con el pin' {
        ($script:Catalog | Where-Object id -eq 'python').winget | Should -Match '3\.13$'
        ($script:Catalog | Where-Object id -eq 'java').winget | Should -Match '\.21\.JDK$'
    }
    It 'rechaza una plantilla desconocida' {
        { & $IwinEngineCommands['devenv.status'] ([pscustomobject]@{ contract = 1; template = 'cobol' }) } | Should -Throw '*cobol*'
    }
}

Describe 'Paso Corepack' {
    It 'con Node 25 o posterior sin Corepack no dice que falte Node' {
        $script:Versions = @{ node = [version]'26.13.1' }
        & $IwinDevSteps['corepack'] | Should -Match 'no viene con este Node'
    }
    It 'sin Node dice que falta Node' {
        $script:Versions = @{}
        & $IwinDevSteps['corepack'] | Should -Match 'Node no está instalado'
    }
}

Describe 'Pin de versión' {
    It 'minMajor acepta versiones iguales o mayores' {
        $pin = [pscustomobject]@{ minMajor = 22 }
        Test-IwinDevPin $pin ([version]'22.1.0') | Should -BeTrue
        Test-IwinDevPin $pin ([version]'24.0.0') | Should -BeTrue
        Test-IwinDevPin $pin ([version]'20.9.0') | Should -BeFalse
        Test-IwinDevPin $pin $null | Should -BeFalse
    }
    It 'major y minor exactos' {
        $pin = [pscustomobject]@{ major = 3; minor = 13 }
        Test-IwinDevPin $pin ([version]'3.13.1') | Should -BeTrue
        Test-IwinDevPin $pin ([version]'3.12.4') | Should -BeFalse
    }
}

Describe 'Estado' {
    BeforeEach { $script:Installed = @(); $script:Versions = @{} }
    It 'sin nada instalado lista todo como pendiente' {
        $status = & $IwinEngineCommands['devenv.status'] ([pscustomobject]@{ contract = 1; template = 'node' })
        $status.ready | Should -BeFalse
        @($status.missing) | Should -Be @('git', 'vscode', 'node', 'pnpm')
        $status.pins[0].found | Should -BeNullOrEmpty
    }
    It 'con todo instalado y la versión correcta está listo' {
        $script:Installed = @('git', 'vscode', 'node', 'pnpm'); $script:Versions = @{ node = [version]'22.11.0' }
        $status = & $IwinEngineCommands['devenv.status'] ([pscustomobject]@{ contract = 1; template = 'node' })
        $status.ready | Should -BeTrue
        @($status.missing).Count | Should -Be 0
    }
    It 'detecta una versión distinta de la fijada aunque esté instalada' {
        $script:Installed = @('git', 'vscode', 'python'); $script:Versions = @{ python = [version]'3.11.9' }
        $status = & $IwinEngineCommands['devenv.status'] ([pscustomobject]@{ contract = 1; template = 'python' })
        $status.ready | Should -BeFalse
        $status.pins[0].ok | Should -BeFalse
        $status.pins[0].found | Should -Be '3.11.9'
    }
    It 'devenv.list devuelve las tres plantillas' {
        @((& $IwinEngineCommands['devenv.list'] ([pscustomobject]@{ contract = 1 })).templates.template) | Should -Be @('node', 'python', 'java')
    }
}

Describe 'Configuración' {
    BeforeEach { $script:Versions = @{} }
    It 'los pasos se omiten con un aviso si la herramienta no está' {
        $out = & $IwinEngineCommands['devenv.configure'] ([pscustomobject]@{ contract = 1; template = 'node' })
        $out.lines[0] | Should -Match 'omitido'
    }
}
