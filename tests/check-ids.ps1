param([string]$Solo)  # ids de apps.json separados por espacios o comas; vacío = todas
# Comprueba que cada id de winget de apps.json existe en su origen. Sale con el número de ids que no se encuentran.
$apps = @(Get-Content (Join-Path $PSScriptRoot '..\apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }) | Where-Object { $_.type -in 'winget', 'wingetall' }
if ($Solo) {
    $lista = @($Solo -split '[\s,;]+' | Where-Object { $_ })
    $apps = @($apps | Where-Object { $lista -contains $_.id })
    $sobran = @($lista | Where-Object { $_ -notin $apps.id })
    if ($sobran) { Write-Output "Ids de apps.json desconocidos o sin winget: $($sobran -join ', ')"; exit 1 }
}
$apps = foreach ($a in $apps) { foreach ($w in @($a.winget)) { [pscustomobject]@{ id = $a.id; name = $a.name; winget = $w; source = $a.source; scope = $a.scope; architecture = $a.architecture } } }
$bad = @()
foreach ($a in $apps) {
    $src = if ($a.source) { $a.source } else { 'winget' }
    # Con el mismo ámbito y arquitectura que pedirá la instalación: un id válido sin instalador para ese ámbito también falla
    $extra = @(); if ($a.scope) { $extra += @('--scope', $a.scope) }; if ($a.architecture) { $extra += @('--architecture', $a.architecture) }
    $out = (winget show -e --id $a.winget --source $src @extra --accept-source-agreements --disable-interactivity 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0) { Write-Output "OK    $($a.winget)" }
    else { Write-Output "FALLA $($a.winget) ($($a.name)) código $LASTEXITCODE · $(($out -split "`n" | Select-Object -Last 1))"; $bad += "$($a.id): $($a.winget)"
        # Pistas: lo que encuentra winget buscando por nombre
        foreach ($s in 'winget', 'msstore') { "      [$s]"; winget search --name $a.name --source $s --accept-source-agreements --disable-interactivity 2>&1 | Select-Object -Last 4 | ForEach-Object { "      $_" } } }
}
Write-Output "`n$($apps.Count - $bad.Count)/$($apps.Count) ids encontrados"
if ($bad) { Write-Output "No encontrados:`n$($bad -join "`n")" }
exit $bad.Count
