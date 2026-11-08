# Pruebas de exclusiones, lista y aplicación de actualizaciones (v4.5) sin ejecutar winget.

BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('iwin-excl-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:LogDir -ItemType Directory | Out-Null
    $script:Apps = @(
        [pscustomobject]@{ id = 'git'; name = 'Git'; type = 'winget'; winget = 'Git.Git' },
        [pscustomobject]@{ id = 'asistente'; name = 'Asistente'; type = 'winget'; winget = 'Vendor.Wizard'; interactive = $true }
    )
    $script:wingetOk = @(0)
    function Write-Log($msg) { }
    . (Join-Path $root 'src\engine\09-Contract.ps1')
    . (Join-Path $root 'src\engine\10-Updates.ps1')
}

AfterAll { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Exclusiones' {
    It 'se guardan, se leen y se quitan' {
        Set-IwinExclusion 'VideoLAN.VLC' $true
        Set-IwinExclusion 'Git.Git' $true
        @(Get-IwinExclusions) | Should -Be @('VideoLAN.VLC', 'Git.Git')
        Set-IwinExclusion 'Git.Git' $false
        @(Get-IwinExclusions) | Should -Be @('VideoLAN.VLC')
        (Get-Content (Get-IwinExclusionsPath) -Raw | ConvertFrom-Json).format | Should -Be 'iWinInstaller-exclusiones'
    }

    It 'rechaza ids con caracteres extraños' {
        { Set-IwinExclusion 'a b;rm' $true } | Should -Throw
    }

    It 'un archivo dañado no impide seguir' {
        Set-Content (Get-IwinExclusionsPath) '{roto' -Encoding UTF8
        @(Get-IwinExclusions).Count | Should -Be 0
        Set-IwinExclusion 'A.B' $true
        @(Get-IwinExclusions) | Should -Be @('A.B')
    }
}

Describe 'Lista y aplicación' {
    BeforeEach { Remove-Item (Get-IwinExclusionsPath) -ErrorAction SilentlyContinue }

    It 'marca las excluidas y las del catálogo con asistente' {
        function Get-IwinAvailableUpdates { ,@([pscustomobject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '1'; Available = '2'; Source = 'winget' }, [pscustomobject]@{ Name = 'W'; Id = 'Vendor.Wizard'; Version = '1'; Available = '2'; Source = 'winget' }) }
        Set-IwinExclusion 'Git.Git' $true
        $list = Get-IwinUpdateList
        ($list | Where-Object id -eq 'Git.Git').excluded | Should -BeTrue
        ($list | Where-Object id -eq 'Vendor.Wizard').interactive | Should -BeTrue
        ($list | Where-Object id -eq 'Git.Git').catalogId | Should -Be 'git'
    }

    It 'todo al día es una lista vacía, no $null' {
        function Get-IwinAvailableUpdates { ,@() }
        $list = Get-IwinUpdateList
        $null -eq $list | Should -BeFalse
        @($list).Count | Should -Be 0
    }

    It 'no actualiza las excluidas ni, en modo programado, las que necesitan asistente' {
        function Invoke-Winget($arguments, $label) { $script:wingetCalls += $label; 0 }
        function Invoke-Install($apps, $report) { $script:installed += @($apps | ForEach-Object id); @() }
        $script:wingetCalls = @(); $script:installed = @()
        Set-IwinExclusion 'Excluded.App' $true
        $results = Invoke-IwinUpgradeIds @('Excluded.App', 'Vendor.Wizard', 'Git.Git', 'Other.App') -Scheduled
        $results['Excluded.App'] | Should -Be 'skipped'
        $results['Vendor.Wizard'] | Should -Be 'skipped'
        $results['Git.Git'] | Should -Be 'success'
        $results['Other.App'] | Should -Be 'success'
        $script:installed | Should -Be @('git')
        $script:wingetCalls | Should -Be @('Other.App')
    }
}
