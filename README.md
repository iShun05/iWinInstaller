# iWinInstaller

Centro de control del PC con Windows 10 y 11: instala y mantiene al día tus aplicaciones, revisa la salud del equipo, libera espacio, protege con Defender y conecta tu Mac por SSH, desde una sola ventana oscura en español.

## Descargar e instalar

[Descargar iWinInstaller-Setup.exe](https://github.com/iShun05/iWinInstaller/releases/latest/download/iWinInstaller-Setup.exe)

1. Descarga el instalador y ábrelo con doble clic.
2. Elige un perfil o marca las aplicaciones que necesites.
3. Pulsa **Instalar** y autoriza Windows cuando una aplicación requiera administrador.
   Para quitar algo, pulsa **Desinstalar** en su fila.
4. Al terminar, si algo no se instaló se abre el **informe de la instalación** con el motivo de cada fallo y qué hacer. Los accesos de aplicaciones del escritorio se agrupan en **Aplicaciones**.

El EXE incluye el programa y los componentes de Microsoft para preparar WinGet. Las aplicaciones se descargan de sus fuentes oficiales y necesitan conexión. No requiere cuenta de GitHub ni contraseña propia. Windows pedirá **permiso de administrador una vez** para instalar: desde v4.3 la app vive en `Archivos de programa`, donde ningún programa de tu usuario puede modificarla, y se abre después sin permisos especiales. Windows puede mostrar SmartScreen porque el ejecutable aún no tiene firma (está solicitada): comprueba que procede de esta release antes de abrirlo.

Alternativa ZIP: [iWinInstaller.zip](https://github.com/iShun05/iWinInstaller/releases/latest/download/iWinInstaller.zip), descomprime y abre `iWinInstaller.exe`: la primera apertura pide permiso de administrador, instala y registra la misma app en Windows. Las versiones nuevas sustituyen esa instalación y conservan perfiles, notas y lotes. Si tenías una versión anterior instalada por usuario, se retira sola al instalar la nueva. Para retirarla usa **Configuración de Windows › Aplicaciones instaladas › iWinInstaller › Desinstalar**; los programas instalados y tu seguimiento se conservan.

**Versión actual: v5.2** · Windows 10/11 · x86, x64 y ARM64 según los paquetes disponibles.

**Brave normal o Brave limpio**: en Navegadores puedes instalar Brave oficial tal cual o añadir una limpieza reversible: sin cripto, Leo, VPN ni noticias, con el perfil principal oscuro y sin tarjetas promocionales. Cierra Brave antes de aplicar o deshacer. No copia perfiles ni cuentas, conserva Shields/Sync y no acepta Widevine por ti. Los perfiles adicionales mantienen su aspecto; los widgets de búsqueda/reloj pueden requerir ajuste manual según la versión. Las políticas pueden mostrar «Administrado por tu organización». Para volver al estado anterior usa **Brave limpio → Deshacer**; instalar Brave normal no revierte estos ajustes.


## Puesta a punto de un portátil nuevo

En el catálogo general se incluyen **MyASUS** (soporte, diagnóstico y guía desde Windows vacío), **G-Helper** (alternativa opcional a Armoury Crate) y **OCCT Personal** (pruebas de estabilidad opcionales). No se añade ningún perfil exclusivo de portátil. Las herramientas x64 se ofrecen según la compatibilidad del proveedor; el resto de la aplicación sigue disponible para Windows 10/11 x86, x64 y ARM64.

Para un ASUS sin sistema, prepara primero Windows 11 y los controladores de red/almacenamiento del modelo exacto en otro equipo. Después de instalar Windows y conectar la red, abre iWinInstaller. **MyASUS → Pasos y notas** explica el orden: Windows Update, drivers específicos, ASUS System Control Interface, firmware manual, batería y comprobaciones físicas. [Descargar Windows 11](https://www.microsoft.com/software-download/windows11) · [Soporte ASUS](https://www.asus.com/support/Download-Center/).

Usa **Armoury Crate o G-Helper** como gestor de rendimiento, conservando ASUS System Control Interface. G-Helper no se marca automáticamente por detectar una placa ASUS y no sustituye drivers o BIOS. Sus dependencias se resuelven con WinGet; consulta sus [requisitos](https://github.com/seerge/g-helper/wiki/Requirements). OCCT no inicia pruebas por su cuenta. La instalación de una herramienta no acredita que el hardware o sus controladores funcionen: los pasos físicos se confirman manualmente.

## Funciones principales

- **Mantenimiento y salud** (v4.9): liberar espacio (calcula antes, pide confirmación y nunca toca documentos), reparar Windows con DISM y SFC, salud de discos y batería e informe del equipo sin datos sensibles.
- **Buscar cualquier cosa (`Ctrl + K`)**: una paleta que lleva a cualquier sección, ajuste o app del catálogo escribiendo lo que quieres hacer, sin tildes y con sinónimos.
- **Inicio · Estado del PC**: al abrir, tarjetas con las actualizaciones de apps, Windows Update, antivirus, espacio y salud de los discos, batería, reinicio pendiente y lotes sin terminar. Cada una dice si está correcta, si requiere atención o si no se pudo comprobar (y por qué), con un botón **Abrir** que lleva a la solución.
- **Monitor en vivo**: en Inicio, el uso del procesador, la memoria y el espacio libre del disco del sistema, actualizados cada tres segundos sin PowerShell ni contadores de rendimiento.
- **Segundo plano (opcional)**: en **Ajustes**, «Seguir en segundo plano al cerrar la ventana» deja un icono junto al reloj con el uso del equipo, atajos de Windows, «Comprobar el equipo ahora» y «Salir». Cada dos horas repite las comprobaciones del Inicio y avisa solo de lo que **pasa a requerir atención** (poco espacio, antivirus desactivado, actualizaciones nuevas) o si el procesador o la memoria llevan cinco minutos por encima del 90 %. Puede abrirse en la bandeja al iniciar sesión. Desactivado al principio; no instala ni actualiza nada por su cuenta.
- **Windows a mano**: 81 atajos a los ajustes y herramientas de Windows (pantalla, sonido, red, Bluetooth, arranque, privacidad, recuperación, Administrador de dispositivos, Visor de eventos, variables de entorno…), con buscador y también desde `Ctrl + K` y la bandeja. Solo los abren: no cambian nada.
- **Una sola ventana**: abrir la app por segunda vez trae al frente la que ya existe.
- **Actualizaciones** (v4.5): qué apps tienen versión nueva, cuáles actualizar, **Mantener esta versión** para las que quieras fijar y actualización programada opcional (con tu usuario, sin reiniciar ni abrir asistentes).
- **Subsecciones con comparativa**: dentro de cada categoría, las apps que hacen lo mismo se agrupan en subsecciones (p. ej. Optimización y privacidad › Quitar telemetría y bloatware, Consola y shells › Terminales, Navegadores › Basados en Firefox). Cada subsección abre con un recuadro **«Cuál elegir»** que dice cuándo compensa una, otra o las dos juntas, y cada app añade una línea con lo que ofrece y lo que no. 84 subsecciones en 24 categorías; la búsqueda también encuentra por esas comparativas.
- **Sistema · Resolución y frecuencia** sin abrir Configuración: elige monitor, resolución y Hz entre los modos que admite; si no pulsas **Mantener** en 15 s vuelve solo al modo anterior, como hace Windows. En la misma sección, **Energía** ajusta apagado de pantalla, suspensión e hibernación del plan activo.
- **Pasos y notas**: en cada opción relevante (123 guías), pasos marcables, tu nota y **Comprobar**, que separa la detección técnica de las confirmaciones manuales de cuentas, conexiones, licencias y pruebas físicas. El filtro **Por configurar** muestra lo pendiente. El seguimiento se conserva al cerrar y actualizar.
- **Lotes recuperables**: el progreso se guarda antes y después de cada aplicación. **Pausar al terminar esta app** deja finalizar el instalador actual y conserva el resto. **Reanudar lote** continúa los pendientes más recientes; los anteriores también se conservan y se ofrecen al completar ese lote. Desde consola: `iWinInstaller.ps1 -Resume`. No se ejecuta un lote automáticamente tras reiniciar.
- **Resumen antes de instalar**: incluye dependencias, permisos, ajustes y reinicios previstos; comprueba espacio de preparación y conexión HTTPS al origen de WinGet. Los requisitos finales de cada proveedor pueden ser mayores.
- **Deshacer con estado anterior**: los ajustes reversibles aplicados desde v3.2 guardan valores y tipos originales. El ajuste de acceso remoto conserva energía, red, servicios y accesos. Si el cambio viene de una versión antigua sin estado guardado, se explica y se evita imponer valores genéricos. WSL y puntos de restauración no se deshacen desde aquí; RGB retira su tarea, sin recuperar colores físicos anteriores.
- **Reinicios visibles**: las aplicaciones que lo solicitan quedan identificadas hasta un nuevo arranque y se pueden comprobar otra vez. iWinInstaller no reinicia por su cuenta.
- **Actualización opcional de iWinInstaller** (Ajustes): desactivada inicialmente; al activarla (pide permiso de administrador una vez) comprueba GitHub al abrir la app, al iniciar sesión y una vez al día mediante una tarea del sistema que solo ejecuta el actualizador instalado. Descarga solo la nueva versión estable, verifica SHA256 y sustituye la app cuando la cierras. No actualiza otras aplicaciones. **Buscar nueva versión ahora** lo hace a mano.

- **430 entradas en tres secciones**, cada una con sus categorías:
  - **Sistema**: ajustes de Windows (tema oscuro, extensiones visibles, menú contextual clásico, rutas largas, Inicio sin Bing, punto de restauración, alto rendimiento, modo desarrollador, WSL…), optimización y privacidad (O&O ShutUp10++, WinToys, Winhance, privacy.sexy, BleachBit…) y drivers y componentes (Visual C++, .NET, DirectX, NVIDIA, Intel).
  - **Terminal**: consola y shells (Windows Terminal, PowerShell 7, WezTerm, Starship, Oh My Posh, gsudo…), lenguajes y entornos (Git, Python, Node.js, Deno, Go, Rust, Java, .NET SDK, Ruby, Zig, C/C++ con LLVM, CMake y Build Tools, PostgreSQL, MongoDB…) y herramientas de línea de comandos (Claude Code, Codex CLI, lazygit, ripgrep, fzf, FFmpeg, yt-dlp, Azure y AWS CLI…).
  - **Aplicaciones**: todo lo que tiene ventana propia (juegos, navegadores, IA, utilidades, multimedia…).
  Los elementos opcionales se eligen expresamente. Los perfiles «Solo sistema» y «Solo terminal» marcan únicamente esa sección.
- **Escritorio remoto para jugar desde fuera** (Sistema › Acceso remoto o perfil «Escritorio remoto»): **PC siempre disponible** desactiva la suspensión y la hibernación con corriente, activa Wake-on-LAN y deja Sunshine y Tailscale como servicios automáticos que se reinician solos; Tailscale pasa a modo desatendido y deja una carpeta **Acceso remoto** en el escritorio y el menú Inicio con el panel de Sunshine, los equipos de Tailscale y Escritorio remoto de Chrome. **Autologon** (Sysinternals) inicia sesión al encender con la contraseña cifrada por Windows, y **Escritorio remoto de Chrome** sirve de respaldo por navegador cuando la red solo deja HTTPS. Ver [Jugar en remoto](#jugar-en-remoto).
- **Luces RGB apagadas** (Sistema › Iluminación RGB): **Apagar todas las luces RGB** instala OpenRGB y su driver PawnIO, anota placa, RAM, gráfica, controladoras USB y software RGB del fabricante en el registro, apaga cada dispositivo (modo Off o negro) y crea una tarea de SYSTEM que lo repite en cada arranque, también sin sesión. Incluido en el perfil «Escritorio remoto». Ver [Luces RGB](#luces-rgb).
- **Apps de tus componentes** (Sistema › Software de los fabricantes o perfil «Apps de mis componentes (detectadas)»): el perfil lee placa base, procesador, gráfica (y su fabricante), RAM, discos y dispositivos USB, y marca solo las apps de esas marcas: NVIDIA App, AMD Adrenalin, Intel DSA, Armoury Crate, GPU Tweak III, MSI Center, RGB Fusion, iCUE, NZXT CAM, L-Connect 3, G HUB, Synapse, SteelSeries GG, Samsung Magician, Kingston SSD Manager y Crucial Storage Executive. Cada una se puede instalar por separado. Con **Apagar todas las luces RGB** aplicado, el perfil omite las que gestionan iluminación, porque vuelven a encender los LED.
- **Desinstalar desde la app**: botón en cada fila instalada (o marca varias y pulsa **Desinstalar**). Pide confirmación, usa winget, Microsoft Store o el desinstalador oficial y comprueba que la app ya no está. Los ajustes reversibles recuperan el estado anterior guardado desde v3.2. Visual C++, .NET, DirectX, Edge y Store no se ofrecen.
- **Línea de comandos documentada**: `-Check -Json` da el estado del equipo en JSON para scripts; modos y códigos de salida en [docs/cli.md](docs/cli.md).
- **Perfiles propios para llevar a otro PC**: **Guardar perfil…** guarda lo marcado; **Exportar…** crea un `.iwin.json`; en el otro PC, **Importar…** lo marca todo de una vez, o sin ventana: `iWinInstaller.ps1 -Silent -Perfil archivo.iwin.json`. Solo contiene ids del catálogo.
- **Acceso remoto · Vincular equipos**: prepara este PC como servidor SSH (solo claves, por Tailscale y opcionalmente red local), te da el comando para la Terminal del Mac o PowerShell de otro Windows (crea clave y alias y la copia al portapapeles) y autoriza ese equipo pegando su clave pública. Después: `ssh <nombre-del-pc>`, `scp`, Claude o VS Code por SSH.
- **Seguridad con Microsoft Defender**: tiempo real, protección contra alteraciones, firmas y último análisis; análisis rápido, completo o de una carpeta, actualizar firmas y amenazas recientes. No instala otro antivirus; el catálogo incluye la sección **Antivirus y antimalware** si quieres uno: Bitdefender Free (abre su asistente oficial, que hay que completar), Malwarebytes, Emsisoft Emergency Kit (se extrae en `C:\EEK` con permiso de administrador) y AdwCleaner.
- **Pantallas pequeñas y máquinas virtuales**: la ventana nunca abre más grande que la pantalla. **A− / A+**, `Ctrl + rueda` o `Ctrl + + / − / 0` cambian el tamaño de todo del 70 % al 200 % y se recuerda.
- **Detección de aplicaciones existentes** para evitar reinstalarlas. Una operación no se confirma únicamente por su código de salida.
- **Selección segura**: Instalar abre con el perfil Manual y nada marcado; elige un perfil o marca elementos antes de instalar. Las apps ya instaladas no se marcan.
- **Informe al terminar**: si algo falla o necesita tu intervención, se abre una tarjeta por aplicación: motivo en lenguaje claro, código del instalador (p. ej. `0x80070005`), qué hacer y las líneas relevantes del registro. Separa los fallos de las instalaciones manuales (Norton VPN, asistentes) y de lo pendiente. **Reintentar fallidas** y **Copiar informe** (texto listo para pegar en un chat). Se reabre con **Informe de la última instalación**, y **Ajustes › Exportar diagnóstico** guarda el TXT completo, que empieza por ese resumen.
- **Actividad visible**: cada fila muestra su estado y el progreso del lote (`3/12`); el registro técnico completo de cada sesión está en **Ajustes › Abrir la carpeta de registros**.
- **Escritorio organizado**: mueve accesos `.lnk` a ejecutables y accesos de juegos Steam/Epic a una carpeta Aplicaciones del escritorio del usuario. Incluye los accesos públicos cuando el lote tiene permisos. No mueve documentos, carpetas ni enlaces web generales; conserva ambos archivos cuando coincide el nombre.
- **Interfaz oscura** con navegación lateral, búsqueda por palabras, filtros, paleta `Ctrl + K`, navegación por teclado y nombres accesibles para lectores de pantalla.
- **Actualización pública** del instalador, con comprobación SHA256. Los lotes separan las instalaciones por usuario de las que requieren administrador.

Algunos productos necesitan su asistente o una suscripción. Norton VPN se instala desde la cuenta del proveedor: abrir sus instrucciones no se considera una instalación correcta. WSL puede requerir reiniciar Windows. La app no importa configuraciones personales ni administra proyectos de código.

## Jugar en remoto

1. En el PC de casa: perfil **Escritorio remoto (este PC como servidor)** › Instalar. Abre Tailscale e inicia sesión; vuelve a aplicar **PC siempre disponible** para el modo desatendido. En el panel de Tailscale, desactiva la caducidad de clave de este PC.
2. Abre `https://localhost:47990`, crea el usuario de Sunshine y empareja Moonlight con el PIN (una vez, en casa).
3. En la BIOS/UEFI: **Restore on AC Power Loss = Power On**, para que arranque solo tras un corte.
4. En el equipo cliente: Tailscale y Moonlight con la misma cuenta. Conecta a la IP `100.x` del PC.
5. Sin monitor: **Pantalla virtual** (Virtual Display Driver) instala el controlador y **Activar monitor virtual** crea el monitor, así que Sunshine sigue funcionando con las pantallas apagadas o el HDMI desconectado. Con el monitor encendido, `Win + P` › Duplicar.
6. Portapapeles compartido: KDE Connect en los dos equipos (en macOS, `brew install --cask kde-connect`). Vincúlalos añadiendo la IP `100.x` del PC y acepta en el PC; lo copiado en uno se pega en el otro. Si del Mac al PC no pasa nada, en KDE Connect del Mac abre el PC › ajustes del plugin **Portapapeles** y activa el envío automático, y comprueba que en el PC se ejecutó **PC siempre disponible** (abre los puertos 1714-1764 solo a Tailscale).
7. Control por comandos: lo más rápido es **Vincular equipos** (icono de enlace), que lo hace paso a paso. Manualmente: **Control remoto por SSH (Tailscale)** activa OpenSSH Server con PowerShell, solo claves y el puerto 22 abierto únicamente para `100.64.0.0/10`. Pega la clave pública del Mac en el archivo que abre la app y conecta con `ssh <usuario>@<IP 100.x>`.

Si la red bloquea UDP, Tailscale va por sus relés HTTPS (443): funciona, con más latencia. Para jugar fluido en una red muy filtrada, conecta el cliente a los datos del móvil. Escritorio remoto de Chrome es el respaldo para trabajar desde un navegador. Respeta las normas de uso de la red en la que estés.

## Luces RGB

1. Si quieres software del fabricante solo para drivers, firmware o ventiladores, instálalo y desactiva en él la iluminación; si no lo necesitas, mejor no instalarlo.
2. **Sistema › Iluminación RGB › Apagar todas las luces RGB** › Instalar. Si dice que no detecta nada, reinicia (PawnIO se carga al arrancar) y vuelve a aplicarlo.
3. Si OpenRGB falla o supera cinco minutos, se informa del fallo y el ajuste queda pendiente. Un proceso completado confirma que OpenRGB aceptó la orden, no una medición física de los LED.
4. Revisa el registro: lista los componentes y lo que OpenRGB ha apagado. El último arranque queda en `C:\ProgramData\iWinInstaller\OpenRGB\apagar-rgb.log`.
5. Si hay software RGB del fabricante (Armoury Crate, iCUE, Mystic Light, RGB Fusion, NZXT CAM, SignalRGB…), desinstálalo o quítalo del inicio: vuelve a encender las luces.
6. En la BIOS/UEFI, apaga el LED de la placa al arrancar y apagado (ASUS «LED lighting», MSI «EZ LED Control», Gigabyte «RGB Fusion», ASRock «RGB LED»).
7. Lo que siga encendido no es compatible con OpenRGB: ventiladores en un hub con botón propio se apagan desde ese botón o desconectando el cable ARGB/SATA de LED del hub.

Deshacer quita la tarea; las luces vuelven a su efecto de serie al quitar la corriente.

## Tecnología

Interfaz en C# con WPF sobre .NET Framework 4.8 (incluido en Windows); motor en PowerShell 5.1 con un contrato JSON entre ambos; C# para el lanzador; WinGet y Microsoft Store para los paquetes; Python estándar para construir la alternativa BAT. Pester 5 y JSON Schema para las pruebas. Sin servicio propio ni telemetría propia. La actualización opcional utiliza una tarea de Windows de tu usuario; permanece desactivada hasta que la habilites.

## Estructura

| Archivo | Función |
| --- | --- |
| `iWinInstaller.ps1` | Arranque del motor y modos de consola (abre la interfaz si no recibe parámetros) |
| `src/engine/` | Motor por áreas: WinGet, paquetes, sistema, remoto, RGB, ajustes, perfiles, lotes y contrato con la interfaz |
| `src/app/` | Interfaz (C#, WPF): Inicio, Instalar, Actualizaciones, Mantenimiento, Sistema, Acceso remoto, Seguridad, Ajustes y paleta |
| `apps.json`, `profiles.json` | Catálogo, guías de postinstalación y perfiles |
| `lifecycle.ps1` | Lotes, comprobaciones, restauración y actualizaciones opcionales |
| `install.ps1`, `launch.ps1`, `Iniciar.bat` | Instalación, desinstalación y apertura |
| `native/` | Lanzador C#, manifiesto y dependencias Microsoft verificadas |
| `scripts/` | Construcción del EXE y BAT |
| `src/catalog/schema/` | Esquemas que validan el catálogo y los perfiles |
| `tests/` | Pruebas unitarias (Pester), pruebas aisladas, aceptación en un Windows desechable y comprobación de la release |
| `docs/` | Línea de comandos (`cli.md`) y política de firma de código |
| `specs/`, `.specify/` | Especificación y plan del camino a v5.0 (Spec Kit) |
| `assets/` | Iconos |

## Compilar e instalar

En Windows, con Git y PowerShell disponibles:

```powershell
git clone https://github.com/iShun05/iWinInstaller.git
cd iWinInstaller
git checkout v5.2
./scripts/build_exe.ps1 -OutputDirectory "$env:TEMP/iwin-release" -Ref v5.2
```

Abre `iWinInstaller-Setup.exe` del directorio de salida. El compilador C# de .NET Framework está incluido en Windows; la interfaz necesita además el SDK de .NET (solo para compilar, no para usar la app). La construcción descarga los paquetes Microsoft cuyos hashes están fijados en `native/prerequisites.json`.

El EXE AnyCPU funciona como proceso de 32 bits en Windows x86 y usa el host nativo en x64/ARM64. CI ejecuta también PowerShell de 32 bits y un lanzador compilado x86 en Windows x64, además de los runners x64/ARM64. Los instaladores oficiales incluidos deben contener x86, x64 y ARM64. Algunos programas del catálogo solo existen para ciertas arquitecturas; un controlador de kernel debe corresponder al Windows real. La matriz no equivale a probar un Windows 10 de 32 bits completo.

Las pruebas de `check-native.ps1` y `check-acceptance.ps1` están destinadas a runners desechables; instalan aplicaciones y no deben ejecutarse en un PC con datos reales. Los workflows verifican PowerShell 5.1, apertura de WPF, sustitución segura, integridad del paquete, actividad y organización del escritorio.

## Privacidad y límites

No incluye correos, credenciales ni ajustes del autor. Conserva localmente registros técnicos, las preferencias de la ventana, los perfiles propios y un seguimiento por IDs de las aplicaciones que el usuario marca como configuradas. Los diagnósticos ocultan la ruta del perfil y patrones habituales de secretos y correos; revisa el TXT antes de compartirlo. Los proveedores externos gestionan sus propias cuentas y condiciones.

No se garantiza la instalación de todos los paquetes en todas las ediciones de Windows. Las restricciones empresariales, permisos, disponibilidad regional de Store y los cambios del proveedor pueden dejar una aplicación pendiente. La ausencia de contraseña propia no elimina UAC ni las comprobaciones de seguridad de Windows.

## Versiones y código fuente

| Versión | Fecha | Novedades | Código |
| --- | --- | --- | --- |
| v5.2 **(actual, pendiente de publicar)** | 2026-11-10 | Segundo plano con icono en la bandeja y monitor en vivo, «Windows a mano» con 81 atajos, animaciones, Brave limpio con marcadores visibles, instancia única y motor más resistente | [Ver código](https://github.com/iShun05/iWinInstaller/tree/main) |
| [v5.1](https://github.com/iShun05/iWinInstaller/releases/tag/v5.1) | 2026-11-09 | Apariencia renovada: barra de título oscura, navegación con iconos, Inicio en rejilla y controles oscuros en todas las pantallas | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v5.1) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v5.1.zip) |
| [v5.0](https://github.com/iShun05/iWinInstaller/releases/tag/v5.0) | 2026-11-09 | Centro de control del PC: una sola ventana nueva para instalar, actualizar, mantener, proteger y conectar; se retira la ventana clásica | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v5.0) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v5.0.zip) |
| [v4.9](https://github.com/iShun05/iWinInstaller/releases/tag/v4.9) | 2026-11-09 | Mantenimiento y salud: liberar espacio con confirmación, reparar Windows, salud de discos y batería e informe del equipo | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.9) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.9.zip) |
| [v4.8](https://github.com/iShun05/iWinInstaller/releases/tag/v4.8) | 2026-11-09 | Paleta de búsqueda (Ctrl + K) para llegar a cualquier acción o app | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.8) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.8.zip) |
| [v4.7](https://github.com/iShun05/iWinInstaller/releases/tag/v4.7) | 2026-11-09 | Sistema, Seguridad, Acceso remoto y Ajustes en la interfaz nueva | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.7) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.7.zip) |
| [v4.6](https://github.com/iShun05/iWinInstaller/releases/tag/v4.6) | 2026-11-09 | Instalar en la interfaz nueva: catálogo, perfiles, lotes con pausa, pasos y notas e informe | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.6) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.6.zip) |
| [v4.5](https://github.com/iShun05/iWinInstaller/releases/tag/v4.5) | 2026-11-08 | Actualizaciones en la interfaz nueva: lista con versiones, «Mantener esta versión» y actualización programada | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.5) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.5.zip) |
| [v4.4](https://github.com/iShun05/iWinInstaller/releases/tag/v4.4) | 2026-11-08 | Interfaz nueva con Inicio: estado del PC (actualizaciones, Windows Update, antivirus, discos, batería, reinicio) | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.4) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.4.zip) |
| [v4.3](https://github.com/iShun05/iWinInstaller/releases/tag/v4.3) | 2026-11-08 | Instalación protegida en Archivos de programa con migración automática; actualización programada como SYSTEM | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.3) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.3.zip) |
| [v4.2](https://github.com/iShun05/iWinInstaller/releases/tag/v4.2) | 2026-11-08 | Motor dividido por áreas, `-Check -Json`, contrato del motor e integridad de todos los archivos | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.2) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.2.zip) |
| [v4.1](https://github.com/iShun05/iWinInstaller/releases/tag/v4.1) | 2026-11-08 | Base de calidad: licencia MIT, esquema del catálogo, pruebas Pester y verificación automática de cada release | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.1) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.1.zip) |
| [v4.0](https://github.com/iShun05/iWinInstaller/releases/tag/v4.0) | 2026-11-03 | MyASUS, G-Helper y OCCT en el catálogo general; puesta a punto de portátiles y guías de GPU | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v4.0) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v4.0.zip) |
| [v3.9](https://github.com/iShun05/iWinInstaller/releases/tag/v3.9) | 2026-10-30 | Informe de fallos al terminar la instalación y auditoría: antivirus, códigos de salida, catálogo revisado contra WinGet | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.9) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.9.zip) |
| v3.8 (sin release: incluida en v3.9) | 2026-10-30 | Vincular equipos: controlar el PC desde un Mac u otro Windows por SSH con guía y comandos | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.8) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.8.zip) |
| v3.7 (sin release: incluida en v3.9) | 2026-10-30 | Panel Seguridad (Defender), sección antivirus y arreglos del instalador, directivas de usuario y PowerShell 7 | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.7) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.7.zip) |
| [v3.6](https://github.com/iShun05/iWinInstaller/releases/tag/v3.6) | 2026-10-29 | Subsecciones con comparativa («Cuál elegir»), resolución/frecuencia del monitor y ajustes de energía desde la app | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.6) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.6.zip) |
| [v3.5](https://github.com/iShun05/iWinInstaller/releases/tag/v3.5) | 2026-10-27 | Brave normal y Brave limpio reversible, sin datos personales | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.5) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.5.zip) |
| [v3.4](https://github.com/iShun05/iWinInstaller/releases/tag/v3.4) | 2026-10-26 | Apagar luces RGB funciona con OpenRGB 1.1 y su servicio | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.4) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.4.zip) |
| [v3.3](https://github.com/iShun05/iWinInstaller/releases/tag/v3.3) | 2026-10-26 | Control remoto por SSH solo desde Tailscale y solo con clave | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.3) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.3.zip) |
| [v3.2](https://github.com/iShun05/iWinInstaller/releases/tag/v3.2) | 2026-10-26 | Postinstalación guiada, notas, comprobaciones, lotes reanudables, restauración, instalación registrada y actualización automática opcional | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.2) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.2.zip) |
| [v3.1](https://github.com/iShun05/iWinInstaller/releases/tag/v3.1) | 2026-10-26 | Detección RGB corregida, bloqueo acotado, errores comprobados y versión coherente del instalador | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.1) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.1.zip) |
| [v3.0](https://github.com/iShun05/iWinInstaller/releases/tag/v3.0) | 2026-10-26 | Pantalla virtual para transmitir con los monitores apagados o desconectados | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.0) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.0.zip) |
| [v2.9](https://github.com/iShun05/iWinInstaller/releases/tag/v2.9) | 2026-10-26 | Portapapeles compartido Mac ↔ Windows con KDE Connect por Tailscale | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.9) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.9.zip) |
| [v2.8](https://github.com/iShun05/iWinInstaller/releases/tag/v2.8) | 2026-10-26 | Luces RGB apagadas siempre con OpenRGB y apps de los fabricantes según el hardware detectado | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.8) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.8.zip) |
| [v2.7](https://github.com/iShun05/iWinInstaller/releases/tag/v2.7) | 2026-10-26 | Escritorio remoto: PC siempre disponible con Sunshine y Tailscale, Autologon y Escritorio remoto de Chrome | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.7) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.7.zip) |
| [v2.6](https://github.com/iShun05/iWinInstaller/releases/tag/v2.6) | 2026-10-19 | Inicio manual sin selecciones automáticas, arquitectura visible y prueba de Windows corregida | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.6) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.6.zip) |
| [v2.5](https://github.com/iShun05/iWinInstaller/releases/tag/v2.5) | 2026-10-17 | Etiqueta Terminal, abrir desde el clic derecho, catálogo reorganizado y más apps de notas | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.5) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.5.zip) |
| [v2.4](https://github.com/iShun05/iWinInstaller/releases/tag/v2.4) | 2026-10-16 | ChatGPT pasa a la app nueva de OpenAI (Chat, Codex y agente) | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.4) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.4.zip) |
| [v2.3](https://github.com/iShun05/iWinInstaller/releases/tag/v2.3) | 2026-10-16 | Interfaz adaptable con zoom, desinstalar, perfiles exportables y 149 entradas nuevas | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.3) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.3.zip) |
| [v2.2](https://github.com/iShun05/iWinInstaller/releases/tag/v2.2) | 2026-10-15 | Auditoría de seguridad: firma del fabricante obligatoria, SHA256 de VirtualBox y procedencia firmada de las descargas | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.2) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.2.zip) |
| [v2.1](https://github.com/iShun05/iWinInstaller/releases/tag/v2.1) | 2026-10-14 | Catálogo en tres secciones (Sistema, Terminal y Aplicaciones), ajustes de Windows y pruebas en ARM64 | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.1) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.1.zip) |
| [v2.0](https://github.com/iShun05/iWinInstaller/releases/tag/v2.0) | 2026-10-14 | Instalador público, escritorio organizado y actividad legible | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.0) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.0.zip) |

## Licencia

[MIT](LICENSE). Firma de código: ver la [política de firma](docs/code-signing-policy.md).

## Contacto

[Instagram @_shun._05](https://www.instagram.com/_shun._05/)
