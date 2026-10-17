# Solo para un runner Windows desechable: instala el paquete incluido sin red.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$fixture=Join-Path $env:TEMP ('iwin-embedded-'+[guid]::NewGuid().ToString('N'))
New-Item $fixture -ItemType Directory | Out-Null
$zip=Join-Path $fixture 'app.zip'; $bat=Join-Path $fixture "instalador ' completo.bat"
& git -C $root archive --format=zip --prefix=iWinInstaller/ -o $zip HEAD
if ($LASTEXITCODE) { throw 'No se pudo empaquetar la app' }
& python (Join-Path $root 'scripts/build_installer.py') $zip $bat
if ($LASTEXITCODE) { throw 'No se pudo construir el BAT' }
$previous=$env:LOCALAPPDATA; $previousSetup=$env:IWIN_SETUP_FILE
try {
    $env:LOCALAPPDATA=Join-Path $fixture 'local'
    $env:IWIN_SETUP_FILE=$bat
    # Cualquier intento de acceso remoto en esta ruta debe fallar la prueba.
    function Invoke-WebRequest { throw 'El paquete incluido no debe descargar nada' }
    function Invoke-RestMethod { throw 'El paquete incluido no debe consultar GitHub' }
    function gh { throw 'El paquete incluido no debe pedir acceso a GitHub' }
    $text=[IO.File]::ReadAllText($bat)
    $start=$text.IndexOf('#INSTALL'+'_PS1#'); $end=$text.IndexOf('#PAYLOAD'+'_ZIP#')
    & ([scriptblock]::Create($text.Substring($start,$end-$start))) -Silent
    $installed=Join-Path $env:LOCALAPPDATA 'Programs/iWinInstaller'
    if (-not (Test-Path (Join-Path $installed 'iWinInstaller.ps1'))) { throw 'No se instalo la app incluida' }
    if ((Get-Content (Join-Path $installed 'instalado.txt') -Raw) -notmatch 'v2.5') { throw 'Version instalada incorrecta' }
    Write-Host 'OK: instalacion completa desde BAT incluido, sin descarga ni inicio de sesion.'
} finally {
    $env:LOCALAPPDATA=$previous; $env:IWIN_SETUP_FILE=$previousSetup
    Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
