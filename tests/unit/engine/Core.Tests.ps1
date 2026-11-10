# Resiliencia (v5.2): rotación de registros y copia de trabajo sin duplicados de sincronización.

BeforeAll {
    $script:Root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    . (Join-Path $script:Root 'tests\lib\IwinSource.ps1')
    # Solo se carga la función que se prueba, sin ejecutar el resto del motor
    $errors = $null
    $tree = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root 'src\engine\01-Core.ps1'), [ref]$null, [ref]$errors)
    $node = $tree.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Clear-IwinOldLogs' }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
    $script:Logs = Join-Path ([IO.Path]::GetTempPath()) ('iwin-logs-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:Logs -ItemType Directory | Out-Null
}

AfterAll { Remove-Item $script:Logs -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Rotación de registros' {
    It 'borra los antiguos, conserva los recientes y nunca toca otros archivos' {
        1..6 | ForEach-Object {
            $file = Join-Path $script:Logs ("iWinInstaller_2026-01-0$_.log")
            Set-Content $file 'x'
            (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-40 - $_)
        }
        $recent = Join-Path $script:Logs 'iWinInstaller_reciente.log'; Set-Content $recent 'x'
        $other = Join-Path $script:Logs 'preferencias.json'; Set-Content $other '{}'
        (Get-Item $other).LastWriteTime = (Get-Date).AddDays(-400)
        # Se conservan los 3 más recientes aunque sean antiguos: el reciente y los dos antiguos más nuevos
        Clear-IwinOldLogs $script:Logs 30 3 | Should -Be 4
        @(Get-ChildItem $script:Logs -Filter 'iWinInstaller_*.log').Count | Should -Be 3
        Test-Path $recent | Should -BeTrue
        Test-Path $other | Should -BeTrue
        Clear-IwinOldLogs $script:Logs 30 3 | Should -Be 0
    }

    It 'una carpeta que no existe no es un error' {
        Clear-IwinOldLogs (Join-Path $script:Logs 'no-existe') | Should -Be 0
    }
}

Describe 'Motor en equipos restringidos' {
    It 'comprueba el modo de lenguaje antes de cargar el motor y sale con el código 12' {
        $main = Get-Content (Join-Path $script:Root 'iWinInstaller.ps1') -Raw -Encoding UTF8
        $guard = $main.IndexOf("LanguageMode -ne 'FullLanguage'")
        $guard | Should -BeGreaterThan 0
        $guard | Should -BeLessThan $main.IndexOf('$EngineFiles = @(')
        $main.Substring($guard, 1200) | Should -Match 'exit 12'
    }
}

Describe 'Copia de trabajo limpia' {
    It 'no hay duplicados de sincronización (archivos «nombre 2.ext»)' {
        $duplicates = @(Get-ChildItem $script:Root -Recurse -File -Force |
            Where-Object { $_.FullName -notmatch '\\(\.git|bin|obj|TestResults)\\' -and $_.Name -match ' \d+\.[^.]+$' } |
            ForEach-Object { $_.FullName.Substring($script:Root.Path.Length + 1) })
        $duplicates | Should -BeNullOrEmpty
    }
}
