# Valida apps.json y profiles.json contra sus esquemas y comprueba las referencias cruzadas.
# Requiere PowerShell 7.4 o posterior (Test-Json con JSON Schema 2020-12).

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $schemaDir = Join-Path $root 'src\catalog\schema'
    $appsText = Get-Content (Join-Path $root 'apps.json') -Raw -Encoding UTF8
    $profilesText = Get-Content (Join-Path $root 'profiles.json') -Raw -Encoding UTF8
    $apps = @($appsText | ConvertFrom-Json)
    $profiles = $profilesText | ConvertFrom-Json

    # Devuelve los mensajes de error de Test-Json; vacío solo si el documento es válido
    function Get-SchemaErrors([string]$json, [string]$schemaFile) {
        $schemaErrors = @()
        $ok = Test-Json -Json $json -SchemaFile $schemaFile -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
        Write-Host "Test-Json $(Split-Path $schemaFile -Leaf): $ok · $(@($schemaErrors).Count) error(es)"
        if ($ok) { return @() }
        $messages = @($schemaErrors | ForEach-Object { $_.ToString() } | Select-Object -First 20)
        if (-not $messages) { $messages = @('Test-Json devolvió falso sin detalle') }
        $messages
    }
}

Describe 'Esquema del catálogo' {
    It 'apps.json cumple apps.schema.json' {
        Get-SchemaErrors $appsText (Join-Path $schemaDir 'apps.schema.json') | Should -BeNullOrEmpty
    }

    It 'profiles.json cumple profiles.schema.json' {
        Get-SchemaErrors $profilesText (Join-Path $schemaDir 'profiles.schema.json') | Should -BeNullOrEmpty
    }

    It 'rechaza una entrada con un campo desconocido' {
        $broken = '[{"id":"x","section":"Sistema","group":"g","name":"n","desc":"d","icon":"i","type":"tweak","campoInventado":true}]'
        Get-SchemaErrors $broken (Join-Path $schemaDir 'apps.schema.json') | Should -Not -BeNullOrEmpty
    }

    It 'rechaza una app de winget sin id de winget' {
        $broken = '[{"id":"x","section":"Sistema","group":"g","name":"n","desc":"d","icon":"i","type":"winget"}]'
        Get-SchemaErrors $broken (Join-Path $schemaDir 'apps.schema.json') | Should -Not -BeNullOrEmpty
    }
}

Describe 'Referencias del catálogo' {
    It 'no repite ids' {
        $dupes = $apps | Group-Object id | Where-Object Count -gt 1 | ForEach-Object Name
        $dupes | Should -BeNullOrEmpty
    }

    It 'las dependencias (requires) apuntan a ids existentes' {
        $ids = $apps.id
        $missing = foreach ($app in $apps) { foreach ($r in @($app.requires)) { if ($r -and $ids -notcontains $r) { "$($app.id) → $r" } } }
        $missing | Should -BeNullOrEmpty
    }

    It 'cada elemento de un perfil es un id, un grupo, una sección o un comodín' {
        $valid = @($apps.id) + @($apps.group) + @($apps.section | ForEach-Object { "@$_" }) + @('*', '@hardware')
        $unknown = foreach ($p in $profiles.PSObject.Properties) { foreach ($e in @($p.Value)) { if ($valid -notcontains $e) { "$($p.Name) → $e" } } }
        $unknown | Should -BeNullOrEmpty
    }
}
