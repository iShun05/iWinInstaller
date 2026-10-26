# Solo runner desechable: compila y ejecuta el EXE real con su paquete incluido.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../lifecycle.ps1')
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Esta prueba solo se ejecuta en un runner desechable de GitHub.' }
# Simula la politica restrictiva de rutas sin modificar ningun equipo del usuario.
$policy='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$priorLongPaths=(Get-ItemProperty $policy -Name LongPathsEnabled).LongPathsEnabled
Set-ItemProperty $policy -Name LongPathsEnabled -Value 0
try {
$root=Split-Path $PSScriptRoot
$expectedVersion=[regex]::Match((Get-Content (Join-Path $root 'iWinInstaller.ps1') -Raw -Encoding UTF8), '(?m)^\$Version = ''(v\d+\.\d+)''').Groups[1].Value
$output=Join-Path $env:RUNNER_TEMP 'iwin-native'
& (Join-Path $root 'scripts/build_exe.ps1') -OutputDirectory $output
$setup=Join-Path $output 'iWinInstaller-Setup.exe'
# El bundle oficial debe contener las tres arquitecturas que promete el instalador.
$bundle=Join-Path $output 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
$archive=[IO.Compression.ZipFile]::OpenRead($bundle)
try{
    $manifest=$archive.GetEntry('AppxMetadata/AppxBundleManifest.xml')
    $reader=New-Object IO.StreamReader($manifest.Open())
    try{[xml]$xml=$reader.ReadToEnd()}finally{$reader.Dispose()}
    $architectures=@($xml.SelectNodes('//*[local-name()="Package"]') | ForEach-Object {$_.GetAttribute('Architecture')})
    foreach($architecture in 'x86','x64','arm64'){if($architectures -notcontains $architecture){throw "El paquete Microsoft incluido no contiene $architecture"}}
}finally{$archive.Dispose()}
Write-Host 'OK: dependencias oficiales disponibles para x86, x64 y ARM64.'

$process=Start-Process $setup -ArgumentList '--silent' -PassThru -Wait
if ($process.ExitCode -ne 0) { throw "El EXE no se instalo: $($process.ExitCode)" }
$installed=Join-Path $env:LOCALAPPDATA 'Programs\iWinInstaller'
foreach ($name in @('iWinInstaller.exe','launch.ps1','lifecycle.ps1','install.ps1','iWinInstaller.ps1','apps.json','profiles.json','prerequisites\DesktopAppInstaller_Dependencies.zip')) {
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
foreach ($name in @('iWinInstaller.ps1','apps.json','profiles.json','lifecycle.ps1','install.ps1','launch.ps1','integrity.sha256')) { Copy-Item (Join-Path $installed $name) $fixture -Force }
Set-Content (Join-Path $fixture 'apps.json') '[]'
$p=Start-Process (Join-Path $fixture 'iWinInstaller.exe') -ArgumentList '--silent' -Wait -PassThru
if ($p.ExitCode -ne 1) { throw 'Un archivo esencial modificado debe rechazarse' }
Write-Host 'OK: EXE real instalado, dependencias incluidas, acceso directo nativo y fallo diagnosticado.'
$registration='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\iWinInstaller'
$entry=Get-ItemProperty $registration -ErrorAction Stop
if($entry.DisplayVersion -ne $expectedVersion.Substring(1) -or $entry.UninstallString -notmatch '--uninstall' -or $entry.InstallLocation -ne $installed){throw 'La app debe registrarse en Aplicaciones instaladas de Windows'}
. (Join-Path $installed 'lifecycle.ps1')
try{
    Set-IwinAutoUpdate $true
    $task=Get-ScheduledTask -TaskName 'iWinInstaller actualizaciones' -ErrorAction Stop
    if($task.Actions.Execute -ne (Join-Path $installed 'iWinInstaller.exe') -or $task.Actions.Arguments -ne '--update-only'){throw 'El actualizador solo debe ejecutar la actualización de iWinInstaller'}
}finally{Set-IwinAutoUpdate $false}
Write-Host 'OK: registro en Windows y tarea opcional de actualización con identidad del usuario.'


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


# Ejecutar el ZIP instala en la ubicación canónica y conserva seguimiento/perfiles fuera de ella.
$portable=Join-Path $env:RUNNER_TEMP 'iwin-primera-ejecucion'
Expand-Archive (Join-Path $output 'iWinInstaller.zip') $portable -Force
$portableExe=Join-Path $portable 'iWinInstaller/iWinInstaller.exe'
if($env:PROCESSOR_ARCHITECTURE -eq 'AMD64'){
    # Variante de prueba x86: ejecuta el mismo lanzador en WOW64 y verifica selección del host nativo.
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
    & $compiler /nologo /target:winexe /platform:x86 /codepage:65001 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll "/out:$portableExe" (Join-Path $root 'native/Launcher.cs')
    if($LASTEXITCODE){throw 'No se pudo construir el lanzador x86 de prueba'}
    $integrity=Join-Path $portable 'iWinInstaller/integrity.sha256'
    $lines=@(Get-Content $integrity | ForEach-Object {if($_ -match '  iWinInstaller\.exe$'){(Get-FileHash $portableExe).Hash.ToLowerInvariant()+'  iWinInstaller.exe'}else{$_}})
    $lines | Set-Content $integrity -Encoding ASCII
}

$noteDir=Join-Path $env:LOCALAPPDATA 'iWinInstaller'
$retained=Join-Path $noteDir 'retencion-prueba.json'
Set-Content $retained '{"nota":"conservar en actualización y desinstalación"}' -Encoding UTF8
$env:IWIN_PRUEBA_GUI='1'
try{
    $p=Start-Process (Join-Path $portable 'iWinInstaller/iWinInstaller.exe') -PassThru
    $null=$p.Handle
    if(-not $p.WaitForExit(180000) -or $p.ExitCode -ne 0){throw 'La primera apertura del ZIP debe instalar la app'}
    Start-Sleep -Seconds 2
    foreach($running in @(Get-Process -Name iWinInstaller -ErrorAction SilentlyContinue)){
        $null=$running.Handle
        if(-not $running.WaitForExit(240000) -or $running.ExitCode -ne 0){throw 'La app instalada desde ZIP debe completar su apertura'}
    }
    if($env:PROCESSOR_ARCHITECTURE -eq 'AMD64'){
        $launchLog=Get-ChildItem $noteDir -Filter ('arranque-*-'+$p.Id+'.log') | Select-Object -First 1
        if(-not $launchLog -or (Get-Content $launchLog.FullName -Raw) -notmatch 'proceso x86: True'){throw 'Debe ejecutarse realmente el lanzador de 32 bits'}
    }
    if(-not (Test-Path $retained) -or (Get-Content (Join-Path $installed 'instalado.txt') -Raw).Trim() -ne $expectedVersion){throw 'La sustitución debe conservar el estado y registrar la versión correcta'}
}finally{Remove-Item Env:IWIN_PRUEBA_GUI -ErrorAction SilentlyContinue}
$p=Start-Process (Join-Path $installed 'iWinInstaller.exe') -ArgumentList '--uninstall' -PassThru
$null=$p.Handle
if(-not $p.WaitForExit(30000) -or $p.ExitCode -ne 0){throw 'El desinstalador debe iniciarse'}
$timer=[Diagnostics.Stopwatch]::StartNew()
while(((Test-Path $installed) -or (Test-Path $registration)) -and $timer.Elapsed.TotalSeconds -lt 60){Start-Sleep -Milliseconds 250}
if((Test-Path $installed) -or (Test-Path $registration) -or -not (Test-Path $retained)){throw 'Desinstalar debe retirar la app y su registro, conservando notas y perfiles'}
Remove-Item $retained -Force
Write-Host 'OK: primera ejecución del ZIP, reemplazo, conservación de datos y desinstalación real.'

} finally { Set-ItemProperty $policy -Name LongPathsEnabled -Value $priorLongPaths }
