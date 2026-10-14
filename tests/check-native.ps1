# Solo runner desechable: compila y ejecuta el EXE real con su paquete incluido.
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Esta prueba solo se ejecuta en un runner desechable de GitHub.' }
# Simula la politica restrictiva de rutas sin modificar ningun equipo del usuario.
$policy='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$priorLongPaths=(Get-ItemProperty $policy -Name LongPathsEnabled).LongPathsEnabled
Set-ItemProperty $policy -Name LongPathsEnabled -Value 0
try {
$root=Split-Path $PSScriptRoot
$output=Join-Path $env:RUNNER_TEMP 'iwin-native'
& (Join-Path $root 'scripts/build_exe.ps1') -OutputDirectory $output
$setup=Join-Path $output 'iWinInstaller-Setup.exe'
$process=Start-Process $setup -ArgumentList '--silent' -PassThru -Wait
if ($process.ExitCode -ne 0) { throw "El EXE no se instalo: $($process.ExitCode)" }
$installed=Join-Path $env:LOCALAPPDATA 'Programs\iWinInstaller'
foreach ($name in @('iWinInstaller.exe','launch.ps1','iWinInstaller.ps1','apps.json','profiles.json','prerequisites\DesktopAppInstaller_Dependencies.zip')) {
    if (-not (Test-Path (Join-Path $installed $name))) { throw "Falta el archivo instalado $name" }
}
$ws=New-Object -ComObject WScript.Shell
$link=$ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'iWinInstaller.lnk'))
if ($link.TargetPath -ne (Join-Path $installed 'iWinInstaller.exe')) { throw 'El acceso directo debe abrir el EXE nativo' }
# Sin un archivo esencial, el lanzador debe devolver error y conservar el diagnostico.
$fixture=Join-Path $env:RUNNER_TEMP 'iwin-fallo'
New-Item $fixture -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $installed 'iWinInstaller.exe') $fixture
$p=Start-Process (Join-Path $fixture 'iWinInstaller.exe') -ArgumentList '--silent' -Wait -PassThru
if ($p.ExitCode -ne 1) { throw 'Un paquete incompleto debe rechazarse' }
$reports=@(Get-ChildItem (Join-Path $env:USERPROFILE 'Downloads\iWinInstaller-error-*.txt'))
if (-not $reports.Count -or -not (($reports | Get-Content -Raw) -match 'Falta un archivo esencial')) { throw 'Debe conservar el motivo del error aunque no haya interfaz' }
# Un archivo presente pero alterado tampoco debe ejecutarse.
foreach ($name in @('iWinInstaller.ps1','apps.json','profiles.json','launch.ps1','integrity.sha256')) { Copy-Item (Join-Path $installed $name) $fixture -Force }
Set-Content (Join-Path $fixture 'apps.json') '[]'
$p=Start-Process (Join-Path $fixture 'iWinInstaller.exe') -ArgumentList '--silent' -Wait -PassThru
if ($p.ExitCode -ne 1) { throw 'Un archivo esencial modificado debe rechazarse' }
Write-Host 'OK: EXE real instalado, dependencias incluidas, acceso directo nativo y fallo diagnosticado.'

# Instala realmente el paquete Microsoft incluido; no se consulta ningun origen remoto.
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $installed 'iWinInstaller.ps1'),[ref]$null,[ref]$errors)
foreach ($name in @('Install-BundledWinget','Update-EnvPath','Test-Cmd','Test-WingetReady')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($node.Extent.Text))
}
function Write-Log($message) { Write-Host $message }
$Root=$installed
if (-not (Install-BundledWinget)) { throw 'El paquete Microsoft incluido no se pudo preparar sin descarga' }
Write-Host 'OK: winget y sus dependencias preparados desde los archivos incluidos.'

# Abre el EXE instalado y ejercita el arranque de la ventana, no solo el constructor XAML.
$env:IWIN_PRUEBA_GUI='1'
try {
    $p=Start-Process (Join-Path $installed 'iWinInstaller.exe') -ArgumentList '--silent' -PassThru
    $null=$p.Handle
    Start-Sleep -Seconds 2
    $repair=Start-Process $setup -ArgumentList '--silent' -PassThru -Wait
    if ($repair.ExitCode -ne 0) { throw 'La reparacion no debe fallar por el ejecutable anterior en uso' }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw 'El EXE instalado no completo el arranque real de WPF' }
} finally { Remove-Item Env:IWIN_PRUEBA_GUI }
Write-Host 'OK: ventana real del EXE instalado, inventario y cambios de perfil.'

# Tambien ejecuta el formulario del Setup, su progreso y el arranque automatico final.
$env:IWIN_PRUEBA_GUI='1'
try {
    $p=Start-Process $setup -PassThru
    $null=$p.Handle
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw 'El formulario del EXE no completo la instalacion' }
    Start-Sleep -Seconds 1
    $opened=@(Get-Process -Name iWinInstaller -ErrorAction SilentlyContinue)
    if (-not $opened.Count) { throw 'El Setup no abrio la aplicacion' }
    foreach ($running in $opened) {
        $null=$running.Handle
        if (-not $running.WaitForExit(180000) -or $running.ExitCode -ne 0) { throw 'La app iniciada por el Setup no completo su ventana de prueba' }
    }
} finally { Remove-Item Env:IWIN_PRUEBA_GUI }
Write-Host 'OK: formulario del Setup con progreso y apertura automatica de la app.'

} finally { Set-ItemProperty $policy -Name LongPathsEnabled -Value $priorLongPaths }
