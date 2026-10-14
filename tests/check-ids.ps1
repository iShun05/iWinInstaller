param([string]$Solo)  # ids de apps.json separados por espacios; vacío = todas
# Comprueba que cada id de winget de apps.json existe en su origen. Sale con el número de ids que no se encuentran.
$apps = @(Get-Content (Join-Path $PSScriptRoot '..\apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }) | Where-Object { $_.type -in 'winget', 'wingetall' }
if ($Solo) { $lista = $Solo -split '\s+'; $apps = @($apps | Where-Object { $lista -contains $_.id }) }
$apps = foreach ($a in $apps) { foreach ($w in @($a.winget)) { [pscustomobject]@{ id = $a.id; name = $a.name; winget = $w; source = $a.source } } }
$bad = @()
foreach ($a in $apps) {
    $src = if ($a.source) { $a.source } else { 'winget' }
    $out = (winget show -e --id $a.winget --source $src --accept-source-agreements --disable-interactivity 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0) { Write-Output "OK    $($a.winget)" }
    else { Write-Output "FALLA $($a.winget) ($($a.name)) código $LASTEXITCODE · $(($out -split "`n" | Select-Object -Last 1))"; $bad += "$($a.id): $($a.winget)"
        # Pistas: lo que encuentra winget buscando por nombre
        foreach ($s in 'winget', 'msstore') { "      [$s]"; winget search --name $a.name --source $s --accept-source-agreements --disable-interactivity 2>&1 | Select-Object -Last 4 | ForEach-Object { "      $_" } } }
}
Write-Output "`n$($apps.Count - $bad.Count)/$($apps.Count) ids encontrados"
if ($bad) { Write-Output "No encontrados:`n$($bad -join "`n")" }
exit $bad.Count
