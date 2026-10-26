# Estado local del instalador. Los JSON son datos: nunca se evalúan como órdenes.
function Write-IwinJson($path, $value) {
    $parent = Split-Path $path -Parent
    New-Item $parent -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $temporary = Join-Path $parent ([guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, ($value | ConvertTo-Json -Depth 18), (New-Object Text.UTF8Encoding $false))
        if (Test-Path $path) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $path) }
    } finally { Remove-Item $temporary -Force -ErrorAction SilentlyContinue }
}
function Get-InstallPlan($selection) {
    $ordered = New-Object Collections.ArrayList
    $visited = @{}; $visiting = @{}
    $visit = {
        param($app)
        if ($visited[$app.id]) { return }
        if ($visiting[$app.id]) { throw "Dependencias circulares en $($app.name)." }
        $visiting[$app.id] = $true
        $requires = @($app.requires)
        if ($app.type -eq 'vboxga') { $requires += 'virtualbox' }
        foreach ($id in $requires) {
            if (-not $id) { continue }
            $dependency = $Apps | Where-Object id -eq $id | Select-Object -First 1
            if (-not $dependency) { throw "Falta la dependencia $id." }
            & $visit $dependency
        }
        $visiting.Remove($app.id); $visited[$app.id] = $true
        [void]$ordered.Add($app)
    }
    foreach ($app in $selection) { & $visit $app }
    @($ordered | ForEach-Object { $_ })
}
function Get-IwinBootId {
    try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o') }
    catch { 'desconocido' }
}
function Test-IwinRebootCode($code) { $code -in @(3010, 1641, -1978334967, -1978334966, -1978334965) }
function Save-IwinBatch {
    if ($script:Batch -and $script:BatchPath) { Write-IwinJson $script:BatchPath $script:Batch }
}
function Start-IwinBatch($selection, $operation = 'install') {
    $script:StopRequested = $false
    if ($WorkerMode -or -not $LogDir) { return }
    $script:Batch = [pscustomobject]@{
        format = 'iWinInstaller-lote'; version = 1; id = [guid]::NewGuid().ToString('N')
        created = (Get-Date).ToUniversalTime().ToString('o'); operation = $operation
        items = @($selection | ForEach-Object { [pscustomobject]@{ id=$_.id; state='pending'; reboot=$false; boot=''; code=0 } })
    }
    $script:BatchPath = Join-Path (Join-Path $LogDir 'lotes') ($script:Batch.id + '.json')
    Save-IwinBatch
}
function Set-IwinBatchResult($app, [bool]$ok, $code = 0) {
    if ($WorkerMode -or -not $script:Batch) { return }
    foreach ($entry in @($script:Batch.items | Where-Object id -eq $app.id)) {
        $entry.state = if ($ok) { 'done' } elseif (Test-IwinStop) { 'pending' } else { 'failed' }
        $entry.code = [long]$code
        $entry.reboot = (Test-IwinRebootCode $code) -or ($ok -and [bool]$app.restart)
        if ($entry.reboot) { $entry.boot = Get-IwinBootId }
    }
    Save-IwinBatch
}
function Set-IwinBatchRunning($app) {
    if (-not $WorkerMode -and $script:Batch) {
        foreach ($entry in @($script:Batch.items | Where-Object id -eq $app.id)) { $entry.state='running' }
        Save-IwinBatch
    }
}
function Get-IwinPendingBatches {
    if (-not $LogDir) { return }
    $known = @($Apps | ForEach-Object id)
    foreach ($file in @(Get-ChildItem (Join-Path $LogDir 'lotes') -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            if ($file.Length -gt 2MB) { continue }
            $data = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if ($data.format -ne 'iWinInstaller-lote' -or $data.version -ne 1 -or $data.operation -notin @('install','upgrade','uninstall')) { continue }
            if (@($data.items | Where-Object { $_.id -notin $known -or $_.state -notin @('pending','running','failed','done') }).Count) { continue }
            if (@($data.items | Where-Object state -ne 'done').Count) { [pscustomobject]@{ Path=$file.FullName; Data=$data } }
        } catch { Write-Log "  Lote ilegible ignorado: $($file.Name)." }
    }
}
function Get-IwinRebootPending {
    if (-not $LogDir) { return @() }
    $boot = Get-IwinBootId
    $ids = @()
    foreach ($file in @(Get-ChildItem (Join-Path $LogDir 'lotes') -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            if ($file.Length -gt 2MB) { continue }
            $data = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if ($data.format -eq 'iWinInstaller-lote') { $ids += @($data.items | Where-Object { $_.reboot -and ($_.boot -eq $boot -or $boot -eq 'desconocido') } | ForEach-Object id) }
        } catch { }
    }
    @($ids | Select-Object -Unique)
}
function Test-IwinStop {
    [bool]($script:StopRequested -or ($WorkerMode -and $PlanFile -and (Test-Path ($PlanFile + '.cancel'))))
}
function Request-IwinStop {
    $script:StopRequested = $true
    if ($script:ActiveCancelFile) { [IO.File]::WriteAllText($script:ActiveCancelFile, 'stop') }
    Write-Log 'Pausa solicitada: termina la aplicación actual y conserva el resto para reanudar.'
}
function Get-IwinPreflight($selection) {
    $messages = @(); $blocked = $false
    foreach ($rootPath in @($env:TEMP, $env:LOCALAPPDATA, $env:ProgramFiles) | Where-Object { $_ } | Select-Object -Unique) {
        try {
            $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($rootPath))
            $messages += "$($drive.Name): $([math]::Round($drive.AvailableFreeSpace / 1GB, 1)) GB libres"
            if ($drive.AvailableFreeSpace -lt 1GB) { $blocked=$true }
        } catch { $messages += 'No se pudo comprobar el espacio disponible.'; $blocked=$true }
    }
    if (@($selection | Where-Object type -ne 'tweak').Count) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $request = [Net.WebRequest]::Create('https://cdn.winget.microsoft.com/cache/source2.msix')
            $request.Method='HEAD'; $request.Timeout=6000
            $response=$request.GetResponse(); $response.Close()
            $messages += 'Conexión HTTPS con el origen de WinGet disponible.'
        } catch { $messages += 'No se pudo acceder al origen de WinGet. Comprueba conexión, proxy o firewall y reintenta.'; $blocked=$true }
    }
    $messages += 'Se exige 1 GB libre para preparar el lote; cada programa puede necesitar más.'
    [pscustomobject]@{ Ok=(-not $blocked); Text=($messages -join "`n") }
}
# Comprobaciones cortas de solo lectura, sin consola, salida al log ni credenciales guardadas.
function Invoke-IwinProbe([string]$exe, [string]$arguments, [int]$timeoutMs = 8000) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments=$arguments; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $stdout=$p.StandardOutput.ReadToEndAsync(); $stderr=$p.StandardError.ReadToEndAsync()
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while (-not $p.HasExited -and $timer.ElapsedMilliseconds -lt $timeoutMs) { Invoke-UiPump; Start-Sleep -Milliseconds 50 }
        if (-not $p.HasExited) { $p.Kill(); throw 'La comprobación superó el tiempo disponible. Puedes reintentarlo.' }
        $p.WaitForExit()
        [pscustomobject]@{ Code=$p.ExitCode; Output=$stdout.Result }
    } finally { $p.Dispose() }
}
function Get-PostInstallGuide($app) {
    if ($app.postInstall -and @($app.postInstall.steps).Count) { return $app.postInstall }
    [pscustomobject]@{ steps=@('Abre la aplicación y revisa sus preferencias.', 'Prueba la función que necesitas antes de marcarla como lista.'); note='La detección técnica no comprueba cuentas, licencias ni datos personales.' }
}
function Get-IwinGuideHash($app) {
    $guide=Get-PostInstallGuide $app
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((@($guide.steps) | ConvertTo-Json -Compress))))).Replace('-','')}finally{$sha.Dispose()}
}
function Get-PostInstallState {
    $path=Join-Path $LogDir 'postinstalacion.json'
    $state=@{}
    if (Test-Path $path) {
        try {
            $file=Get-Item $path
            if ($file.Length -gt 4MB) { throw 'Seguimiento demasiado grande.' }
            $saved=Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($entry in $saved.PSObject.Properties) {
                if ($entry.Name -notin @($Apps.id)) { continue }
                $app=$Apps | Where-Object id -eq $entry.Name | Select-Object -First 1
                $hash=Get-IwinGuideHash $app
                $steps=if($entry.Value.guideHash -eq $hash){@($entry.Value.steps | Where-Object { ($_ -is [int] -or $_ -is [long]) -and $_ -ge 0 -and $_ -lt 100 })}else{@()}
                $state[$entry.Name]=@{ steps=@($steps); guideHash=$hash; note=([string]$entry.Value.note).Substring(0,[math]::Min(2000,([string]$entry.Value.note).Length)) }
            }
        } catch { Write-Log 'No se pudo leer el seguimiento de postinstalación; no se sobrescribe automáticamente.'; throw }
    }
    $state
}
function Save-PostInstallState {
    if($script:PostInstallReadOnly){throw 'Seguimiento ilegible: se conserva el original para evitar perder tus notas.'}
    foreach($id in @($script:PostInstallState.Keys)){
        if(-not $script:PostInstallState[$id].guideHash){
            $app=$Apps | Where-Object id -eq $id | Select-Object -First 1
            if($app){$script:PostInstallState[$id].guideHash=Get-IwinGuideHash $app}
        }
    }
    Write-IwinJson (Join-Path $LogDir 'postinstalacion.json') $script:PostInstallState
}
function Test-PostInstall($app) {
    try {
        if (-not (Test-AppInstalled $app)) { return [pscustomobject]@{ Ok=$false; Text='No se detecta instalada o aplicada. Instala y vuelve a comprobar.' } }
        switch ($app.id) {
            'tailscale' {
                $probe=Invoke-IwinProbe (Get-TailscaleExe) 'status --json'
                $status=$probe.Output | ConvertFrom-Json -ErrorAction Stop
                if ($probe.Code -ne 0 -or $status.BackendState -ne 'Running') { throw 'Tailscale no está conectado. Abre la app e inicia sesión.' }
            }
            'sunshine' { if ((Get-Service SunshineService -ErrorAction Stop).Status -ne 'Running') { throw 'El servicio de Sunshine no está en ejecución.' } }
            'remotehost' {
                foreach ($name in 'SunshineService','Tailscale') { if ((Get-Service $name -ErrorAction Stop).Status -ne 'Running') { throw "El servicio $name no está en ejecución." } }
                $probe=Invoke-IwinProbe (Get-TailscaleExe) 'status --json'
                if ($probe.Code -ne 0 -or ($probe.Output | ConvertFrom-Json).BackendState -ne 'Running') { throw 'Tailscale no está conectado.' }
            }
            'gh' { if ((Invoke-IwinProbe (Get-Command gh -ErrorAction Stop).Source 'auth status').Code -ne 0) { throw 'Falta iniciar sesión en GitHub CLI: abre su terminal y ejecuta gh auth login.' } }
            'wsl' { if ((Invoke-IwinProbe (Get-Command wsl.exe -ErrorAction Stop).Source '--status').Code -ne 0) { throw 'WSL aún necesita preparación o reinicio.' } }
        }
        $reboot=@(Get-IwinRebootPending)
        if ($reboot -contains $app.id) { return [pscustomobject]@{Ok=$false;Text='Detectada. Reinicia Windows y vuelve a comprobar; la app no reinicia por su cuenta.'} }
        [pscustomobject]@{ Ok=$true; Text='Comprobación técnica correcta. Confirma abajo las pruebas de uso que requieren tu intervención.' }
    } catch { [pscustomobject]@{ Ok=$false; Text=('No se pudo confirmar: ' + $_.Exception.Message) } }
}
# Restauración: rutas y nombres permitidos proceden del código, nunca del archivo guardado.
function Get-TweakRegistryTargets($id) {
    switch ($id) {
        'showext' { ,@($ExplorerAdv,'HideFileExt') }
        'showhidden' { ,@($ExplorerAdv,'Hidden') }
        'darkmode' { ,@($Personalize,'AppsUseLightTheme'); ,@($Personalize,'SystemUsesLightTheme') }
        'devmode' { ,@($AppModelUnlock,'AllowDevelopmentWithoutDevLicense') }
        'longpaths' { ,@($FileSystemKey,'LongPathsEnabled') }
        'classicmenu' { ,@("$ClassicMenu\InprocServer32",'') }
        'nobing' { ,@($SearchPolicy,'DisableSearchBoxSuggestions') }
        'taskbarleft' { ,@($ExplorerAdv,'TaskbarAl') }
        'clockseconds' { ,@($ExplorerAdv,'ShowSecondsInSystemClock') }
        'thispc' { ,@($ExplorerAdv,'LaunchTo') }
        'endtask' { ,@($DevSettings,'TaskbarEndTask') }
        'mouseaccel' { foreach ($name in 'MouseSpeed','MouseThreshold1','MouseThreshold2') { ,@($MouseKey,$name) } }
        'remotehost' { ,@($PasswordLessKey,'DevicePasswordLessBuildVersion') }
    }
}
function Get-TweakSnapshotPath($id) {
    if ($id -notin @($Apps | Where-Object type -eq 'tweak' | ForEach-Object id)) { throw 'Ajuste no válido.' }
    $machine = (Get-InstallContext ($Apps | Where-Object id -eq $id | Select-Object -First 1)) -eq 'machine'
    $base = if ($machine) { Join-Path $env:ProgramData 'iWinInstaller\restauracion' } else { Join-Path $LogDir 'restauracion' }
    if ($machine) {
        foreach($directory in @((Join-Path $env:ProgramData 'iWinInstaller'),$base)){
            if(Test-Path $directory){
                if((Get-Item $directory -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'No se guarda estado privilegiado a través de enlaces de carpetas.'}
            }else{New-Item $directory -ItemType Directory -ErrorAction Stop | Out-Null}
            & icacls.exe $directory /setowner '*S-1-5-32-544' | Out-Null
            if($LASTEXITCODE){throw 'No se pudo proteger el propietario del estado anterior.'}
            & icacls.exe $directory /reset | Out-Null
            if($LASTEXITCODE){throw 'No se pudieron limpiar los permisos del estado anterior.'}
            & icacls.exe $directory /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
            if($LASTEXITCODE){throw 'No se pudieron proteger los datos de restauración.'}
        }
    }
    Join-Path $base ($id + '.json')
}
function Save-TweakSnapshot($id) {
    if ($id -in @('wsl','restorepoint','rgboff')) { return }
    $path=Get-TweakSnapshotPath $id
    if (Test-Path $path) { return }
    $values=@()
    foreach ($target in @(Get-TweakRegistryTargets $id)) {
        $key=Get-Item -LiteralPath $target[0] -ErrorAction SilentlyContinue
        $exists=$key -and $key.GetValueNames() -contains $target[1]
        $values += [pscustomobject]@{ exists=[bool]$exists; kind=$(if ($exists) {[string]$key.GetValueKind($target[1])} else {'String'}); value=$(if ($exists) {$key.GetValue($target[1],$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)} else {$null}) }
    }
    $state=[ordered]@{format='iWinInstaller-restauracion';version=1;id=$id;values=$values;power=$null;remote=$null}
    if ($id -in @('power','remotehost')) {
        $plan=(& powercfg /getactivescheme 2>$null | Out-String)
        if ($LASTEXITCODE -ne 0 -or $plan -notmatch '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}') { throw 'No se pudo guardar el plan de energía anterior.' }
        $state.power=$Matches[0]
    }
    if ($id -eq 'remotehost') { $state.remote=Get-RemoteSnapshot }
    Write-IwinJson $path $state
}
function Restore-TweakSnapshot($id) {
    if ($id -eq 'rgboff') { return (Reset-RgbOff) }
    $path=Get-TweakSnapshotPath $id
    if (-not (Test-Path $path)) { throw 'No se guardó el estado anterior (ajuste previo a v3.2). No se impondrán valores genéricos; revísalo desde Configuración de Windows.' }
    $file=Get-Item $path
    if ($file.Length -gt 2MB) { throw 'Datos de restauración no válidos.' }
    $state=Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $targets=@(Get-TweakRegistryTargets $id)
    if ($state.format -ne 'iWinInstaller-restauracion' -or $state.version -ne 1 -or $state.id -ne $id -or @($state.values).Count -ne $targets.Count) { throw 'Estado de restauración no válido.' }
    for ($index=0;$index -lt $targets.Count;$index++) {
        $target=$targets[$index];$value=$state.values[$index]
        if ($value.exists) {
            if ($value.kind -notin @('String','ExpandString','DWord','QWord','Binary','MultiString')) { throw 'Tipo de registro no válido.' }
            if(-not (Test-Path $target[0])){New-Item $target[0] -Force -ErrorAction Stop | Out-Null}
            $hive=if($target[0].StartsWith('HKCU:\')){[Microsoft.Win32.Registry]::CurrentUser}else{[Microsoft.Win32.Registry]::LocalMachine}
            $key=$hive.OpenSubKey($target[0].Substring(6),$true)
            if(-not $key){throw 'No se pudo abrir el estado anterior para escribirlo.'}
            $data=$value.value
            if ($value.kind -eq 'DWord') { $data=[int]$data }
            if ($value.kind -eq 'QWord') { $data=[long]$data }
            if ($value.kind -eq 'Binary') { $data=[byte[]]$data }
            if ($value.kind -eq 'MultiString') { $data=[string[]]$data }
            try{$key.SetValue([string]$target[1],$data,[Microsoft.Win32.RegistryValueKind]$value.kind)}finally{$key.Dispose()}
        } elseif (Test-Path $target[0]) {
            $hive=if($target[0].StartsWith('HKCU:\')){[Microsoft.Win32.Registry]::CurrentUser}else{[Microsoft.Win32.Registry]::LocalMachine}
            $key=$hive.OpenSubKey($target[0].Substring(6),$true)
            if(-not $key){throw 'No se pudo recuperar la ausencia original del valor.'}
            try{$key.DeleteValue([string]$target[1],$false)}finally{$key.Dispose()}
        }
    }
    if ($id -eq 'classicmenu' -and -not $state.values[0].exists) {
        $key=Get-Item "$ClassicMenu\InprocServer32" -ErrorAction SilentlyContinue
        if ($key -and -not $key.GetValueNames().Count -and -not $key.GetSubKeyNames().Count) { Remove-Item "$ClassicMenu\InprocServer32" -ErrorAction Stop }
    }
    if ($state.power) {
        if ($state.power -notmatch '^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { throw 'Plan de energía no válido.' }
        & powercfg /setactive $state.power | Out-Null
        if ($LASTEXITCODE) { throw 'No se pudo restaurar el plan de energía.' }
    }
    if ($id -eq 'remotehost') { Restore-RemoteSnapshot $state.remote }
    Remove-Item $path -Force -ErrorAction Stop
    Write-Log '  Estado anterior restaurado. Algunos ajustes requieren reiniciar la sesión o Windows.'
    return $true
}
function Initialize-IwinServices {
    if ('IwinServiceRecovery' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public class IwinRecoveryData { public int Reset; public string Reboot; public string Command; public int[] Types; public int[] Delays; }
public static class IwinServiceRecovery {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct Config { public int Reset; [MarshalAs(UnmanagedType.LPWStr)] public string Reboot; [MarshalAs(UnmanagedType.LPWStr)] public string Command; public int Count; public IntPtr Actions; }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenSCManager(string m,string d,int access);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenService(IntPtr manager,string name,int access);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryServiceConfig2(IntPtr service,int level,IntPtr buffer,int size,out int needed);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ChangeServiceConfig2(IntPtr service,int level,ref Config config);
    [DllImport("advapi32.dll")] static extern bool CloseServiceHandle(IntPtr handle);
    static IntPtr Open(string name, int access, out IntPtr manager) {
        if (name != "SunshineService" && name != "Tailscale") throw new ArgumentException("Servicio no permitido");
        manager=OpenSCManager(null,null,1); if(manager==IntPtr.Zero) throw new Win32Exception();
        IntPtr service=OpenService(manager,name,access); if(service==IntPtr.Zero){CloseServiceHandle(manager);throw new Win32Exception();} return service;
    }
    public static IwinRecoveryData Read(string name) {
        IntPtr manager; IntPtr service=Open(name,1,out manager); IntPtr data=IntPtr.Zero;
        try {
            int size; QueryServiceConfig2(service,2,IntPtr.Zero,0,out size);
            if(size<=0) throw new Win32Exception(); data=Marshal.AllocHGlobal(size);
            if(!QueryServiceConfig2(service,2,data,size,out size)) throw new Win32Exception();
            Config c=(Config)Marshal.PtrToStructure(data,typeof(Config));
            IwinRecoveryData result=new IwinRecoveryData {Reset=c.Reset,Reboot=c.Reboot,Command=c.Command,Types=new int[c.Count],Delays=new int[c.Count]};
            for(int i=0;i<c.Count;i++){result.Types[i]=Marshal.ReadInt32(c.Actions,i*8);result.Delays[i]=Marshal.ReadInt32(c.Actions,i*8+4);} return result;
        } finally {if(data!=IntPtr.Zero)Marshal.FreeHGlobal(data);CloseServiceHandle(service);CloseServiceHandle(manager);}
    }
    public static void Restore(string name,int reset,string reboot,string command,int[] types,int[] delays) {
        if(types.Length!=delays.Length || types.Length>20)throw new ArgumentException("Acciones no válidas");
        IntPtr manager;IntPtr service=Open(name,18,out manager);IntPtr actions=Marshal.AllocHGlobal(Math.Max(8,types.Length*8));
        try {
            for(int i=0;i<types.Length;i++){if(types[i]<0||types[i]>3)throw new ArgumentException();Marshal.WriteInt32(actions,i*8,types[i]);Marshal.WriteInt32(actions,i*8+4,delays[i]);}
            Config c=new Config {Reset=reset,Reboot=reboot??"",Command=command??"",Count=types.Length,Actions=actions};
            if(!ChangeServiceConfig2(service,2,ref c))throw new Win32Exception();
        } finally {Marshal.FreeHGlobal(actions);CloseServiceHandle(service);CloseServiceHandle(manager);}
    }
}
'@
}
function Get-RemoteSnapshot {
    Initialize-IwinServices
    $remote=[ordered]@{standby=(Get-AcPowerValue 'SUB_SLEEP' 'STANDBYIDLE');hibernateTimeout=(Get-AcPowerValue 'SUB_SLEEP' 'HIBERNATEIDLE');hibernate=(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled');hibernateType=(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HiberFileType');hibernateSize=(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HiberFileSizePercent');services=@();nics=@();rules=@();links=@();unattended=$null}
    if ($null -eq $remote.standby) { throw 'No se pudo guardar la suspensión anterior.' }
    foreach ($name in 'SunshineService','Tailscale') {
        $service=Get-Service $name -ErrorAction SilentlyContinue
        if ($service) { $remote.services += [pscustomobject]@{name=$name;start=[string]$service.StartType;running=($service.Status -eq 'Running');delayed=(Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\$name" 'DelayedAutoStart');recovery=[IwinServiceRecovery]::Read($name)} }
    }
    foreach ($nic in @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -ne 'Disabled')) {
        $pm=Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction Stop
        $remote.nics += [pscustomobject]@{name=$nic.Name;wake=[string]$pm.WakeOnMagicPacket;power=[string]$pm.AllowComputerToTurnOffDevice}
    }
    foreach ($rule in @(Get-NetFirewallRule -Group $KdeRuleGroup -ErrorAction SilentlyContinue)) {
        $port=$rule | Get-NetFirewallPortFilter; $address=$rule | Get-NetFirewallAddressFilter
        $remote.rules += [pscustomobject]@{name=$rule.DisplayName;enabled=[string]$rule.Enabled;profile=[string]$rule.Profile;direction=[string]$rule.Direction;action=[string]$rule.Action;protocol=[string]$port.Protocol;localPort=@($port.LocalPort);remotePort=@($port.RemotePort);localAddress=@($address.LocalAddress);remoteAddress=@($address.RemoteAddress)}
    }
    foreach ($dir in Get-RemoteLinkDirs) {
        foreach ($name in $RemoteLinks.Keys) {
            $path=Join-Path $dir "$name.url"; $exists=Test-Path -LiteralPath $path
            if ($exists -and (Get-Item -LiteralPath $path).Length -gt 64KB) { throw 'Un acceso remoto existente es demasiado grande para conservarlo.' }
            $remote.links += [pscustomobject]@{directory=$dir;name=$name;exists=$exists;content=$(if($exists){[Convert]::ToBase64String([IO.File]::ReadAllBytes($path))}else{''})}
        }
    }
    $ts=Get-TailscaleExe
    if ($ts) {
        $probe=Invoke-IwinProbe $ts 'debug prefs'
        if ($probe.Code -ne 0) { throw 'No se pudo guardar el modo anterior de Tailscale; abre Tailscale y reintenta.' }
        $prefs=$probe.Output | ConvertFrom-Json -ErrorAction Stop
        $remote.unattended=[bool]$prefs.ForceDaemon
    }
    [pscustomobject]$remote
}
function Restore-RemoteSnapshot($remote) {
    if (-not $remote -or $remote.standby -isnot [ValueType]) { throw 'Falta el estado remoto anterior.' }
    & powercfg /change standby-timeout-ac ([int][math]::Ceiling([long]$remote.standby/60)) | Out-Null
    # setacvalueindex conserva los segundos exactos del plan original.
    & powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE ([long]$remote.standby) | Out-Null
    if ($LASTEXITCODE) { throw 'No se pudo restaurar la suspensión.' }
    if ($null -ne $remote.hibernate) {
        & powercfg /hibernate $(if($remote.hibernate){'on'}else{'off'}) | Out-Null
        if ($LASTEXITCODE) { throw 'No se pudo restaurar la hibernación.' }
        if ($remote.hibernate) { & powercfg /hibernate /type $(if($remote.hibernateType -eq 1){'reduced'}else{'full'}) | Out-Null; if ($LASTEXITCODE) { throw 'No se pudo restaurar el tipo de hibernación.' } }
    }
    if($remote.hibernate -and $remote.hibernateType -ne 1 -and $remote.hibernateSize -ge 40 -and $remote.hibernateSize -le 100){& powercfg /hibernate /size ([int]$remote.hibernateSize) | Out-Null;if($LASTEXITCODE){throw 'No se pudo restaurar el tamaño de hibernación.'}}
    if ($null -ne $remote.hibernateTimeout) { & powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE ([long]$remote.hibernateTimeout) | Out-Null; if($LASTEXITCODE){throw 'No se pudo restaurar el plazo de hibernación.'} }
    & powercfg /setactive SCHEME_CURRENT | Out-Null
    if ($null -ne $remote.unattended) {
        $ts=Get-TailscaleExe
        if (-not $ts) { throw 'No se encuentra Tailscale para recuperar su modo anterior.' }
        $probe=Invoke-IwinProbe $ts ('set --unattended='+([string][bool]$remote.unattended).ToLowerInvariant())
        if ($probe.Code -ne 0) { throw 'No se pudo restaurar el modo anterior de Tailscale.' }
    }
    Initialize-IwinServices
    foreach ($service in @($remote.services)) {
        if ($service.name -notin @('SunshineService','Tailscale') -or $service.start -notin @('Automatic','Manual','Disabled')) { throw 'Servicio de restauración no válido.' }
        $recovery=$service.recovery
        [IwinServiceRecovery]::Restore($service.name,[int]$recovery.Reset,[string]$recovery.Reboot,[string]$recovery.Command,[int[]]@($recovery.Types),[int[]]@($recovery.Delays))
        Set-Service $service.name -StartupType $service.start -ErrorAction Stop
        if ($null -ne $service.delayed) { Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($service.name)" -Name DelayedAutoStart -Value ([int]$service.delayed) -Type DWord -ErrorAction Stop }
        else { Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($service.name)" -Name DelayedAutoStart -ErrorAction SilentlyContinue }
        if ($service.running) { Start-Service $service.name -ErrorAction Stop }
        else { Stop-Service $service.name -ErrorAction Stop }
    }
    foreach ($nic in @($remote.nics)) {
        $params=@{Name=[string]$nic.name;ErrorAction='Stop'}
        if ($nic.wake -in @('Enabled','Disabled')) { $params.WakeOnMagicPacket=$nic.wake }
        if ($nic.power -in @('Enabled','Disabled')) { $params.AllowComputerToTurnOffDevice=$nic.power }
        if ($params.Count -gt 2) { Set-NetAdapterPowerManagement @params }
    }
    Remove-NetFirewallRule -Group $KdeRuleGroup -ErrorAction SilentlyContinue
    foreach ($rule in @($remote.rules)) {
        New-NetFirewallRule -DisplayName $rule.name -Group $KdeRuleGroup -Enabled $rule.enabled -Profile $rule.profile -Direction $rule.direction -Action $rule.action -Protocol $rule.protocol -LocalPort $rule.localPort -RemotePort $rule.remotePort -LocalAddress $rule.localAddress -RemoteAddress $rule.remoteAddress -ErrorAction Stop | Out-Null
    }
    foreach ($link in @($remote.links)) {
        if ($link.directory -notin @(Get-RemoteLinkDirs) -or $link.name -notin @($RemoteLinks.Keys)) { throw 'Acceso remoto de restauración no válido.' }
        $path=Join-Path $link.directory "$($link.name).url"
        if ($link.exists) { [IO.Directory]::CreateDirectory($link.directory) | Out-Null; [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($link.content)) }
        else { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
    foreach ($dir in Get-RemoteLinkDirs) { if ((Test-Path $dir) -and -not @(Get-ChildItem $dir -Force).Count) { Remove-Item -LiteralPath $dir -ErrorAction Stop } }
    Write-Log '  Energía, red, servicios y accesos anteriores restaurados. Si activaste Autologon, quítalo desde su botón Disable.'
}
function Complete-IwinItem($app, [bool]$ok, [scriptblock]$onProgress) {
    Set-IwinBatchResult $app $ok $script:LastInstallCode
    if ($onProgress) { & $onProgress $app $ok }
}
function Set-IwinAutoUpdate([bool]$enabled) {
    $name='iWinInstaller actualizaciones'
    if(-not $enabled){Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue;return}
    $exe=Join-Path $env:LOCALAPPDATA 'Programs\iWinInstaller\iWinInstaller.exe'
    if(-not (Test-Path $exe)){throw 'Instala iWinInstaller antes de activar sus actualizaciones automáticas.'}
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $action=New-ScheduledTaskAction -Execute $exe -Argument '--update-only'
    $daily=New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddHours(16))
    $logon=New-ScheduledTaskTrigger -AtLogOn -User $sid
    $principal=New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 25)
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $daily,$logon -Principal $principal -Settings $settings -Description 'Actualiza solo iWinInstaller desde su release pública verificada; no instala ni actualiza otras aplicaciones.' -Force -ErrorAction Stop | Out-Null
}
function Test-IwinAppOpen {
    $installed=Join-Path $env:LOCALAPPDATA 'Programs\iWinInstaller\iWinInstaller.exe'
    foreach($process in @(Get-Process -Name iWinInstaller -ErrorAction SilentlyContinue)){
        if($env:IWIN_HOST_PID -and $process.Id -eq [int]$env:IWIN_HOST_PID){continue}
        try{if($process.Path -eq $installed){return $true}}catch{}
    }
    $false
}
function Invoke-IwinWebTransfer([string]$url, [string]$outFile, [int]$timeoutSec=600) {
    $uri=[uri]$url
    if($uri.Scheme -ne 'https'){throw 'La actualización exige una conexión HTTPS.'}
    $client=New-Object Net.WebClient
    $client.Headers['User-Agent']='iWinInstaller/'+$Version
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try{
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $task=if($outFile){$client.DownloadFileTaskAsync($uri,$outFile)}else{$client.DownloadStringTaskAsync($uri)}
        while(-not $task.IsCompleted){
            if($timer.Elapsed.TotalSeconds -gt $timeoutSec -or (Test-IwinStop)){$client.CancelAsync();throw 'Actualización pospuesta: cancelada o sin respuesta. Puedes reintentarlo.'}
            Invoke-UiPump;Start-Sleep -Milliseconds 100
        }
        $task.GetAwaiter().GetResult()
    }finally{$client.Dispose()}
}
function Clear-IwinUpdateDownloads {
    $base=Join-Path $LogDir 'actualizacion'
    foreach($directory in @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue)){
        if($directory.Name -notmatch '^v\d+\.\d+$' -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
        if([version]$directory.Name.Substring(1) -le [version]$Version.Substring(1)){
            try{Remove-Item $directory.FullName -Recurse -Force -ErrorAction Stop}catch{Write-Log 'El paquete de actualización aún está en uso; se retirará al abrir de nuevo.'}
        }
    }
}

function Invoke-IwinInstallAction($app) {
    $values=@(Install-App $app)
    $results=@($values | Where-Object {$_ -is [bool]})
    if(-not $results.Count){Write-Log '  El instalador no devolvió un resultado comprobable.';return $false}
    # La salida de un asistente o una tarea .NET nunca convierte un false en éxito.
    [bool]$results[-1]
}
