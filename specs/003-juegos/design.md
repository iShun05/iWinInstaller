# Diseño · Juegos: detectar, comprobar y optimizar (v5.3)

Estado: **revisado** (Elephant-Goldfish Model: 1 pez de comprensión, 1 crítico y 1 de preparación; sus hallazgos están incorporados, ver § 8). Pendiente de aprobación de David.
Base: rama de la v5.2 (PR 29). Se construye encima de la página «Juego» (latencia).

## 1. Objetivo

Petición del usuario (2026-11-17):
1. Una **sección de videojuegos** que primero compruebe si cada juego **está instalado** y **sus archivos están bien**.
2. **Detalles** de cada juego para comprobarlo.
3. Un botón **«Optimizar»**: máximo FPS, menor input lag, texturas para rendimiento.
4. Juegos: **Fortnite, Honkai: Star Rail, Zenless Zone Zero, Arknights: Endfield y Genshin Impact**. **Desbloquear 120 FPS/Hz** donde se pueda.
5. **Sin riesgo de baneo** («no sé si te pueden banear»).

### Regla de seguridad (no negociable)
Solo se toca lo que el propio juego o Windows guardan como **ajuste del usuario**:
- archivos de configuración del juego fuera de su carpeta de instalación (`%LOCALAPPDATA%`), o
- valores del registro de usuario (`HKCU`) que el juego escribe desde su propio menú, o
- ajustes de Windows por programa (preferencia de GPU).

**Nunca**: inyectar en memoria, «FPS unlockers», modificar ejecutables, DLL o archivos de la carpeta del juego, poner archivos en solo lectura, ni leer archivos del juego mientras el juego o su lanzador están en marcha. La app **no repara**: detecta y manda al lanzador oficial.

### Verdad técnica (se explica en la UI y el README)
- **Genshin Impact en PC no ofrece más de 60 FPS** (PCGamingWiki: la opción de 120 se quitó tras la beta). Los 120 solo se consiguen con unlockers que escriben en la memoria del juego: viola los términos de HoYoverse. **No se hace.** El texto dice «a fecha de v5.3»; si HoYoverse lo añade, se elige en su menú.
- **Zenless Zone Zero** ofrece «Ilimitado» en su menú (PCGamingWiki); sus ajustes viven cifrados dentro de la carpeta del juego: **no se tocan**; se guía.
- **Arknights: Endfield** ofrece 120 FPS en su menú; no hay formato de ajustes documentado: **no se toca**; se guía.
- **Honkai: Star Rail** solo ofrece 30/60 en el menú de PC. Guarda sus gráficos en `HKCU` como JSON y **acepta 120** en ese valor (PCGamingWiki, Collapse Launcher). Es **no oficial**: apagado por defecto, etiqueta «No oficial · riesgo bajo». Tras aplicarlo el menú puede mostrar otro valor de FPS: **no hay que tocar la opción FPS en el juego** o se pierde.
- **Fortnite** guarda sus gráficos en `GameUserSettings.ini` (`%LOCALAPPDATA%`), el mismo archivo que escribe su menú. No lo vigila el anticheat.
- El juego reescribe su configuración **al cerrarse**: Optimizar y Restaurar solo con el juego **cerrado**.
- **La app no mide FPS.** Para comparar antes/después: contador de FPS del juego o CapFrameX (ya en el catálogo).

## 2. Alcance

### 2.1 Navegación
- Nueva página `NavItem("games","Juegos","Tus juegos: instalación, archivos y optimización.",false)` justo antes de la actual; `GlyphFor`: `games` → `` (Game).
- **La página actual «Juego» pasa a llamarse «Latencia»** (id `gaming` igual; `GlyphFor("gaming")` → `` Wifi). También cambia: título de `GamingView.xaml`, módulo `"Juego"` de `nav.gaming` en `ActionRegistry.BuiltIn()` (`PaletteSearch.cs`), comentario de `ShellViewModel.Selected` y README. Motivo: «Juego» y «Juegos» juntos confunden.
- Paleta: `PaletteAction("nav.games","Optimizar juegos (FPS e input lag)","Juegos","fortnite genshin star rail honkai zenless zzz endfield arknights fps 120 input lag optimizar texturas juegos instalado archivos verificar")` (sin «hz», para no competir con Sistema). `ActionRouter` ya navega cualquier `nav.*`.
- `ShellViewModel.Selected`: siempre `Gaming.Stop(); Games.Stop();` y después `Start()` de la página activa. `MainWindow.xaml.cs` `Closing` → `Gaming.Stop(); Games.Stop();`.

### 2.2 Bloques de la página
1. **Pantalla** (arriba, solo lectura): «Pantalla principal: 60 Hz · admite hasta 144 Hz a esta resolución» con `DisplaySettings` (`Monitors()`, `CurrentMode`, `Modes`; se reutiliza, no se duplica) y la función pura nueva `DisplaySettings.MaxRefreshFor(width,height,modes)`. Si la actual es menor: botón **«Subir a 144 Hz en Sistema»** que navega a Sistema (que ya aplica con `CDS_TEST`, confirmación de 15 s y vuelta atrás). Si ya está al máximo: «Al máximo».
2. **Una tarjeta por juego** (rejilla de 1 a 2 columnas según ancho), orden: Fortnite, Honkai: Star Rail, Zenless Zone Zero, Arknights: Endfield, Genshin Impact.
   - Cabecera: nombre, pastilla de estado, lanzador.
   - **Estados** (prioridad de mayor a menor): `En marcha` (Accent) > `Revisar archivos` (Attention) > `Instalado` (Ok) > `No instalado` (Unknown). `Detectando…` (Unknown) solo mientras detecta. `Revisar archivos` persiste (desde `estado.json`) hasta una comprobación correcta.
   - Resumen: versión · tamaño · FPS configurados (si se leen; si no, «—»).
   - Botones: **Optimizar** (principal), **Comprobar archivos**, **Detalles**, **Restaurar** (si hay copia), **Abrir carpeta** (`explorer.exe "<ruta>"`). Sin instalar: **«Buscar el ejecutable…»** (`IDialogService.OpenFile("Juego|<exe>")`) y enlace a la web oficial.
   - En marcha: Optimizar, Restaurar y Comprobar desactivados con el texto «Cierra el juego (y su lanzador) para continuar».
3. **Detalles** (expande): ruta, lanzador, versión, tamaño, espacio libre de la unidad, ejecutable(s), preferencia de GPU actual, ajustes actuales leídos (Fortnite: límite de FPS, modo de renderizado, VSync, pantalla completa; Star Rail: FPS, VSync), anticheat del juego, última copia y última comprobación (fecha, modo y totales).
4. **Optimizar** (panel dentro de la tarjeta): lista de cambios con **casilla**, valor actual → nuevo (en texto: «Bajo», «Desactivado»…) y etiqueta (`Ajuste del juego` / `Ajuste de Windows` / `No oficial · riesgo bajo`). Debajo, **«Hazlo tú en el juego»** (lo que no se toca y por qué). Botón «Aplicar»: copia de seguridad → si la copia falla, no se aplica nada → cambios → resultado por línea (✓ Ok / ✗ Attention con motivo). Un fallo a medias no se revierte solo: queda Restaurar.
   Para ZZZ, Endfield y Genshin el panel dice claramente «Solo se puede ajustar la GPU desde fuera del juego; el resto, en su menú».

### 2.3 Detección
Una vez al entrar en la página, en segundo plano. Gana la primera fuente que dé una carpeta **con el ejecutable dentro**. Todo de solo lectura.

| Juego | Fuentes (en orden) | Ejecutable principal | Procesos «en marcha» |
|---|---|---|---|
| Fortnite | Epic `%ProgramData%\Epic\EpicGamesLauncher\Data\Manifests\*.item` (JSON) con `AppName` = `Fortnite` → `InstallLocation`, `AppVersionString`, `InstallSize` | `FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe` | `FortniteClient-Win64-Shipping*`, `FortniteLauncher`, `EpicGamesLauncher` (este solo bloquea Comprobar) |
| Genshin | HoYoPlay `HKCU\Software\{Cognosphere,miHoYo}\HYP\*\{hk4e_global,hk4e_cn}` → `GameInstallPath` (se recorren todas las subclaves); Epic `DisplayName` contiene «Genshin Impact» | `GenshinImpact.exe` / `YuanShen.exe` | `GenshinImpact`, `YuanShen`, `HYP` |
| Star Rail | HoYoPlay `hkrpg_global`, `hkrpg_cn`; Epic «Honkai: Star Rail» | `StarRail.exe` | `StarRail`, `HYP` |
| ZZZ | HoYoPlay `nap_global`, `nap_cn`; Epic «Zenless Zone Zero» | `ZenlessZoneZero.exe` | `ZenlessZoneZero`, `HYP` |
| Endfield | Steam app `4732690` (`HKCU\Software\Valve\Steam\SteamPath` → `steamapps\libraryfolders.vdf` → `appmanifest_4732690.acf`: `installdir`, `SizeOnDisk`, `buildid`); Epic `DisplayName` contiene «Endfield»; desinstaladores con «Endfield» o «GRYPHLINK» | primer `.exe` de la carpeta o de `games\EndField Game` (sin recursión) cuyo `CompanyName` contenga «Hypergryph» o «Gryphline», o cuyo nombre empiece por «Endfield» (**por verificar en el PC**) | ese exe, `GRYPHLINK` |

- Comparaciones de nombres: «contiene», sin distinguir mayúsculas. Si hay global y china, gana la global. HoYo: versión de `config.ini` (`game_version`) en la carpeta del juego.
- Respaldo común: desinstaladores `HKLM\…\Uninstall`, `HKLM\WOW6432Node\…\Uninstall`, `HKCU\…\Uninstall` (`DisplayName` contiene el nombre) → `InstallLocation`.
- **Ejecutable elegido a mano**: `%LOCALAPPDATA%\iWinInstaller\Juegos\rutas.json` `{format:"iWinInstaller-juegos-rutas",version:1,paths:{id:carpeta}}`; solo si el nombre coincide con los de la tabla; se revalida en cada arranque y se descarta si ya no está. Nunca se ejecuta nada de ahí.
- **Tamaño**: HoYo = suma de `fileSize` de `pkg_version`; Steam = `SizeOnDisk`; Fortnite = `InstallSize`; si no hay dato, «—». No se recorre el disco para esto.
- En marcha: cada 3 s con la página abierta (`Process.GetProcessesByName`, sin abrir handles). Al cerrarse el juego se recalcula el estado sin volver a detectar. Si el juego se abre durante una comprobación, se cancela.
- Abstracción para pruebas: `IGameEnvironment` (registro, existe archivo/carpeta, leer texto, enumerar, info de versión de archivo) con `WindowsGameEnvironment` real y una en memoria para MSTest.

### 2.4 Comprobar archivos (botón; nunca automático; bloqueado con juego o lanzador en marcha)
- **HoYo**: todos los `*pkg_version` de la raíz (una línea JSON por archivo: `remoteName`, `md5`, `fileSize`). **Rápida** (por defecto): existe y tamaño = `fileSize`. **Completa** (casilla): además MD5, en segundo plano, con progreso y Cancelar, `FileShare.ReadWrite`. Cada fallo se etiqueta `falta`, `tamaño` o `MD5`; se muestran 20 y «y N más». Si fallan más del 5 % de los archivos: «La lista del juego parece desactualizada; usa Reparar en HoYoPlay» (no «dañado»). Si fallan pocos: «Repáralo en HoYoPlay › ⚙ › Reparar juego». Sin `pkg_version`: «Este juego no trae lista de archivos; usa Reparar en el lanzador».
- **Fortnite** («comprobación básica», se dice así): ejecutable, `FortniteGame\Content\Paks` con al menos un `.pak` o `.utoc` y la carpeta `.egstore`. Siempre muestra: «Para una verificación real: Epic › Biblioteca › ⋯ › Administrar › Verificar».
- **Endfield**: ejecutable; si es de Steam, botón «Verificar en Steam» (`steam://validate/4732690`); si no, instrucción del «Reparar» de GRYPHLINK.
- Resultado en `Juegos\estado.json` `{format:"iWinInstaller-juegos-estado",version:1,games:{id:{at,mode,total,ok,missing,size,md5}}}` (`at` ISO 8601 UTC).

### 2.5 Optimizar: cambios por juego
Se saltan los que ya tienen el valor nuevo. Marcado por defecto salvo que se diga.

**Común a los 5 · GPU de alto rendimiento (Ajuste de Windows)**
`HKCU\Software\Microsoft\DirectX\UserGpuPreferences`, valor = ruta completa del ejecutable. Se cambia **solo el par** `GpuPreference=2;` y se conservan los demás pares (`SwapEffectUpgradeEnable`, `AutoHDREnable`…). Ejecutables: el principal; en Fortnite también `…-Shipping_EAC_EOS.exe` y `…-Shipping_BE.exe` si existen. Si `Win32_VideoController` muestra una sola GPU (sin contar «Microsoft Basic Display» ni adaptadores remotos), la casilla sale desmarcada con «Sin efecto: este equipo tiene una sola GPU».

**Fortnite** — `%LOCALAPPDATA%\FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini`. Si no existe: «Abre Fortnite una vez y ciérralo». Si es de solo lectura o es un enlace (reparse point): no se toca y se avisa.
| Cambio | Clave | Valor |
|---|---|---|
| Modo de renderizado **Rendimiento** | `[D3DRHIPreference]` `PreferredRHI` / `PreferredFeatureLevel` | `dx11` / `es31` (**por verificar en la build actual**) |
| Mallas bajas | `[PerformanceMode]` `MeshQuality` | `0` |
| Texturas bajas | `[ScalabilityGroups]` `sg.TextureQuality` | `0` |
| Distancia de visión lejana (ver lejos en competitivo; cuesta poco en Rendimiento) | `sg.ViewDistanceQuality` | `3` |
| Resolución 3D al 100 % | `sg.ResolutionQuality` | `100` |
| Límite de FPS | `[/Script/FortniteGame.FortGameUserSettings]` `FrameRateLimit` | desplegable: **Hz actuales** (por defecto; `144.000000`), **Hz − 3** («con G‑Sync/FreeSync»), **Sin límite** (`0.000000`, «con Reflex + Boost; más calor»). Se usan los Hz del momento de aplicar |
| VSync desactivado | `bUseVSync` | `False` |
| Contador de FPS (para comprobar) | `bShowFPS` | `True` |
| Pantalla completa exclusiva · **desmarcado** («algo menos de latencia; alt‑tab más lento») | `FullscreenMode`, `LastConfirmedFullscreenMode`, `PreferredFullscreenMode` | `0` |
Fuera por placebo en modo Rendimiento (lo ignora): resto de `sg.*`, `bMotionBlur`, `bShowGrass`, resolución dinámica.
Hazlo tú: **NVIDIA Reflex: Activado + Boost** (la clave del .ini no está documentada); comprueba tras reiniciar que «Modo de renderizado» dice Rendimiento.

**Honkai: Star Rail** — solo global: `HKCU\Software\Cognosphere\Star Rail`. En la china, solo el común.
- Requisitos: existe `GraphicsSettings_Model_h2986158309` (REG_BINARY, JSON UTF‑8, normalmente terminado en `\0`) y se puede leer. Si existe `App_Settings_h2319593470`, se avisa «El juego tiene activa una prueba de ajustes; puede ignorar estos cambios» y se deja aplicar (Collapse Launcher bloquea en este caso; aquí solo se avisa, porque no hay fuente pública que lo confirme). Si falta el modelo: «Abre el juego, cambia un ajuste de gráficos y ciérralo».
- Cambios (sustitución en el sitio de `"Clave":valor` sin reserializar; una clave que no exista **no** se añade y su casilla se oculta):
  - **120 FPS** · `FPS` → `120` · `No oficial · riesgo bajo` · **desmarcado**. Texto: «Escribe en el registro el mismo valor que guarda el juego, con el juego cerrado; no toca memoria ni archivos. No es una opción oficial: HoYoverse no lo garantiza. No cambies la opción FPS dentro del juego».
  - **VSync desactivado** · `EnableVSync` → `false`.
  - **Gráficos para rendimiento** (solo baja, nunca sube): `ShadowQuality`→2 Bajo, `LightQuality`→1 Muy bajo, `CharacterQuality`→2 Bajo, `EnvDetailQuality`→1 Muy bajo, `ReflectionQuality`→1 Muy bajo, `BloomQuality`→1 Muy bajo, `SFXQuality`→2 Bajo. `RenderScale` y `AAMode` sin cambios. Escala tomada de Collapse (0 desactivado, 1 muy bajo … 5 muy alto); **por verificar en el juego**.
  - Siempre que se aplique algo del JSON: `GraphicsSettings_GraphicsQuality_h523255858` (DWORD) → `0` (Personalizado; Collapse lo hace igual: sin esto el juego aplica su preajuste).
- Hazlo tú: DLSS si hay NVIDIA.

**Zenless Zone Zero** — solo el común. Hazlo tú: Límite de FPS **Ilimitado**, VSync **No**, calidad baja o personalizada, «Animación de personajes de alta precisión» **Desactivada**.
**Arknights: Endfield** — solo el común. Hazlo tú: FPS **120**, Sincronización vertical **No**, **NVIDIA Reflex Activado**, DLSS «Equilibrado» o TAAU, generación de fotogramas **desactivada** (añade latencia).
**Genshin Impact** — solo el común. Hazlo tú: FPS **60** (máximo oficial a fecha de v5.3), VSync **No**, calidad personalizada baja. Texto: «Genshin no permite más de 60 FPS en PC. Los desbloqueadores escriben en la memoria del juego y violan sus términos: iWinInstaller no lo hace».
Para todos: «Modo Juego» y «Sin grabación en segundo plano» ya están en Latencia › Ajustes de juego (enlace).

### 2.6 Copias de seguridad y Restaurar
- Antes de aplicar: `%LOCALAPPDATA%\iWinInstaller\Juegos\copias\<id>\<aaaaMMdd-HHmmss>\manifest.json` `{format:"iWinInstaller-juegos-copia",version:1,game,at,items:[{kind:"file"|"reg-binary"|"reg-dword"|"reg-string",target,existed,data,file}]}`; `data` en base64 (binario), número (DWORD) o texto; `file` = nombre del archivo copiado **en esa misma carpeta**. Para la GPU se guarda la cadena entera.
- **Restaurar** devuelve la última copia entera (incluido el `.ini` completo) y, si el valor no existía, lo borra. Solo con el juego cerrado. Aviso: «Se perderán los cambios que hicieras en el juego después de optimizar». Sigue con el resto si un elemento falla y muestra el resultado por línea. Restaurar no crea copia nueva. Se guardan las 10 últimas por juego.
- **Lista blanca al restaurar**: `target` debe ser exactamente la ruta del `.ini` de Fortnite (sin reparse point), un valor de `HKCU\Software\Cognosphere\Star Rail` de los dos nombrados, o un valor de `UserGpuPreferences` cuyo nombre sea un ejecutable del juego detectado; `file` resuelto con `Path.GetFullPath` debe quedar dentro de la carpeta de esa copia y no ser reparse point. Lo demás se ignora.
- Escritura atómica (`.ini` y JSON propios): temporal en la misma carpeta con `FileOptions.WriteThrough`, después `File.Replace` si el destino existe o `File.Move` si no (patrón de `Preferences.Save`).

## 3. Archivos
**Interfaz (C#, sin PowerShell; contexto de usuario, la app es `asInvoker`)** en `src/app/Modules/Games/`, espacio `IWinInstaller.App.Modules.Games`:
- `GameDefinitions.cs` — ids (`fortnite`, `starrail`, `zzz`, `endfield`, `genshin`), nombres, ejecutables, procesos, fuentes, textos («Hazlo tú», avisos) y webs oficiales.
- `GameEnvironment.cs` — `IGameEnvironment`, `WindowsGameEnvironment`.
- `GameLocator.cs` — `Locate(GameDefinition, IGameEnvironment)`; parsers puros `EpicManifest.Parse`, `SteamLibrary.ParseFolders(vdf)`, `SteamLibrary.ParseManifest(acf)`, `HoyoConfig.ParseVersion(ini)`.
- `GameFiles.cs` — `PkgVersion.Parse`, `CheckQuick`, `CheckFullAsync(progress, token)`, `CheckFortnite`.
- `IniDocument.cs` — puro: secciones y claves sin distinguir mayúsculas; `Set` cambia la primera línea `Clave=` de la sección (no toca líneas con prefijo `+`, `-`, `.`, `!`), la añade al final de la sección o crea la sección al final; conserva BOM, codificación (UTF‑8/UTF‑16 por BOM) y saltos de línea.
- `StarRailSettings.cs` — puro: `Decode(byte[])` → (json, terminaEnNul), `Encode`, `TryGetNumber/Bool`, `Replace(json,key,raw)`.
- `GpuPreference.cs` — puro `SetPair(cadena,"GpuPreference","2")` + lectura/escritura.
- `GameTweaks.cs` — `TweakItem` (id, título, etiqueta, actual, nuevo, marcado, oculto) por juego y aplicación con copia.
- `GameBackup.cs` — crear, listar, podar y restaurar con lista blanca.
- `GamesViewModel.cs`, `GameCardViewModel.cs`, `GamesView.xaml(.cs)` (cada archivo < 1.500 líneas, `Size.Tests.ps1`).
- `Modules/Tools/DisplaySettings.cs`: añadir `MaxRefreshFor` (puro).
- `ShellViewModel`, `MainWindow.xaml(.cs)`, `PaletteSearch.cs`, `GamingView.xaml` según § 2.1.

**Versión 5.3**: `iWinInstaller.ps1:52`, `install.ps1` (119, 141, 230), `native/Launcher.cs` (10, 11, 28, 38), `src/app/app.manifest`, `<Version>` del csproj, `tests/check-acceptance.ps1:15`, README (versión actual, `git checkout`/`build_exe -Ref`, tabla de versiones, funciones, estructura) y `CHANGELOG.md` con `## v5.3 — 2026-11-17`.

**Pruebas** `tests/unit/app/GamesTests.cs` (MSTest; el csproj de pruebas ya incluye todo `.cs` de su carpeta): `IniDocument` (BOM/sin BOM, UTF‑16, CRLF/LF, clave nueva, sección nueva, prefijo `+` intacto, resto byte a byte igual), `StarRailSettings` (cambia `FPS`, conserva el resto, `\0` final, clave ausente no se añade), `GpuPreference.SetPair` (conserva otros pares), `PkgVersion` + `CheckQuick` (carpeta temporal, etiquetas falta/tamaño), `EpicManifest`, `SteamLibrary`, `HoyoConfig`, `GameLocator` con entorno en memoria (HoYoPlay gana, ruta sin exe se descarta, global antes que china), `GameBackup` (lista blanca rechaza otra clave, `file` con `..`), `MaxRefreshFor`.

## 4. Riesgos
| Riesgo | Mitigación |
|---|---|
| Baneo | Solo ajustes de usuario (§ 1); nada con el juego abierto; 120 FPS de Star Rail desmarcado y explicado |
| El juego pisa los cambios | Bloqueo con el juego o el lanzador en marcha |
| `.ini` corrupto | Edición por líneas, escritura atómica, copia previa, pruebas |
| JSON de Star Rail cambia | Solo claves existentes; si no se lee, no se toca |
| Copia manipulada | Lista blanca por destino y archivo dentro de su carpeta, sin reparse points |
| Falsos positivos en archivos | Umbral del 5 % y mensaje de «lista desactualizada»; siempre se manda al «Reparar» del lanzador |
| GPU: borrar otros ajustes | Se cambia solo el par `GpuPreference` |
| Rutas no detectadas (Endfield) | «Buscar el ejecutable…»; pendiente de prueba física |
| Sincronización en la nube del juego | Fortnite guarda gráficos en local; se comprueba en la prueba física |

## 5. Verificación
- CI de Windows: compilación y MSTest.
- En la nube: las clases puras (sin WPF ni registro) se compilan y prueban con un proyecto temporal de .NET 8 fuera del repo; es una comprobación extra, no sustituye a la CI.
- Prueba física (pendiente para David): detección de los 5; comprobación rápida y completa; Optimizar y Restaurar en Fortnite (modo Rendimiento, FPS) y Star Rail (FPS 120 en el juego); GPU en Configuración › Pantalla › Gráficos; ejecutable de Endfield.

## 6. Fuera de alcance
Descargar o reparar juegos, unlockers, ReShade, mods, perfiles del driver, HAGS (depende del driver), prioridad de proceso, «optimizaciones de pantalla completa», «Optimizar todos» (cada juego necesita revisar su lista) y las copias `LegacyBridge 2.cs` / `check-icons 2.ps1` del repo.

## 7. Fuentes
PCGamingWiki (Fortnite, Genshin Impact, Zenless Zone Zero); código de Collapse Launcher (`StarRail/RegistryClass/Model.cs`, `StarRailGameSettingsPage.xaml.cs`, `Metadata/PresetConfig.cs`, `InstallManagerBase.PkgVersion.cs`); SteamDB (4732690); archivos `GameUserSettings.ini` públicos de Fortnite.

## 8. Hallazgos de la revisión incorporados
- **Comprensión** (22): firma real de `NavItem` y `GlyphFor`; reutilizar `DisplaySettings`; arranque y parada de las dos páginas; prioridad y persistencia de estados; Hz actuales para `FrameRateLimit`; tamaño sin recorrer el disco; etiquetas falta/tamaño/MD5; esquemas de `estado.json` y de la copia; global antes que china; Endfield sin recursión; Star Rail solo baja calidad; restaurar sigue ante fallos y no crea copia; par `GpuPreference`; renombre en la paleta.
- **Crítica**: GPU sin borrar otros pares y aviso con una sola GPU; pantalla delegada a Sistema (ya confirma en 15 s); texto correcto de Star Rail sobre la opción FPS; lista blanca también del `file` y sin reparse points; procesos de lanzador y anticheat; `pkg_version` desactualizado; Fortnite «comprobación básica»; claves `sg.*` placebo quitadas; pantalla completa exclusiva desmarcada; calidades en texto y por verificar; escritura atómica con `File.Move`; enlace a Modo Juego. La marca A/B de Star Rail **sí** aparece en el código de Collapse (`App_Settings_h2319593470`): se mantiene, pero solo avisa.
- **Preparación** (veredicto IR): no duplicar `DisplayMode`; selector de ejecutable con `OpenFile`; procesos por juego; colores del tema; archivos del renombre; `check-acceptance.ps1` y README en la versión; límite de 1.500 líneas; verificación en la nube aclarada.
