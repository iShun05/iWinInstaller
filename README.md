# iWinInstaller

Instalador de aplicaciones para Windows 10 y 11: selecciona programas, instálalos y comprueba el resultado desde una interfaz oscura en español.

## Descargar e instalar

[Descargar iWinInstaller-Setup.exe](https://github.com/iShun05/iWinInstaller/releases/latest/download/iWinInstaller-Setup.exe)

1. Descarga el instalador y ábrelo con doble clic.
2. Elige un perfil o marca las aplicaciones que necesites.
3. Pulsa **Instalar** y autoriza Windows cuando una aplicación requiera administrador.
   Para quitar algo, pulsa **Desinstalar** en su fila.
4. Al terminar, revisa los resultados. Los accesos de aplicaciones del escritorio se agrupan en **Aplicaciones**.

El EXE incluye el programa y los componentes de Microsoft para preparar WinGet. Las aplicaciones se descargan de sus fuentes oficiales y necesitan conexión. No requiere cuenta de GitHub ni contraseña propia. Windows puede mostrar SmartScreen porque el ejecutable no tiene certificado comercial: comprueba que procede de esta release antes de abrirlo.

Alternativa ZIP: [iWinInstaller.zip](https://github.com/iShun05/iWinInstaller/releases/latest/download/iWinInstaller.zip), descomprime y abre `iWinInstaller.exe`: la primera apertura instala y registra la misma app en Windows. Las versiones nuevas sustituyen esa instalación y conservan perfiles, notas y lotes. Para retirarla usa **Configuración de Windows › Aplicaciones instaladas › iWinInstaller › Desinstalar**; los programas instalados y tu seguimiento se conservan.

**Versión actual: v3.5** · Windows 10/11 · x86, x64 y ARM64 según los paquetes disponibles.

**Brave normal o Brave limpio**: en Navegadores puedes instalar Brave oficial tal cual o añadir una limpieza reversible: sin cripto, Leo, VPN ni noticias, con el perfil principal oscuro y sin tarjetas promocionales. Cierra Brave antes de aplicar o deshacer. No copia perfiles ni cuentas, conserva Shields/Sync y no acepta Widevine por ti. Los perfiles adicionales mantienen su aspecto; los widgets de búsqueda/reloj pueden requerir ajuste manual según la versión. Las políticas pueden mostrar «Administrado por tu organización». Para volver al estado anterior usa **Brave limpio → Deshacer**; instalar Brave normal no revierte estos ajustes.


## Funciones principales

- **Después de instalar**: botón permanente y «Pasos y notas» en cada opción relevante. Hay guías para **122 opciones**, pasos marcables y notas propias; «Comprobar de nuevo» y «Comprobar todo» separan la detección técnica de las confirmaciones manuales de cuentas, conexiones, licencias y pruebas físicas. El seguimiento se conserva al cerrar y actualizar.
- **Lotes recuperables**: el progreso se guarda antes y después de cada aplicación. **Pausar al terminar esta app** deja finalizar el instalador actual y conserva el resto. **Reanudar lote** continúa los pendientes más recientes; los anteriores también se conservan y se ofrecen al completar ese lote. Desde consola: `iWinInstaller.ps1 -Resume`. No se ejecuta un lote automáticamente tras reiniciar.
- **Resumen antes de instalar**: incluye dependencias, permisos, ajustes y reinicios previstos; comprueba espacio de preparación y conexión HTTPS al origen de WinGet. Los requisitos finales de cada proveedor pueden ser mayores.
- **Deshacer con estado anterior**: los ajustes reversibles aplicados desde v3.2 guardan valores y tipos originales. El ajuste de acceso remoto conserva energía, red, servicios y accesos. Si el cambio viene de una versión antigua sin estado guardado, se explica y se evita imponer valores genéricos. WSL y puntos de restauración no se deshacen desde aquí; RGB retira su tarea, sin recuperar colores físicos anteriores.
- **Reinicios visibles**: las aplicaciones que lo solicitan quedan identificadas hasta un nuevo arranque y se pueden comprobar otra vez. iWinInstaller no reinicia por su cuenta.
- **Actualización opcional de iWinInstaller**: en **⋯ › Actualizar iWinInstaller automáticamente**. Desactivada inicialmente; al activarla comprueba GitHub al abrir, al iniciar sesión y una vez al día con tu usuario. Descarga solo la nueva versión estable, verifica SHA256 y sustituye la app cuando se cierra. Si está abierta, la comprobación programada pospone el cambio. No actualiza otras aplicaciones ni ejecuta lotes pendientes. Se puede desactivar en el mismo menú; **Buscar nueva versión** permite hacerlo manualmente.

- **421 entradas en tres secciones**, cada una con sus categorías:
  - **Sistema**: ajustes de Windows (tema oscuro, extensiones visibles, menú contextual clásico, rutas largas, Inicio sin Bing, punto de restauración, alto rendimiento, modo desarrollador, WSL…), optimización y privacidad (O&O ShutUp10++, WinToys, Winhance, privacy.sexy, BleachBit…) y drivers y componentes (Visual C++, .NET, DirectX, NVIDIA, Intel).
  - **Terminal**: consola y shells (Windows Terminal, PowerShell 7, WezTerm, Starship, Oh My Posh, gsudo…), lenguajes y entornos (Git, Python, Node.js, Deno, Go, Rust, Java, .NET SDK, Ruby, Zig, C/C++ con LLVM, CMake y Build Tools, PostgreSQL, MongoDB…) y herramientas de línea de comandos (Claude Code, Codex CLI, lazygit, ripgrep, fzf, FFmpeg, yt-dlp, Azure y AWS CLI…).
  - **Aplicaciones**: todo lo que tiene ventana propia (juegos, navegadores, IA, utilidades, multimedia…).
  Los elementos opcionales se eligen expresamente. Los perfiles «Solo sistema» y «Solo terminal» marcan únicamente esa sección.
- **Escritorio remoto para jugar desde fuera** (Sistema › Acceso remoto o perfil «Escritorio remoto»): **PC siempre disponible** desactiva la suspensión y la hibernación con corriente, activa Wake-on-LAN y deja Sunshine y Tailscale como servicios automáticos que se reinician solos; Tailscale pasa a modo desatendido y deja una carpeta **Acceso remoto** en el escritorio y el menú Inicio con el panel de Sunshine, los equipos de Tailscale y Escritorio remoto de Chrome. **Autologon** (Sysinternals) inicia sesión al encender con la contraseña cifrada por Windows, y **Escritorio remoto de Chrome** sirve de respaldo por navegador cuando la red solo deja HTTPS. Ver [Jugar en remoto](#jugar-en-remoto).
- **Luces RGB apagadas** (Sistema › Iluminación RGB): **Apagar todas las luces RGB** instala OpenRGB y su driver PawnIO, anota placa, RAM, gráfica, controladoras USB y software RGB del fabricante en el registro, apaga cada dispositivo (modo Off o negro) y crea una tarea de SYSTEM que lo repite en cada arranque, también sin sesión. Incluido en el perfil «Escritorio remoto». Ver [Luces RGB](#luces-rgb).
- **Apps de tus componentes** (Sistema › Software de los fabricantes o perfil «Apps de mis componentes (detectadas)»): el perfil lee placa base, procesador, gráfica (y su fabricante), RAM, discos y dispositivos USB, y marca solo las apps de esas marcas: NVIDIA App, AMD Adrenalin, Intel DSA, Armoury Crate, GPU Tweak III, MSI Center, RGB Fusion, iCUE, NZXT CAM, L-Connect 3, G HUB, Synapse, SteelSeries GG, Samsung Magician, Kingston SSD Manager y Crucial Storage Executive. Cada una se puede instalar por separado. Con **Apagar todas las luces RGB** aplicado, el perfil omite las que gestionan iluminación, porque vuelven a encender los LED.
- **Desinstalar desde la app**: botón en cada fila instalada (o marca varias y pulsa **Desinstalar**). Pide confirmación, usa winget, Microsoft Store o el desinstalador oficial y comprueba que la app ya no está. Los ajustes reversibles recuperan el estado anterior guardado desde v3.2. Visual C++, .NET, DirectX, Edge y Store no se ofrecen.
- **Perfiles propios para llevar a otro PC**: **Guardar…** guarda lo marcado (y, si quieres, lo ya instalado); **⋯ › Exportar** crea un `.iwin.json`; en el otro PC, **Importar…** lo marca todo de una vez, o sin ventana: `iWinInstaller.ps1 -Silent -Perfil archivo.iwin.json`. Solo contiene ids del catálogo.
- **Pantallas pequeñas y máquinas virtuales**: la ventana se ajusta a la pantalla, oculta las secciones tras ☰ y agrupa acciones en ⋯ cuando falta sitio. **A− / A+**, `Ctrl + rueda` o `Ctrl + + / − / 0` cambian el tamaño de todo del 70 % al 200 % y se recuerda.
- **Detección de aplicaciones existentes** para evitar reinstalarlas. Una operación no se confirma únicamente por su código de salida.
- **Selección segura**: la ventana abre con el perfil Manual vacío; elige un perfil o marca elementos antes de instalar. La cabecera muestra la arquitectura del Windows, incluida ARM64.
- **Actividad visible**: aplicación actual, fases que comunica WinGet, resultado y duración. El TXT conserva la salida técnica completa de la sesión.
- **Escritorio organizado**: mueve accesos `.lnk` a ejecutables y accesos de juegos Steam/Epic a una carpeta Aplicaciones del escritorio del usuario. Incluye los accesos públicos cuando el lote tiene permisos. No mueve documentos, carpetas ni enlaces web generales; conserva ambos archivos cuando coincide el nombre.
- **Interfaz oscura** con búsqueda (`Ctrl + F`), filtros, navegación por teclado (`Espacio` marca, `Supr` desinstala), apertura de aplicaciones y notas y seguimiento de postinstalación con comprobaciones técnicas y pasos manuales.
- **Actualización pública** del instalador, con comprobación SHA256. Los lotes separan las instalaciones por usuario de las que requieren administrador.

Algunos productos necesitan su asistente o una suscripción. Norton VPN se instala desde la cuenta del proveedor: abrir sus instrucciones no se considera una instalación correcta. WSL puede requerir reiniciar Windows. La app no importa configuraciones personales ni administra proyectos de código.

## Jugar en remoto

1. En el PC de casa: perfil **Escritorio remoto (este PC como servidor)** › Instalar. Abre Tailscale e inicia sesión; vuelve a aplicar **PC siempre disponible** para el modo desatendido. En el panel de Tailscale, desactiva la caducidad de clave de este PC.
2. Abre `https://localhost:47990`, crea el usuario de Sunshine y empareja Moonlight con el PIN (una vez, en casa).
3. En la BIOS/UEFI: **Restore on AC Power Loss = Power On**, para que arranque solo tras un corte.
4. En el equipo cliente: Tailscale y Moonlight con la misma cuenta. Conecta a la IP `100.x` del PC.
5. Sin monitor: **Pantalla virtual** (Virtual Display Driver) instala el controlador y **Activar monitor virtual** crea el monitor, así que Sunshine sigue funcionando con las pantallas apagadas o el HDMI desconectado. Con el monitor encendido, `Win + P` › Duplicar.
6. Portapapeles compartido: KDE Connect en los dos equipos (en macOS, `brew install --cask kde-connect`). Vincúlalos añadiendo la IP `100.x` del PC y acepta en el PC; lo copiado en uno se pega en el otro. Si del Mac al PC no pasa nada, en KDE Connect del Mac abre el PC › ajustes del plugin **Portapapeles** y activa el envío automático, y comprueba que en el PC se ejecutó **PC siempre disponible** (abre los puertos 1714-1764 solo a Tailscale).
7. Control por comandos: **Control remoto por SSH (Tailscale)** activa OpenSSH Server con PowerShell, solo claves y el puerto 22 abierto únicamente para `100.64.0.0/10`. Pega la clave pública del Mac en el archivo que abre la app y conecta con `ssh <usuario>@<IP 100.x>`.

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

PowerShell 5.1 y WPF para la interfaz; C# y .NET Framework incluido en Windows para los ejecutables; WinGet y Microsoft Store para los paquetes; Python estándar para construir la alternativa BAT. Sin servicio propio ni telemetría propia. La actualización opcional utiliza una tarea de Windows de tu usuario; permanece desactivada hasta que la habilites.

## Estructura

| Archivo | Función |
| --- | --- |
| `iWinInstaller.ps1` | Interfaz, inventario, lotes, organización del escritorio y diagnóstico |
| `apps.json`, `profiles.json` | Catálogo, guías de postinstalación y perfiles |
| `lifecycle.ps1` | Lotes, comprobaciones, restauración y actualizaciones opcionales |
| `install.ps1`, `launch.ps1`, `Iniciar.bat` | Instalación, desinstalación y apertura |
| `native/` | Lanzador C#, manifiesto y dependencias Microsoft verificadas |
| `scripts/` | Construcción del EXE y BAT |
| `tests/` | Pruebas aisladas y aceptación en un Windows desechable |
| `assets/` | Iconos |

## Compilar e instalar

En Windows, con Git y PowerShell disponibles:

```powershell
git clone https://github.com/iShun05/iWinInstaller.git
cd iWinInstaller
git checkout v3.5
./scripts/build_exe.ps1 -OutputDirectory "$env:TEMP/iwin-release" -Ref v3.5
```

Abre `iWinInstaller-Setup.exe` del directorio de salida. El compilador C# de .NET Framework está incluido en Windows. La construcción descarga los paquetes Microsoft cuyos hashes están fijados en `native/prerequisites.json`.

El EXE AnyCPU funciona como proceso de 32 bits en Windows x86 y usa el host nativo en x64/ARM64. CI ejecuta también PowerShell de 32 bits y un lanzador compilado x86 en Windows x64, además de los runners x64/ARM64. Los instaladores oficiales incluidos deben contener x86, x64 y ARM64. Algunos programas del catálogo solo existen para ciertas arquitecturas; un controlador de kernel debe corresponder al Windows real. La matriz no equivale a probar un Windows 10 de 32 bits completo.

Las pruebas de `check-native.ps1` y `check-acceptance.ps1` están destinadas a runners desechables; instalan aplicaciones y no deben ejecutarse en un PC con datos reales. Los workflows verifican PowerShell 5.1, apertura de WPF, sustitución segura, integridad del paquete, actividad y organización del escritorio.

## Privacidad y límites

No incluye correos, credenciales ni ajustes del autor. Conserva localmente registros técnicos, las preferencias de la ventana, los perfiles propios y un seguimiento por IDs de las aplicaciones que el usuario marca como configuradas. Los diagnósticos ocultan la ruta del perfil y patrones habituales de secretos y correos; revisa el TXT antes de compartirlo. Los proveedores externos gestionan sus propias cuentas y condiciones.

No se garantiza la instalación de todos los paquetes en todas las ediciones de Windows. Las restricciones empresariales, permisos, disponibilidad regional de Store y los cambios del proveedor pueden dejar una aplicación pendiente. La ausencia de contraseña propia no elimina UAC ni las comprobaciones de seguridad de Windows.

## Versiones y código fuente

| Versión | Fecha | Novedades | Código |
| --- | --- | --- | --- |
| [v3.5](https://github.com/iShun05/iWinInstaller/releases/tag/v3.5) **(actual)** | 2026-10-27 | Brave normal y Brave limpio reversible, sin datos personales | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v3.5) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v3.5.zip) |
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

## Contacto

[Instagram @_shun._05](https://www.instagram.com/_shun._05/)
