# Pruebas aisladas: no instalan programas ni cambian ajustes reales.
$ErrorActionPreference = 'Stop'
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\iWinInstaller.ps1'), [ref]$null, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
function Get-FunctionBody($name) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "Falta $name" }
    [scriptblock]::Create($node.Extent.Text)
}
& {
    . (Get-FunctionBody 'Ensure-Winget')
    . (Get-FunctionBody 'Test-WingetReady')
    function Install-BundledWinget { $false }
    function Update-EnvPath { }
    function Write-Log($msg) { }
    function Test-Cmd($name) { $script:ready }
    function winget { $global:LASTEXITCODE = 0 }
    function Add-AppxPackage { throw 'No registrado' }
    function Install-PackageProvider { }
    function Install-Module { }
    function Import-Module { }
    function Repair-WinGetPackageManager { $script:repaired++; $script:ready = $true }
    $script:ready = $false; $script:repaired = 0
    if (-not (Ensure-Winget) -or $script:repaired -ne 1) { throw 'Debe preparar winget si falta' }
    if (-not (Ensure-Winget) -or $script:repaired -ne 1) { throw 'No debe reparar winget si ya funciona' }
}
& {
    . (Get-FunctionBody 'Invoke-Install')
    function Organize-Desktop { }
    function Test-Administrator { $false }
    function Get-InstallContext { 'user' }
    function Write-Log($msg) { }
    function Update-WingetCache { $script:WingetIds = @() }
    function Ensure-Winget { $true }
    function Test-AppInstalled($app) { $app.id -eq 'existente' -or $app.id -eq 'correcta' -and $script:calls -contains 'correcta' }
    function Install-App($app) { $script:calls += $app.id; $script:done = $true; $true }
    $Apps = @('cancelada', 'correcta', 'existente') | ForEach-Object { [pscustomobject]@{ id = $_; name = $_; type = $(if ($_ -eq 'cancelada') { 'download' } else { 'winget' }); winget = $_ } }
    $Retryable = @(); $script:calls = @(); $script:done = $false
    $fail = @(Invoke-Install $Apps $null)
    if ($fail.Count -ne 1 -or $fail[0].id -ne 'cancelada') { throw 'No puede confirmar una instalacion cancelada' }
    if ($script:calls -contains 'existente' -or $script:calls -notcontains 'correcta') { throw 'Debe omitir lo instalado y continuar con el resto' }
}
& {
    . (Get-FunctionBody 'Invoke-Update')
    function Write-Log($msg) { }
    function Ensure-Winget { $true }
    function Start-Process { [pscustomobject]@{ HasExited = $true; ExitCode = 0 } }
    function Wait-Proc { }
    function Update-Self { $false }
    function Update-WingetCache { }
    function Invoke-Install { @() }
    $Apps = @()
    $wingetOk = @(0); $SetupDir = $env:TEMP; $Version = 'prueba'
    if (Invoke-Update) { throw 'Una autoactualizacion fallida no puede anunciar exito' }
}
Write-Host 'OK: prepara dependencias, omite lo instalado, confirma el resultado y propaga errores.'

& {
    . (Get-FunctionBody 'Wait-Proc')
    function Invoke-UiPump { }
    $p = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile -Command exit 7'
    Wait-Proc $p 30
    if (-not $p.HasExited -or $p.ExitCode -ne 7) { throw 'Debe conservar el codigo de salida del proceso' }
    Write-Host 'OK: el proceso fallido devuelve su codigo de salida real.'
}

# Un Chrome Beta no debe ocultar la ausencia de Chrome estable.
& {
    . (Get-FunctionBody 'Test-LocalApp')
    . (Get-FunctionBody 'Get-NormName')
    $app = [pscustomobject]@{name='Google Chrome'; id='chrome'; winget='Google.Chrome'}
    $RegistryApps = @([pscustomobject]@{DisplayName='Google Chrome Beta'})
    $AppxApps = @()
    if (Test-LocalApp $app) { throw 'Chrome Beta no es Chrome estable' }
    $RegistryApps = @([pscustomobject]@{DisplayName='Google Chrome'})
    if (-not (Test-LocalApp $app)) { throw 'Debe detectar Chrome instalado para el equipo' }
}
# EarTrumpet necesita VCLibs x86, no basta con que exista la variante x64.
& {
    . (Get-FunctionBody 'Test-LocalApp')
    . (Get-FunctionBody 'Get-NormName')
    $app = [pscustomobject]@{name='Bibliotecas'; families=@('Microsoft.VCLibs.140.00_8wekyb3d8bbwe'); architecture='x86'}
    $RegistryApps = @()
    $AppxApps = @([pscustomobject]@{Name='Microsoft.VCLibs.140.00';PackageFamilyName='Microsoft.VCLibs.140.00_8wekyb3d8bbwe';Architecture='x64'})
    if (Test-LocalApp $app) { throw 'No puede confundir VCLibs x64 con x86' }
    $AppxApps[0].Architecture='x86'
    if (-not (Test-LocalApp $app)) { throw 'Debe detectar VCLibs x86' }
}
# La comprobacion de tarjetas no debe lanzar una consulta de winget por aplicacion.
& {
    . (Get-FunctionBody 'Test-AppInstalled')
    function Test-LocalApp { $false }
    function Start-Process { throw 'Consulta de red inesperada por tarjeta' }
    $WingetIds=@('Google.Chrome')
    $all=Get-Content (Join-Path $PSScriptRoot '..\apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $timer=[Diagnostics.Stopwatch]::StartNew()
    foreach ($app in $all) { if ($app.type -eq 'winget') { [void](Test-AppInstalled $app) } }
    Write-Host "OK: comprobacion del catalogo sin procesos por tarjeta: $($timer.ElapsedMilliseconds) ms"
}

# El codigo nativo debe conservarse tambien con stdout y stderr redirigidos.
& {
    function Invoke-UiPump { }
    $script:nativeLogs=@()
    function Write-Log($msg) { $script:nativeLogs += $msg }
    . (Get-FunctionBody 'Wait-Proc')
    . (Get-FunctionBody 'Invoke-Winget')
    function Start-Process { param($FilePath, [switch]$PassThru, $WindowStyle, $ArgumentList, $RedirectStandardOutput, $RedirectStandardError)
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('[Console]::Error.WriteLine("fallo nativo"); exit 7'))
        Microsoft.PowerShell.Management\Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -RedirectStandardOutput $RedirectStandardOutput -RedirectStandardError $RedirectStandardError
    }
    $LogDir=$env:TEMP
    $result=Invoke-Winget @('show') 'salida-nativa' 30
    if (($script:nativeLogs -join ' ') -notmatch 'fallo nativo') { throw 'Debe conservar stderr real' }
    if ($result -ne 7) { throw "Codigo nativo perdido: $result" }
}

# stderr de una comprobacion fallida debe permitir reparar WinGet.
& {
    . (Get-FunctionBody 'Test-WingetReady')
    function Update-EnvPath { }
    function Test-Cmd { $true }
    function winget { & $env:ComSpec /d /c 'echo winget no disponible 1>&2 & exit /b 5' }
    if (Test-WingetReady) { throw 'winget averiado no esta listo' }
    if ($ErrorActionPreference -ne 'Stop') { throw 'Debe restaurar la politica del llamador' }
    Write-Host 'OK: stderr nativo no aborta las comprobaciones previas de WinGet.'
}

# La actualizacion del EXE desde su ventana se prepara y espera a cerrar sin bloquear el padre.
& {
    . (Get-FunctionBody 'Update-Self')
    $fixture=Join-Path $env:TEMP ('iwin-update-'+[guid]::NewGuid().ToString('N'))
    New-Item $fixture -ItemType Directory | Out-Null
    Set-Content (Join-Path $fixture 'instalado.txt') 'v2.0'
    Set-Content (Join-Path $fixture 'iWinInstaller.exe') 'fixture'
    $Root=$fixture; $LogDir=$fixture; $ReleaseApi='https://example.invalid/latest'; $Version='v2.0'; $UI=$true
    $previousHost=$env:IWIN_HOST_PID; $env:IWIN_HOST_PID='123'
    function Invoke-RestMethod { [pscustomobject]@{tag_name='v2.1'; assets=@([pscustomobject]@{name='iWinInstaller-Setup.exe';digest=('sha256:'+('a'*64));browser_download_url='https://example.invalid/setup.exe'})} }
    function Invoke-WebRequest { param($Uri,$OutFile,[switch]$UseBasicParsing) Set-Content $OutFile 'fixture' }
    function Get-FileHash { [pscustomobject]@{Hash=('a'*64)} }
    function Write-Log { }
    function Start-Process {
        param($FilePath,[switch]$PassThru,$WindowStyle,$ArgumentList)
        [pscustomobject]@{HasExited=$true; ExitCode=0}
    }
    $script:waits=0
    function Wait-Proc { $script:waits++ }
    try { if (-not (Update-Self) -or $script:waits -ne 0) { throw 'El actualizador debe esperar la descarga y dejar libre la ventana' } }
    finally { $env:IWIN_HOST_PID=$previousHost; Remove-Item $fixture -Recurse -Force }
    Write-Host 'OK: actualizacion EXE diferida hasta cerrar la ventana.'
}

# Desinstalar: nada esencial se ofrece, los MSI se quitan sin ventana y una desinstalacion fallida no se da por buena.
& {
    . (Get-FunctionBody 'Test-Uninstallable')
    . (Get-FunctionBody 'Get-UninstallCommand')
    . (Get-FunctionBody 'Invoke-Uninstall')
    $all = @(Get-Content (Join-Path $PSScriptRoot '..\apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
    $blocked = @($all | Where-Object { $_.id -in @('vcredist', 'vcredistall', 'vclibs14', 'dotnet', 'directx', 'msstore', 'edge', 'wsl', 'restorepoint', 'vboxga') -and (Test-Uninstallable $_) })
    if ($blocked) { throw "No deben ofrecerse para desinstalar: $($blocked.id -join ', ')" }
    if ((Get-UninstallCommand ([pscustomobject]@{UninstallString='MsiExec.exe /I{12345678-1234-1234-1234-123456789ABC}'})) -ne 'msiexec.exe /x {12345678-1234-1234-1234-123456789ABC} /qn /norestart') { throw 'Un MSI debe desinstalarse sin ventana' }
    if ((Get-UninstallCommand ([pscustomobject]@{UninstallString='"C:\a\u.exe"'; QuietUninstallString='"C:\a\u.exe" /S'})) -ne '"C:\a\u.exe" /S') { throw 'Debe preferir la orden silenciosa' }
    function Write-Log($msg) { }
    function Ensure-Winget { $true }
    function Update-WingetCache { }
    function Test-Administrator { $false }
    function Get-InstallContext { 'user' }
    function Test-AppInstalled($app) { $app.id -ne 'ausente' }
    function Uninstall-App($app) { $script:removed += $app.id; $app.id -eq 'quitada' }
    $script:removed = @()
    $sel = @('quitada', 'resiste', 'ausente', 'dotnet') | ForEach-Object { [pscustomobject]@{ id = $_; name = $_; type = 'winget'; winget = $_; keep = ($_ -eq 'dotnet') } }
    $fail = @(Invoke-Uninstall $sel $null)
    if (@($fail.id) -join ',' -ne 'dotnet,resiste') { throw "Fallos de desinstalacion mal contados: $(@($fail.id) -join ',')" }
    if ($script:removed -contains 'dotnet' -or $script:removed -contains 'ausente') { throw 'No debe tocar lo protegido ni lo que ya no esta' }
    Write-Host 'OK: desinstalar protege componentes, usa ordenes silenciosas y confirma el resultado.'
}

# Los errores nativos anteriores son deliberados; todas las aserciones han pasado.
$global:LASTEXITCODE = 0
