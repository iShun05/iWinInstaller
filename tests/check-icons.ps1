param([string]$SourceFile=(Join-Path $PSScriptRoot '..\iWinInstaller.ps1'))
$ErrorActionPreference='Stop'
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourceFile,[ref]$null,[ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$source=$ast.Find({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match 'public static class IwinIcons'},$true).Value
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
$refs=@([Windows.Media.ImageSource],[Windows.Threading.Dispatcher],[System.Xaml.XamlType],[System.Net.WebClient]) | ForEach-Object { $_.Assembly.Location } | Select-Object -Unique
Add-Type -TypeDefinition $source -ReferencedAssemblies $refs
$dir=Join-Path $env:TEMP ('iwin-icons-'+[guid]::NewGuid().ToString('N'))
$dispatcher=[Windows.Threading.Dispatcher]::CurrentDispatcher
$app=New-Object IwinApp
$app.IconSpec='invalido'+[char]0
if ($env:IWIN_ICON_PROBE) { Set-Content $env:IWIN_ICON_PROBE 'ANTES_ICONOS' }
[IwinIcons]::Start([IwinApp[]]@($app),$dir,$dispatcher)
Start-Sleep -Seconds 2
$dispatcher.InvokeShutdown()
[IwinIcons]::Start([IwinApp[]]@($app),$dir,$dispatcher)
Start-Sleep -Milliseconds 500
Remove-Item $dir -Recurse -Force
if ($env:IWIN_ICON_PROBE) { Add-Content $env:IWIN_ICON_PROBE 'DESPUES_ICONOS' }
Write-Host 'OK: un icono invalido y un dispatcher cerrado no terminan el proceso.'
