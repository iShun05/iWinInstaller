# Historial de versiones

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
