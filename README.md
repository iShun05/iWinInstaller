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

Alternativa portátil: [iWinInstaller.zip](https://github.com/iShun05/iWinInstaller/releases/latest/download/iWinInstaller.zip), descomprimir y abrir `iWinInstaller.exe`. Para desinstalar el programa, ejecuta `install.ps1 -Uninstall`; las aplicaciones instaladas se conservan.

**Versión actual: v2.7** · Windows 10/11 · x86, x64 y ARM64 según los paquetes disponibles.

## Funciones principales

- **400 entradas en tres secciones**, cada una con sus categorías:
  - **Sistema**: ajustes de Windows (tema oscuro, extensiones visibles, menú contextual clásico, rutas largas, Inicio sin Bing, punto de restauración, alto rendimiento, modo desarrollador, WSL…), optimización y privacidad (O&O ShutUp10++, WinToys, Winhance, privacy.sexy, BleachBit…) y drivers y componentes (Visual C++, .NET, DirectX, NVIDIA, Intel).
  - **Terminal**: consola y shells (Windows Terminal, PowerShell 7, WezTerm, Starship, Oh My Posh, gsudo…), lenguajes y entornos (Git, Python, Node.js, Deno, Go, Rust, Java, .NET SDK, Ruby, Zig, C/C++ con LLVM, CMake y Build Tools, PostgreSQL, MongoDB…) y herramientas de línea de comandos (Claude Code, Codex CLI, lazygit, ripgrep, fzf, FFmpeg, yt-dlp, Azure y AWS CLI…).
  - **Aplicaciones**: todo lo que tiene ventana propia (juegos, navegadores, IA, utilidades, multimedia…).
  Los elementos opcionales se eligen expresamente. Los perfiles «Solo sistema» y «Solo terminal» marcan únicamente esa sección.
- **Escritorio remoto para jugar desde fuera** (Sistema › Acceso remoto o perfil «Escritorio remoto»): **PC siempre disponible** desactiva la suspensión y la hibernación con corriente, activa Wake-on-LAN y deja Sunshine y Tailscale como servicios automáticos que se reinician solos; Tailscale pasa a modo desatendido. **Autologon** (Sysinternals) inicia sesión al encender con la contraseña cifrada por Windows, y **Escritorio remoto de Chrome** sirve de respaldo por navegador cuando la red solo deja HTTPS. Ver [Jugar en remoto](#jugar-en-remoto).
- **Desinstalar desde la app**: botón en cada fila instalada (o marca varias y pulsa **Desinstalar**). Pide confirmación, usa winget, Microsoft Store o el desinstalador oficial y comprueba que la app ya no está. Los ajustes de Windows se deshacen igual. Visual C++, .NET, DirectX, Edge y Store no se ofrecen.
- **Perfiles propios para llevar a otro PC**: **Guardar…** guarda lo marcado (y, si quieres, lo ya instalado); **⋯ › Exportar** crea un `.iwin.json`; en el otro PC, **Importar…** lo marca todo de una vez, o sin ventana: `iWinInstaller.ps1 -Silent -Perfil archivo.iwin.json`. Solo contiene ids del catálogo.
- **Pantallas pequeñas y máquinas virtuales**: la ventana se ajusta a la pantalla, oculta las secciones tras ☰ y agrupa acciones en ⋯ cuando falta sitio. **A− / A+**, `Ctrl + rueda` o `Ctrl + + / − / 0` cambian el tamaño de todo del 70 % al 200 % y se recuerda.
- **Detección de aplicaciones existentes** para evitar reinstalarlas. Una operación no se confirma únicamente por su código de salida.
- **Selección segura**: la ventana abre con el perfil Manual vacío; elige un perfil o marca elementos antes de instalar. La cabecera muestra la arquitectura del Windows, incluida ARM64.
- **Actividad visible**: aplicación actual, fases que comunica WinGet, resultado y duración. El TXT conserva la salida técnica completa de la sesión.
- **Escritorio organizado**: mueve accesos `.lnk` a ejecutables y accesos de juegos Steam/Epic a una carpeta Aplicaciones del escritorio del usuario. Incluye los accesos públicos cuando el lote tiene permisos. No mueve documentos, carpetas ni enlaces web generales; conserva ambos archivos cuando coincide el nombre.
- **Interfaz oscura** con búsqueda (`Ctrl + F`), filtros, navegación por teclado (`Espacio` marca, `Supr` desinstala), apertura de aplicaciones y seguimiento manual de sesiones pendientes.
- **Actualización pública** del instalador, con comprobación SHA256. Los lotes separan las instalaciones por usuario de las que requieren administrador.

Algunos productos necesitan su asistente o una suscripción. Norton VPN se instala desde la cuenta del proveedor: abrir sus instrucciones no se considera una instalación correcta. WSL puede requerir reiniciar Windows. La app no importa configuraciones personales ni administra proyectos de código.

## Jugar en remoto

1. En el PC de casa: perfil **Escritorio remoto (este PC como servidor)** › Instalar. Abre Tailscale e inicia sesión; vuelve a aplicar **PC siempre disponible** para el modo desatendido. En el panel de Tailscale, desactiva la caducidad de clave de este PC.
2. Abre `https://localhost:47990`, crea el usuario de Sunshine y empareja Moonlight con el PIN (una vez, en casa).
3. En la BIOS/UEFI: **Restore on AC Power Loss = Power On**, para que arranque solo tras un corte.
4. En el equipo cliente: Tailscale y Moonlight con la misma cuenta. Conecta a la IP `100.x` del PC.

Si la red bloquea UDP, Tailscale va por sus relés HTTPS (443): funciona, con más latencia. Para jugar fluido en una red muy filtrada, conecta el cliente a los datos del móvil. Escritorio remoto de Chrome es el respaldo para trabajar desde un navegador. Respeta las normas de uso de la red en la que estés.

## Tecnología

PowerShell 5.1 y WPF para la interfaz; C# y .NET Framework incluido en Windows para los ejecutables; WinGet y Microsoft Store para los paquetes; Python estándar para construir la alternativa BAT. Sin servicio propio ni telemetría propia.

## Estructura

| Archivo | Función |
| --- | --- |
| `iWinInstaller.ps1` | Interfaz, inventario, lotes, organización del escritorio y diagnóstico |
| `apps.json`, `profiles.json` | Catálogo y perfiles |
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
git checkout v2.7
./scripts/build_exe.ps1 -OutputDirectory "$env:TEMP/iwin-release" -Ref v2.7
```

Abre `iWinInstaller-Setup.exe` del directorio de salida. El compilador C# de .NET Framework está incluido en Windows. La construcción descarga los paquetes Microsoft cuyos hashes están fijados en `native/prerequisites.json`.

Las pruebas de `check-native.ps1` y `check-acceptance.ps1` están destinadas a runners desechables; instalan aplicaciones y no deben ejecutarse en un PC con datos reales. Los workflows verifican PowerShell 5.1, apertura de WPF, sustitución segura, integridad del paquete, actividad y organización del escritorio.

## Privacidad y límites

No incluye correos, credenciales ni ajustes del autor. Conserva localmente registros técnicos, las preferencias de la ventana, los perfiles propios y un seguimiento por IDs de las aplicaciones que el usuario marca como configuradas. Los diagnósticos ocultan la ruta del perfil y patrones habituales de secretos y correos; revisa el TXT antes de compartirlo. Los proveedores externos gestionan sus propias cuentas y condiciones.

No se garantiza la instalación de todos los paquetes en todas las ediciones de Windows. Las restricciones empresariales, permisos, disponibilidad regional de Store y los cambios del proveedor pueden dejar una aplicación pendiente. La ausencia de contraseña propia no elimina UAC ni las comprobaciones de seguridad de Windows.

## Versiones y código fuente

| Versión | Fecha | Novedades | Código |
| --- | --- | --- | --- |
| [v2.7](https://github.com/iShun05/iWinInstaller/releases/tag/v2.7) **(actual)** | 2026-10-26 | Escritorio remoto: PC siempre disponible con Sunshine y Tailscale, Autologon y Escritorio remoto de Chrome | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.7) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.7.zip) |
| [v2.6](https://github.com/iShun05/iWinInstaller/releases/tag/v2.6) | 2026-10-19 | Inicio manual sin selecciones automáticas, arquitectura visible y prueba de Windows corregida | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.6) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.6.zip) |
| [v2.5](https://github.com/iShun05/iWinInstaller/releases/tag/v2.5) | 2026-10-17 | Etiqueta Terminal, abrir desde el clic derecho, catálogo reorganizado y más apps de notas | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.5) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.5.zip) |
| [v2.4](https://github.com/iShun05/iWinInstaller/releases/tag/v2.4) | 2026-10-16 | ChatGPT pasa a la app nueva de OpenAI (Chat, Codex y agente) | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.4) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.4.zip) |
| [v2.3](https://github.com/iShun05/iWinInstaller/releases/tag/v2.3) | 2026-10-16 | Interfaz adaptable con zoom, desinstalar, perfiles exportables y 149 entradas nuevas | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.3) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.3.zip) |
| [v2.2](https://github.com/iShun05/iWinInstaller/releases/tag/v2.2) | 2026-10-15 | Auditoría de seguridad: firma del fabricante obligatoria, SHA256 de VirtualBox y procedencia firmada de las descargas | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.2) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.2.zip) |
| [v2.1](https://github.com/iShun05/iWinInstaller/releases/tag/v2.1) | 2026-10-14 | Catálogo en tres secciones (Sistema, Terminal y Aplicaciones), ajustes de Windows y pruebas en ARM64 | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.1) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.1.zip) |
| [v2.0](https://github.com/iShun05/iWinInstaller/releases/tag/v2.0) | 2026-10-14 | Instalador público, escritorio organizado y actividad legible | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.0) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.0.zip) |

## Contacto

[Instagram @_shun._05](https://www.instagram.com/_shun._05/)
