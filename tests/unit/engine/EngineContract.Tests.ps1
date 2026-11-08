# Pruebas del contrato interfaz ↔ motor (src/engine/09-Contract.ps1) sin instalar nada.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    # Entorno mínimo que el motor espera del script principal
    $script:Apps = @(
        [pscustomobject]@{ id = 'demo'; name = 'Demo'; type = 'winget'; winget = 'Demo.Demo' },
        [pscustomobject]@{ id = 'otra'; name = 'Otra'; type = 'winget'; winget = 'Otra.Otra' }
    )
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('iwin-contract-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:LogDir -ItemType Directory | Out-Null
    function Write-Log($msg) { }
    function Test-Cmd($name) { $false }
    function Update-WingetCache { }
    function Test-AppInstalled($app) { if ($app.id -eq 'otra') { throw 'sin acceso' }; $true }
    function Get-IwinPendingBatches { }
    function Get-IwinLastReport { $null }
    . (Join-Path $root 'src\engine\09-Contract.ps1')

    function New-Operation {
        $dir = Join-Path $script:LogDir ([guid]::NewGuid().ToString('N'))
        New-Item $dir -ItemType Directory | Out-Null
        [pscustomobject]@{ Request = Join-Path $dir 'request.json'; Response = Join-Path $dir 'response.json'; Events = Join-Path $dir 'events.jsonl' }
    }
    function Read-Events($path) { @(Get-Content $path -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }) }
}

AfterAll { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Contrato del motor' {
    It 'un comando desconocido sale con 2 y termina con el evento done' {
        $op = New-Operation
        Invoke-IwinEngineCommand 'no.existe' $null $op.Response $op.Events | Should -Be 2
        $events = Read-Events $op.Events
        $events[-1].type | Should -Be 'done'
        $events[-1].exitCode | Should -Be 2
        Test-Path $op.Response | Should -BeFalse
    }

    It 'rechaza una versión de contrato mayor con 2' {
        $op = New-Operation
        Set-Content $op.Request '{"contract":99}' -Encoding UTF8
        Invoke-IwinEngineCommand 'report.last' $op.Request $op.Response $op.Events | Should -Be 2
    }

    It 'rechaza un Request que no es JSON con 2' {
        $op = New-Operation
        Set-Content $op.Request '{roto' -Encoding UTF8
        Invoke-IwinEngineCommand 'report.last' $op.Request $op.Response $op.Events | Should -Be 2
        (Read-Events $op.Events)[-1].type | Should -Be 'done'
    }

    It 'report.last sin informe responde con report nulo' {
        $op = New-Operation
        Invoke-IwinEngineCommand 'report.last' $null $op.Response $op.Events | Should -Be 0
        $response = Get-Content $op.Response -Raw -Encoding UTF8 | ConvertFrom-Json
        $response.contract | Should -Be 1
        $response.report | Should -BeNullOrEmpty
    }

    It 'catalog.inventory distingue instalado de no comprobable' {
        $op = New-Operation
        Set-Content $op.Request '{"contract":1,"ids":["demo","otra"]}' -Encoding UTF8
        Invoke-IwinEngineCommand 'catalog.inventory' $op.Request $op.Response $op.Events | Should -Be 0
        $items = (Get-Content $op.Response -Raw -Encoding UTF8 | ConvertFrom-Json).items
        ($items | Where-Object id -eq 'demo').installed | Should -BeTrue
        ($items | Where-Object id -eq 'otra').checkable | Should -BeFalse
        $events = Read-Events $op.Events
        @($events | Where-Object type -eq 'progress').Count | Should -Be 2
        $events[-1].type | Should -Be 'done'
        $events[-1].outcome | Should -Be 'success'
    }
}
