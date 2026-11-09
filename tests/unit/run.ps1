# Ejecuta las pruebas unitarias con Pester 5 y sale con el número de fallos.
# -Shell powershell → pruebas de sintaxis 5.1; -Shell pwsh → pruebas de esquema (Test-Json 2020-12).
param([ValidateSet('powershell', 'pwsh')][string]$Shell = 'pwsh')

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.5.0' })) {
    # Pester 3 viene con Windows: se instala la 5 solo para el usuario actual
    Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module Pester -MinimumVersion 5.5.0

$files = if ($Shell -eq 'powershell') { 'Syntax.Tests.ps1', 'EngineContract.Tests.ps1', 'Updates.Tests.ps1', 'Report.Tests.ps1', 'Exclusions.Tests.ps1', 'Install.Tests.ps1', 'Tools.Tests.ps1' } else { 'Catalog.Schema.Tests.ps1' }
$config = New-PesterConfiguration
$config.Run.Path = @($files | ForEach-Object { Join-Path $PSScriptRoot "engine\$_" })
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $PSScriptRoot "resultados-$Shell.xml"
$result = Invoke-Pester -Configuration $config
exit $result.FailedCount
