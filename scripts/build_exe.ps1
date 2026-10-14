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
$zip=Join-Path $OutputDirectory 'iWinInstaller.zip'
& git -C $root archive --format=zip --prefix=iWinInstaller/ -o $zip $Ref -- . ':!.github' ':!tests' ':!installer-header.bat'
if ($LASTEXITCODE) { throw 'No se pudo empaquetar la app.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Update)
try {
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$launcher,'iWinInstaller/iWinInstaller.exe')
    $lines=@()
    foreach ($name in @('iWinInstaller.ps1','apps.json','profiles.json','launch.ps1','iWinInstaller.exe')) {
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
            Invoke-WebRequest $asset.browser_download_url -OutFile $file -UseBasicParsing
        }
        if ((Get-FileHash $file).Hash.ToLowerInvariant() -ne $asset.digest.Substring(7)) { throw "Hash incorrecto: $($asset.name)" }
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file,('iWinInstaller/prerequisites/'+$asset.name),[IO.Compression.CompressionLevel]::NoCompression)
    }
} finally { $archive.Dispose() }
$hash=Join-Path $OutputDirectory 'payload.sha256'
(Get-FileHash $zip).Hash.ToLowerInvariant() | Set-Content $hash -Encoding ASCII
$setup=Join-Path $OutputDirectory 'iWinInstaller-Setup.exe'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 "/win32manifest:$root\native\app.manifest" /define:SETUP @references "/win32icon:$root\assets\icon.ico" "/resource:$zip,payload.zip" "/resource:$hash,payload.sha256" "/out:$setup" $source
if ($LASTEXITCODE) { throw 'No se pudo compilar el instalador.' }
Write-Host "EXE y ZIP listos en $OutputDirectory"
