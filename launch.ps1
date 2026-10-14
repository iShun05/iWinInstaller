# El lanzador nativo conserva stderr y el código de salida aunque la ventana se cierre.
$ErrorActionPreference = 'Stop'
try {
    & (Join-Path $PSScriptRoot 'iWinInstaller.ps1')
} catch {
    [Console]::Error.WriteLine(($_ | Format-List * -Force | Out-String))
    [Console]::Error.WriteLine($_.ScriptStackTrace)
    exit 1
}
