# iWinInstaller — motor: actualizaciones disponibles de WinGet (tarjeta del Inicio y, desde v4.5, su módulo).
# Se carga con «.» desde iWinInstaller.ps1, en orden, en el ámbito del script principal.

# Convierte la tabla de «winget upgrade» en objetos. Las columnas se localizan por la posición de
# los títulos (que cambian con el idioma de Windows); el nombre puede contener espacios, el id no.
function ConvertFrom-WingetTable([string[]]$lines) {
    # La animación de progreso de winget escribe varios trozos separados por «\r»: vale el último
    $clean = @($lines | ForEach-Object { $parts = @($_ -split "`r" | Where-Object { $_.Trim() }); if ($parts) { $parts[-1] } else { '' } })
    $separator = -1
    for ($i = 1; $i -lt $clean.Count; $i++) { if ($clean[$i] -match '^-{10,}\s*$') { $separator = $i; break } }
    if ($separator -lt 1) { return @() }
    $header = $clean[$separator - 1]
    $starts = @([regex]::Matches($header, '\S+') | ForEach-Object Index)
    if ($starts.Count -lt 4) { return @() }
    foreach ($line in $clean[($separator + 1)..($clean.Count - 1)]) {
        if ($line.Length -le $starts[1] -or $line -match '^\s*$') { continue }
        # Las líneas de resumen («3 upgrades available.», «3 actualizaciones disponibles.») no tienen id
        $cells = for ($c = 0; $c -lt $starts.Count; $c++) {
            $from = $starts[$c]
            if ($from -ge $line.Length) { ''; continue }
            $to = if ($c + 1 -lt $starts.Count) { [Math]::Min($starts[$c + 1], $line.Length) } else { $line.Length }
            $line.Substring($from, $to - $from).Trim()
        }
        $cells = @($cells)
        if ($cells.Count -lt 4 -or $cells[1] -notmatch '^[A-Za-z0-9][\w.+-]*\.[\w.+-]+$|^9[A-Z0-9]{11}$|^XP[A-Z0-9]{10}$') { continue }
        if (-not $cells[3]) { continue }
        [pscustomobject]@{
            Name = $cells[0] -replace '…$', ''
            Id = $cells[1]
            Version = $cells[2]
            Available = $cells[3]
            Source = if ($cells.Count -gt 4) { $cells[4] } else { '' }
        }
    }
}

# Lista las actualizaciones que ofrece WinGet. Devuelve $null si no se pudo comprobar.
function Get-IwinAvailableUpdates([int]$timeoutSec = 180) {
    if (-not (Test-Cmd winget)) { return $null }
    $out = Join-Path $env:TEMP ('iwin_upgrade_' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $p = Start-Process winget -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -ArgumentList @('upgrade', '--accept-source-agreements', '--disable-interactivity')
        $null = $p.Handle
        if (-not $p.WaitForExit($timeoutSec * 1000)) { try { $p.Kill() } catch { }; return $null }
        if (-not (Test-Path $out)) { return $null }
        $lines = [IO.File]::ReadAllLines($out, [Text.Encoding]::UTF8)
        # Sin actualizaciones winget no imprime tabla: es un resultado válido (lista vacía)
        @(ConvertFrom-WingetTable $lines)
    } catch { $null }
    finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
}
