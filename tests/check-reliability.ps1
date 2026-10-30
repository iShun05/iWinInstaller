# Pruebas aisladas: no instalan programas ni cambian ajustes reales.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lifecycle.ps1')
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
    function Invoke-IwinWebTransfer($url,$outFile,$timeoutSec){if($outFile){Set-Content $outFile 'fixture'}else{Invoke-RestMethod | ConvertTo-Json -Depth 5}}
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

# Informe final: motivo de cada fallo a partir del registro real (caso del 30/10: PowerShell 7, Bing y Norton).
& {
    $Version = 'prueba'; $WorkerMode = ''
    $LogDir = Join-Path $env:TEMP ('iwin-informe-' + [guid]::NewGuid().ToString('N'))
    New-Item $LogDir -ItemType Directory -Force | Out-Null
    $LogFile = Join-Path $LogDir 'prueba.log'
    try {
        Set-Content $LogFile 'previo: no debe aparecer' -Encoding UTF8
        $offset = Get-IwinLogLength
        @(
            '06:40:30  Instalando PowerShell 7...',
            '06:40:32    pwsh · Instalando…',
            '06:40:43      This application is licensed to you by its owner.',
            '06:40:43      Installer failed with exit code: 0x80070005 : Acceso denegado.',
            '06:40:43    pwsh · codigo -2147024891 · 13.1 s',
            '06:40:43    FALLÓ: PowerShell 7',
            '06:41:02  Instalando gsudo...',
            '06:41:06    OK: gsudo',
            '06:47:05  Instalando Inicio sin resultados de Bing...',
            "06:47:05    Se denegó el acceso a la clave de Registro 'HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\Explorer'.",
            '06:47:05    FALLÓ: Inicio sin resultados de Bing',
            '06:55:50  Instalando Norton VPN...',
            '06:55:50    Se instala desde la web o la cuenta del proveedor: completa su asistente y vuelve a verificar.',
            '06:55:50    FALLÓ: Norton VPN'
        ) | Add-Content $LogFile -Encoding UTF8
        $plan = @(
            [pscustomobject]@{ id = 'pwsh'; name = 'PowerShell 7'; type = 'winget' },
            [pscustomobject]@{ id = 'gsudo'; name = 'gsudo'; type = 'winget' },
            [pscustomobject]@{ id = 'nobing'; name = 'Inicio sin resultados de Bing'; type = 'tweak'; restart = $true },
            [pscustomobject]@{ id = 'nortonvpn'; name = 'Norton VPN'; type = 'manual' },
            [pscustomobject]@{ id = 'wsl'; name = 'WSL'; type = 'tweak'; restart = $true }
        )
        $script:RunResults = @{
            pwsh = [pscustomobject]@{ ok = $false; code = -2147024891; stopped = $false }
            gsudo = [pscustomobject]@{ ok = $true; code = 0; stopped = $false }
            nobing = [pscustomobject]@{ ok = $false; code = 0; stopped = $false }
            nortonvpn = [pscustomobject]@{ ok = $false; code = 0; stopped = $false }
            wsl = [pscustomobject]@{ ok = $true; code = 0; stopped = $false }
        }
        $report = New-IwinInstallReport $plan @($plan[0], $plan[2], $plan[3]) $offset
        if ($report.ok -ne 2 -or $report.failed -ne 2 -or $report.manual -ne 1) { throw "Recuento del informe incorrecto: $($report.ok)/$($report.failed)/$($report.manual)" }
        $pwsh = $report.items | Where-Object id -eq 'pwsh'
        if ($pwsh.codeText -ne '0x80070005' -or $pwsh.reason -notmatch 'Acceso denegado' -or ($pwsh.details -join ' ') -notmatch 'Installer failed') { throw 'PowerShell 7 debe explicar el acceso denegado con su detalle' }
        if (($pwsh.details -join ' ') -match 'licensed') { throw 'El detalle no debe incluir el texto de licencia' }
        $bing = $report.items | Where-Object id -eq 'nobing'
        if ($bing.kind -ne 'fallo' -or $bing.hint -notmatch 'administrador') { throw 'Bing debe indicar que hace falta administrador' }
        if (($report.items | Where-Object id -eq 'nortonvpn').kind -ne 'manual') { throw 'Norton VPN es una instalación manual, no un fallo' }
        if ($report.items | Where-Object id -eq 'gsudo') { throw 'gsudo terminó bien y no puede aparecer como fallo' }
        if (@($report.reboot) -notcontains 'WSL') { throw 'WSL debe aparecer como pendiente de reinicio' }
        $text = Format-IwinReportText $report
        foreach ($expected in 'FALLARON', 'REQUIEREN ACCIÓN MANUAL', 'PowerShell 7 [pwsh] · código 0x80070005', 'REQUIEREN REINICIAR WINDOWS') {
            if ($text -notlike "*$expected*") { throw "Falta en el texto del informe: $expected" }
        }
        if ($text -match 'previo: no debe aparecer') { throw 'El informe solo debe leer el registro de esta pasada' }
        Save-IwinInstallReport $report
        $again = Get-IwinLastReport
        if (-not $again -or @($again.items).Count -ne 3 -or (Format-IwinReportText $again) -notmatch '0x80070005') { throw 'El informe guardado debe poder abrirse de nuevo' }
        if ((Get-IwinCodeText 3010) -ne '3010' -or (Get-IwinCodeText -1978335224) -ne '0x8A150008') { throw 'Formato de códigos incorrecto' }
        Write-Host 'OK: informe final con motivo, código, detalle, acción manual y reinicio.'
    } finally { Remove-Item $LogDir -Recurse -Force -ErrorAction SilentlyContinue }
}
# Kits portátiles sin entrada en Programas: se detectan por su carpeta.
& {
    . (Get-FunctionBody 'Test-LocalApp')
    . (Get-FunctionBody 'Get-NormName')
    $RegistryApps = @(); $AppxApps = @()
    $folder = Join-Path $env:TEMP ('iwin-kit-' + [guid]::NewGuid().ToString('N'))
    $app = [pscustomobject]@{ name = 'Kit portátil'; detectPaths = @($folder) }
    if (Test-LocalApp $app) { throw 'No puede detectar un kit ausente' }
    New-Item $folder -ItemType Directory | Out-Null
    try { if (-not (Test-LocalApp $app)) { throw 'Debe detectar el kit por su carpeta' } } finally { Remove-Item $folder -Force }
    Write-Host 'OK: detección por carpeta.'
}
