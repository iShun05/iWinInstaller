# Texto completo del script principal: iWinInstaller.ps1 seguido de los archivos de src/engine en
# orden de carga. Las pruebas buscan funciones aquí sin importar en qué archivo viven.
function Get-IwinEngineFiles([string]$root) {
    @(Get-ChildItem (Join-Path $root 'src\engine') -Filter *.ps1 -File | Where-Object Name -match '^\d\d-' | Sort-Object Name)
}
function Get-IwinSource([string]$root) {
    $parts = @(Get-Content (Join-Path $root 'iWinInstaller.ps1') -Raw -Encoding UTF8)
    foreach ($file in Get-IwinEngineFiles $root) { $parts += Get-Content $file.FullName -Raw -Encoding UTF8 }
    $parts -join "`n"
}
