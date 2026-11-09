# Ningún archivo de código supera ~1.500 líneas (SC-007 del plan): archivos pequeños y por áreas.

BeforeDiscovery {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $files = Get-ChildItem $root -Recurse -File -Include *.ps1, *.cs, *.xaml |
        Where-Object { $_.FullName -notmatch '\\(\.git|bin|obj|\.specify|\.claude)\\' } |
        ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Path.Length + 1) } }
}

Describe 'Tamaño de los archivos de código' {
    It '<Name> tiene como mucho 1.500 líneas' -ForEach $files {
        @(Get-Content -LiteralPath $Path).Count | Should -BeLessOrEqual 1500
    }
}
