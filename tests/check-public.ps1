# Pruebas de regresión en carpetas temporales: nunca ordenan el escritorio del runner.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../lifecycle.ps1')
$root=Split-Path $PSScriptRoot
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'iWinInstaller.ps1'),[ref]$null,[ref]$errors)
if ($errors) { throw ($errors | Out-String) }
foreach ($name in @('Organize-Desktop','Write-Log')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($node.Extent.Text))
}
$fixture=Join-Path $env:TEMP ('iwin-desktop-'+[guid]::NewGuid().ToString('N'))
New-Item $fixture -ItemType Directory | Out-Null
$ws=New-Object -ComObject WScript.Shell
try {
    $shortcut=$ws.CreateShortcut((Join-Path $fixture 'Programa.lnk')); $shortcut.TargetPath=$env:ComSpec; $shortcut.Save()
    $document=Join-Path $fixture 'Documento.txt'; Set-Content $document 'conservar'
    $shortcut=$ws.CreateShortcut((Join-Path $fixture 'Documento.lnk')); $shortcut.TargetPath=$document; $shortcut.Save()
    New-Item (Join-Path $fixture 'Mis archivos') -ItemType Directory | Out-Null
    New-Item (Join-Path $fixture 'Aplicaciones') -ItemType Directory | Out-Null
    Set-Content (Join-Path $fixture 'Aplicaciones\Programa.lnk') 'anterior'
    Set-Content (Join-Path $fixture 'Juego.url') '[InternetShortcut]', 'URL=steam://rungameid/123'
    Set-Content (Join-Path $fixture 'Web.url') '[InternetShortcut]', 'URL=https://example.invalid/'
    function Get-DesktopPaths { @($fixture) }
    $LogFile=Join-Path $fixture 'registro.log'; $log=$null; $WorkerMode=''; $Check=$false
    Organize-Desktop -destinationFolder (Join-Path $fixture 'Aplicaciones')
    if ((Get-Content (Join-Path $fixture 'Aplicaciones\Programa.lnk')) -ne 'anterior') { throw 'No puede sobrescribir un acceso existente' }
    if (-not (Test-Path (Join-Path $fixture 'Aplicaciones\Programa (1).lnk'))) { throw 'Debe conservar ambos accesos de igual nombre' }
    if (-not (Test-Path (Join-Path $fixture 'Aplicaciones\Juego.url'))) { throw 'Debe organizar accesos de juegos' }
    foreach ($name in @('Documento.txt','Documento.lnk','Mis archivos','Web.url')) {
        if (-not (Test-Path (Join-Path $fixture $name))) { throw "No puede mover $name" }
    }
    Organize-Desktop -destinationFolder (Join-Path $fixture 'Aplicaciones')
    if (@(Get-ChildItem (Join-Path $fixture 'Aplicaciones')).Count -ne 3) { throw 'Repetir no debe duplicar accesos' }
    $ResultFile=Join-Path $fixture 'events.jsonl'; $WorkerMode='machine'
    function Write-WorkerEvent($event) { Add-Content $ResultFile ($event | ConvertTo-Json -Compress) }
    Write-Log 'Instalando Programa...'
    Write-Log '    detalle técnico'
    $events=@(Get-Content $ResultFile | ForEach-Object { $_ | ConvertFrom-Json })
    if ($events.Count -ne 1 -or $events[0].message -ne 'Instalando Programa...') { throw 'El proceso debe transmitir actividad legible sin inundar la ventana' }
    if ((Get-Content $LogFile -Raw) -notmatch 'detalle técnico') { throw 'El TXT debe conservar el detalle técnico' }
} finally { Remove-Item $fixture -Recurse -Force }
$apps=@(Get-Content (Join-Path $root 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
if (($apps | Group-Object id | Where-Object Count -gt 1)) { throw 'IDs duplicados' }
if (($apps | Where-Object { $_.type -in @('projects','claudesetup','gitconfig','obsidianvault','schedtask') -or $_.mac })) { throw 'El catálogo debe contener solo operaciones generales' }
foreach ($name in @('acceso.json','claude-setup','extras','mac')) {
    if (Test-Path (Join-Path $root $name)) { throw "Contenido privado distribuido: $name" }
}
$source=Get-Content (Join-Path $root 'iWinInstaller.ps1') -Raw
if ($source -match 'Request-Clave|Test-Clave|IWIN_CLAVE|Get-ProjectList|Install-ClaudeSetup') { throw 'Queda una función privada' }
$installer=Get-Content (Join-Path $root 'install.ps1') -Raw
if ($installer -match 'gh auth|Ensure-GitHubCli') { throw 'La instalación pública no debe pedir una cuenta' }
Write-Host 'OK: escritorio real aislado, colisiones, documentos intactos, IPC y producto sin funciones privadas.'
