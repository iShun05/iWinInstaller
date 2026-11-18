# iWinInstaller — motor: sincronizar la configuración entre PC con un repo PRIVADO de GitHub del usuario.
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.
#
# Complementa a Exportar/Importar (16-Config.ps1): el mismo documento JSON, guardado en un clon local del repo
# que el usuario elige (%LOCALAPPDATA%\iWinInstaller\sync\repo). Usa el git y las credenciales del propio usuario
# (Git Credential Manager o `gh auth`); iWinInstaller no guarda ningún token. Antes de subir se comprueba que el
# repo no sea público; los datos personales (notas, servidor del juego) nunca se suben.

$IwinSyncFile = 'iwininstaller-config.json'

function Get-IwinSyncDir { Join-Path $LogDir 'sync' }
function Get-IwinSyncSettingsPath { Join-Path (Get-IwinSyncDir) 'sync.json' }
function Get-IwinSyncRepoDir { Join-Path (Get-IwinSyncDir) 'repo' }

# Solo https://github.com/<usuario>/<repo>[.git]; nada de rutas locales, ssh ni otros servidores
function ConvertTo-IwinSyncRepo([string]$url) {
    $text = ([string]$url).Trim()
    if ($text -notmatch '^https://github\.com/([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))/([A-Za-z0-9._-]{1,100}?)(?:\.git)?/?$') { return $null }
    if ($Matches[2].StartsWith('.')) { return $null }
    [pscustomobject]@{ Owner = $Matches[1]; Name = $Matches[2]; Url = "https://github.com/$($Matches[1])/$($Matches[2]).git" }
}

function Read-IwinSyncSettings {
    $path = Get-IwinSyncSettingsPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { throw 'La configuración de sincronización está dañada.' }
    $repo = ConvertTo-IwinSyncRepo ([string]$data.repo)
    if (-not $repo) { throw 'La configuración de sincronización no tiene un repo de GitHub válido.' }
    $repo
}

# ¿El repo es público? Una petición anónima a la API de GitHub solo ve repos públicos.
# Devuelve $true (público), $false (privado o inexistente para un anónimo) o $null (no se pudo saber).
function Test-IwinSyncRepoPublic($repo) {
    try {
        $null = Invoke-RestMethod -Uri "https://api.github.com/repos/$($repo.Owner)/$($repo.Name)" -Headers @{ 'User-Agent' = 'iWinInstaller'; Accept = 'application/vnd.github+json' } -TimeoutSec 20 -ErrorAction Stop
        return $true
    } catch {
        $status = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        if ($status -eq 404) { return $false }
        return $null
    }
}

function Invoke-IwinGit([string[]]$arguments, [string]$dir) {
    if (-not (Test-Cmd git)) { throw 'Falta Git. Instálalo desde el catálogo (Git) y vuelve a intentarlo.' }
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        # GIT_TERMINAL_PROMPT=0: si no hay credenciales guardadas falla en vez de quedarse esperando una consola
        $env:GIT_TERMINAL_PROMPT = '0'
        $out = if ($dir) { & git -C $dir @arguments 2>&1 } else { & git @arguments 2>&1 }
        [pscustomobject]@{ Code = $LASTEXITCODE; Text = (($out | Out-String).Trim()) }
    } finally { $ErrorActionPreference = $previous }
}

function Get-IwinSyncClone($repo) {
    $dir = Get-IwinSyncRepoDir
    if (-not (Test-Path -LiteralPath (Join-Path $dir '.git'))) {
        New-Item (Get-IwinSyncDir) -ItemType Directory -Force | Out-Null
        $clone = Invoke-IwinGit @('clone', '--quiet', $repo.Url, $dir) $null
        if ($clone.Code -ne 0) { throw "No se pudo clonar el repo (¿existe y has iniciado sesión en GitHub?): $($clone.Text)" }
    } else {
        $remote = Invoke-IwinGit @('remote', 'get-url', 'origin') $dir
        if ($remote.Text -ne $repo.Url) { throw 'El clon local apunta a otro repo; usa «sync.disconnect» y vuelve a conectar.' }
        $fetch = Invoke-IwinGit @('pull', '--quiet', '--ff-only') $dir
        if ($fetch.Code -ne 0 -and $fetch.Text -notmatch 'empty|no tracking|Cannot fast-forward') { throw "No se pudo actualizar el clon: $($fetch.Text)" }
    }
    $dir
}

Register-IwinEngineCommand 'sync.status' {
    param($request)
    $repo = Read-IwinSyncSettings
    if (-not $repo) { return @{ connected = $false } }
    $file = Join-Path (Get-IwinSyncRepoDir) $IwinSyncFile
    @{ connected = $true; repo = "$($repo.Owner)/$($repo.Name)"; cloned = (Test-Path -LiteralPath (Join-Path (Get-IwinSyncRepoDir) '.git')); hasConfig = (Test-Path -LiteralPath $file) }
}

Register-IwinEngineCommand 'sync.connect' {
    param($request)
    $repo = ConvertTo-IwinSyncRepo ([string]$request.repo)
    if (-not $repo) { throw [ArgumentException]'Indica un repo con la forma https://github.com/usuario/repo.' }
    $public = Test-IwinSyncRepoPublic $repo
    if ($public -eq $true) { throw [ArgumentException]'Ese repo es público. Crea uno privado: la configuración de tu PC no debe publicarse.' }
    Write-IwinJson (Get-IwinSyncSettingsPath) ([ordered]@{ format = 'iWinInstaller-sync'; version = 1; repo = $repo.Url })
    @{ connected = $true; repo = "$($repo.Owner)/$($repo.Name)"; privateChecked = ($public -eq $false) }
}

Register-IwinEngineCommand 'sync.disconnect' {
    param($request)
    $dir = Get-IwinSyncDir
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop }
    @{ connected = $false }
}

# Exporta la configuración de este PC al repo y la sube. Sin datos personales.
Register-IwinEngineCommand 'sync.push' {
    param($request)
    $repo = Read-IwinSyncSettings
    if (-not $repo) { throw [ArgumentException]'Primero conecta un repo privado.' }
    if ((Test-IwinSyncRepoPublic $repo) -eq $true) { throw [ArgumentException]'Ese repo es público: no se sube nada.' }
    $dir = Get-IwinSyncClone $repo
    $ids = @(Get-IwinInstalledIds)
    $ctx = New-IwinConfigContext $false $false $ids
    $built = New-IwinConfigDocument ([string]$env:COMPUTERNAME) $ctx
    Write-IwinJson (Join-Path $dir $IwinSyncFile) $built.Document
    $null = Invoke-IwinGit @('add', '--', $IwinSyncFile) $dir
    $diff = Invoke-IwinGit @('diff', '--cached', '--quiet') $dir
    if ($diff.Code -eq 0) { return @{ pushed = $false; unchanged = $true; count = $ids.Count; sections = @($built.Document.secciones.Keys) } }
    $commit = Invoke-IwinGit @('-c', 'user.name=iWinInstaller', '-c', 'user.email=iwininstaller@users.noreply.github.com', 'commit', '--quiet', '-m', "Configuración de $($env:COMPUTERNAME)") $dir
    if ($commit.Code -ne 0) { throw "No se pudo guardar el cambio: $($commit.Text)" }
    $push = Invoke-IwinGit @('push', '--quiet') $dir
    if ($push.Code -ne 0) { throw "No se pudo subir (¿sesión de GitHub iniciada y permiso de escritura?): $($push.Text)" }
    @{ pushed = $true; unchanged = $false; count = $ids.Count; sections = @($built.Document.secciones.Keys); failed = @($built.Failed) }
}

# Descarga la configuración del repo y la describe (o aplica con apply = true); devuelve los ids para batch.run
Register-IwinEngineCommand 'sync.pull' {
    param($request)
    $repo = Read-IwinSyncSettings
    if (-not $repo) { throw [ArgumentException]'Primero conecta un repo privado.' }
    $dir = Get-IwinSyncClone $repo
    $file = Join-Path $dir $IwinSyncFile
    if (-not (Test-Path -LiteralPath $file)) { throw [ArgumentException]'El repo todavía no tiene configuración: haz «Subir» desde otro PC.' }
    $config = try { Read-IwinConfigFile $file } catch { throw [ArgumentException]$_.Exception.Message }
    $plan = Invoke-IwinConfigImport $config ([bool]$request.apply) @($request.sections | Where-Object { $_ })
    @{ name = $config.Name; applied = [bool]$request.apply; ignored = $plan.Ignored; lines = $plan.Lines; errors = $plan.Errors; ids = $plan.Ids }
}
