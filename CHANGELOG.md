# Historial de versiones

## v4.9 — 2026-11-09

Novena versión del camino a v5.0: **Mantenimiento y salud**.

### Añadido
- **Liberar espacio**: calcula antes cuánto ocupa cada categoría y pide confirmación antes de borrar. Categorías: temporales de tu usuario y de Windows, descargas de Windows Update ya instaladas, caché de Optimización de distribución, miniaturas, volcados de errores, papelera y descargas antiguas de iWinInstaller.
  - Solo archivos de **más de un día** en una lista cerrada de ubicaciones; **nunca documentos** ni carpetas personales. Lo que está en uso se omite y se cuenta.
  - Las del sistema se limpian con **una sola** solicitud de administrador.
- **Reparar Windows**: DISM (imagen) y SFC (archivos del sistema), con el resultado explicado.
- **Salud del equipo**: espacio, estado de cada disco, desgaste de la batería y reinicio pendiente, más el **informe de batería** de Windows.
- **Informe del equipo** en JSON: sistema, procesador, gráfica, RAM, placa, BIOS y discos. **Sin números de serie, nombre del equipo ni usuario** salvo que marques incluirlos.
- Las tarjetas de espacio, discos y batería del Inicio abren ya Mantenimiento, y la paleta encuentra «liberar espacio», «reparar», «sfc»…
- Línea de comandos: `-Clean [-Categories a,b]` (solo estima) y `-Clean -Yes` (libera), y `-MachineReport <ruta> [-IncludeSensitive]`.

### Archivos y pruebas
- `src/engine/14-Maintenance.ps1`, `src/app/Modules/Maintenance/**`, navegación, paleta, `iWinInstaller.ps1` (CLI) y `docs/cli.md`.
- Pester en carpetas de prueba: solo se borra lo de más de un día, las categorías desconocidas se rechazan y el informe no incluye datos sensibles sin marcarlo.
- **Afecta a Windows x86/x64/ARM64 por igual**. Pendientes físicos: SMART real, batería y reparación en un equipo con problemas.

## v4.8 — 2026-11-09

Octava versión del camino a v5.0: **paleta de búsqueda** para llegar a cualquier cosa con el teclado.

### Añadido
- **`Ctrl + K`** (o el botón **Buscar…** de la barra lateral) abre una paleta: escribe «resolución», «hibernar», «ssh», «defender», «diagnóstico» o el nombre de cualquier app del catálogo y pulsa Enter.
  - Busca sin tildes ni mayúsculas, con sinónimos en español y todas las palabras; prioriza el título y las acciones de la app frente a apps con nombres parecidos.
  - Las apps del catálogo llevan a Instalar con la búsqueda ya hecha; «Informe de la última instalación», «Reanudar lote pendiente», «Abrir Windows Update» y el resto de secciones se abren directamente.
  - Flechas para moverse, Enter para abrir, Esc para cerrar. Nunca ejecuta nada que necesite confirmación: solo abre el sitio donde hacerlo.

### Archivos y pruebas
- `src/app/Shell/Palette/**` (búsqueda, acciones y ventana), `ShellViewModel.cs`, `MainWindow.xaml(.cs)`.
- MSTest con las búsquedas de referencia del plan (SC-003): «frecuencia», «resolución», «defender», «ssh» y «git» dan el destino correcto en el primer resultado.
- **Afecta a Windows x86/x64/ARM64 por igual**.

## v4.7 — 2026-11-09

Séptima versión del camino a v5.0: todo lo de la ventana clásica está ya en la interfaz nueva.

### Añadido
- **Sistema**: resolución y frecuencia de cada monitor (con **Mantener / Volver** y vuelta automática al modo anterior a los 15 s, como Windows) y energía del plan activo (apagar pantalla, suspender, hibernar tras y activar o desactivar la hibernación).
- **Seguridad**: estado de Microsoft Defender u otro antivirus, firmas y últimos análisis, amenazas recientes, análisis rápido, completo o de una carpeta y actualizar firmas. Los análisis corren en el motor y no bloquean la ventana.
- **Acceso remoto · Vincular equipos**: preparar el servidor SSH (solo claves), comandos para Mac o Windows, permitir la red local privada, autorizar una clave pública (rechaza claves privadas) y ver los equipos autorizados.
- **Ajustes**: actualización automática de iWinInstaller, buscar versión nueva, exportar diagnóstico y abrir la carpeta de registros.
- Motor: `power.*`, `security.*`, `link.*` y `app.*` (`src/engine/13-Tools.ps1`).

### Cambiado
- Las funciones de Vincular equipos pasan del script principal al motor, sin cambios en su lógica (mismos scripts de cortafuegos y permisos de clave).
- La **ventana clásica** ya no es necesaria para nada. Se puede abrir desde Ajustes durante la transición; se retira en v5.0.

### Archivos y pruebas
- `src/app/Modules/Tools/**` (incluye `DisplaySettings.cs`, la misma API de user32 que la ventana clásica), `src/engine/13-Tools.ps1`, navegación y `Ajustes`.
- Pester: límites de energía, claves privadas o mal formadas rechazadas, autorizar una clave una sola vez y acciones de seguridad no válidas.
- **Afecta a Windows x86/x64/ARM64 por igual**. CI en x64 y ARM64 y proceso x86. Pendientes físicos: monitores reales, hibernación y SSH desde otro equipo.

## v4.6 — 2026-11-09

Sexta versión del camino a v5.0: **Instalar** pasa a la interfaz nueva con todo lo que hacía la ventana clásica.

### Añadido
- **Catálogo en la interfaz nueva**: las 427 entradas agrupadas por sección, grupo y subsección, con el recuadro «Cuál elegir» y la comparativa de cada app. Lista virtualizada (fluida aunque esté todo visible), iconos con la misma caché que la ventana clásica y la etiqueta «Terminal» en las herramientas de consola.
- **Búsqueda por palabras** (nombre, uso, grupo, comparativa o id) y filtros por sección, grupo y estado (marcadas, faltan, instaladas, por configurar).
- **Perfiles**: elegir, guardar, eliminar, importar y exportar `.iwin.json`. Las apps ya instaladas no se marcan.
- **Lotes**: resumen previo (dependencias, contexto, ajustes, reinicios, espacio y conexión), progreso por app, **Pausar al terminar esta app** (la pausa llega también al proceso de administrador entre aplicaciones), **Reanudar lote**, **Desinstalar** o **Deshacer** por fila o las marcadas, **Abrir** (también en terminal) y **Verificar**.
- **Pasos y notas**: pasos marcables, tu nota y **Comprobar** (detección técnica), con el mismo seguimiento que la ventana clásica.
- **Informe al terminar**: una tarjeta por app con motivo, código, qué hacer y líneas del registro. **Copiar informe** y **Reintentar fallidas**; las de instalación manual no se reintentan.
- Motor: comandos `install.preflight`, `batch.run` (instalar, desinstalar, actualizar o reanudar), `profiles.*`, `postinstall.*` y `app.open` (`src/engine/12-Install.ps1`). `report.last` incluye el texto listo para copiar.

### Cambiado
- `Resume-IwinBatch` pasa del script principal al motor (`08-Batch.ps1`), sin cambios.
- Las tarjetas «Lotes de instalación» del Inicio abren ya Instalar.
- La ventana clásica sigue disponible para Sistema, Acceso remoto y Seguridad hasta la v4.7.

### Archivos y pruebas
- `src/app/Modules/Install/**`, `Shell/DialogService.cs`, `Engine/EngineOperation.cs`, `src/engine/12-Install.ps1`, `01-Core.ps1` y `lifecycle.ps1` (pausa desde la interfaz), `09-Contract.ps1`.
- MSTest con el `apps.json` real (sin ids repetidos, notas por subsección, reglas de desinstalar, iconos, estados tras un lote, informe y pasos). Pester de los comandos (ids desconocidos, plan, operaciones no válidas, pasos guardados y archivo de pausa).
- **Afecta a Windows x86/x64/ARM64 por igual**. CI en x64 y ARM64 y proceso x86.

## v4.5 — 2026-11-08

Quinta versión del camino a v5.0: **Actualizaciones** pasa a la interfaz nueva, y ahora ves y decides qué se actualiza.

### Añadido
- **Actualizaciones**: lista de las apps con versión nueva (instalada → disponible), con casillas para elegir cuáles y **Actualizar seleccionadas**. Las que necesitan su asistente lo avisan. El progreso y el resultado aparecen en cada fila, y se puede cancelar.
- **«Mantener esta versión»**: excluye una app de forma persistente (`%LOCALAPPDATA%\iWinInstaller\exclusiones.json`). Se respeta en la lista, en **Actualizar todo** de la ventana clásica, en `-Update` y en la actualización programada.
- **Actualización programada (opcional, desactivada)**: cada día o cada domingo a la hora que elijas. Corre con tu usuario, omite las excluidas y las que necesitan asistente, no reinicia Windows y deja el informe.
- **Línea de comandos**: `-Updates -List [-Json]`, `-Updates -Exclude <id>` / `-Include <id>`, `-Update -Scheduled` y `-Status [-Json]` (las tarjetas del Inicio). Documentado en `docs/cli.md`.
- La tarjeta **Actualizaciones de apps** del Inicio abre ya esta sección.

### Archivos y pruebas
- `src/engine/10-Updates.ps1` (exclusiones, lista, aplicar, programar y comandos `updates.*`), `06-Tweaks.ps1` (`-Update` respeta exclusiones), `iWinInstaller.ps1` (parámetros nuevos), `src/app/Modules/Updates/**`, `Core/Converters.cs`, navegación.
- Pester: exclusiones (guardar, quitar, archivo dañado, ids no válidos), lista vacía frente a «no se pudo comprobar» y omisión de excluidas e interactivas en modo programado. MSTest: lectura de la lista y de la programación, y resultados por app.
- **Afecta a Windows x86/x64/ARM64 por igual**. CI en x64 y ARM64 y proceso x86.

## v4.4 — 2026-11-08

Cuarta versión del camino a v5.0: primera pantalla de la **interfaz nueva**, con el estado del PC.

### Añadido
- **Interfaz nueva en C#** (WPF sobre .NET Framework 4.8, que ya viene con Windows): ventana negra con navegación lateral, tamaño de 70 a 200 % (A− / A+, `Ctrl + rueda`, `Ctrl + + / − / 0`, se recuerda), versión e Instagram siempre visibles.
- **Inicio · Estado del PC**: tarjetas que se rellenan en segundo plano, sin bloquear la ventana:
  - **Actualizaciones de apps**: cuántas ofrece WinGet y cuáles.
  - **Windows Update**: cuándo buscó por última vez.
  - **Protección antivirus**: Defender u otro antivirus, tiempo real y antigüedad de las firmas.
  - **Espacio en disco**: aviso por debajo del 10 % o de 15 GB libres.
  - **Salud de los discos**: estado que informa Windows de cada disco físico.
  - **Batería**: desgaste frente a la capacidad original. No aparece en equipos sin batería.
  - **Reinicio pendiente** y **lotes sin terminar**.
  - Cada tarjeta distingue *Correcto*, *Requiere atención* y *No se pudo comprobar* (con el motivo real); nunca da por bueno lo que no pudo comprobar. **Abrir** lleva a la solución, y **Comprobar de nuevo** (o `F5`) repite todo.
- **Instalar, Actualizaciones, Sistema, Acceso remoto y Seguridad** se abren todavía en la **ventana clásica**, con todas sus funciones. Pasarán a la interfaz nueva en v4.5–v4.7.
- Motor: comando `status.collect` y lectura de `winget upgrade` en cualquier idioma de Windows (`src/engine/10-Updates.ps1`, `11-Status.ps1`).
- Pruebas: 17 pruebas de la interfaz (MSTest: reglas de las tarjetas, eventos del motor, lector incremental, zoom y preferencias), Pester de la lectura de WinGet en inglés y español, y una prueba de CI que abre la ventana nueva, rellena el Inicio con el motor real y completa la prueba de la ventana clásica.

### Cambiado
- El lanzador abre la interfaz nueva. Si falta (un paquete construido sin el SDK de .NET), abre la ventana clásica como antes.
- **Puerta de publicación nueva `app`**: compila la interfaz y pasa sus pruebas en Windows.

### Archivos y pruebas
- `src/app/**` (proyecto `iWinInstaller.App.csproj`), `tests/unit/app/**`, `.github/workflows/app.yml`, `src/engine/10-Updates.ps1`, `src/engine/11-Status.ps1`, `native/Launcher.cs`, `scripts/build_exe.ps1` y `release.yml` (la publicación exige la interfaz compilada).
- **Afecta a Windows x86/x64/ARM64**: la interfaz es AnyCPU. En ARM64 corre nativa con .NET Framework 4.8.1 y emulada con 4.8. CI en x64 y ARM64; el lanzador x86 abre la misma interfaz.

## v4.3 — 2026-11-08

Tercera versión del camino a v5.0. La app pasa a una carpeta que solo pueden modificar los administradores.

### Cambiado
- **Instalación en `Archivos de programa\iWinInstaller`**: antes estaba en `%LOCALAPPDATA%\Programs\iWinInstaller`.
  - Antes: cualquier programa que se ejecutara con tu usuario podía modificar la app sin avisar.
  - Ahora: hace falta permiso de administrador. El instalador lo pide **una vez** (Setup.exe, primera apertura del ZIP o BAT) y la app se abre después **sin** permisos especiales.
- **Registro del equipo** en Aplicaciones instaladas y acceso del menú Inicio para todos los usuarios. Desinstalar pide permiso de administrador.
- **Actualización automática opcional como SYSTEM**: activarla o desactivarla pide permiso una vez. La tarea solo ejecuta el actualizador instalado, que descarga de la release oficial y comprueba SHA256. Al ser SYSTEM, ya no depende de que haya una sesión de usuario con la preferencia guardada.

### Añadido
- **Migración automática**: al instalar v4.3 se retiran la carpeta, el registro y el acceso del menú Inicio de la instalación por usuario anterior. Si tenías activada la actualización automática, se vuelve a crear como tarea del sistema. **Notas, perfiles, lotes, informes y preferencias se conservan**, porque viven en `%LOCALAPPDATA%\iWinInstaller`, que no se toca.
- Pruebas en CI: instalación real en Program Files, retirada de la copia anterior, que ningún grupo de usuarios normales tenga permisos de escritura en la carpeta y tarea de actualización como SYSTEM.

### Corregido
Hallado en un diagnóstico real de v4.0 (Windows 11 Pro 10.0.26300, lote de 78 apps):
- **PowerShell 7 fallaba con 0x8A150113** («la configuración del sistema no admite la instalación de este paquete») y no se probaba la alternativa. Ahora se reintenta con el paquete **MSIX oficial**, igual que ya se hacía con 0x80070005, y el informe explica el código.
- **EarTrumpet fallaba con 0x80072EFD** (no pudo conectar con el servidor de descarga). Ahora los fallos de red puntuales (0x80072EFD, 0x80072EE2, 0x80072EE7, 0x80072EFE) **se reintentan una vez** a los 15 s, respetando la pausa, y el informe dice qué revisar (conexión, VPN, proxy, cortafuegos, fecha y hora).
- **Motivo del informe más útil**: muestra el mensaje del instalador (p. ej. «InternetOpenUrl() failed», «does not support…») en lugar de la línea interna `app · codigo N`.
- Process Explorer (0x8A150011, huella distinta) es un cambio del fabricante en WinGet: el informe ya lo explicaba y no cambia.

### Pendiente
- **Firma con SignPath**: el paso de firma se añadirá cuando SignPath apruebe la solicitud. Hasta entonces se publica sin firma, con procedencia de GitHub (`gh attestation verify`).

### Archivos y pruebas
- `install.ps1`, `installer-header.bat`, `native/Launcher.cs`, `native/setup.manifest` (Setup.exe pide administrador), `scripts/build_exe.ps1`, `lifecycle.ps1` (`Get-IwinInstallDir`, `Set-IwinAutoUpdate`, `Test-IwinAppOpen`), `iWinInstaller.ps1` (modo `-AutoUpdate` como SYSTEM), `tests/check-native.ps1`, `tests/check-embedded-install.ps1`, README y SECURITY.
- **Afecta a Windows x86/x64/ARM64 por igual**: la ruta usa la carpeta de programas nativa también desde el lanzador de 32 bits. Pruebas reales en CI Windows x64/ARM64 y proceso x86.

## v4.2 — 2026-11-08

Segunda versión del camino a v5.0. Por dentro, el programa queda dividido por áreas. Por fuera, la app hace lo mismo, con dos novedades para scripts: `-Check -Json` y el contrato del motor.

### Añadido
- **`-Check -Json`**: el informe del equipo en JSON estable (versión, WinGet, total, cuántas faltan y el estado de cada app), sin líneas de registro mezcladas. Documentado en `docs/cli.md`, con los códigos de salida de cada modo.
- **Contrato interfaz ↔ motor** (`-EngineCommand` con `-EngineRequest`, `-EngineResponse` y `-EngineEvents`): petición y respuesta en JSON y eventos de progreso en JSONL, con `done` siempre al final y códigos 0/2/3/4/10. Comandos iniciales: `catalog.inventory`, `batch.pending` y `report.last`. Es la base de la nueva interfaz de v4.4.
- **Pruebas unitarias nuevas**: contrato del motor (peticiones inválidas, versión de contrato, JSON roto, inventario con apps no comprobables) y una barrera que exige BOM en los scripts con texto no ASCII, porque PowerShell 5.1 los leería mal.

### Cambiado
- **Motor dividido en `src/engine/01-Core.ps1` … `09-Contract.ps1`**: el código se ha movido sin cambios, se carga en el mismo orden y comparte el mismo ámbito que antes. `iWinInstaller.ps1` pasa de 4.074 a unas 1.700 líneas.
- **Ventana y diálogos en `src/ui/*.xaml`**: antes estaban incrustados en el script.
- **Integridad**: el manifiesto `integrity.sha256` incluye ahora todo `src/`, y el lanzador comprueba **cada línea** del manifiesto, no solo una lista fija. Un archivo del motor o de la interfaz alterado o ausente impide abrir la app, con el aviso de reinstalar.
- `.gitattributes` excluye del paquete de la app las carpetas de desarrollo (`specs/`, Spec Kit, `docs/`, esquemas).
- **Afecta a Windows x86/x64/ARM64 por igual**: mismo código para las tres arquitecturas.

### Archivos y pruebas
- `iWinInstaller.ps1`, `src/engine/*.ps1`, `src/ui/*.xaml`, `native/Launcher.cs`, `scripts/build_exe.ps1`, `docs/cli.md`, `tests/lib/IwinSource.ps1` y las pruebas `check-*` que leían funciones del script principal.
- División comprobada en macOS: uniendo los trozos se reproduce el original byte a byte. Pruebas reales en CI Windows x64/ARM64 y proceso x86: instalador, aceptación, EXE nativo y unitarias.

## v4.1 — 2026-11-08

Primera versión del camino a v5.0 (plan en `specs/001-centro-de-control/`). No cambia nada de lo que ves en la app: refuerza cómo se comprueba y se publica cada versión.

### Añadido
- **Licencia MIT** (`LICENSE`). Es requisito para pedir la firma gratuita de SignPath Foundation, que quitará el aviso «Editor desconocido» de SmartScreen.
- **Política de firma de código** en `docs/code-signing-policy.md`, enlazada desde README y SECURITY.
- **Esquemas del catálogo** (`src/catalog/schema/apps.schema.json` y `profiles.schema.json`): cada entrada se valida antes de publicar. Se rechazan los campos desconocidos (erratas), las apps de WinGet sin id, las descargas directas sin firma esperada y las subsecciones sin comparativa.
- **Pruebas unitarias con Pester 5** (`tests/unit/`): sintaxis de todos los scripts con el analizador de PowerShell 5.1, esquema del catálogo, ids únicos, dependencias y perfiles que apuntan a entradas existentes.
- **Comprobación de la release publicada** (`tests/check-release.ps1`): la release es la última, tiene notas y sus tres descargas, cada huella SHA256 coincide con la que publica GitHub y los enlaces fijos del README responden.

### Mejorado
- **Publicación**: la prueba `unit` pasa a ser la octava puerta obligatoria, y un job `verify` comprueba la release justo después de publicarla.
- **Aviso de releases que faltan**: el workflow programado `release-check.yml` revisa cada 6 horas que el tag más alto tenga su release. Si falla, GitHub avisa por correo. Esto evita que se repita lo de v3.7–v3.8, cuando los tags no tuvieron release y la actualización siguió ofreciendo v3.6.
- `windows.yml` y `arm.yml` quedan documentados como diagnósticos que no deciden la publicación. Las 8 puertas no tienen `continue-on-error`.
- **Afecta a Windows x86/x64/ARM64 por igual**: no cambia el programa, solo la versión visible.

### Archivos y pruebas
- `LICENSE`, `docs/code-signing-policy.md`, `src/catalog/schema/*.json`, `tests/unit/**`, `tests/check-release.ps1`, `.github/workflows/unit.yml`, `release-check.yml`, `release.yml`, versión en `iWinInstaller.ps1`, `install.ps1`, `native/Launcher.cs` y `tests/check-acceptance.ps1`.
- Catálogo (427 entradas) y perfiles comprobados contra las reglas del esquema en macOS. Pester y la comprobación de la release se ejecutan en GitHub Actions (Windows y Ubuntu).

## v4.0 — 2026-11-03

### Añadido
- **MyASUS**, **G-Helper** y **OCCT Personal** en el catálogo general (427 entradas). Sin perfiles exclusivos de portátil.
- **Guía de puesta a punto en MyASUS → Pasos y notas**: preparar Windows 11 y drivers offline en otro equipo, instalación de Windows previa a iWinInstaller, Windows Update, soporte por modelo/serie, ASUS System Control Interface, firmware manual, batería, seguridad y pruebas físicas.

### Mejorado
- **Guías de Armoury Crate y NVIDIA App**: un solo gestor ASUS, Game Ready o Studio, gráfica integrada en equipos híbridos y comprobaciones reales. G-Helper queda opcional, sin selección automática por fabricante.
- **Afecta a Windows x86/x64/ARM64**: catálogo común y perfiles anteriores intactos. G-Helper y OCCT se declaran x64 conforme a sus manifiestos; no se promete soporte de esas herramientas para otras arquitecturas.

### Archivos y pruebas
- `apps.json`, versiones de `iWinInstaller.ps1`, `install.ps1`, `native/Launcher.cs`, fixture de aceptación y README/CHANGELOG.
- JSON, ids únicos, referencias y conservación de perfiles comprobados en macOS. Manifiestos de G-Helper y OCCT consultados directamente en microsoft/winget-pkgs; MyASUS verificado en Microsoft Store.
- Pruebas reales de instalador y WPF en CI Windows x64/ARM64 y proceso x86; el resultado se registra en Obsidian. Hardware ASUS físico, drivers y firmware pendientes del portátil real.
- Incluye los cambios v3.7–v3.9 que todavía no estaban disponibles en la última release pública v3.6.

## v3.9 — 2026-10-30

> Primera release desde v3.6: incluye también **v3.7** (panel Seguridad, arreglos del instalador, directivas de usuario, PowerShell 7 y gsudo) y **v3.8** (Vincular equipos). Sus tags se crearon, pero sus releases no llegaron a publicarse, por lo que la actualización automática seguía ofreciendo v3.6.

### Añadido
- **Informe al terminar la instalación**: si algo falla o necesita tu intervención se abre una sección con una tarjeta por aplicación: **motivo** en lenguaje claro, **código** del instalador (decimal o `0x…`), **qué hacer** y las líneas relevantes del registro (sin el texto de licencias). Separa **Falló**, **Acción manual** (Norton VPN, AMD Software, Samsung Magician, asistentes) y **Pendiente** (lote pausado), y lista lo que requiere reiniciar.
  - Botones **Reintentar fallidas** (no reintenta las manuales), **Copiar informe** (texto listo para pegar en un chat o correo) y **Guardar diagnóstico**. `Esc` lo cierra.
  - **⋯ › Informe de la última instalación** lo vuelve a abrir. Se guardan el último y los diez anteriores en `%LOCALAPPDATA%\iWinInstaller\informes`.
  - El **TXT de diagnóstico empieza por ese resumen** (`=== INFORME DE INSTALACIÓN ===`) antes del registro completo, y el registro termina con una línea por fallo.
  - Explicación de los códigos documentados de WinGet (`0x8A150008` descarga, `0x8A150011` huella, `0x8A150101`/`0x8A150103` app o archivo en uso, `0x8A150105` disco lleno…), `0x80070005` (acceso denegado) y MSI (1602, 1603, 1618, 1625).
- Campo `interactive` del catálogo: los instaladores que solo tienen asistente se abren con aviso («complétalo para continuar») y esperan hasta 1 h en lugar de agotar los 15 min.
- Campo `detectPaths` del catálogo: detección por carpeta de kits portátiles sin entrada en Programas.

### Corregido
- **Antivirus**:
  - **Bitdefender Free** usaba su descargador sin modo silencioso: se quedaba esperando con el asistente abierto y acababa como fallo. Ahora avisa de que hay que completar el asistente y espera. Se quita `--scope machine`, que su instalador no declara.
  - **Emsisoft Emergency Kit** estaba como app de usuario, pero se extrae en `C:\EEK` y necesita administrador; además no aparece en Programas, por lo que nunca se confirmaba. Pasa al lote de administrador y se detecta por su carpeta.
  - **Panel Seguridad**: un análisis o una actualización de firmas que terminaba rápido podía mostrarse como «no se completó (código )», porque PowerShell 5.1 pierde el código de salida si no se guarda el handle del proceso al lanzarlo.
- **Códigos de salida perdidos** en otros tres puntos por la misma causa: comandos elevados cuando la app ya es administrador (WSL, punto de restauración) y el actualizador sin ventana (`-Update`/`-Silent`), que podía anunciar «Actualización incompleta» tras actualizar bien.
- **PowerShell 7**: tras el reintento con el paquete MSIX se relee también el inventario de paquetes de la Store, para confirmar la instalación aunque el comando `pwsh` aún no esté en el PATH.
- **Catálogo revisado contra el repositorio oficial de WinGet** (382 paquetes):
  - **Zed** pedía instalación para todo el equipo y su instalador solo es por usuario: WinGet no encontraba instalador. Pasa a usuario.
  - **Zen Browser**: se quita `--scope machine`, que su instalador no declara.
  - **13 apps** marcadas como «de usuario» cuyo instalador solo es para el equipo (TickTick, MongoDB Compass, Podman Desktop, ScreenToGif, Quick Share, Monitorian, komorebi, Keyviz, Patch My PC, Viber, Lunacy, Upscayl, Seelen UI) pasan al lote de administrador: antes podían pedir permiso una por una o fallar con una cuenta estándar.
  - **Battle.net** y **Razer Synapse 4** solo tienen asistente: se marcan como interactivos.
- El resumen «Terminado con fallos en…» ya no repite nombres.
- README: el catálogo tiene 424 entradas (decía 421).

### Archivos y pruebas
- `iWinInstaller.ps1` (panel `ReportPanel`, menú `MReport`, `Install-WingetPackage`, `Test-LocalApp`, `Export-Diagnostic`, handles de proceso), `lifecycle.ps1` (`New-IwinInstallReport`, `Format-IwinReportText`, `Get-IwinCodeHint`, resultados en `Complete-IwinItem`), `apps.json`, versiones en `install.ps1`, `native/Launcher.cs` y `tests/check-acceptance.ps1`, README.
- Nuevas regresiones en `tests/check-reliability.ps1`: informe construido con el registro real del 30/10 (PowerShell 7 `0x80070005`, Inicio sin Bing denegado, Norton VPN manual, gsudo correcto, WSL con reinicio), lectura solo desde el inicio de la pasada, guardar y reabrir, formato de códigos y detección por carpeta. El autotest de la ventana pinta el informe con datos de ejemplo.
- Solo Windows 10/11 (x86, x64, ARM64); sin variantes macOS/iOS. Validado en el Mac: JSON y XAML bien formados y catálogo contrastado con `microsoft/winget-pkgs`. CI de Windows en GitHub antes de publicar. Pendiente de prueba física: Bitdefender y Emsisoft en un PC real y el informe tras una instalación con fallos.

## v3.8 — 2026-10-30

### Añadido
- **Vincular equipos** (icono de enlace en la barra superior o **⋯ › Vincular equipos**): controla este PC desde un Mac u otro portátil Windows por SSH, sin contraseñas.
  1. **Este PC**: estado del servidor SSH, IP de Tailscale (desde cualquier red), IP local y equipos autorizados. **Preparar este PC** aplica «Control remoto por SSH» (OpenSSH Server, solo claves, PowerShell como shell) con una sola solicitud de administrador.
  2. **Comando para el otro equipo**, listo para copiar (Terminal del Mac o PowerShell de Windows): crea la clave `ed25519` si falta, añade un alias `Host <nombre-del-pc>` en `~/.ssh/config` con `ServerAliveInterval` y copia la clave pública al portapapeles.
  3. **Autorizar equipo**: pegas la clave en la app, que la valida (rechaza claves privadas) y la añade al archivo correcto (`administrators_authorized_keys` con permisos protegidos, o `~\.ssh\authorized_keys` si no eres administrador).
  4. **Guía para conectar**: `ssh <alias>`, `scp`, Claude (conexión SSH con el alias), VS Code Remote - SSH, KDE Connect y Sunshine/Moonlight.
- Casilla **Permitir también desde la red local**: abre el puerto 22 solo a la subred local en redes privadas. Por defecto solo se admite Tailscale (`100.64.0.0/10`).

### Archivos y pruebas
- `iWinInstaller.ps1` (panel `LinkPanel`), nota de `remotessh` en `apps.json`, versiones en `install.ps1`, `native/Launcher.cs` y `tests/check-acceptance.ps1`, README.
- Windows 10/11 como servidor; Mac (macOS) o Windows como cliente. Validado en el Mac: XAML bien formado. Pendiente: CI Windows y prueba manual Mac → PC por Tailscale y por red local.

## v3.7 — 2026-10-30

> Sin release propia: sus pruebas se corrigieron después del tag y se publica dentro de **v3.8**.

### Añadido
- **Panel Seguridad** (escudo en la barra superior y **⋯ › Seguridad (antivirus de Windows)…**): estado de Microsoft Defender (tiempo real, protección contra alteraciones, firmas, último análisis), análisis rápido, completo o de una carpeta, actualización de firmas y amenazas recientes. Los análisis corren en un proceso aparte y no bloquean la ventana. Si hay otro antivirus residente, lo indica y deja Defender para análisis manuales. No instala nada nuevo.
- La sección **Antivirus y antimalware** del catálogo (Bitdefender Free, Malwarebytes, Emsisoft Emergency Kit, AdwCleaner) entra en esta versión.

### Corregido
- **Instalador/actualizador**: «Acceso denegado» al sustituir `%LOCALAPPDATA%\Programs\iWinInstaller`. Ahora espera a que terminen los procesos de la app que usan la carpeta, reintenta el cambio de nombre (antivirus/indexador) y, como último recurso, actualiza los archivos dentro de la carpeta existente.
- **Lanzador**: ya no muestra un error cuando Windows cierra la app al apagar, reiniciar o cerrar sesión (códigos `0x40010004` y `0xC000013A`).
- **Inicio sin resultados de Bing** y **Brave limpio**: fallaban con «Se denegó el acceso» porque `HKCU\Software\Policies` exige administrador. Se pide permiso una sola vez y se escribe en la rama del usuario actual (`HKEY_USERS\<SID>`), también al deshacer.
- **PowerShell 7**: si el MSI devuelve `0x80070005` (acceso denegado), se reintenta con el paquete MSIX oficial.
- **Apps instaladas marcadas como fallidas** (p. ej. gsudo): el lote podía perder un evento si la ventana leía el archivo a la vez. Se escriben con reintento y, si falta un evento, se comprueba en el equipo antes de marcar el fallo.

### Archivos y pruebas
- `iWinInstaller.ps1`, `lifecycle.ps1`, `install.ps1`, `native/Launcher.cs`, versión en `tests/check-acceptance.ps1`, README.
- Solo Windows 10/11 (x86, x64, ARM64); sin variantes macOS/iOS. Validado en el Mac: XAML bien formado y balance de llaves. Pendiente: CI Windows y prueba manual (actualizar con la app abierta, Brave limpio sin admin, PowerShell 7, panel Seguridad).

## v3.6 — 2026-10-29

### Añadido
- **Subsecciones con comparativa** en todas las categorías con apps que se solapan: 84 subsecciones (Quitar telemetría y bloatware, Drivers de NVIDIA, Terminales, Prompt, Node.js, Python, Lanzadores unificados, Basados en Chromium/Firefox, IA local, Editores de código, Compresores, Capturas, VPN, Gestores de contraseñas…). Cada cabecera muestra **«Cuál elegir»**: cuándo compensa una, otra o ambas, y qué conflictos evitar.
- **Línea comparativa en cada app agrupada**: qué ofrece frente a sus alternativas y qué no. Se puede buscar por ese texto.
- **Resolución y tasa de refresco del monitor**: botón de monitor en la barra superior y **⋯ › Resolución y frecuencia de la pantalla…**. Lista monitores activos, resoluciones y frecuencias admitidas (misma profundidad de color), prueba el modo antes de aplicarlo y vuelve al anterior si no se confirma en 15 s.
- **Energía en el mismo panel** («Pantalla y energía»): apagar la pantalla tras, suspender tras, hibernación activada/desactivada e hibernar tras, sobre el plan activo (incluido alto rendimiento), con corriente y con batería. Activar o quitar la hibernación pide administrador; los tiempos no.

### Cambiado
- `apps.json` reordena cada categoría para que las apps de una subsección queden juntas; ids, perfiles e instalaciones no cambian. Campos nuevos opcionales: `subgroup`, `compare` y `subgroupNote` (en la primera app de cada subsección).
- `-Check` en consola encabeza con «Categoría › Subsección».

### Archivos y pruebas
- `apps.json`, `iWinInstaller.ps1` (clase `IwinDisplay` sobre `EnumDisplaySettings`/`ChangeDisplaySettingsEx`, panel Pantalla, cabeceras de grupo), versiones de `install.ps1`, `native/Launcher.cs` y `tests/check-acceptance.ps1`, README.
- Validado en la nube: JSON y referencias de ids de las subsecciones. Pendiente CI Windows (x64/ARM64) y prueba manual del cambio de modo en un PC con monitor real.

## v3.5 — 2026-10-27

### Añadido
- **Brave normal y Brave limpio** en Aplicaciones → Navegadores. Ambos usan el instalador oficial `Brave.Brave`; la opción limpia añade políticas locales del usuario para desactivar Rewards, Wallet/Web3, VPN, Leo, noticias y Talk, manteniendo Shields y Sync. No desbloquea Brave Origin ni modifica licencias.
- **Aspecto del perfil principal**: tema oscuro/ultraoscuro, fondo negro fijo, tarjetas y anuncios de nueva pestaña apagados, sin botones promocionales ni barra de marcadores. Los perfiles adicionales no se copian ni cambian de aspecto. Los widgets de búsqueda/reloj pueden requerir ajuste manual según la versión de Brave.
- **Deshacer** recupera las políticas anteriores y únicamente los valores visuales afectados. Conserva cuentas, contraseñas, marcadores y preferencias ajenas. Exige cerrar Brave antes de aplicar o restaurar; no termina procesos por su cuenta.

### Archivos y pruebas
- Windows 10/11 x86, x64 y ARM64 según disponibilidad del instalador oficial. Sin variantes macOS/iOS.
- Archivos: `apps.json`, `iWinInstaller.ps1`, `lifecycle.ps1`, versiones de `install.ps1` y `native/Launcher.cs`, README, regresión `tests/check-brave-clean.ps1` y workflow bootstrap.
- Instalador incrustado: se conserva `install.ps1` sin BOM para evitar que PowerShell interprete un carácter invisible como parte de la primera orden.
- Regresión aislada: aplicación y verificación de políticas, conservación de datos ajenos, restauración de valores/ausencia, rechazo de JSON inválido y de perfiles abiertos. CI Windows x64/ARM64 pendiente antes de publicar.
- Widevine requiere aceptación del usuario dentro de Brave; no se activa ni acepta un contrato automáticamente. La configuración puede mostrar «Administrado por tu organización» y se revierte desde Brave limpio → Deshacer. Brave normal no deshace una limpieza existente.

## v3.4 — 2026-10-26

### Corregido
- **Apagar todas las luces RGB no apagaba nada**: con OpenRGB 1.1, `--list-devices` solo devuelve los nombres y los modos salen con `--list-detailed`, que entrecomilla con `'`. El script no encontraba ningún modo y no enviaba órdenes. Ahora lee `--list-detailed` y entiende las dos comillas.
- **Servicio de OpenRGB**: si está instalado, es él quien tiene el hardware. El script le envía las órdenes como cliente (`--nodetect`, conexión automática a 127.0.0.1:6742) en lugar de abrir una segunda detección. El ajuste deja el servicio en automático y lo arranca, y el script reintenta durante 2 minutos mientras el servicio detecta al arrancar Windows.
- **Tiras ARGB de la placa (JRAINBOW de MSI y similares)**: OpenRGB las crea con 0 LED, así que el negro no les llegaba. Ahora se les da tamaño 60 antes de apagarlas, con una orden por zona para que un tamaño no admitido no anule el resto.

### Incluye v3.3 (no se publicó aparte)
- **Control remoto por SSH (Tailscale)**, solo con clave y con el puerto 22 abierto solo para Tailscale.
- **Activar monitor virtual**: crea el monitor de Virtual Display Driver, porque el paquete de WinGet solo dejaba los archivos.

### Guías posteriores
- **Acceso remoto documentado dentro de la app** (panel «Después de instalar»): monitor virtual y elección de pantalla en Sunshine, audio de Sunshine, emparejar Moonlight por IP de Tailscale, KDE Connect por IP con red Privada y portapapeles automático, Autologon tras cambiar el nombre del equipo y SSH con tu propia clave. Sin datos de ningún equipo concreto.

### Archivos y pruebas
- **Archivos**: `iWinInstaller.ps1`, `install.ps1`, `native/Launcher.cs`, `README.md`, `tests/check-acceptance.ps1`, `tests/check-audit.ps1` (carga los nuevos analizadores, simula `--list-detailed` y comprueba la elección de modo y de tamaño por zona).
- **Verificación**: formato de `--list-detailed`, `--size` y conexión del cliente contrastados con `cli.cpp` de OpenRGB `release_1.1` y con la salida real de un PC con placa, gráfica y refrigeración RGB. Pendiente: comprobar el apagado tras reiniciar.

## v3.3 — 2026-10-26

### Añadido
- **Control remoto por SSH (Tailscale)** en Sistema › Acceso remoto y en el perfil **Escritorio remoto**: instala OpenSSH Server si falta, pone PowerShell como shell, desactiva contraseñas (solo claves), protege `administrators_authorized_keys`, sustituye la regla de Windows del puerto 22 por una limitada a Tailscale (`100.64.0.0/10`) y deja `sshd` automático. Comprueba la configuración con `sshd -t` y la deja como estaba si falla. Abre el archivo de claves para pegar la del Mac.
- Restauración: guarda y recupera el servicio, la regla de Windows, `sshd_config` y el shell por defecto.
- **Activar monitor virtual** en Sistema › Acceso remoto y en el perfil **Escritorio remoto**: el paquete de WinGet de Virtual Display Driver solo deja los archivos, así que ahora se crea el dispositivo `Root\MttVDD` con `devcon` (eligiendo el INF por su sección de arquitectura, aunque esté en una carpeta `x86`) y se copia `vdd_settings.xml` a `C:\VirtualDisplayDriver`. Deshacer quita el dispositivo y deja el controlador.

### Archivos y pruebas
- **Archivos**: `iWinInstaller.ps1`, `lifecycle.ps1`, `apps.json`, `profiles.json`, `README.md`, `install.ps1`, `native/Launcher.cs`, `tests/check-acceptance.ps1`.
- **Verificación**: parser de PowerShell sin errores y JSON válidos. Pendiente: runners Windows y conexión real desde el Mac.

## v3.2 — 2026-10-26

### Añadido
- **Después de instalar**: panel dentro de la ventana, acceso desde cada fila, 122 guías con pasos, notas personales persistentes y comprobaciones técnicas de solo lectura. Distingue explícitamente funcionamiento detectado de cuentas, emparejamientos y pruebas físicas confirmadas por el usuario.
- **Reanudar y pausar**: lotes persistidos de forma atómica con resultados por ID. Una pausa deja terminar la aplicación actual. Tras cerrar o reiniciar, el usuario puede continuar lo pendiente, sin repetir resultados completados ni ejecutar lotes por su cuenta.
- **Resumen previo** de aplicaciones, dependencias, permisos, ajustes y reinicios, con comprobación de espacio y conexión HTTPS al origen de WinGet.
- **Reinicio pendiente** por aplicación y comprobación posterior, incluyendo códigos del instalador y HRESULT de WinGet. No se fuerza el reinicio.
- **Aplicación registrada en Windows** con Inicio, escritorio y desinstalación desde Aplicaciones instaladas. La primera apertura del ZIP instala en la misma ubicación canónica. Una versión nueva reemplaza la anterior conservando datos locales fuera de la carpeta de programa.
- **Actualización automática opcional**, desactivada inicialmente: comprobación al abrir, al iniciar sesión y diaria mediante tarea del usuario. Solo actualiza iWinInstaller, verifica SHA256, evita versiones anteriores y espera a cerrar antes de sustituir. Controles de consulta manual y desactivación.

### Mejorado
- **Estética Apple adaptada a WPF**: negro profundo, superficies sobrias, acento azul, mayor legibilidad, filas con acciones claras, panel no modal, expansión accesible por teclado y transición breve que respeta la preferencia de movimiento.
- **Restauración de ajustes**: conserva valores y tipos previos; para acceso remoto también energía, adaptadores, recuperación de servicios, firewall y accesos. Los registros de equipo se guardan con permisos restringidos.
- **Publicación condicionada** al éxito de bootstrap, aceptación y EXE/estabilidad en x64 y ARM64, más las regresiones en PowerShell x86 real del mismo commit. El EXE x86 en Windows de 64 bits utiliza el host nativo para evitar redirecciones de rutas y registro.

### Corregido
- **Desinstalación incierta**: un error de consulta se conserva como pendiente; solo el código documentado de ausencia acredita que el paquete ya no aparece.
- **Actualizador**: comparación numérica de versiones, exclusión mutua entre comprobaciones, descarga temporal y validación antes de ejecutar, sin esperar a sí mismo.

### Archivos y pruebas
- **Afecta a** Windows 10/11 x86, x64 y ARM64; no existen variantes macOS/iOS/web.
- **Archivos**: `iWinInstaller.ps1`, nuevo `lifecycle.ps1`, `apps.json`, `install.ps1`, `native/Launcher.cs`, `scripts/build_exe.ps1`, `tests/`, workflows y README.
- **Pruebas**: sintaxis PowerShell y XML, compilación del puente de servicios y regresiones locales de dependencias, pausa/reanudación, reinicios, incertidumbre de desinstalación y notas. CI verifica Windows PowerShell 5.1, restauración en claves aisladas y servicio efímero, interfaz y capturas en dos tamaños, registro, primera apertura desde ZIP, sustitución, conservación de datos y desinstalación real en runners desechables x64/ARM64.
- **Límites**: los estados anteriores a v3.2 sin registro previo no se pueden reconstruir; Autologon se desactiva desde su herramienta y RGB no recupera colores anteriores. Pendientes de prueba física: hardware RGB, BIOS, acceso desde otra red y cuentas personales; No hay runner de Windows 10 de 32 bits: se prueban procesos x86 reales en Windows x64, además de los runners x64/ARM64. Las comprobaciones no garantizan todas las funciones de las 418 aplicaciones.

## v3.1 — 2026-10-26

### Corregido
- **Inventario RGB**: separados el inventario completo y el filtro de desinstalación. Una función duplicada ocultaba OpenRGB fuera de su ruta predeterminada, PawnIO y las apps RGB del fabricante.
- **Bloqueos de OpenRGB**: lectura simultánea de stdout/stderr con límite efectivo de cinco minutos, cierre y liberación del proceso si no responde.
- **Resultados fiables**: un error de enumeración o apagado devuelve fallo, conserva el diagnóstico y no marca RGB como aplicado. Se retira el informe anterior antes de ejecutar para evitar confirmar resultados antiguos. La confirmación acredita la orden aceptada por OpenRGB; no mide físicamente los LED.
- **Versión del instalador**: EXE, formulario, registro de arranque e instalación incrustada muestran v3.1, en lugar de las referencias antiguas a v2.0/v2.5.

### Archivos y pruebas
- **Afecta a** Windows 10/11 x86, x64 y ARM64; sin versiones macOS/iOS/web publicadas.
- **Archivos**: `iWinInstaller.ps1`, `install.ps1`, `native/Launcher.cs`, `tests/check-audit.ps1`, `tests/check-acceptance.ps1`, `tests/check-embedded-install.ps1`, `.github/workflows/bootstrap.yml`, `README.md`.
- **Regresiones**: proceso simulado real con ambas salidas de 128 KiB, bloqueo con tuberías abiertas, enumeración fallida, apagado fallido, informe persistido, detección de funciones duplicadas y coherencia de versiones. Suite de arranque ampliada a x64 y ARM64 en PowerShell 5.1.
- **Límites**: pendiente de prueba con hardware RGB físico y Windows 10/x86. La revisión no garantiza ausencia de fallos en las 418 entradas ni en todos los equipos.

## v3.0 — 2026-10-26

### Añadido
- **Pantalla virtual (Virtual Display Driver)** en Sistema › Acceso remoto y en el perfil **Escritorio remoto**: Windows conserva un monitor virtual, de modo que Sunshine sigue transmitiendo con las pantallas apagadas o el HDMI desconectado.
- **PC siempre disponible** indica en el registro si hay pantalla virtual y, con el monitor encendido, cómo duplicar (`Win + P`).

### Archivos y pruebas
- **Archivos**: `iWinInstaller.ps1`, `apps.json`, `profiles.json`, `README.md`, `tests/check-acceptance.ps1`.
- **Verificación**: parser de PowerShell sin errores y JSON válidos. Pendiente: id de winget en los runners y prueba sin monitor en el PC.

## v2.9 — 2026-10-26

### Añadido
- **Portapapeles compartido Mac ↔ Windows**: el perfil **Escritorio remoto** incluye **KDE Connect**, y **PC siempre disponible** abre sus puertos (TCP/UDP 1714-1764) solo para la red de Tailscale (`100.64.0.0/10`) en cualquier perfil de red. La regla se quita al deshacer.

### Cambiado
- La descripción de KDE Connect indica su uso como portapapeles con el Mac.

### Archivos y pruebas
- **Archivos**: `iWinInstaller.ps1`, `apps.json`, `profiles.json`, `README.md`, `tests/check-acceptance.ps1`.
- **Verificación**: parser de PowerShell sin errores y JSON válidos. Pendiente: runners Windows y vinculación real con el Mac.

## v2.8 — 2026-10-26

### Añadido
- **Grupo Sistema › Iluminación RGB** con **OpenRGB** (`OpenRGB.OpenRGB`) y su driver **PawnIO** (`namazso.PawnIO`).
- **Apagar todas las luces RGB** (ajuste, pide administrador): anota en el registro placa base, módulos de RAM, gráficas, controladoras USB con posible RGB y software RGB del fabricante; apaga cada dispositivo que detecta OpenRGB con su modo *Off* o, si no lo tiene, *Direct*/*Static* en negro y brillo 0; crea la tarea `\iWinInstaller\Apagar luces RGB` como SYSTEM al arrancar (30 s) y al iniciar sesión (20 s), con una segunda pasada al minuto para controladoras USB que se reinician. Se deshace desde la app.
- El perfil **Escritorio remoto** incluye el apagado de luces.
- **Sistema › Software de los fabricantes** (14 nuevas): AMD Adrenalin y Samsung Magician (web oficial), Armoury Crate, ASUS GPU Tweak III, MSI Center, GIGABYTE RGB Fusion, Corsair iCUE, NZXT CAM, Lian Li L-Connect 3, Logitech G HUB, Razer Synapse 4, SteelSeries GG, Kingston SSD Manager y Crucial Storage Executive. NVIDIA App e Intel DSA pasan a reconocer su hardware.
- **Perfil «Apps de mis componentes (detectadas)»**: lee placa, CPU, gráfica y su fabricante (subsistema PCI), RAM, discos y VIDs USB, y marca solo las apps de esas marcas.

### Cambiado
- **Software RGB frente a luces apagadas**: con «Apagar todas las luces RGB» aplicado, el perfil detectado omite las apps que gestionan iluminación; si se marcan a mano junto al apagado, el registro avisa de que pueden volver a encender los LED.
- Las entradas «manual» indican que se instalan desde la web o la cuenta del proveedor.

### Seguridad
- La carpeta `C:\ProgramData\iWinInstaller\OpenRGB` (script, configuración y plugins de OpenRGB) queda solo para SYSTEM y administradores; los usuarios solo leen, porque la tarea corre como SYSTEM.

### Archivos y pruebas
- **Archivos**: `iWinInstaller.ps1`, `apps.json`, `profiles.json`, `README.md`, `tests/check-acceptance.ps1`.
- **Verificación**: JSON válido sin ids duplicados (417 entradas); ids, ámbito y dependencias comprobados en los manifiestos de winget-pkgs (AMD.AMDSoftwareCloudEdition descartado: es la edición para máquinas en la nube); argumentos de la CLI contrastados con `cli.cpp` de OpenRGB 1.1. Parser de PowerShell, `check-ids.ps1` y prueba con hardware RGB real pendientes en Windows.

## v2.7 — 2026-10-26

### Añadido
- **Grupo Sistema › Acceso remoto** y perfil **Escritorio remoto (este PC como servidor)** para usar el PC de casa desde fuera con Moonlight.
- **PC siempre disponible** (ajuste, pide administrador): sin suspensión ni hibernación con corriente (también quita el inicio rápido), Wake-on-LAN y sin ahorro de energía en los adaptadores, Sunshine y Tailscale automáticos con reinicio tras fallo y Tailscale en modo desatendido si ya hay sesión. Crea la carpeta **Acceso remoto** (escritorio y menú Inicio públicos) con accesos al panel de Sunshine, los equipos de Tailscale y Escritorio remoto de Chrome; se quita al deshacer. Si Autologon está instalado y no configurado, lo abre para escribir la contraseña. Se deshace desde la app.
- **Autologon (Sysinternals)**: inicio de sesión automático con la contraseña guardada cifrada por Windows.
- **Escritorio remoto de Chrome (anfitrión)**: respaldo por navegador en redes que solo dejan HTTPS.

### Archivos y pruebas
- **Archivos**: `iWinInstaller.ps1`, `apps.json`, `profiles.json`, `README.md`, `tests/check-acceptance.ps1`.
- **Verificación**: sintaxis con el parser de PowerShell, JSON válido sin ids duplicados y lectura del valor de suspensión de `powercfg` en español. Ids de winget y aplicación real pendientes de los runners Windows.

## v2.6 — 2026-10-19

### Añadido
- **Perfil Manual vacío al abrir**: ya no queda una lista amplia marcada para instalar por accidente; los perfiles existentes siguen disponibles cuando el usuario los elige.
- **Arquitectura visible**: la cabecera identifica ARM64, x64 o x86 antes de seleccionar paquetes.

### Corregido
- **Prueba de instalación de Windows**: el workflow usaba el perfil retirado «Optimización» y ahora ejecuta el perfil vigente «Solo sistema (ajustes y optimización)».

### Archivos y pruebas
- **Archivos**: `iWinInstaller.ps1`, `profiles.json`, `tests/check-acceptance.ps1`, `tests/check-native.ps1` y `.github/workflows/windows.yml`.
- **Verificación prevista**: sintaxis PowerShell, aceptación y ventana WPF en los runners Windows x64 y ARM64.

## v2.5 — 2026-10-17

### Interfaz
- **Etiqueta «>_ Terminal»** en todo lo que se usa desde la consola (sección Terminal), también al buscar o ver todo el catálogo.
- **Abrir desde el clic derecho**: las apps instaladas muestran **Abrir**; las herramientas de terminal, **Abrir en terminal** (consola nueva con el PATH actualizado). El menú solo enseña las acciones que sirven para esa fila.
- Abrir encuentra mejor la app en el menú Inicio (p. ej. «7-Zip File Manager»).

### Catálogo reorganizado (397 entradas)
- **Notas y tareas**: Obsidian, Notion, Logseq, Joplin, Anytype, Todoist y Microsoft To Do juntos, y nuevas OneNote, Evernote, Standard Notes, Notesnook, AFFiNE, SiYuan, Trilium, Zettlr, Simplenote y TickTick.
- **Almacenamiento y nube** (antes «Nube y archivos») incluye iCloud.
- Nuevo grupo **Contraseñas** (Bitwarden, KeePassXC, 1Password, Proton Pass) y **Bases de datos** en Terminal (MySQL, PostgreSQL, MongoDB, SQLite).
- VLC pasa a Multimedia, Discord a Comunicación, SumatraPDF y Acrobat a Ofimática, Notepad++ a Desarrollo y Microsoft Store a Sistema.
- Los perfiles Base, Gaming, Desarrollo e IA conservan VLC, Discord, Bitwarden, SumatraPDF y Notepad++.

## v2.4 — 2026-10-16

### Cambiado
- **ChatGPT**: instala la app actual de OpenAI de Microsoft Store (`9PLM9XGG6VKS`, con Chat, Codex y agente) en lugar de ChatGPT Classic (`9NT1R1C2HH7J`).

## v2.3 — 2026-10-16

### Interfaz
- **Rediseño oscuro más limpio**: barra superior con búsqueda, barras de desplazamiento finas, diálogos propios y menús oscuros.
- **Pantallas pequeñas y máquinas virtuales**: la ventana se adapta a la pantalla (se abre maximizada si es pequeña), oculta las secciones tras el botón ☰ cuando falta ancho y agrupa las acciones secundarias en ⋯. La lista conserva el espacio.
- **Tamaño del texto**: botones **A− / A+**, `Ctrl + rueda` y `Ctrl + + / − / 0` escalan toda la ventana del 70 % al 200 %. Se recuerda para la próxima vez.
- Atajos: `Ctrl + F` busca, `Espacio` marca, `Supr` desinstala la fila seleccionada.

### Añadido
- **Desinstalar**: botón **Desinstalar** en cada app instalada, en el menú del clic derecho y para todo lo instalado que marques. Pide confirmación, usa winget, el paquete de Store o el desinstalador oficial, y comprueba que la app ya no está. Los componentes del sistema (Visual C++, .NET, DirectX, Edge, Store) no se ofrecen.
- **Deshacer ajustes**: los ajustes de Windows vuelven al valor de serie con el mismo botón.
- **Perfiles propios**: **Guardar…** lo marcado (opcionalmente con lo ya instalado), **⋯ › Exportar** a un archivo `.iwin.json` e **Importar…** en otro PC. Sin ventana: `iWinInstaller.ps1 -Silent -Perfil archivo.iwin.json`. Un perfil solo contiene ids del catálogo; los desconocidos se ignoran.
- **149 entradas nuevas (387 en total)**: lenguajes (Deno, .NET SDK, Ruby, Java 17/25, Lua, Zig, Julia, R, Perl, CMake, LLVM, MSYS2, Build Tools…), bases de datos, herramientas de terminal (lazygit, Starship, Oh My Posh, gsudo, Codex CLI, Azure/AWS CLI…), y apps de desarrollo, utilidades, calidad de vida, multimedia, seguridad, juegos y personalización.
- **8 ajustes de Windows**: rutas largas, menú contextual clásico, Inicio sin Bing, barra a la izquierda, segundos en el reloj, Explorador en «Este equipo», «Finalizar tarea» y ratón sin aceleración.

### Pruebas
- La prueba de ventana comprueba zoom, tamaños 1180×780, 800×600 y 600×440, desinstalar y la ida y vuelta de perfiles.
- `check-ids.ps1` valida cada id con su ámbito y arquitectura.

## v2.2 — 2026-10-15

### Seguridad
- Los instaladores directos (HoYoPlay, Riot) solo se abren si los firma **su fabricante**; antes valía cualquier firma válida.
- Las Guest Additions de VirtualBox se comprueban con el SHA256 que publica Oracle.
- Cada descarga de la Release lleva **procedencia firmada** por GitHub: `gh attestation verify iWinInstaller-Setup.exe --repo iShun05/iWinInstaller`.
- Nuevo `SECURITY.md` con cómo informar de un fallo y qué verifica la app.

## v2.1 — 2026-10-14

### Cambiado
- **Tres secciones** en el catálogo y en la barra lateral: **Sistema** (ajustes, optimización y privacidad, drivers y componentes), **Terminal** (consola, lenguajes y herramientas de línea de comandos) y **Aplicaciones** (todo lo que tiene ventana propia). Ya no se mezclan herramientas de terminal ni ajustes con las apps.
- «Optimización y mantenimiento» pasa a ser «Mantenimiento y hardware» (apps), y lo que cambia Windows (ShutUp10++, WinToys, Winhance, BleachBit, Autoruns) va a Sistema › Optimización y privacidad.
- Perfiles: «Optimización» se sustituye por «Solo sistema (ajustes y optimización)» y se añade «Solo terminal». Un perfil puede incluir una sección entera con `@Sistema`, `@Terminal` o `@Aplicaciones`.

### Añadido
- **Ajustes de Windows** (sin marcar): punto de restauración, mostrar extensiones, mostrar ocultos, tema oscuro, plan de alto rendimiento y modo desarrollador.
- Pruebas automáticas también en **Windows 11 ARM64**.

## v2.0 — 2026-10-14

### Añadido
- **Organización del escritorio al terminar**: agrupa accesos de aplicaciones y juegos en Aplicaciones, preservando documentos y archivos existentes. Las colisiones crean un nombre distinto, sin sobrescribir.
- **Descarga pública sin cuenta**: instalación y actualización desde las releases, con comprobación SHA256.
- **Pruebas de escritorio e IPC**: accesos reales en una carpeta temporal, colisiones, repetición y transmisión de actividad desde el proceso de instalación.

### Mejorado
- **Interfaz oscura más limpia**: mayor jerarquía tipográfica, superficies sobrias, actividad abierta y respuesta visible al pulsar botones.
- **Entrada suave de 180 ms**: respeta la opción de animaciones de Windows.
- **Progreso legible**: muestra la aplicación actual, la fase que comunica WinGet y el número de operaciones completadas. El detalle técnico permanece en el TXT.

### Corregido
- **Norton VPN**: ya no intenta ejecutar una página HTML como instalador; indica que debe completarse desde la cuenta del proveedor y permanece pendiente hasta verificarse.
- **Registro de los lotes**: los procesos hijos transmiten actividad a la interfaz mientras trabajan, en lugar de dejarla sin información.
- **Diagnóstico por sesión**: evita mezclar resultados de ejecuciones anteriores y oculta patrones de correo además de secretos y rutas del perfil.

### Eliminado
- **Contraseña propia, migración, proyectos y configuraciones del autor**: el producto se centra en instalar aplicaciones.
- **Sincronización de configuraciones y preferencias personales**: no importa normas, inventarios de otro equipo ni cuentas del autor.

### Archivos y pruebas
- **Archivos principales**: `iWinInstaller.ps1`, `install.ps1`, `apps.json`, `profiles.json`, `native/Launcher.cs`, documentación, empaquetado y workflows.
- **Verificación**: pruebas de PowerShell 5.1, interfaz WPF real, EXE instalado, integridad y reparación, Chrome desde cero y segunda pasada, escritorio aislado y transmisión de actividad.
- **Límite**: no se ha instalado todo el catálogo en un PC físico; la instalación manual de productos con suscripción requiere intervención del usuario.
