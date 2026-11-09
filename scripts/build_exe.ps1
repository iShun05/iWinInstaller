param([Parameter(Mandatory=$true)][string]$OutputDirectory, [string]$Ref='HEAD')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root=Split-Path $PSScriptRoot
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null
$OutputDirectory=(Resolve-Path $OutputDirectory).Path
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $compiler)) { $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $compiler)) { throw 'Falta el compilador .NET Framework de Windows.' }
$source=Join-Path $root 'native\Launcher.cs'
$launcher=Join-Path $OutputDirectory 'iWinInstaller.exe'
$references=@('/r:System.Windows.Forms.dll','/r:System.Drawing.dll','/r:System.IO.Compression.dll','/r:System.IO.Compression.FileSystem.dll')
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 "/win32manifest:$root\native\app.manifest" @references "/win32icon:$root\assets\icon.ico" "/out:$launcher" $source
if ($LASTEXITCODE) { throw 'No se pudo compilar el lanzador.' }
# Interfaz WPF (v4.4+): se compila con el SDK de .NET. Sin SDK se empaqueta solo la ventana clásica,
# salvo que IWIN_REQUIRE_APP lo exija (publicación).
$appBuild=Join-Path $OutputDirectory 'app-build'
$appFiles=@()
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    & dotnet build (Join-Path $root 'src\app\iWinInstaller.App.csproj') -c Release -o $appBuild --nologo
    if ($LASTEXITCODE) { throw 'No se pudo compilar la interfaz.' }
    $appFiles=@('iWinInstaller.App.exe','iWinInstaller.App.exe.config') | ForEach-Object { Join-Path $appBuild $_ } | Where-Object { Test-Path $_ }
    if (-not ($appFiles | Where-Object { $_ -like '*.exe' })) { throw 'La compilación de la interfaz no produjo iWinInstaller.App.exe.' }
} elseif ($env:IWIN_REQUIRE_APP) { throw 'Falta el SDK de .NET para compilar la interfaz.' }
else { Write-Warning 'Sin SDK de .NET: el paquete abrirá la ventana clásica.' }
$zip=Join-Path $OutputDirectory 'iWinInstaller.zip'
& git -C $root archive --format=zip --prefix=iWinInstaller/ -o $zip $Ref -- . ':!.github' ':!tests' ':!installer-header.bat'
if ($LASTEXITCODE) { throw 'No se pudo empaquetar la app.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Update)
try {
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$launcher,'iWinInstaller/iWinInstaller.exe')
    foreach ($file in $appFiles) { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file,('iWinInstaller/'+(Split-Path $file -Leaf))) }
    $lines=@()
    # Archivos esenciales y todo src/ (motor e interfaz): el lanzador verifica cada línea del manifiesto
    $names=@('iWinInstaller.ps1','apps.json','profiles.json','lifecycle.ps1','install.ps1','launch.ps1','iWinInstaller.exe')
    $names+=@($archive.Entries | Where-Object { $_.FullName -like 'iWinInstaller/src/*' -and $_.Name } | ForEach-Object { $_.FullName.Substring('iWinInstaller/'.Length) } | Sort-Object)
    $names+=@($appFiles | ForEach-Object { Split-Path $_ -Leaf })
    foreach ($name in $names) {
        $entry=$archive.GetEntry('iWinInstaller/'+$name)
        $stream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant(); $lines+="$hash  $name" }
        finally { $stream.Dispose(); $sha.Dispose() }
    }
    $manifest=$archive.CreateEntry('iWinInstaller/integrity.sha256')
    $writer=New-Object IO.StreamWriter($manifest.Open())
    try { $writer.Write(($lines -join "`n")) } finally { $writer.Dispose() }
    $metadata=Get-Content (Join-Path $root 'native\prerequisites.json') -Raw | ConvertFrom-Json
    foreach ($asset in $metadata.assets) {
        $file=Join-Path $OutputDirectory $asset.name
        if (-not (Test-Path $file) -or (Get-FileHash $file).Hash.ToLowerInvariant() -ne $asset.digest.Substring(7)) {
            # Las descargas de GitHub fallan a veces con 502/504: hasta cinco intentos. Si la ruta pública sigue
            # fallando y hay CLI de GitHub (CI), se descarga por la API, que usa otro servidor. La huella se comprueba igual.
            for ($attempt = 1; ; $attempt++) {
                try { Invoke-WebRequest $asset.browser_download_url -OutFile $file -UseBasicParsing; break }
                catch {
                    Write-Warning "Descarga de $($asset.name) fallida ($($_.Exception.Message)); intento $attempt"
                    if ($attempt -ge 3 -and (Get-Command gh -ErrorAction SilentlyContinue)) {
                        & gh release download $metadata.version --repo microsoft/winget-cli --pattern $asset.name --dir $OutputDirectory --clobber
                        if ($LASTEXITCODE -eq 0 -and (Test-Path $file)) { break }
                    }
                    if ($attempt -ge 5) { throw }
                    Start-Sleep -Seconds (10 * $attempt)
                }
            }
        }
        if ((Get-FileHash $file).Hash.ToLowerInvariant() -ne $asset.digest.Substring(7)) { throw "Hash incorrecto: $($asset.name)" }
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file,('iWinInstaller/prerequisites/'+$asset.name),[IO.Compression.CompressionLevel]::NoCompression)
    }
} finally { $archive.Dispose() }
$hash=Join-Path $OutputDirectory 'payload.sha256'
(Get-FileHash $zip).Hash.ToLowerInvariant() | Set-Content $hash -Encoding ASCII
$setup=Join-Path $OutputDirectory 'iWinInstaller-Setup.exe'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 "/win32manifest:$root\native\setup.manifest" /define:SETUP @references "/win32icon:$root\assets\icon.ico" "/resource:$zip,payload.zip" "/resource:$hash,payload.sha256" "/out:$setup" $source
if ($LASTEXITCODE) { throw 'No se pudo compilar el instalador.' }
Write-Host "EXE y ZIP listos en $OutputDirectory"
