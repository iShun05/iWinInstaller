# Pruebas reales en un runner Windows desechable. No ejecutar en el PC del usuario.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lifecycle.ps1')
$root = Split-Path $PSScriptRoot
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'iWinInstaller.ps1'),[ref]$null,[ref]$errors)
if ($errors) { throw ($errors | Out-String) }
# Carga las funciones sin abrir la ventana ni instalar un perfil entero.
foreach ($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { . ([scriptblock]::Create($node.Extent.Text)) }
$Apps=@(Get-Content (Join-Path $root 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object {$_})
$Profiles=Get-Content (Join-Path $root 'profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($Profiles.Manual).Count) { throw 'El perfil Manual debe empezar sin seleccionar aplicaciones.' }
$Root=$root; $WorkerMode='machine'; $UI=$false; $Check=$false; $Silent=$true
$Version='v3.7'; $LogDir=Join-Path $env:TEMP 'iwin-aceptacion'; New-Item $LogDir -ItemType Directory -Force | Out-Null
$LogFile=Join-Path $LogDir 'prueba.log'; $log=$null; $wingetOk=@(0,3010,-1978335135,-1978335189)
if (-not (Ensure-Winget)) { throw 'winget no disponible' }
Update-WingetCache
# Un error real de winget debe conservar texto, codigo y duracion.
$code=Invoke-Winget @('show','--id','NoExiste.PaqueteDePrueba','--source','winget','--disable-interactivity','--accept-source-agreements') 'fallo-controlado' 60
if ($null -eq $code -or $code -eq 0 -or -not (Select-String $LogFile -Pattern 'fallo-controlado.*codigo')) { throw 'El fallo real debe quedar en el diagnostico' }
# Chrome se retira SOLO de este runner para probar instalacion desde cero.
& winget uninstall -e --id Google.Chrome --source winget --silent --disable-interactivity --accept-source-agreements *> $null
$global:LASTEXITCODE=0
Update-WingetCache
$chrome=$Apps | Where-Object id -eq 'chrome'
if (Test-LocalApp $chrome) { throw 'No se pudo preparar Chrome ausente para la prueba' }
$before=[Diagnostics.Stopwatch]::StartNew()
$fail=@(Invoke-Install @($chrome) $null)
if ($fail.Count) { throw 'Chrome no se instalo desde cero' }
Update-LocalInventory
if (-not (Test-LocalApp $chrome)) { throw 'Chrome no aparece realmente instalado' }
$files=@((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'))
if (-not ($files | Where-Object { Test-Path $_ })) { throw 'No se encuentra el ejecutable de Chrome' }
Write-Host "Chrome instalado y verificado en $([math]::Round($before.Elapsed.TotalSeconds,1)) s"
# Repetir la seleccion no debe lanzar ningun instalador.
$prior=Get-Content $LogFile -Raw
$fail=@(Invoke-Install @($chrome) $null)
if ($fail.Count) { throw 'La segunda pasada de Chrome debe ser idempotente' }
$after=Get-Content $LogFile -Raw
if ($after.Substring($prior.Length) -notmatch 'Ya instalada, se omite') { throw 'Chrome debe omitirse en la segunda pasada' }
# El hijo real debe comunicar el resultado de un lote ya instalado.
$WorkerMode=''
$fail=@(Invoke-InstallWorker @($chrome) $null)
if ($fail.Count) { throw 'El proceso de lote no devolvio el resultado de Chrome' }
$WorkerMode='machine'
# Recorre el catalogo sin consultas externas por tarjeta.
$timer=[Diagnostics.Stopwatch]::StartNew()
foreach ($app in $Apps) { if ($app.type -eq 'winget') { [void](Test-AppInstalled $app) } }
Write-Host "Inventario local de catalogo: $($timer.ElapsedMilliseconds) ms"
# Exporta al directorio de prueba, sin modificar Descargas del runner.
function Get-RegValue { $LogDir }
$report=Export-Diagnostic
if (-not (Test-Path $report) -or (Get-Content $report -Raw) -notmatch 'fallo-controlado') { throw 'El informe debe incluir el fallo' }
Copy-Item $LogFile (Join-Path $PSScriptRoot 'aceptacion.log')
Write-Host 'OK: Chrome nuevo/existente, error real, inventario y exportacion.'
