# Prueba aislada: simula Windows sin gh ni winget, sin instalar nada.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lifecycle.ps1')
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\install.ps1'), [ref]$null, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Remove-InstallerDirectory' }, $true)
. ([scriptblock]::Create($fn.Extent.Text))
$moveFn = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Move-InstallerDirectory'},$true)
. ([scriptblock]::Create($moveFn.Extent.Text))
# Comprueba la restauracion con carpetas temporales, incluida una ruta con espacios.
$fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-ReleaseFiles' }, $true)
. ([scriptblock]::Create($fn.Extent.Text))
$fixture = Join-Path $env:TEMP ('iwin test ' + [Guid]::NewGuid().ToString())
$src = Join-Path $fixture 'source'; $dst = Join-Path $fixture 'installed'
New-Item $src, $dst -ItemType Directory -Force | Out-Null
foreach ($f in @('iWinInstaller.ps1', 'apps.json', 'profiles.json', 'install.ps1')) { Set-Content (Join-Path $src $f) 'nuevo' }
Set-Content (Join-Path $dst 'anterior.txt') 'conservar'
function Move-InstallerDirectory {
    param($Path, $Destination)
    if ($Path -like '*.new-*') { throw 'Cambio simulado fallido' }
    [IO.Directory]::Move($Path, $Destination)
}
try {
    $failed = $false
    try { Install-ReleaseFiles $src $dst 'prueba' } catch { $failed = $true }
    if (-not $failed -or -not (Test-Path (Join-Path $dst 'anterior.txt'))) { throw 'Debe restaurar la instalacion anterior' }
    Write-Host 'OK: una sustitucion fallida conserva la version anterior.'
} finally { Remove-Item $fixture -Recurse -Force }

# La cabecera usa una variable de entorno: los apostrofos de la ruta no entran en codigo.
$header = Get-Content (Join-Path $PSScriptRoot '..\installer-header.bat') -Raw
if (-not $header.Contains('[IO.File]::ReadAllText($env:IWIN_SETUP_FILE)')) { throw 'La ruta del BAT debe pasarse como dato' }
$embedded = $header + (Get-Content (Join-Path $PSScriptRoot '..\install.ps1') -Raw)
$marker = $embedded.IndexOf('#INSTALL' + '_PS1#')
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($embedded.Substring($marker), [ref]$null, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }
Write-Host 'OK: el instalador incrustado tiene sintaxis valida y admite apostrofos en la ruta.'

# Copia real, reemplazo y limpieza de una ruta profunda sin habilitar rutas largas globalmente.
Remove-Item Function:\Move-InstallerDirectory
. ([scriptblock]::Create($moveFn.Extent.Text))
$fixture = Join-Path $env:TEMP ('iwin long ' + [Guid]::NewGuid().ToString())
$src = Join-Path $fixture 'source'; $dst = Join-Path $fixture 'installed'
New-Item $src -ItemType Directory -Force | Out-Null
foreach ($f in @('iWinInstaller.ps1', 'apps.json', 'profiles.json', 'install.ps1')) { Set-Content (Join-Path $src $f) 'nuevo' }
$relative = ('resources\fixture\' + ('profundo-0123456789\' * 15) + 'opc-contentTypes.xsd')
$longFile = Join-Path $src $relative
if ($longFile.Length -le 260) { throw 'La prueba requiere una ruta de mas de 260 caracteres' }
[void][IO.Directory]::CreateDirectory('\\?\' + [IO.Path]::GetDirectoryName($longFile))
[IO.File]::WriteAllText('\\?\' + $longFile, 'contenido profundo')
try {
    Install-ReleaseFiles $src $dst 'prueba'
    if ([IO.File]::ReadAllText('\\?\' + (Join-Path $dst $relative)) -ne 'contenido profundo') { throw 'Debe copiar el archivo profundo' }
    Install-ReleaseFiles $src $dst 'prueba2'
    if ((Get-Content (Join-Path $dst 'instalado.txt')).Trim() -ne 'prueba2') { throw 'Debe reemplazar una instalacion con rutas profundas' }
    Write-Host "OK: copia y reemplazo reales con ruta de $($longFile.Length) caracteres."
} finally { Remove-InstallerDirectory $fixture }
if (Test-Path $fixture) { throw 'Debe limpiar las carpetas profundas' }

# El paquete incrustado funciona sin red y rechaza datos alterados.
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-EmbeddedArchive' }, $true)
. ([scriptblock]::Create($fn.Extent.Text))
$fixture = Join-Path $env:TEMP ('iwin payload ' + [Guid]::NewGuid().ToString('N'))
New-Item $fixture -ItemType Directory -Force | Out-Null
try {
    $zip = Join-Path $fixture 'app.zip'; $bat = Join-Path $fixture "Instalador O'Connor.bat"; $out = Join-Path $fixture 'extraido.zip'
    Set-Content (Join-Path $fixture 'ejemplo.txt') 'contenido comprobable'
    Compress-Archive (Join-Path $fixture 'ejemplo.txt') $zip
    & python (Join-Path $PSScriptRoot '..\scripts\build_installer.py') $zip $bat
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo construir el paquete incrustado' }
    if (-not (Read-EmbeddedArchive $bat $out) -or (Get-FileHash $zip).Hash -ne (Get-FileHash $out).Hash) { throw 'El ZIP incrustado debe ser identico' }
    $text = [IO.File]::ReadAllText($bat)
    $i = $text.IndexOf('#INSTALL' + '_PS1#'); $e = $text.IndexOf('#PAYLOAD' + '_ZIP#')
    $err = $null
    [void][Management.Automation.Language.Parser]::ParseInput($text.Substring($i, $e-$i), [ref]$null, [ref]$err)
    if ($err) { throw ($err | Out-String) }
    $broken = $text.Substring(0,$e) + $text.Substring($e).Replace((Get-FileHash $zip).Hash.ToLowerInvariant(), ('0' * 64))
    [IO.File]::WriteAllText($bat, $broken)
    $rejected = $false
    try { [void](Read-EmbeddedArchive $bat $out) } catch { $rejected = $true }
    if (-not $rejected) { throw 'Debe rechazar un paquete con hash incorrecto' }
    Write-Host 'OK: paquete sin red, ruta con apostrofo y rechazo de hash incorrecto.'
} finally { Remove-InstallerDirectory $fixture }
