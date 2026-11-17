# iWinInstaller — DNS más rápido (v5.2). Lo ejecuta la tarea «\iWinInstaller\DNS más rápido» como SYSTEM
# al arrancar, al iniciar sesión y al conectar a una red. Mide el DNS de la red y tres públicos y deja el más rápido.
# Solo toca adaptadores con DNS automático o con un DNS que puso este script: nunca un DNS manual del usuario,
# un equipo de dominio ni una VPN. Sin internet devuelve el adaptador a automático (portales cautivos).
# -Library solo define las funciones (pruebas y motor); la tarea lo ejecuta sin parámetros.
param([switch]$Library)

$GameDnsProviders = @(
    [pscustomobject]@{ provider = 'Cloudflare'; servers4 = @('1.1.1.1', '1.0.0.1'); servers6 = @('2606:4700:4700::1111', '2606:4700:4700::1001') }
    [pscustomobject]@{ provider = 'Google'; servers4 = @('8.8.8.8', '8.8.4.4'); servers6 = @('2001:4860:4860::8888', '2001:4860:4860::8844') }
    [pscustomobject]@{ provider = 'Quad9'; servers4 = @('9.9.9.9', '149.112.112.112'); servers6 = @('2620:fe::fe', '2620:fe::9') }
)
$GameDnsNames = @('www.google.com', 'steamcommunity.com', 'www.riotgames.com')
$GameDnsVirtual = 'Hyper-V|VMware|VirtualBox|TAP|WireGuard|Tailscale|Wintun|VPN|Virtual'

# Elige el DNS: el más rápido, salvo que el de la red esté a max(5 ms, 15 %) del mejor (menos cambios y CDN más cercano).
# Results: @{ provider; ms; failed }. Devuelve el resultado elegido o $null si no hay ninguno utilizable.
function Select-GameDns([object[]]$Results, [string]$Network = 'Red') {
    $usable = @($Results | Where-Object { $_ -and -not $_.failed -and $null -ne $_.ms } | Sort-Object { [double]$_.ms })
    if (-not $usable) { return $null }
    $best = $usable[0]
    $own = $usable | Where-Object { $_.provider -eq $Network } | Select-Object -First 1
    if ($own -and [double]$own.ms -le [double]$best.ms + [math]::Max(5, [double]$best.ms * 0.15)) { return $own }
    return $best
}

# Lista de servidores de un proveedor conocido que coincide exactamente con la del adaptador, o $null
function Get-GameDnsOwner([string[]]$Servers) {
    $current = @($Servers | Where-Object { $_ } | ForEach-Object { $_.Trim().ToLowerInvariant() })
    if (-not $current) { return $null }
    foreach ($p in $GameDnsProviders) {
        $all = @($p.servers4 + $p.servers6 | ForEach-Object { $_.ToLowerInvariant() })
        if (-not @($current | Where-Object { $all -notcontains $_ }).Count -and @($p.servers4 | Where-Object { $current -contains $_ }).Count) { return $p.provider }
    }
    return $null
}

function Split-GameDnsList([string]$text) {
    @(($text -split '[,\s]+') | Where-Object { $_ } | Where-Object { $ip = $null; [Net.IPAddress]::TryParse($_, [ref]$ip) })
}

function Get-GameDnsAdapters {
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        if ($adapter.InterfaceDescription -match $GameDnsVirtual -or $adapter.Name -match $GameDnsVirtual) { continue }
        if (-not (Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) { continue }
        $guid = $adapter.InterfaceGuid
        $v4 = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid" -ErrorAction SilentlyContinue
        $v6 = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$guid" -ErrorAction SilentlyContinue
        $static = @(Split-GameDnsList ([string]$v4.NameServer)) + @(Split-GameDnsList ([string]$v6.NameServer))
        $owner = Get-GameDnsOwner $static
        # DNS manual del usuario (Pi-hole, NextDNS, empresa…): no se toca
        if ($static.Count -and -not $owner) { continue }
        [pscustomobject]@{
            index = $adapter.ifIndex; guid = $guid
            type = $(if ($adapter.PhysicalMediaType -match '802\.11|Wireless' -or $adapter.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11') { 'wifi' } else { 'ethernet' })
            ours = [bool]$owner
            network = @(Split-GameDnsList ([string]$v4.DhcpNameServer))
        }
    }
}

# Mediana de los tiempos de un servidor; $null si falla más de 2 veces
function Measure-GameDnsServer([string]$Server, [int]$Rounds = 5) {
    $times = @(); $fails = 0
    for ($round = 0; $round -lt $Rounds; $round++) {
        foreach ($name in $GameDnsNames) {
            $watch = [Diagnostics.Stopwatch]::StartNew()
            try { Resolve-DnsName $name -Type A -Server $Server -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop | Out-Null; $watch.Stop(); if ($round -gt 0) { $times += $watch.Elapsed.TotalMilliseconds } }
            catch { $fails++ }
        }
    }
    if ($fails -gt 2 -or -not $times) { return $null }
    $sorted = @($times | Sort-Object)
    [math]::Round($sorted[[int][math]::Floor($sorted.Count / 2)], 1)
}

function Invoke-GameDnsMeasure($Adapter) {
    $candidates = @()
    if ($Adapter.network) { $candidates += [pscustomobject]@{ provider = 'Red'; servers4 = $Adapter.network; servers6 = @() } }
    $candidates += $GameDnsProviders
    foreach ($c in $candidates) {
        $ms = Measure-GameDnsServer $c.servers4[0]
        [pscustomobject]@{ provider = $c.provider; ms = $ms; failed = ($null -eq $ms) }
    }
}

function Write-GameDnsJson([string]$Path, $Data) {
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $Data -Depth 5), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Invoke-GameDnsRun([string]$Folder) {
    if ((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain) { return }
    $appliedPath = Join-Path $Folder 'aplicado.json'
    $applied = @()
    try { $applied = @((Get-Content $appliedPath -Raw -Encoding UTF8 | ConvertFrom-Json).adapters | Where-Object { $_ -match '^\{[0-9A-Fa-f-]{36}\}$' }) } catch { }
    $summary = $null
    foreach ($adapter in @(Get-GameDnsAdapters)) {
        # Espera a que la red tenga internet; sin ella, el adaptador vuelve a automático (portal cautivo)
        $online = $false
        for ($wait = 0; $wait -lt 20; $wait++) {
            $connection = Get-NetConnectionProfile -InterfaceIndex $adapter.index -ErrorAction SilentlyContinue
            if ($connection -and [string]$connection.IPv4Connectivity -eq 'Internet') { $online = $true; break }
            Start-Sleep -Seconds 1
        }
        if (-not $online) {
            if ($adapter.ours) { Set-DnsClientServerAddress -InterfaceIndex $adapter.index -ResetServerAddresses -ErrorAction SilentlyContinue }
            continue
        }
        $results = @(Invoke-GameDnsMeasure $adapter)
        $chosen = Select-GameDns $results 'Red'
        if (-not $chosen) { continue }
        if ($chosen.provider -eq 'Red') {
            if ($adapter.ours) { Set-DnsClientServerAddress -InterfaceIndex $adapter.index -ResetServerAddresses -ErrorAction Stop }
        } else {
            $p = $GameDnsProviders | Where-Object provider -eq $chosen.provider
            $list = @($p.servers4)
            if ([string]$connection.IPv6Connectivity -eq 'Internet') { $list += $p.servers6 }
            Set-DnsClientServerAddress -InterfaceIndex $adapter.index -ServerAddresses $list -ErrorAction Stop
            if ($applied -notcontains $adapter.guid) { $applied += $adapter.guid }
        }
        $summary = [ordered]@{ format = 'iWinInstaller-dns-resultado'; version = 1; at = (Get-Date).ToUniversalTime().ToString('o'); adapterType = $adapter.type; chosen = $chosen.provider; results = @($results) }
    }
    Write-GameDnsJson $appliedPath ([ordered]@{ format = 'iWinInstaller-dns'; version = 1; adapters = @($applied) })
    if ($summary) { Write-GameDnsJson (Join-Path $Folder 'dns.json') $summary }
}

if ($Library) { return }

$ErrorActionPreference = 'Continue'
$mutex = New-Object Threading.Mutex($false, 'Global\iWinInstaller-dns')
$locked = $false
try {
    try { $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(90)) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if ($locked) { Invoke-GameDnsRun $PSScriptRoot }
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
