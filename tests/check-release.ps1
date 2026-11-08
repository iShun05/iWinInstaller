# Verifica que la versión publicada es la última y que sus descargas están completas e íntegras.
# Requiere PowerShell 7 y la CLI de GitHub (gh) con GH_TOKEN. Sale con el número de fallos.
#   -Tag          tag a comprobar (vacío = el tag de versión más alto del repositorio)
#   -GraceMinutes margen para un tag recién creado cuya publicación sigue en curso
param(
    [string]$Repo = 'iShun05/iWinInstaller',
    [string]$Tag,
    [int]$GraceMinutes = 0
)
$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()
$required = 'iWinInstaller-Setup.exe', 'iWinInstaller.zip', 'install.ps1'

function Fail([string]$message) {
    $failures.Add($message)
    Write-Host "::error title=Verificación de la release::$message"
}

function Invoke-GhJson([string]$endpoint) {
    $json = gh api $endpoint 2>&1
    if ($LASTEXITCODE) { throw "gh api $endpoint falló: $json" }
    ($json -join "`n") | ConvertFrom-Json
}

# Tag de versión más alto (vX.Y). --jq aplana todas las páginas a un nombre por línea.
$tags = @(gh api "repos/$Repo/tags?per_page=100" --paginate --jq '.[].name' | Where-Object { $_ -match '^v\d+\.\d+$' })
if ($LASTEXITCODE) { throw 'No se pudieron leer los tags' }
if (-not $tags) { throw 'El repositorio no tiene tags de versión' }
$highest = $tags | Sort-Object { [version]$_.Substring(1) } | Select-Object -Last 1
if (-not $Tag) { $Tag = $highest }
Write-Host "Tag más alto: $highest · comprobando: $Tag"

# Un tag recién creado puede estar aún publicándose
if ($GraceMinutes -gt 0) {
    $date = [datetime](Invoke-GhJson "repos/$Repo/commits/$Tag").commit.committer.date
    if (((Get-Date).ToUniversalTime() - $date.ToUniversalTime()).TotalMinutes -lt $GraceMinutes) {
        Write-Host "El commit de $Tag tiene menos de $GraceMinutes min: se comprobará en la siguiente ejecución."
        exit 0
    }
}

# Release marcada como última
$latest = Invoke-GhJson "repos/$Repo/releases/latest"
if ($latest.tag_name -ne $Tag) { Fail "La última release es $($latest.tag_name), pero se esperaba $Tag." }
if ($Tag -ne $highest) { Fail "$Tag no es el tag más alto ($highest)." }

$release = Invoke-GhJson "repos/$Repo/releases/tags/$Tag"
if ($release.draft -or $release.prerelease) { Fail "La release $Tag es borrador o prerelease." }
if ([string]::IsNullOrWhiteSpace($release.body)) { Fail "La release $Tag no tiene notas." }

# Descargas presentes y con la huella que publica GitHub
$work = Join-Path ([IO.Path]::GetTempPath()) "iwin-release-$([guid]::NewGuid().ToString('N'))"
New-Item $work -ItemType Directory | Out-Null
try {
    foreach ($name in $required) {
        $asset = @($release.assets | Where-Object name -eq $name)[0]
        if (-not $asset) { Fail "Falta la descarga $name en $Tag."; continue }
        if ($asset.size -le 0) { Fail "La descarga $name está vacía."; continue }
        gh release download $Tag --repo $Repo --pattern $name --dir $work --clobber
        if ($LASTEXITCODE) { Fail "No se pudo descargar $name."; continue }
        $hash = (Get-FileHash (Join-Path $work $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($asset.digest -match '^sha256:(?<h>[0-9a-f]{64})$') {
            if ($Matches.h -ne $hash) { Fail "$name no coincide con su huella publicada ($($Matches.h) ≠ $hash)." }
            else { Write-Host "OK  $name  sha256:$hash" }
        } else {
            Write-Host "::warning title=Verificación de la release::GitHub no publica huella para $name; descargado correctamente (sha256:$hash)."
        }
    }

    # El enlace fijo del README debe llevar a la última versión
    foreach ($name in 'iWinInstaller-Setup.exe', 'iWinInstaller.zip') {
        $url = "https://github.com/$Repo/releases/latest/download/$name"
        try {
            $response = Invoke-WebRequest $url -Method Head -MaximumRedirection 10 -UseBasicParsing
            if ($response.StatusCode -ne 200) { Fail "$url responde $($response.StatusCode)." }
        } catch { Fail "$url no responde: $($_.Exception.Message)" }
    }
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { Write-Host "`n$($failures.Count) fallo(s) en $Tag."; exit $failures.Count }
Write-Host "`n$Tag publicada, última y con sus descargas íntegras."
