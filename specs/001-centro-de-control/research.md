# Investigación y decisiones: camino a v5.0

Fecha: 2026-11-08. Cada decisión indica lo elegido, el motivo y las alternativas descartadas.

## R1. Firma de código

- **Decisión**: SignPath Foundation (programa gratuito para código abierto), integrado en
  `release.yml` como paso de firma de `iWinInstaller.exe`, `iWinInstaller-Setup.exe` y el lanzador.
- **Motivo**: elección del usuario; gratis y con la clave en un HSM gestionado. El repositorio ya es
  público.
- **Requisitos que hay que cumplir antes de solicitarlo** (los pone SignPath, no el proyecto):
  licencia aprobada por OSI en todos los componentes, sin código propietario, proyecto mantenido y
  ya publicado, verificación en dos pasos en todas las cuentas del equipo y una página pública de
  política de firma. Hoy el repositorio **no tiene licencia**: hay que añadir una (propuesta: MIT).
- **Consecuencia visible**: el editor que muestra Windows es «SignPath Foundation», no el nombre del
  autor. La reputación de SmartScreen se acumula con las descargas; los primeros días puede seguir
  habiendo aviso.
- **Alternativas descartadas**: Azure Artifact Signing (9,99 $/mes, solo particulares de EE. UU. o
  Canadá); Certum Open Source (desde ~49 €/año, de pago); sin firma (mantiene el aviso).
- **Acción del usuario**: aceptar la licencia y enviar la solicitud en signpath.org. Los agentes no
  envían formularios ni aceptan términos por el usuario.

## R2. Tecnología de la interfaz

- **Decisión**: nueva interfaz WPF en C# (patrón MVVM ligero, sin dependencias externas) dirigida a
  .NET Framework 4.8. El motor sigue en PowerShell 5.1, dividido en módulos `.psm1`.
- **Motivo**: elección del usuario. .NET Framework 4.8 viene con Windows 10 (1903+) y 11, ya se usa
  en el lanzador y no añade runtimes. C# da arranque más rápido, enlace de datos, virtualización de
  listas (427 entradas) y pruebas unitarias reales.
- **Compilación**: proyecto con formato SDK (`Microsoft.NET.Sdk`, `UseWPF`, `net48`) compilado en
  los runners Windows de CI con el SDK de .NET; las referencias de .NET Framework llegan por el
  paquete oficial de ensamblados de referencia. El EXE resultante solo necesita .NET Framework 4.8.
  La ruta actual con `csc.exe` incluido en Windows se mantiene para el lanzador hasta v4.4 y después
  se unifica.
- **ARM64**: AnyCPU; en Windows 11 ARM64 con .NET Framework 4.8.1 corre nativo, en 4.8 por
  emulación x64. Se verifica en el runner ARM64.
- **Alternativas descartadas**: seguir con WPF en PowerShell (lento y frágil a este tamaño);
  WinUI 3/.NET 8 (requiere runtime aparte o publicación autocontenida de >60 MB y Windows App SDK);
  Electron/web (peso y superficie de ataque).

## R3. Comunicación interfaz ↔ motor

- **Decisión**: la interfaz lanza procesos `powershell.exe` del motor con un contrato de archivos
  JSON (plan de entrada, resultado de salida) y un canal de eventos JSONL, generalizando el modo
  `-WorkerMode/-PlanFile/-ResultFile/-SharedLog` que ya existe. Lecturas rápidas y sin privilegios
  (disco, batería, CIM) se hacen directamente en C#.
- **Motivo**: la elevación (UAC) exige un proceso aparte de todas formas; reutiliza el modelo de
  lotes reanudables probado desde v3.2; aísla fallos del motor de la ventana.
- **Alternativas descartadas**: alojar un runspace de PowerShell dentro del proceso C#
  (`System.Management.Automation`): no resuelve la elevación y un bloqueo del motor congela la
  interfaz.

## R4. Instalación protegida y actualización

- **Decisión**: el programa se instala en `%ProgramFiles%\iWinInstaller` (por equipo, una UAC al
  instalar). Los datos del usuario siguen en `%LOCALAPPDATA%\iWinInstaller` (perfiles, notas, lotes,
  informes, preferencias), por lo que la migración solo mueve el programa y elimina la copia antigua
  de `%LOCALAPPDATA%\Programs\iWinInstaller` tras verificar la nueva.
- **Actualización automática**: tarea programada como SYSTEM que solo descarga de la release
  oficial, comprueba SHA256 y, cuando haya firma, el editor esperado; si la firma aún no existe, la
  actualización pide UAC al usuario en lugar de ejecutarse como SYSTEM.
- **Motivo**: cierra el límite documentado en SECURITY.md (un proceso del usuario podía alterar la
  app antes de una elevación).
- **Alternativas descartadas**: mantener la instalación por usuario; servicio de Windows propio
  (más superficie, contradice «sin servicio propio»).

## R5. Pruebas

- **Decisión**: tres niveles.
  1. **Unitarias**: Pester 5 para los módulos del motor (lógica pura: plan de instalación, códigos,
     informes, exclusiones, limpieza simulada) y MSTest/xUnit para los ViewModel de C#.
  2. **Integración en CI Windows** (x64, ARM64, proceso x86): las suites actuales (`tests/check-*`)
     se mantienen y se adaptan al nuevo EXE.
  3. **Aceptación** en runners desechables: instalar/actualizar/desinstalar reales y aplicar →
     deshacer → comparar estado (SC-005).
- **Motivo**: la constitución exige prueba por cambio de comportamiento y puertas sin
  `continue-on-error`.

## R6. Estado del PC (fuentes de datos)

| Tarjeta | Fuente | Sin datos |
|---|---|---|
| Actualizaciones de apps | `winget upgrade` (motor) | «No se pudo comprobar» + motivo |
| Windows Update | API COM de Windows Update (solo lectura) | Igual |
| Antivirus | `Get-MpComputerStatus` / Centro de seguridad (WMI `SecurityCenter2`) | Igual |
| Espacio | `DriveInfo` (C#) | — |
| Salud de discos | `MSFT_PhysicalDisk` / `MSFT_StorageReliabilityCounter` (CIM) | «No disponible» |
| Batería | `powercfg /batteryreport` (XML) y `BatteryStaticData` (WMI) | Tarjeta oculta |
| Temperaturas | `MSAcpi_ThermalZoneTemperature` cuando existe | «No disponible»; sin drivers de terceros |
| Reinicio pendiente | Claves conocidas de CBS/WU/PendingFileRename + estado propio | — |
| Lotes sin terminar | Estado de lotes existente (`lifecycle.ps1`) | — |

## R7. Validación del catálogo

- **Decisión**: JSON Schema (draft 2020-12) para `apps.json` y `profiles.json`, validado en CI con
  una prueba Pester; el catálogo se divide en un archivo por sección/categoría bajo `catalog/` y el
  build los une en un único archivo incluido en la app.
- **Motivo**: 240 KB en un archivo dificultan revisar cambios; el esquema impide entradas rotas.
