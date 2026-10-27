# Regresiones aisladas: no instala aplicaciones ni modifica hardware o ajustes de Windows.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lifecycle.ps1')
$root = Split-Path $PSScriptRoot
$errors = $null
$source = Get-Content (Join-Path $root 'iWinInstaller.ps1') -Raw -Encoding UTF8
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$functions = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false))
$duplicates = @($functions | Group-Object Name | Where-Object Count -gt 1)
if ($duplicates) { throw "Funciones que se sustituyen: $($duplicates.Name -join ', ')" }
foreach ($name in 'Get-AllInstalledEntries', 'Get-UninstallEntries', 'Get-RgbTokens', 'Get-RgbOffArguments', 'Get-RgbResizeArguments', 'Get-RgbBootScript', 'Test-RgbOff') {
    $node = $functions | Where-Object Name -eq $name
    if (-not $node) { throw "Falta $name" }
    . ([scriptblock]::Create($node.Extent.Text))
}
& {
    function Get-ItemProperty { @([pscustomobject]@{DisplayName='OpenRGB'}, [pscustomobject]@{DisplayName='PawnIO'}) }
    $RegistryApps = @([pscustomobject]@{DisplayName='Ejemplo'; UninstallString='quitar.exe'})
    if (@(Get-AllInstalledEntries).Count -ne 2) { throw 'El inventario RGB debe incluir todos los programas' }
    if (@(Get-UninstallEntries ([pscustomobject]@{name='Ejemplo'})).Count -ne 1) { throw 'Desinstalar debe filtrar por la app solicitada' }
    if (@(Get-UninstallEntries ([pscustomobject]@{name='Otra'})).Count) { throw 'No debe seleccionar desinstaladores ajenos' }
}
$detailed = @('0: Placa', "  Modes: [Direct] Static 'Color Cycle'", "  Zones: 'JRAINBOW 1' 'Onboard LEDs'", '1: RAM', "  Modes: 'Spectrum Cycle' Off", '2: Ratón', '  Modes: Breathing')
if (((Get-RgbOffArguments $detailed) -join ' ') -ne '-d 0 -m Direct -c 000000 -b 0 -d 1 -m Off -d 2 -c 000000 -b 0') { throw 'El apagado RGB debe elegir Off, Direct o Static por dispositivo' }
$resize = @(Get-RgbResizeArguments $detailed)
if ($resize.Count -ne 1 -or ($resize[0] -join ' ') -ne '-d 0 -z 0 -sz 60') { throw 'Solo las zonas direccionables deben recibir tamaño' }
$version = [regex]::Match($source, '(?m)^\$Version = ''v(\d+\.\d+)''').Groups[1].Value
$native = Get-Content (Join-Path $root 'native/Launcher.cs') -Raw -Encoding UTF8
$install = Get-Content (Join-Path $root 'install.ps1') -Raw
if (-not $version -or -not $native.Contains('AssemblyFileVersion("' + $version + '.0.0")') -or -not $native.Contains('iWinInstaller v' + $version) -or -not $install.Contains("`$tag = 'v$version'")) { throw 'Las versiones del EXE, instalador y app deben coincidir' }
$fixture = Join-Path $env:TEMP ('iwin rgb test ' + [guid]::NewGuid().ToString('N'))
New-Item $fixture -ItemType Directory | Out-Null
$previousMode = $env:IWIN_RGB_FIXTURE_MODE
try {
    $fake = Join-Path $fixture 'OpenRGB.exe'
    $cs = Join-Path $fixture 'Fixture.cs'
    @'
using System;
class Fixture {
    static int Main(string[] args) {
        string mode = Environment.GetEnvironmentVariable("IWIN_RGB_FIXTURE_MODE");
        if (mode == "hang") { System.Threading.Thread.Sleep(10000); return 0; }
        if (mode == "flood") { Console.Write(new string('a', 131072)); Console.Error.Write(new string('b', 131072)); return 0; }
        if (Array.IndexOf(args, "--list-devices") >= 0 || Array.IndexOf(args, "--list-detailed") >= 0) {
            Console.WriteLine("0: Dispositivo simulado"); Console.WriteLine("  Modes: Off Static"); Console.WriteLine("  Zones: 'JRAINBOW 1'"); return mode == "listfail" ? 9 : 0;
        }
        if (mode == "fail") { Console.Error.WriteLine("Error: apagado fallido"); return 7; }
        return 0;
    }
}
'@ | Set-Content $cs -Encoding UTF8
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    if (-not (Test-Path $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
    & $compiler /nologo /target:exe "/out:$fake" $cs
    if ($LASTEXITCODE) { throw 'No se pudo compilar el proceso simulado' }
    $RgbTaskName = 'Prueba aislada'
    $scriptText = Get-RgbBootScript $fake
    $scriptPath = Join-Path $fixture 'apagar-rgb.ps1'
    $scriptText | Set-Content $scriptPath -Encoding UTF8
    $generated = [Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$null, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $node = $generated.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-OpenRgb'}, $true)
    . ([scriptblock]::Create($node.Extent.Text))
    $exe = $fake; $config = $fixture
    $env:IWIN_RGB_FIXTURE_MODE = 'flood'
    $output = @(Invoke-OpenRgb @('--list-devices') -TimeoutMs 5000)
    if (($output -join '').Length -lt 262144) { throw 'Debe leer stdout y stderr completos sin bloquearse' }
    $env:IWIN_RGB_FIXTURE_MODE = 'hang'
    $timer = [Diagnostics.Stopwatch]::StartNew(); $timedOut = $false
    try { Invoke-OpenRgb @('--list-devices') -TimeoutMs 150 | Out-Null } catch { $timedOut = $_.Exception.Message -match 'tiempo de espera' }
    if (-not $timedOut -or $timer.Elapsed.TotalSeconds -gt 8) { throw 'El plazo debe interrumpir un proceso que mantiene sus tuberías abiertas' }
    foreach ($mode in 'ok', 'fail', 'listfail') {
        $env:IWIN_RGB_FIXTURE_MODE = $mode
        Write-Host "Comprobando script RGB: $mode"
        $run = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Once" -PassThru -WindowStyle Hidden
        $null = $run.Handle
        if (-not $run.WaitForExit(180000)) { $run.Kill(); throw "El script RGB no terminó: $mode" }
        $report = Get-Content (Join-Path $fixture 'apagar-rgb.log') -Raw -Encoding UTF8
        if ($mode -eq 'ok') {
            if ($run.ExitCode -ne 0 -or $report -notmatch 'Apagado aplicado: 1 dispositivos') { throw 'Debe confirmar la orden correcta' }
        } elseif ($run.ExitCode -eq 0 -or $report -match 'Apagado aplicado:' -or $report -notmatch 'ERROR:') { throw "No puede confirmar una orden fallida: $mode" }
    }
    & {
        function Test-Administrator { $false }
        $RgbDir = $fixture; $RgbScript = $scriptPath
        if (Test-RgbOff) { throw 'Un informe fallido no debe marcar RGB como aplicado' }
        Set-Content (Join-Path $fixture 'apagar-rgb.log') 'Apagado aplicado: 1 dispositivos' -Encoding UTF8
        if (-not (Test-RgbOff)) { throw 'Debe reconocer una aplicación completada' }
    }
    Write-Host 'OK: inventarios separados, versiones coherentes, tuberías simultáneas, límite real y rechazo de fallos RGB.'
} finally {
    $env:IWIN_RGB_FIXTURE_MODE = $previousMode
    Remove-Item $fixture -Recurse -Force
}
$global:LASTEXITCODE = 0
