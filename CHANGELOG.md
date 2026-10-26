# Historial de versiones

## v3.3 — 2026-10-26

### Añadido
- **Control remoto por SSH (Tailscale)** en Sistema › Acceso remoto y en el perfil **Escritorio remoto**: instala OpenSSH Server si falta, pone PowerShell como shell, desactiva contraseñas (solo claves), protege `administrators_authorized_keys`, sustituye la regla de Windows del puerto 22 por una limitada a Tailscale (`100.64.0.0/10`) y deja `sshd` automático. Comprueba la configuración con `sshd -t` y la deja como estaba si falla. Abre el archivo de claves para pegar la del Mac.
- Restauración: guarda y recupera el servicio, la regla de Windows, `sshd_config` y el shell por defecto.

### Archivos y pruebas
- **Archivos**: `iWinInstaller.ps1`, `lifecycle.ps1`, `apps.json`, `profiles.json`, `README.md`, `tests/check-acceptance.ps1`.
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
