# Diseño · Juego competitivo y latencia (v5.2)

Estado: **revisado** (Elephant-Goldfish Model: 1 pez de comprensión, 1 crítico, 1 de preparación; sus hallazgos están incorporados, ver § 8). Pendiente de aprobación de David.

## 1. Objetivo

Portátil gamer, shooters online. Requisitos del usuario:
1. Ping y latencia lo más bajos posible, siempre.
2. Que se adapte solo a la red/ubicación en la que esté.
3. Apps útiles para juego competitivo.
4. App **ligera** y **cerrable** que sirva para **monitorizar** y optimizar.

Restricciones: ajustes reversibles con estado guardado, nada placebo ni peligroso, español, Windows 10/11 x86/x64/ARM64, WPF .NET Framework 4.8 (C# 7.3), motor PowerShell 5.1 con BOM UTF‑8.

### Verdad técnica (se explica en la UI y el README)
- El ping de partida depende de: región/servidor elegido en el juego, Wi‑Fi frente a cable, **bufferbloat** y tráfico de fondo. Windows solo puede quitar estorbos.
- **El DNS no cambia el ping en partida**: acelera la resolución de nombres (lanzador, matchmaking, web).
- Los shooters usan UDP: los ajustes TCP (Nagle…) no les afectan.

## 2. Alcance

### 2.1 Ajustes nuevos (Sistema › grupo nuevo «Red y juego competitivo»)
`type: "tweak"`, `extra: true` (opcional, no se marca solo), con `postInstall` (pasos + nota honesta).

| id | Nombre | Qué hace exactamente | context |
|---|---|---|---|
| `gamedns` | DNS más rápido (se adapta a cada red) | § 3 | machine |
| `wifiperf` | Wi‑Fi sin ahorro de energía (con corriente) | En **todos** los planes (`powercfg /list`): `powercfg /setacvalueindex <plan> 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0` (0 = Máximo rendimiento), después `powercfg /setactive SCHEME_CURRENT`. Solo con corriente: con batería se mantiene el ahorro. Sin Wi‑Fi o sin ese ajuste: registra «este equipo no tiene ajuste de energía de Wi‑Fi» y devuelve falso | machine |
| `nodvr` | Sin grabación en segundo plano | `HKCU:\System\GameConfigStore` `GameDVR_Enabled`=0 y `HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR` `AppCaptureEnabled`=0 | user |
| `gamemode` | Modo Juego activado | `HKCU:\Software\Microsoft\GameBar` `AutoGameModeEnabled`=1 y `AllowAutoGameMode`=1. Nota: viene activado por defecto; el ajuste lo garantiza si se desactivó | user |

Se reutilizan `power` (alto rendimiento: procesador al 100 % y PCIe ASPM desactivado con corriente) y `mouseaccel` (ratón 1:1).

**Descartados con motivo** (README): Nagle/`TcpAckFrequency`/`TCPNoDelay` (TCP; los shooters usan UDP); `NetworkThrottlingIndex`/`SystemResponsiveness` (sin efecto medible en Win10/11 actuales); «reserva QoS 20 %» (mito); autotuning TCP; desactivar `WlanSvc` (rompe el Wi‑Fi); Delivery Optimization (el modo por defecto ya es solo red local: casi placebo y mostraría «administrado por tu organización»); HAGS/ajustes de GPU (dependen del driver: NVIDIA App/Adrenalin); limpiadores de RAM (ISLC); «optimizadores» de registro; EEE/interrupt moderation/roaming del adaptador (propiedades del driver con nombres distintos por fabricante: se explican en los pasos de `wifiperf`, no se tocan automáticamente).

**GPU dedicada**: muchos portátiles lanzan el juego en la gráfica integrada. No se puede fijar de forma genérica (es por ejecutable). La página «Juego» tiene el botón «Elegir GPU por juego» que abre `ms-settings:display-advancedgraphics` y lo explica.

### 2.2 Apps nuevas (Aplicaciones › Juegos › subgrupo nuevo «Latencia y diagnóstico»)
Ids comprobados en `microsoft/winget-pkgs` el 2026‑11‑17 (CI los vuelve a validar con `tests/check-ids.ps1`):

| id | Nombre | winget | compare |
|---|---|---|---|
| `speedtest` | Speedtest by Ookla | `Ookla.Speedtest.Desktop` | Velocidad y ping al servidor cercano |
| `latencymon` | LatencyMon | `Resplendence.LatencyMon` | Drivers que causan tirones (DPC/ISR) |
| `capframex` | CapFrameX | `CXWorld.CapFrameX` | Frametimes y 1 % low, antes/después |
| `processlasso` | Process Lasso | `BitSum.ProcessLasso` | Prioridad de CPU por juego; queda residente (opcional) |

`subgroupNote`: «Mide antes de tocar: Speedtest para la línea, LatencyMon si hay tirones, CapFrameX para comparar FPS. Process Lasso solo si un juego compite con procesos de fondo». RTSS y Afterburner ya están en «Rendimiento y overlay». Descartados: ExitLag/NoPing (pago, efecto variable), PingPlotter/WinMTR (sin manifiesto WinGet).

### 2.3 Perfil nuevo `"Juego competitivo (baja latencia)"` (`profiles.json`)
`["power","wifiperf","gamedns","nodvr","gamemode","mouseaccel","rtss","latencymon","speedtest"]`. `power` va antes que `wifiperf` (aunque `wifiperf` ya cubre todos los planes).

### 2.4 Página nueva «Juego» (monitor ligero)
`NavItem("gaming","Juego","Ping en vivo, bufferbloat y ajustes para jugar online.")` tras «Sistema»; glyph `""` (Game) en `NavItem.GlyphFor`. Paleta: `PaletteAction("nav.gaming","Ping y latencia para jugar","Juego","ping latencia lag jitter perdida bufferbloat juego shooter competitivo red wifi dns")`.

Bloques:
1. **Ping en vivo** a: *Router* (puerta de enlace IPv4 de la interfaz con la ruta por defecto de menor métrica), *Internet* (1.1.1.1) y *Servidor del juego* (opcional; IP o nombre). Por destino: último, media, jitter (media de |Δ| entre respuestas consecutivas), pérdida de los últimos 60 s, máximo, y una línea de 60 puntos. Colores: Internet/juego verde < 40 ms, ámbar < 80, rojo ≥ 80 o pérdida > 2 %; Router verde < 5, ámbar < 20, rojo ≥ 20 o pérdida > 0.
   **Picos de la sesión**: lista de los 20 últimos picos (> media + 50 ms o pérdida) con hora, para revisar después de una partida.
   **Sin respuesta ICMP**: si el servidor del juego pierde el 100 % durante 10 s e Internet responde, se muestra «Este servidor no responde a ping (habitual); usa el ping del propio juego» en vez de rojo.
2. **Bufferbloat** (botón, nunca automático): 10 pings en reposo; después 8 s de descarga con 4 flujos `GET https://speed.cloudflare.com/__down?bytes=25000000` repetidos y 8 s de subida con 2 flujos `POST https://speed.cloudflare.com/__up` de 10 MB, con tope total de 400 MB, midiendo ping a 1.1.1.1 cada 100 ms. Resultado por sentido: p90 bajo carga − mediana en reposo. Nota (límite inferior incluido): A+ < 5, A < 30, B < 60, C < 200, D < 400, F ≥ 400 ms. Aviso previo: «Usa hasta 400 MB; evita hacerlo con datos móviles». Si falla la red: «No se pudo completar la prueba». Nota ≥ C: «Activa SQM/QoS (fq_codel o CAKE) en el router o limita la subida de otros equipos». Cliente: `HttpWebRequest` con TLS 1.2 y `CancellationToken`.
3. **Conexión**: Ethernet/Wi‑Fi y velocidad de enlace (`NetworkInterface`). Con Wi‑Fi, `netsh wlan show interfaces` desde C# (sin PowerShell) una vez al entrar: señal = primer `\d+\s*%`, canal = número tras «Canal|Channel», banda = línea «Banda|Band» si existe o deducida del canal (1–14 → 2,4 GHz; 32–177 → 5 GHz); si la línea de radio indica 6 GHz se respeta. No se muestran SSID ni BSSID. Recomendación con Wi‑Fi: cable, o 5/6 GHz cerca del router.
4. **DNS**: lee `%ProgramData%\iWinInstaller\Latencia\dns.json` (§ 3) y muestra proveedor elegido, tiempos y hora. Si no existe: «Aplica DNS más rápido en Ajustes de juego».
5. **Botones**: «Ver ajustes de juego» (navega a Instalar con `Install.Search = "Red y juego competitivo"`) y «Elegir GPU por juego».

**Ligereza**
- `System.Net.NetworkInformation.Ping`, **una instancia por destino**, sin solapar ciclos (si la anterior no ha vuelto, se salta), 1 por segundo, espera 1000 ms. El nombre del servidor se resuelve una vez y cada 5 min. `NetworkChange.NetworkAddressChanged` recalcula la puerta de enlace.
- El monitor corre **mientras la página Juego esté seleccionada**, también con la ventana minimizada (para poder jugar y revisar los picos después). Se detiene al cambiar de página o cerrar la app; un `CancellationTokenSource` descarta respuestas tardías. Coste: 3 ICMP por segundo y un temporizador; sin procesos.
- Al cerrar la app no queda nada en marcha salvo la tarea de `gamedns`, que dura segundos y solo al conectar a una red.

## 3. `gamedns`

### Principio
Solo toca adaptadores que **usan DNS automático (DHCP)** o que ya tienen un DNS puesto por este ajuste. Nunca toca un DNS estático del usuario (Pi‑hole, NextDNS…), ni equipos de dominio, ni VPN. No hay reinicio previo a DHCP: se mide con `-Server` sin cambiar nada y solo se cambia si otro gana claramente. Así no hace falta guardar estado por adaptador: el estado original es siempre «automático».

### Archivos
- Fuente: `src/engine/gaming/dns-rapido.ps1` (script autocontenido, sin parámetros salvo `-Library`, que solo define funciones para Pester y para el motor).
- Instalado: `%ProgramData%\iWinInstaller\Latencia\dns-rapido.ps1`; resultados `dns.json`; cambios hechos `aplicado.json` (`{format:"iWinInstaller-dns",version:1,adapters:[guid]}`).
- Carpeta protegida con la función compartida nueva `Protect-IwinProgramDataDir($path)` (extraída del bloque de `Get-TweakSnapshotPath`: rechaza reparse points, `/setowner` Administradores, `/reset`, `/inheritance:r`, SYSTEM y Administradores F, Usuarios RX), aplicada a `iWinInstaller` y `Latencia`.
- `Test-GameDns` = la tarea existe **y** el SHA256 del script instalado coincide con el del motor.

### Tarea
`\iWinInstaller\DNS más rápido`, registrada con `Register-ScheduledTask -Xml` (PS 5.1 no crea disparadores por evento con `New-ScheduledTaskTrigger`). XML: principal SYSTEM `HighestAvailable`; `DisallowStartIfOnBatteries=false`, `StopIfGoingOnBatteries=false`, `StartWhenAvailable=true`, `MultipleInstancesPolicy=Queue`, `ExecutionTimeLimit=PT2M`; disparadores `BootTrigger` (PT30S), `LogonTrigger` (PT20S) y `EventTrigger` con
`<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[EventID=10000]]</Select></Query></QueryList>` y `Delay PT10S`. `Queue` evita perder un cambio de red durante otra ejecución.

### Algoritmo (cada ejecución, con mutex global `Global\iWinInstaller-dns`)
1. Si `Win32_ComputerSystem.PartOfDomain` → termina sin tocar nada.
2. Adaptadores: `Get-NetAdapter -Physical` en `Up`, con ruta por defecto, excluyendo descripciones `Hyper-V|VMware|VirtualBox|TAP|WireGuard|Tailscale|Wintun|VPN`.
3. Por adaptador, DNS estático actual = `NameServer` de `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{guid}` (y `Tcpip6`). Si no está vacío y no coincide exactamente con una lista de proveedor de § 3 → se omite (DNS del usuario).
4. Si `Get-NetConnectionProfile` de esa interfaz no tiene `IPv4Connectivity = Internet` durante 20 s: si el DNS es nuestro, vuelve a automático (`-ResetServerAddresses`, para no bloquear un portal cautivo) y pasa al siguiente.
5. Candidatos: DNS de la red (`DhcpNameServer` del registro, validados con `[ipaddress]::TryParse`; si el DNS es nuestro, los de DHCP siguen ahí), Cloudflare `1.1.1.1,1.0.0.1 / 2606:4700:4700::1111,2606:4700:4700::1001`, Google `8.8.8.8,8.8.4.4 / 2001:4860:4860::8888,2001:4860:4860::8844`, Quad9 `9.9.9.9,149.112.112.112 / 2620:fe::fe,2620:fe::9`.
6. Medición: 5 rondas × 3 nombres (`www.google.com`, `steamcommunity.com`, `www.riotgames.com`), candidatos intercalados en cada ronda, `Resolve-DnsName -Type A -Server <primario> -DnsOnly -NoHostsFile -QuickTimeout`; se descarta la primera ronda; mediana. Un candidato con más de 2 fallos queda fuera.
7. Decisión (`Select-GameDns`, pura): si no queda ningún candidato → no cambia nada. Gana el de menor mediana; si el DNS de la red está dentro de `max(5 ms, 15 %)` del ganador, se usa el de la red (menos cambios; además el DNS del ISP suele dar nodos CDN más cercanos).
8. Aplicar: red → `-ResetServerAddresses` si era nuestro; proveedor → `Set-DnsClientServerAddress -InterfaceIndex i -ServerAddresses <lista mixta IPv4 + IPv6 si IPv6Connectivity = Internet>`. Windows 11 cifra (DoH) automáticamente estos tres proveedores si el usuario lo activa.
9. Escribe `dns.json` `{format:"iWinInstaller-dns-resultado",version:1,at,adapterType:"wifi|ethernet",chosen,results:[{provider,ms,failed}]}` (sin SSID ni nombre de red) y actualiza `aplicado.json`.

### Instalar / Deshacer
- `Set-GameDns` (elevado, worker machine): protege la carpeta, copia el script, registra la tarea, la ejecuta una vez y espera hasta 90 s; devuelve `Test-GameDns`.
- `Reset-GameDns`: `Stop-ScheduledTask`, toma el mutex, `Unregister-ScheduledTask`, para cada guid de `aplicado.json` cuyo DNS siga siendo una lista de proveedor → `-ResetServerAddresses`; borra `Latencia`.
- Integración `lifecycle.ps1`: `gamedns` se trata como `rgboff` (sin snapshot de registro): `Save-TweakSnapshot` lo omite; `Restore-TweakSnapshot` → `Reset-GameDns`; `Test-IwinPreviousState` → existe la tarea.

## 4. `wifiperf`: estado
- `Save-TweakSnapshot`: con `Get-TweakRegistryTargets 'wifiperf'` vacío (`values=@()` válido), añade `state.wifi = @( @{plan='<guid>'; ac=<0..5>} ... )` para cada plan que tenga el ajuste.
- `Restore-TweakSnapshot`: si `id -eq 'wifiperf'`, valida cada `plan` con la regex de GUID y `ac` entero 0–5, escribe `/setacvalueindex` en cada plan **sin activarlo**, y `powercfg /setactive SCHEME_CURRENT`.
- `Test-WifiPerf`: el plan activo tiene AC = 0. Lectura con `powercfg /query SCHEME_CURRENT <sub> <setting>`: el valor AC es el primer `0x[0-9a-f]{8}` de la línea que contiene «(AC|corriente alterna)»; parser puro `Get-PowercfgIndex($text,'ac')` probado con salidas en inglés y español.

## 5. Archivos y firmas

**Motor**
- Nuevo `src/engine/15-Gaming.ps1` (añadido a `$EngineFiles`): `$GameDnsDir`, `$GameDnsScript`, `$GameDnsTaskPath='\iWinInstaller\'`, `$GameDnsTaskName='DNS más rápido'`, `$WifiPowerSub`, `$WifiPowerSetting`; `Get-GameDnsTaskXml`, `Set-GameDns`, `Test-GameDns`, `Reset-GameDns`, `Get-PowercfgIndex`, `Get-WifiPerfPlans`, `Set-WifiPerf`, `Test-WifiPerf`, `Restore-WifiPerf($wifi)`. Carga `gaming\dns-rapido.ps1 -Library` para `Select-GameDns`.
- `src/engine/gaming/dns-rapido.ps1`: `Select-GameDns([object[]]$Results,[string]$Network)` (Results: `@{provider; servers4; servers6; ms; failed}`), `Get-GameDnsAdapters`, `Invoke-GameDnsMeasure`, `Invoke-GameDnsRun`.
- `src/engine/03-System.ps1`: `$GameConfigStore`, `$GameDvrKey`, `$GameBarKey`.
- `src/engine/06-Tweaks.ps1`: `Install-Tweak` → `gamedns` `Set-GameDns`; `wifiperf` `Set-WifiPerf`; `nodvr` y `gamemode` con `Set-RegDword`. `Test-TweakCore`: comparan los valores escritos.
- `lifecycle.ps1`: `Protect-IwinProgramDataDir` (refactor sin cambio de comportamiento en `Get-TweakSnapshotPath`), objetivos `nodvr`/`gamemode`, ramas `gamedns`/`wifiperf` descritas arriba.

**Interfaz**
- Nuevos `src/app/Modules/Gaming/GamingView.xaml(.cs)`, `GamingViewModel.cs` (`Start()`, `Stop()`, `RunBufferbloatAsync()`), `LatencyStats.cs` (pura: `Add(long? ms)`, `Last`, `Average`, `Jitter`, `LossPercent`, `Max`, `Points`; `static string BufferbloatGrade(double ms)`, `static double Percentile(IList<double>, double p)`), `WifiInfo.cs` (pura: `Parse(string netshText)`).
- `ShellViewModel`: recibe ya `Preferences`; crea `Gaming = new GamingViewModel(_preferences, dispatcher)`; en `Selected`: al entrar `Gaming.Start()`, al salir de `gaming` `Gaming.Stop()`. `MainWindow.xaml`: `<gaming:GamingView DataContext="{Binding Gaming}" …ConverterParameter=gaming/>`; `Closing` → `Gaming.Stop()`.
- `Preferences`: `GameServer` (string), se guarda/lee como `gameServer`; válido si `IPAddress.TryParse` o nombre DNS `^(?=.{1,253}$)([a-zA-Z0-9-]{1,63}\.)*[a-zA-Z0-9-]{1,63}$`; si no, se ignora.
- `PaletteSearch.BuiltIn`: acción `nav.gaming` (ajustar el recuento en `PaletteTests` si lo hay).

**Catálogo, docs y pruebas**
- `apps.json`: 4 ajustes + 4 apps (orden: ajustes tras `mouseaccel`; apps tras `rtss`). `profiles.json`: perfil nuevo.
- `README.md`: sección «Juego competitivo y latencia» (qué hace, qué no, descartados) y contadores recalculados con script (entradas, subsecciones, categorías, guías). `CHANGELOG.md` v5.2. `$Version='v5.2'`, `<Version>5.2.0</Version>`.
- `tests/unit/engine/Gaming.Tests.ps1` (Select-GameDns: ganador, umbral, sin candidatos, empate con red; Get-PowercfgIndex en/es; XML de la tarea parsea y contiene el EventID; objetivos de registro) y añadirlo a `tests/unit/run.ps1`. `tests/unit/app/GamingTests.cs` (LatencyStats, BufferbloatGrade límites, Percentile, WifiInfo en/es, validación de GameServer).

## 6. Riesgos
| Riesgo | Mitigación |
|---|---|
| DNS de empresa/estático/VPN pisado | § 3 pasos 1–3: se omiten |
| Portal cautivo | paso 4: vuelve a automático sin internet |
| Tarea muere a mitad | no hay estado intermedio: o queda el DNS anterior o el nuevo, ambos válidos |
| Script SYSTEM manipulable | carpeta protegida, sin parámetros en la tarea, hash comprobado en `Test-GameDns` |
| Batería (portátil) | `wifiperf` solo con corriente; tarea permitida con batería (dura segundos) |
| Bufferbloat consume datos | botón explícito, aviso, tope 400 MB |
| Servidor del juego sin ICMP | estado «no responde a ping» |
| EDR avisa por tarea SYSTEM | mismo patrón que RGB; se documenta |

## 7. Verificación
- Pester y MSTest en CI (Windows); `tests/check-ids.ps1` para los ids.
- Prueba manual en el portátil (pendiente para David): ping en vivo con Wi‑Fi y cable, prueba de bufferbloat, aplicar/deshacer los 4 ajustes, `dns.json` tras cambiar de red.

## 8. Hallazgos de la revisión incorporados
Comprensión: 19 puntos (umbrales, límites de nota, ICMP bloqueado, monitor durante la partida, glyph, contadores). Crítica: no tocar DNS estático/dominio, sin reset previo, tarea con batería y disparador XML, carpeta protegida + hash, IPv6 mixto, mutex en Reset, bufferbloat con flujos y subida, `wifiperf` en todos los planes y solo AC, Delivery Optimization descartado por casi placebo, GPU dedicada, un `Ping` por destino. Preparación: `run.ps1`, contrato de estado, `nav.gaming`, inyección de `Preferences`, `Start/Stop`, XML del evento. Se eliminaron los comandos de motor `gaming.dns.measure`/`gaming.wifi`: la página no lanza PowerShell.
