# Se ejecuta con PowerShell x86 de Windows; no basta con analizar sintaxis desde un host x64.
$ErrorActionPreference='Stop'
if([Environment]::Is64BitProcess){throw 'Esta prueba debe correr realmente en un proceso de 32 bits'}
Write-Host "Host x86 real: PowerShell $($PSVersionTable.PSVersion), proceso $PID"
$root=Split-Path $PSScriptRoot
foreach($name in 'iWinInstaller.ps1','lifecycle.ps1','install.ps1'){
    $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$null,[ref]$errors)
    if($errors){throw ($errors | Out-String)}
}
& (Join-Path $PSScriptRoot 'check-lifecycle.ps1')
if($LASTEXITCODE){throw 'Fallaron las regresiones de ciclo de vida en x86'}
. (Join-Path $root 'lifecycle.ps1')
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'iWinInstaller.ps1'),[ref]$null,[ref]$errors)
$node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Install-BundledWinget'},$true)
. ([scriptblock]::Create($node.Extent.Text))
$fixture=Join-Path $env:TEMP ('iwin-x86-'+[guid]::NewGuid().ToString('N'))
$previousRoot=$Root;$previousArchitecture=$env:PROCESSOR_ARCHITECTURE;$previousWow=$env:PROCESSOR_ARCHITEW6432
try{
    $Root=$fixture
    New-Item (Join-Path $fixture 'native'),(Join-Path $fixture 'prerequisites'),(Join-Path $fixture 'deps/x86'),(Join-Path $fixture 'deps/x64'),(Join-Path $fixture 'deps/arm64') -ItemType Directory -Force | Out-Null
    foreach($arch in 'x86','x64','arm64'){Set-Content (Join-Path $fixture "deps/$arch/Microsoft.Fixture_1.0.0.0_$arch.appx") 'paquete simulado'}
    $zip=Join-Path $fixture 'prerequisites/DesktopAppInstaller_Dependencies.zip'
    Compress-Archive (Join-Path $fixture 'deps/*') $zip
    $bundle=Join-Path $fixture 'prerequisites/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    Set-Content $bundle 'bundle simulado; Add-AppxPackage se intercepta'
    $metadata=@{assets=@($zip,$bundle | ForEach-Object {@{name=(Split-Path $_ -Leaf);digest=('sha256:'+(Get-FileHash $_).Hash.ToLowerInvariant())}})}
    $metadata | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $fixture 'native/prerequisites.json') -Encoding UTF8
    function Write-Log($message){}
    function Update-EnvPath{}
    function Get-AppxPackage{@()}
    function Test-WingetReady{$true}
    $script:dependencies=@()
    function Add-AppxPackage{param($Path,$DependencyPath,$ErrorAction)$script:dependencies=@($DependencyPath)}
    $env:PROCESSOR_ARCHITECTURE='x86';$env:PROCESSOR_ARCHITEW6432=$null
    if(-not (Install-BundledWinget)){throw 'No se seleccionaron las dependencias x86'}
    if($script:dependencies.Count -ne 1 -or $script:dependencies[0] -notmatch '\\x86\\'){throw 'Un Windows x86 debe recibir exclusivamente sus dependencias'}
    Write-Host 'OK: parser, JSON, registro, servicios, recuperación y dependencias en PowerShell x86; sin instalar paquetes reales.'
}finally{
    $Root=$previousRoot;$env:PROCESSOR_ARCHITECTURE=$previousArchitecture;$env:PROCESSOR_ARCHITEW6432=$previousWow
    Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
$global:LASTEXITCODE=0
