$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$errors=$null
$tree=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'lifecycle.ps1'),[ref]$null,[ref]$errors)
if($errors){throw ($errors | Out-String)}
$names=@('Write-IwinJson','Get-BraveCleanPolicies','Get-BraveCleanPreferences','Assert-BraveClosed','Get-BraveDefaultPreferencesPath','Read-BravePreferences','Get-BravePreference','Set-BravePreference','Get-BraveCleanSnapshot','Set-BraveCleanPreferences','Set-BraveClean','Test-BraveClean','Get-TweakRegistryTargets','Get-TweakSnapshotPath','Save-TweakSnapshot','Restore-TweakSnapshot')
foreach($name in $names){
    $node=$tree.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}.GetNewClosure(),$true)
    if(-not $node){throw "Falta $name"}
    . ([scriptblock]::Create($node.Extent.Text))
}
$fixture=Join-Path $env:TEMP ('iwin-brave-'+[guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA
try{
    $env:LOCALAPPDATA=$fixture;$LogDir=Join-Path $fixture 'estado'
    $Apps=@([pscustomobject]@{id='braveclean';type='tweak';context='user'})
    function Get-InstallContext($app){'user'}
    function Write-Log($text){}
    $script:running=$false
    function Get-Process {param($Name,$ErrorAction) if($script:running){[pscustomobject]@{Name='brave'}}}
    $script:registry=@{}
    function Set-RegDword($path,$name,$value){$script:registry[$name]=$value}
    function Get-RegValue($path,$name){$script:registry[$name]}
    # Las directivas reales pueden pedir elevacion; aqui se simulan sobre el mismo registro de prueba.
    function Set-PolicyDwords($path,$values){foreach($k in $values.Keys){Set-RegDword $path $k $values[$k]}}
    function Invoke-UserPolicyElevated($operations){foreach($op in $operations){if($null -eq $op.value){$script:registry.Remove($op.name)}else{$script:registry[$op.name]=$op.value}}}
    function Remove-ItemProperty{param($Path,$Name,$ErrorAction) throw 'Acceso denegado simulado'}
    $path=Get-BraveDefaultPreferencesPath
    New-Item (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
    $original=[pscustomobject]@{browser=[pscustomobject]@{theme=[pscustomobject]@{color_scheme2=1}};preserve=[pscustomobject]@{nested=@('uno','dos')};brave=[pscustomobject]@{new_tab_page=[pscustomobject]@{show_stats=$true}}}
    Write-IwinJson $path $original
    $snapshot=Get-BraveCleanSnapshot
    $result=@(Set-BraveClean)
    if($result.Count -ne 1 -or $result[0] -isnot [bool] -or -not $result[0]){throw 'La limpieza debe devolver solo un bool verdadero'}
    if(-not(Test-BraveClean)){throw 'No verifica las preferencias y politicas aplicadas'}
    $document=Read-BravePreferences
    if(($document.preserve.nested -join ',') -ne 'uno,dos'){throw 'Se modificaron datos ajenos'}
    if((Get-BraveCleanPolicies).Contains('SyncDisabled')){throw 'No debe bloquear Sync'}
    $script:registry.Remove('BraveWalletDisabled')
    if(Test-BraveClean){throw 'No puede acreditar limpieza si falta una politica'}
    Set-BraveCleanPreferences $snapshot
    $document=Read-BravePreferences
    if($document.browser.theme.color_scheme2 -ne 1 -or -not $document.brave.new_tab_page.show_stats){throw 'No recupera preferencias anteriores'}
    if((Get-BravePreference $document 'brave.darker_mode').exists){throw 'No recupera la ausencia original'}
    $before=[IO.File]::ReadAllText($path);$script:running=$true;$blocked=$false
    try{Set-BraveCleanPreferences}catch{$blocked=$true}
    if(-not $blocked -or [IO.File]::ReadAllText($path) -cne $before){throw 'No debe tocar el perfil abierto'}
    $script:running=$false
    [IO.File]::WriteAllText($path,'{invalid');$blocked=$false
    try{Set-BraveCleanPreferences}catch{$blocked=$true}
    if(-not $blocked -or [IO.File]::ReadAllText($path) -cne '{invalid'){throw 'No debe sobrescribir JSON roto'}
    Remove-Item $path
    Set-BraveCleanPreferences
    if((Read-BravePreferences).brave.new_tab_page.background.selected_value -ne '#000000'){throw 'No inicializa el fondo negro del perfil principal'}
    # La captura conserva solo los valores visuales, nunca el documento completo.
    $snapshot=Get-BraveCleanSnapshot
    if($snapshot.PSObject.Properties.Name -contains 'preserve'){throw 'No debe copiar datos del perfil'}
    $catalog=Get-Content (Join-Path $root 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $clean=$catalog | Where-Object id -eq 'braveclean'
    if($clean.context -ne 'user' -or $clean.requires -notcontains 'brave'){throw 'Brave limpio debe depender de Brave oficial y aplicarse al usuario'}
    'Brave limpio: aplicar, verificar, restaurar, JSON invalido, perfil abierto y datos ajenos correctos.'
}finally{$env:LOCALAPPDATA=$oldLocal;Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue}
