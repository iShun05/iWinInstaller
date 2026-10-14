# iWinInstaller

Instalador de aplicaciones para Windows 10 y 11: selecciona programas, instálalos y comprueba el resultado desde una interfaz oscura en español.

## Descargar e instalar

[Descargar iWinInstaller-Setup.exe](https://github.com/iShun05/iWinInstaller/releases/latest/download/iWinInstaller-Setup.exe)

1. Descarga el instalador y ábrelo con doble clic.
2. Elige un perfil o marca las aplicaciones que necesites.
3. Pulsa **Instalar** y autoriza Windows cuando una aplicación requiera administrador.
4. Al terminar, revisa los resultados. Los accesos de aplicaciones del escritorio se agrupan en **Aplicaciones**.

El EXE incluye el programa y los componentes de Microsoft para preparar WinGet. Las aplicaciones se descargan de sus fuentes oficiales y necesitan conexión. No requiere cuenta de GitHub ni contraseña propia. Windows puede mostrar SmartScreen porque el ejecutable no tiene certificado comercial: comprueba que procede de esta release antes de abrirlo.

Alternativa portátil: [iWinInstaller.zip](https://github.com/iShun05/iWinInstaller/releases/latest/download/iWinInstaller.zip), descomprimir y abrir `iWinInstaller.exe`. Para desinstalar el programa, ejecuta `install.ps1 -Uninstall`; las aplicaciones instaladas se conservan.

**Versión actual: v2.1** · Windows 10/11 · x86, x64 y ARM64 según los paquetes disponibles.

## Funciones principales

- **238 entradas en tres secciones**, cada una con sus categorías:
  - **Sistema**: ajustes de Windows (tema oscuro, extensiones visibles, punto de restauración, alto rendimiento, modo desarrollador, WSL), optimización y privacidad (O&O ShutUp10++, WinToys, Winhance, BleachBit, Autoruns) y drivers y componentes (Visual C++, .NET, DirectX, NVIDIA).
  - **Terminal**: consola y shells, lenguajes y entornos (Git, Python, Node.js, Go, Rust, Java, PHP…) y herramientas de línea de comandos (Claude Code, ripgrep, fzf, FFmpeg, yt-dlp…).
  - **Aplicaciones**: todo lo que tiene ventana propia (juegos, navegadores, IA, utilidades, multimedia…).
  Los elementos opcionales se eligen expresamente. Los perfiles «Solo sistema» y «Solo terminal» marcan únicamente esa sección.
- **Detección de aplicaciones existentes** para evitar reinstalarlas. Una operación no se confirma únicamente por su código de salida.
- **Actividad visible**: aplicación actual, fases que comunica WinGet, resultado y duración. El TXT conserva la salida técnica completa de la sesión.
- **Escritorio organizado**: mueve accesos `.lnk` a ejecutables y accesos de juegos Steam/Epic a una carpeta Aplicaciones del escritorio del usuario. Incluye los accesos públicos cuando el lote tiene permisos. No mueve documentos, carpetas ni enlaces web generales; conserva ambos archivos cuando coincide el nombre.
- **Interfaz oscura** con búsqueda, filtros, navegación por teclado, apertura de aplicaciones y seguimiento manual de sesiones pendientes.
- **Actualización pública** del instalador, con comprobación SHA256. Los lotes separan las instalaciones por usuario de las que requieren administrador.

Algunos productos necesitan su asistente o una suscripción. Norton VPN se instala desde la cuenta del proveedor: abrir sus instrucciones no se considera una instalación correcta. WSL puede requerir reiniciar Windows. La app no importa configuraciones personales ni administra proyectos de código.

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
git checkout v2.0
./scripts/build_exe.ps1 -OutputDirectory "$env:TEMP/iwin-release" -Ref v2.0
```

Abre `iWinInstaller-Setup.exe` del directorio de salida. El compilador C# de .NET Framework está incluido en Windows. La construcción descarga los paquetes Microsoft cuyos hashes están fijados en `native/prerequisites.json`.

Las pruebas de `check-native.ps1` y `check-acceptance.ps1` están destinadas a runners desechables; instalan aplicaciones y no deben ejecutarse en un PC con datos reales. Los workflows verifican PowerShell 5.1, apertura de WPF, sustitución segura, integridad del paquete, actividad y organización del escritorio.

## Privacidad y límites

No incluye correos, credenciales ni ajustes del autor. Conserva localmente registros técnicos y un seguimiento por IDs de las aplicaciones que el usuario marca como configuradas. Los diagnósticos ocultan la ruta del perfil y patrones habituales de secretos y correos; revisa el TXT antes de compartirlo. Los proveedores externos gestionan sus propias cuentas y condiciones.

No se garantiza la instalación de todos los paquetes en todas las ediciones de Windows. Las restricciones empresariales, permisos, disponibilidad regional de Store y los cambios del proveedor pueden dejar una aplicación pendiente. La ausencia de contraseña propia no elimina UAC ni las comprobaciones de seguridad de Windows.

## Versiones y código fuente

| Versión | Fecha | Novedades | Código |
| --- | --- | --- | --- |
| [v2.1](https://github.com/iShun05/iWinInstaller/releases/tag/v2.1) **(actual)** | 2026-10-14 | Catálogo en tres secciones (Sistema, Terminal y Aplicaciones), ajustes de Windows y pruebas en ARM64 | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.1) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.1.zip) |
| [v2.0](https://github.com/iShun05/iWinInstaller/releases/tag/v2.0) | 2026-10-14 | Instalador público, escritorio organizado y actividad legible | [Ver código](https://github.com/iShun05/iWinInstaller/tree/v2.0) · [ZIP](https://github.com/iShun05/iWinInstaller/archive/refs/tags/v2.0.zip) |

## Ubicación de desarrollo en el Mac

Desde el 2026-10-14, la copia de trabajo está en `/Users/david/Documents/Desarrollo/iWinInstaller` (SSD interno). Los registros oficiales están en `/Users/david/Documents/Registro_Cambios/` y las cachés compartidas en `/Users/david/Documents/Cache_Dev/`. Las rutas anteriores de desarrollo en SanDisk quedan retiradas; el proyecto puede desarrollarse sin conectar ese disco.


## Contacto

[Instagram @_shun._05](https://www.instagram.com/_shun._05/)
