# Analiza todos los scripts con el analizador de Windows PowerShell 5.1, el que usa la app.
# Se ejecuta con powershell.exe: el analizador de PowerShell 7 acepta sintaxis que 5.1 rechaza.

BeforeDiscovery {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $scripts = Get-ChildItem $root -Recurse -Include *.ps1, *.psm1 -File |
        Where-Object { $_.FullName -notmatch '\\(\.git|\.specify|resultados)\\' } |
        ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Path.Length + 1) } }
}

Describe 'Sintaxis de PowerShell 5.1' {
    It 'se ejecuta en Windows PowerShell 5.1' {
        $PSVersionTable.PSVersion.Major | Should -Be 5
    }

    It '<Name> no tiene errores de sintaxis' -ForEach $scripts {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        @($errors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) | Should -BeNullOrEmpty
    }
}
