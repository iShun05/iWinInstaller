# Juego competitivo (v5.2): decisiones puras del DNS, lectura de powercfg y tarea. Nunca toca la red ni el sistema real.

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    function Write-Log($msg) { }
    function Test-Administrator { $false }
    . (Join-Path $script:Root 'src\engine\15-Gaming.ps1')
    function New-Result($provider, $ms, $failed = $false) { [pscustomobject]@{ provider = $provider; ms = $ms; failed = $failed } }
}

Describe 'Elección del DNS' {
    It 'elige el más rápido' {
        (Select-GameDns @((New-Result 'Red' 40), (New-Result 'Cloudflare' 12), (New-Result 'Google' 15))).provider | Should -Be 'Cloudflare'
    }
    It 'se queda con el de la red si está a 5 ms o menos del mejor' {
        (Select-GameDns @((New-Result 'Red' 17), (New-Result 'Cloudflare' 12))).provider | Should -Be 'Red'
    }
    It 'usa el 15 % como margen cuando es mayor que 5 ms' {
        (Select-GameDns @((New-Result 'Red' 113), (New-Result 'Quad9' 100))).provider | Should -Be 'Red'
        (Select-GameDns @((New-Result 'Red' 116), (New-Result 'Quad9' 100))).provider | Should -Be 'Quad9'
    }
    It 'descarta los que fallan' {
        (Select-GameDns @((New-Result 'Red' $null $true), (New-Result 'Google' 30))).provider | Should -Be 'Google'
    }
    It 'sin candidatos no cambia nada' {
        Select-GameDns @((New-Result 'Red' $null $true), (New-Result 'Google' $null $true)) | Should -BeNullOrEmpty
    }
}

Describe 'DNS puesto por iWinInstaller' {
    It 'reconoce las listas de los proveedores, también con IPv6' {
        Get-GameDnsOwner @('1.1.1.1', '1.0.0.1') | Should -Be 'Cloudflare'
        Get-GameDnsOwner @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888') | Should -Be 'Google'
    }
    It 'no toma como suyo un DNS manual del usuario' {
        Get-GameDnsOwner @('192.168.1.2') | Should -BeNullOrEmpty
        Get-GameDnsOwner @('1.1.1.1', '192.168.1.2') | Should -BeNullOrEmpty
        Get-GameDnsOwner @() | Should -BeNullOrEmpty
    }
}

Describe 'Tarea del DNS' {
    It 'es XML válido con disparador de red conectada y permitida con batería' {
        $xml = [xml](Get-GameDnsTaskXml 'C:\ProgramData\iWinInstaller\Latencia\dns-rapido.ps1')
        $xml.Task.Triggers.EventTrigger.Subscription | Should -Match 'EventID=10000'
        $xml.Task.Settings.DisallowStartIfOnBatteries | Should -Be 'false'
        $xml.Task.Settings.MultipleInstancesPolicy | Should -Be 'Queue'
        $xml.Task.Principals.Principal.UserId | Should -Be 'S-1-5-18'
        $xml.Task.Actions.Exec.Arguments | Should -Match 'dns-rapido\.ps1'
    }
}

Describe 'Lectura de powercfg' {
    It 'lee los valores en inglés' {
        $text = "    Current AC Power Setting Index: 0x00000000`r`n    Current DC Power Setting Index: 0x00000003"
        Get-PowercfgIndex $text 'ac' | Should -Be 0
        Get-PowercfgIndex $text 'dc' | Should -Be 3
    }
    It 'lee los valores en español' {
        $text = "    Índice de configuración de corriente alterna actual: 0x00000002`n    Índice de configuración de corriente continua actual: 0x00000003"
        Get-PowercfgIndex $text 'ac' | Should -Be 2
        Get-PowercfgIndex $text 'dc' | Should -Be 3
    }
    It 'en otros idiomas usa las dos últimas líneas con valor (AC y DC)' {
        $text = "    Mögliche Einstellung: 0x00000005`n    Aktueller Wechselstrom-Energieeinstellungsindex: 0x00000001`n    Aktueller Gleichstrom-Energieeinstellungsindex: 0x00000003"
        Get-PowercfgIndex $text 'ac' | Should -Be 1
        Get-PowercfgIndex $text 'dc' | Should -Be 3
    }
    It 'devuelve nulo si no hay ajuste' {
        Get-PowercfgIndex 'No existe la configuración.' 'ac' | Should -BeNullOrEmpty
    }
}
