# Regresiones de lotes y postinstalación. Solo las claves de prueba se escriben en el registro.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../lifecycle.ps1')
$root=Split-Path $PSScriptRoot
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'iWinInstaller.ps1'),[ref]$null,[ref]$errors)
if($errors){throw ($errors | Out-String)}
foreach($name in 'Invoke-Install','Resume-IwinBatch','Test-StillInstalled'){
    $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($node.Extent.Text))
}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Write-Log($message){}
function Invoke-UiPump{}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('iwin-lifecycle-'+[guid]::NewGuid().ToString('N'))
New-Item $fixture -ItemType Directory | Out-Null
try{
    $LogDir=$fixture;$WorkerMode='';$UpgradePackages=$false;$UI=$false;$LogFile=$null
    function Get-IwinBootId{'boot-de-prueba'}
    $Apps=@(
        [pscustomobject]@{id='primera';name='Primera';type='winget';requires=@('base')},
        [pscustomobject]@{id='base';name='Base';type='winget'},
        [pscustomobject]@{id='ultima';name='Última';type='winget'}
    )
    $plan=@(Get-InstallPlan @($Apps[0],$Apps[2],$Apps[1]))
    Assert (($plan.id -join ',') -eq 'base,primera,ultima') 'Dependencias en orden, sin duplicados'
    $Apps[1] | Add-Member requires @('primera')
    $rejected=$false;try{Get-InstallPlan @($Apps[0]) | Out-Null}catch{$rejected=$true}
    Assert $rejected 'Debe rechazar ciclos'
    $Apps[1].requires=@()
    function Ensure-Winget{$true}
    function Update-WingetCache{}
    function Update-LocalInventory{}
    function Get-InstallContext{'user'}
    function Test-Administrator{$false}
    function Test-AppInstalled{$false}
    function Organize-Desktop{}
    $script:calls=@();$script:pause=$true
    function Install-App($app){$script:calls+=$app.id;if($script:pause){Request-IwinStop};$true}
    $fail=@(Invoke-Install @($Apps[0],$Apps[2]) $null)
    Assert ($fail.Count -eq 2 -and ($script:calls -join ',') -eq 'base') 'Pausa segura entre aplicaciones'
    $pending=Get-IwinPendingBatches | Select-Object -First 1
    Assert ($pending -and @($pending.Data.items | Where-Object state -eq 'done').Count -eq 1) 'Debe conservar el resultado completado en disco'
    $script:pause=$false
    $fail=@(Resume-IwinBatch $pending $null)
    Assert ($fail.Count -eq 0 -and ($script:calls -join ',') -eq 'base,primera,ultima') 'Reanuda solo pendientes, sin repetir dependencias completadas'
    Assert (@(Get-IwinPendingBatches).Count -eq 0) 'El lote completo no debe ofrecer reanudar'
    Set-IwinBatchResult $Apps[0] $true 3010
    Assert (@(Get-IwinRebootPending) -contains 'primera') 'Código de reinicio persistido'
    function Get-IwinBootId{'otro-arranque'}
    Assert (@(Get-IwinRebootPending).Count -eq 0) 'Un arranque nuevo limpia el aviso de ese lote'
    function Test-LocalApp{$false}
    function Invoke-Winget{ -7 }
    $script:WingetIds=@()
    $unknown=$false;try{[void](Test-StillInstalled ([pscustomobject]@{id='base';type='winget';winget='Ejemplo.Base'}))}catch{$unknown=$true}
    Assert $unknown 'Un error de consulta no confirma que se desinstaló'
    function Invoke-Winget{ -1978335212 }
    Assert (-not (Test-StillInstalled ([pscustomobject]@{id='base';type='winget';winget='Ejemplo.Base'}))) 'Solo el código de ausencia confirma retirada'
    $script:PostInstallState=@{base=@{steps=@(0);note='Texto literal $(no ejecutar) con acentos y salto' + "`n" + 'Segunda línea'}}
    Save-PostInstallState
    $read=Get-PostInstallState
    Assert ($read.base.note -eq $script:PostInstallState.base.note -and @($read.base.steps).Count -eq 1) 'Notas y pasos persistidos sin evaluación'
    function Test-AppInstalled{$true}
    $guide=[pscustomobject]@{id='base';postInstall=[pscustomobject]@{steps=@('Inicia sesión','Prueba el uso')}}
    $before=@($script:PostInstallState.base.steps).Count
    $technical=Test-PostInstall $guide
    Assert ($technical.Ok -and @($script:PostInstallState.base.steps).Count -eq $before) 'Una comprobación técnica no marca pasos manuales'
    Set-Content (Join-Path $LogDir 'postinstalacion.json') 'archivo roto' -Encoding UTF8
    $rejected=$false;try{[void](Get-PostInstallState)}catch{$rejected=$true}
    Assert $rejected 'No se pierde silenciosamente un seguimiento dañado'
    Write-Host 'OK: dependencias, pausa, reanudación, reinicios, ausencia frente a error y notas manuales.'
    if($env:OS -eq 'Windows_NT'){
        & {
            $testKey='HKCU:\Software\iWinInstaller-prueba-'+[guid]::NewGuid().ToString('N')
            function Get-TweakRegistryTargets{ ,@($testKey,'existente'); ,@($testKey,'ausente') }
            function Get-TweakSnapshotPath{Join-Path $fixture 'restaurar.json'}
            try{
                New-Item $testKey -Force | Out-Null
                Set-ItemProperty $testKey -Name existente -Value 'valor propio' -Type ExpandString
                Save-TweakSnapshot 'prueba'
                Set-ItemProperty $testKey -Name existente -Value 'modificado' -Type String
                Set-ItemProperty $testKey -Name ausente -Value 123 -Type DWord
                Save-TweakSnapshot 'prueba'
                Assert (Restore-TweakSnapshot 'prueba') 'Debe restaurar el estado anterior'
                $key=Get-Item $testKey
                Assert ($key.GetValue('existente') -eq 'valor propio' -and $key.GetValueKind('existente') -eq 'ExpandString' -and $key.GetValueNames() -notcontains 'ausente') 'Conservar tipo, valor propio y ausencia original'
                $missing=$false;try{Restore-TweakSnapshot 'prueba' | Out-Null}catch{$missing=$true}
                Assert $missing 'No debe imponer valores por defecto a cambios antiguos'
            }finally{Remove-Item $testKey -Recurse -Force -ErrorAction SilentlyContinue}
        }
        Write-Host 'OK: restauración real de valores y tipos del registro en una clave aislada.'
    }
    if($env:GITHUB_ACTIONS -eq 'true'){
        # Servicio efímero en runner: no se arranca ni se usa un servicio que ya exista.
        if(Get-Service SunshineService -ErrorAction SilentlyContinue){throw 'La prueba necesita un runner sin Sunshine'}
        Initialize-IwinServices
        try{
            & sc.exe create SunshineService binPath= "$env:SystemRoot\System32\svchost.exe -k iwinfixture" start= demand | Out-Null
            if($LASTEXITCODE){throw 'No se pudo crear el servicio de prueba'}
            & sc.exe failure SunshineService reset= 1000 actions= restart/111/restart/222 | Out-Null
            $original=[IwinServiceRecovery]::Read('SunshineService')
            & sc.exe failure SunshineService reset= 2000 actions= restart/333 | Out-Null
            [IwinServiceRecovery]::Restore('SunshineService',$original.Reset,$original.Reboot,$original.Command,$original.Types,$original.Delays)
            $restored=[IwinServiceRecovery]::Read('SunshineService')
            Assert ($original.Reset -eq $restored.Reset -and ($original.Delays -join ',') -eq ($restored.Delays -join ',') -and ($original.Types -join ',') -eq ($restored.Types -join ',')) 'Recuperación exacta del servicio'
            Write-Host 'OK: lectura y restauración reales de acciones de recuperación del servicio.'
        }finally{& sc.exe delete SunshineService | Out-Null}
    }
}finally{Remove-Item $fixture -Recurse -Force}
$global:LASTEXITCODE=0
