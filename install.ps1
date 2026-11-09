# iWinInstaller - instalador
# Descarga la ultima version publica y la instala en %ProgramFiles%\iWinInstaller (desde v4.3),
# crea accesos directos en el menu Inicio y el Escritorio y la abre.
# Necesita permiso de administrador: solo los administradores pueden modificar la app instalada.
# No necesita una cuenta de GitHub ni una clave de acceso.
# Opciones: -Silent (no abre la app al terminar), -Uninstall (desinstala),
#           -SourceDirectory (instala desde una copia ya verificada, p. ej. el ZIP descomprimido)
# (Solo ASCII a proposito: tambien va incrustado en iWinInstaller-Setup.bat.)
param([switch]$Silent, [switch]$Uninstall, [int]$WaitForPid = 0, [string]$SourceDirectory)
$ErrorActionPreference = 'Stop'

$Repo = 'iShun05/iWinInstaller'
$ProgramRoot = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
# IWIN_INSTALL_DIR solo lo usan las pruebas aisladas
$Dir = if ($env:IWIN_INSTALL_DIR) { $env:IWIN_INSTALL_DIR } else { Join-Path $ProgramRoot 'iWinInstaller' }
# Instalacion por usuario de v4.2 y anteriores: se migra y se retira
$LegacyDir = Join-Path $env:LOCALAPPDATA 'Programs\iWinInstaller'
$RunningAsSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
$StartLink = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'iWinInstaller.lnk'
$LegacyStartLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'iWinInstaller.lnk'
$DesktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'iWinInstaller.lnk'
$Links = @($StartLink)
# La actualizacion programada corre como SYSTEM: no crea iconos en su propio escritorio
if (-not $RunningAsSystem) { $Links += $DesktopLink }
$Registration = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\iWinInstaller'
$LegacyRegistration = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\iWinInstaller'
if ($env:IWIN_REGISTRATION_KEY) { $Registration = $env:IWIN_REGISTRATION_KEY }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $env:IWIN_INSTALL_DIR) {
    throw 'Se necesita permiso de administrador para instalar o desinstalar iWinInstaller en Program Files.'
}

if ($Uninstall) {
    if($WaitForPid -gt 0){$running=Get-Process -Id $WaitForPid -ErrorAction SilentlyContinue;if($running -and -not $running.WaitForExit(30000)){throw 'Cierra iWinInstaller antes de desinstalar.'}}
    foreach($running in @(Get-Process -Name iWinInstaller -ErrorAction SilentlyContinue)){
        try{$openPath=$running.Path}catch{$openPath=''}
        if($openPath -eq (Join-Path $Dir 'iWinInstaller.exe')){throw 'Cierra iWinInstaller antes de desinstalar.'}
    }
    Unregister-ScheduledTask -TaskName 'iWinInstaller actualizaciones' -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'iWinInstaller semanal' -Confirm:$false -ErrorAction SilentlyContinue
    @($StartLink, $LegacyStartLink, $DesktopLink) | ForEach-Object { Remove-Item $_ -ErrorAction SilentlyContinue }
    Remove-Item $Dir -Recurse -Force -ErrorAction Stop
    Remove-Item $Registration -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $LegacyRegistration -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'iWinInstaller desinstalado. Se conservan tus notas, perfiles, lotes y las aplicaciones instaladas.'
    return
}

function Remove-InstallerDirectory([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { throw 'No se puede limpiar una ruta vacia.' }
    $full = [IO.Path]::GetFullPath($path)
    if ($full -eq [IO.Path]::GetPathRoot($full)) { throw 'No se puede limpiar la raiz de un disco.' }
    $extended = if ($full.StartsWith('\\')) { '\\?\UNC\' + $full.Substring(2) } else { '\\?\' + $full }
    if ([IO.Directory]::Exists($extended)) { [IO.Directory]::Delete($extended, $true) }
}
function Wait-InstallerProcesses($installDir) {
    # Procesos de PowerShell de la app (ventana, lotes o tareas) que siguen usando la carpeta impiden renombrarla.
    $pattern = '*' + $installDir + '*'
    for ($i = 0; $i -lt 60; $i++) {
        $busy = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='iWinInstaller.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $PID -and ($_.CommandLine -like $pattern -or $_.ExecutablePath -like $pattern) })
        if (-not $busy) { return }
        if ($i -eq 0) { Write-Host 'Esperando a que terminen los procesos de iWinInstaller que siguen abiertos.' }
        Start-Sleep -Seconds 1
    }
}
function Move-InstallerDirectory($source, $destination) {
    # Directory.Move renombra la carpeta completa; Move-Item puede mover archivos a medias si uno esta abierto.
    # El antivirus o el indexador pueden bloquearla unos segundos: se reintenta antes de fallar.
    for ($attempt = 1; ; $attempt++) {
        try { [IO.Directory]::Move($source, $destination); return }
        catch [System.IO.IOException], [System.UnauthorizedAccessException] {
            if ($attempt -ge 15) { throw }
            Start-Sleep -Milliseconds (400 * $attempt)
        }
    }
}
function Install-ReleaseFiles($sourceDir, $installDir, $tagName) {
    # Prepara la copia completa antes de sustituir la instalacion anterior.
    $stage = "$installDir.new-$([Guid]::NewGuid().ToString())"
    $backup = "$installDir.previous-$([Guid]::NewGuid().ToString())"
    $hadPrevious = Test-Path $installDir
    try {
        New-Item -ItemType Directory $stage -Force | Out-Null
        # Robocopy admite rutas largas sin cambiar la configuracion global de Windows.
        & robocopy $sourceDir $stage /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "No se pudieron copiar los archivos (robocopy: $LASTEXITCODE)." }
        $global:LASTEXITCODE = 0
        foreach ($file in @('iWinInstaller.ps1', 'apps.json', 'profiles.json', 'install.ps1')) {
            if (-not (Test-Path (Join-Path $stage $file))) { throw "El ZIP esta incompleto: falta $file." }
        }
        Get-ChildItem $stage -File | Unblock-File
        Set-Content (Join-Path $stage 'instalado.txt') $tagName -Encoding ASCII
        if ($hadPrevious) {
            Wait-InstallerProcesses $installDir
            try { Move-InstallerDirectory $installDir $backup }
            catch {
                # Ultimo recurso: sustituir archivo a archivo dentro de la carpeta existente.
                Write-Host 'La carpeta sigue en uso; se actualizan los archivos dentro de ella.'
                & robocopy $stage $installDir /MIR /R:5 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
                if ($LASTEXITCODE -ge 8) { throw "No se pudo reemplazar la instalacion: hay archivos en uso. Reinicia Windows y vuelve a ejecutar el instalador (robocopy: $LASTEXITCODE)." }
                $global:LASTEXITCODE = 0
                return
            }
        }
        try { Move-InstallerDirectory $stage $installDir } catch {
            if ($hadPrevious) { Move-InstallerDirectory $backup $installDir }
            throw
        }
        if ($hadPrevious) {
            try { Remove-InstallerDirectory $backup }
            catch { Write-Host 'La nueva version esta instalada. Los archivos anteriores siguen en uso y se limpiaran al volver a abrir la app.' }
        }
    } finally {
        Remove-InstallerDirectory $stage
    }

}
function Show-InstallProgress([int]$step, [string]$status) {
    Write-Progress -Id 1 -Activity 'Instalando iWinInstaller v4.5' -Status "Etapa $($step + 1) de 7: $status" -PercentComplete ([int](100 * $step / 7))
    Write-Host "[$($step + 1)/7] $status"
}
function Read-EmbeddedArchive([string]$file, [string]$destination) {
    $text = [IO.File]::ReadAllText($file)
    $marker = '#PAYLOAD' + '_ZIP#'
    $index = $text.IndexOf($marker)
    if ($index -lt 0) { return $false }
    $parts = $text.Substring($index + $marker.Length).Trim() -split '\r?\n', 2
    if ($parts.Count -ne 2 -or $parts[0] -notmatch '^[a-f0-9]{64}$') { throw 'El paquete incrustado esta incompleto.' }
    $bytes = [Convert]::FromBase64String($parts[1].Trim())
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    if ($hash -ne $parts[0]) { throw 'El paquete incrustado no supera la comprobacion SHA256. Descarga de nuevo el instalador.' }
    [IO.File]::WriteAllBytes($destination, $bytes)
    return $true
}
$installMutex=New-Object Threading.Mutex($false,('Local\iWinInstaller-install-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ownsInstall=$false
try{
    try{$ownsInstall=$installMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$ownsInstall=$true}
    if(-not $ownsInstall){throw 'Ya hay otra instalacion de iWinInstaller en curso.'}
$tag = 'v4.5'
$tmp = Join-Path $env:TEMP ('iWinInstaller-' + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory $tmp -Force | Out-Null
$archive = Join-Path $tmp 'iWinInstaller.zip'
if(-not $SourceDirectory){$SourceDirectory=$env:IWIN_SOURCE_DIRECTORY}
if($SourceDirectory){
    $src=Get-Item (Join-Path $SourceDirectory 'iWinInstaller.ps1') -ErrorAction Stop
    Show-InstallProgress 4 'Preparando la primera instalacion desde la copia verificada'
}else{
Show-InstallProgress 0 'Comprobando el paquete incluido'
$embedded = $false
if ($env:IWIN_PACKAGE_PATH -and (Test-Path $env:IWIN_PACKAGE_PATH)) { Copy-Item $env:IWIN_PACKAGE_PATH $archive; $embedded = $true }
if (-not $embedded -and $env:IWIN_SETUP_FILE -and (Test-Path $env:IWIN_SETUP_FILE)) { $embedded = Read-EmbeddedArchive $env:IWIN_SETUP_FILE $archive }
if ($embedded) {
    Show-InstallProgress 1 'Paquete incluido verificado: no necesita iniciar sesion'
    Show-InstallProgress 2 'Preparando la instalacion local'
    Show-InstallProgress 3 'App disponible sin descarga adicional'
} else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Show-InstallProgress 1 'Descarga publica: no necesita una cuenta'
    Show-InstallProgress 2 'Buscando la ultima version'
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    $tag = $release.tag_name
    $asset = $release.assets | Where-Object name -eq 'iWinInstaller.zip' | Select-Object -First 1
    if (-not $tag -or -not $asset -or $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw 'No se encontro la descarga con su hash SHA256.' }
    $expectedHash = $Matches[1]
    Show-InstallProgress 3 "Descargando iWinInstaller $tag"
    # GitHub responde a veces 502/504 en las descargas: hasta cinco intentos antes de rendirse
    for ($attempt = 1; ; $attempt++) {
        try { Invoke-WebRequest $asset.browser_download_url -OutFile $archive -UseBasicParsing; break }
        catch { if ($attempt -ge 5) { throw }; Write-Host "La descarga fallo ($($_.Exception.Message)); reintento $attempt de 4."; Start-Sleep -Seconds (10 * $attempt) }
    }
    if ((Get-FileHash $archive).Hash -ne $expectedHash) { throw 'La descarga no supera la comprobacion SHA256.' }
}
Show-InstallProgress 4 'Descomprimiendo y comprobando los archivos'
Unblock-File (Join-Path $tmp 'iWinInstaller.zip')
Expand-Archive (Join-Path $tmp 'iWinInstaller.zip') (Join-Path $tmp 'x') -Force
$src = Get-Item (Join-Path $tmp 'x\iWinInstaller\iWinInstaller.ps1') -ErrorAction SilentlyContinue
if (-not $src) { throw 'El ZIP no contiene iWinInstaller.ps1.' }

}

Unregister-ScheduledTask -TaskName 'iWinInstaller semanal' -Confirm:$false -ErrorAction SilentlyContinue
$previousTag=Get-Content (Join-Path $Dir 'instalado.txt') -Raw -ErrorAction SilentlyContinue
if($previousTag -and $previousTag.Trim() -match '^v\d+\.\d+$' -and $tag -match '^v\d+\.\d+$'){
    if([version]$previousTag.Trim().Substring(1) -gt [version]$tag.Substring(1)){Remove-InstallerDirectory $tmp;throw 'Ya hay una version mas nueva instalada. No se sustituye por una anterior.'}
}
Show-InstallProgress 5 'Instalando la nueva version'
try { Install-ReleaseFiles $src.DirectoryName $Dir $tag } finally { Remove-InstallerDirectory $tmp }

$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$args0 = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$Dir\iWinInstaller.ps1`""
Show-InstallProgress 6 'Creando accesos directos'
$shell = New-Object -ComObject WScript.Shell
foreach ($l in $Links) {
    $s = $shell.CreateShortcut($l)
    $native = Join-Path $Dir 'iWinInstaller.exe'
    $s.TargetPath = if (Test-Path $native) { $native } else { $ps }
    $s.Arguments = if (Test-Path $native) { '' } else { $args0 }
    $s.WorkingDirectory = $Dir
    $ico = Join-Path $Dir 'assets\icon.ico'
    if (Test-Path $ico) { $s.IconLocation = $ico }
    $s.Description = 'Instala aplicaciones para Windows'
    $s.Save()
}
# Registro del equipo en Aplicaciones instaladas (desde v4.3).
$registration=$Registration
if(-not (Test-Path $registration)){New-Item $registration -Force | Out-Null}
$native=Join-Path $Dir 'iWinInstaller.exe'
$uninstallCommand=if(Test-Path $native){'"'+$native+'" --uninstall'}else{'"'+$ps+'" -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $Dir 'install.ps1')+'" -Uninstall'}
$properties=@{DisplayName='iWinInstaller';DisplayVersion=$tag.TrimStart('v');Publisher='iShun05';InstallLocation=$Dir;DisplayIcon=(Join-Path $Dir 'assets\icon.ico');UninstallString=$uninstallCommand;URLInfoAbout='https://github.com/iShun05/iWinInstaller';InstallDate=(Get-Date -Format 'yyyyMMdd')}
foreach($name in $properties.Keys){Set-ItemProperty $registration -Name $name -Value $properties[$name] -Type String -ErrorAction Stop}
Set-ItemProperty $registration -Name NoModify -Value 1 -Type DWord
Set-ItemProperty $registration -Name NoRepair -Value 1 -Type DWord
# Migracion desde la instalacion por usuario: se retira solo despues de instalar y registrar la nueva.
if ((Test-Path $LegacyDir) -and ([IO.Path]::GetFullPath($LegacyDir).TrimEnd('\') -ne [IO.Path]::GetFullPath($Dir).TrimEnd('\'))) {
    Show-InstallProgress 6 'Retirando la instalacion anterior por usuario (se conservan notas, perfiles y lotes)'
    try { Wait-InstallerProcesses $LegacyDir; Remove-InstallerDirectory $LegacyDir }
    catch { Write-Host 'La copia anterior sigue en uso; se retirara al reinstalar. La nueva version ya esta instalada.' }
}
Remove-Item $LegacyRegistration -Recurse -Force -ErrorAction SilentlyContinue
if ($LegacyStartLink -ne $StartLink) { Remove-Item $LegacyStartLink -ErrorAction SilentlyContinue }
$prefsPath=Join-Path (Join-Path $env:LOCALAPPDATA 'iWinInstaller') 'preferencias.json'
if((Test-Path $prefsPath) -and (Test-Path (Join-Path $Dir 'lifecycle.ps1'))){
    try{
        $preferences=Get-Content $prefsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($preferences.autoUpdate -eq $true){. (Join-Path $Dir 'lifecycle.ps1');Set-IwinAutoUpdate $true}
    }catch{Write-Host 'La app esta instalada. No se pudo renovar la tarea de actualizacion; revisala desde la app.'}
}
Write-Progress -Id 1 -Activity 'Instalando iWinInstaller v4.5' -Completed
Write-Host '[7/7] Instalacion completada.'
Write-Host "iWinInstaller $tag instalado en $Dir"
Write-Host 'Accesos directos creados en el menu Inicio y en el Escritorio.'
if (-not $Silent) {
    # El instalador corre como administrador; la app se abre sin elevacion a traves del Explorador
    if (Test-Path (Join-Path $Dir 'iWinInstaller.exe')) { Start-Process explorer.exe -ArgumentList ('"' + (Join-Path $Dir 'iWinInstaller.exe') + '"') }
    else { Start-Process $ps -ArgumentList $args0 }
}

}finally{if($ownsInstall){$installMutex.ReleaseMutex()};$installMutex.Dispose()}
