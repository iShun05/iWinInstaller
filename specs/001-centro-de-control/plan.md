# Implementation Plan: Centro de control del PC (camino a v5.0)

**Branch**: `main` | **Date**: 2026-11-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-centro-de-control/spec.md`

## Summary

Convertir iWinInstaller en el centro de control del PC con Windows entregando US1–US5 en nueve
versiones incrementales (v4.1 → v5.0). Primero se refuerza la base (CI estricta, verificación de
releases, esquema del catálogo, motor modular, instalación protegida y firma con SignPath); después
se sustituye la interfaz PowerShell por una interfaz WPF en C# que llama al motor PowerShell por un
contrato JSON, y sobre ella se añaden inicio con estado del PC, actualizaciones con exclusiones,
paleta de búsqueda y mantenimiento/salud. Detalle de decisiones en [research.md](research.md).

## Technical Context

**Language/Version**: C# 7.3 sobre .NET Framework 4.8 (interfaz y lanzador); PowerShell 5.1
(motor). Python 3 estándar solo para construir la alternativa BAT.

**Primary Dependencies**: WPF (.NET Framework), WinGet y Microsoft Store, CIM/WMI de Windows. Sin
paquetes de terceros en tiempo de ejecución. En CI: SDK de .NET (compilación), Pester 5, servicio
de firma de SignPath.

**Storage**: archivos JSON locales en `%LOCALAPPDATA%\iWinInstaller` (preferencias, perfiles,
notas, lotes, informes, exclusiones); estado de ajustes reversibles donde ya se guarda hoy.

**Testing**: Pester 5 (motor), MSTest (ViewModel C#), suites `tests/check-*.ps1` en CI Windows,
aceptación en runners desechables.

**Target Platform**: Windows 10 1903+ y Windows 11; x86, x64 y ARM64.

**Project Type**: aplicación de escritorio (interfaz C#) con motor de scripts y CLI.

**Performance Goals**: inicio utilizable < 2 s; todas las tarjetas < 15 s con red; paleta con
resultados en < 100 ms por pulsación; lista del catálogo virtualizada a 60 fps al desplazarse.

**Constraints**: sin servicio propio ni telemetría; elevación solo por operación agrupada; ningún
archivo de código > ~1.500 líneas; funciona sin conexión en lo que no requiere red; release no se
publica si falla cualquier comprobación de la matriz.

**Scale/Scope**: 427 entradas de catálogo, 122 guías, 10 módulos de navegación, ~143 funciones
actuales del archivo principal y 59 de `lifecycle.ps1` a redistribuir.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principio | Cómo lo cumple el plan | Estado |
|---|---|---|
| I. Seguridad verificable | Firma SignPath, instalación en Program Files, actualizador que verifica SHA256 y editor, sin nuevas conexiones salvo orígenes, Microsoft y GitHub | ✅ |
| II. Reversible y honesto | Tarjetas con estado «no se pudo comprobar»; limpieza con estimación y confirmación; prueba aplicar → deshacer en aceptación | ✅ |
| III. Calidad en Windows real | v4.1 quita `continue-on-error` de las puertas y añade verificación posterior a la release; Pester y MSTest en CI | ✅ |
| IV. Modular y declarativo | Motor en módulos, catálogo por categorías con esquema, interfaz MVVM por módulo | ✅ |
| V. Interfaz negra y accesible | Tema oscuro único, navegación por teclado, zoom 70–200 %, versión e Instagram en Acerca de | ✅ |
| Restricciones de plataforma | .NET Framework 4.8 incluido en Windows; SDK de .NET solo en CI (justificado abajo) | ✅ con justificación |
| Flujo y versiones | Una versión `+0.1` por fase, cada una con CHANGELOG, README, tag y release | ✅ |

Re-evaluado tras la fase 1 (data-model, contratos): sin nuevas violaciones.

## Project Structure

### Documentation (this feature)

```text
specs/001-centro-de-control/
├── spec.md
├── plan.md              # Este archivo
├── research.md          # Decisiones R1–R7
├── data-model.md        # Entidades y estados
├── quickstart.md        # Validación de punta a punta por versión
├── contracts/
│   ├── engine.md        # Contrato interfaz ↔ motor (JSON + eventos JSONL)
│   └── cli.md           # Línea de comandos pública y códigos de salida
├── checklists/
│   └── requirements.md
└── tasks.md             # Generado por /speckit-tasks
```

### Source Code (repository root)

```text
src/
├── app/                         # Interfaz WPF en C# (net48)
│   ├── iWinInstaller.App.csproj
│   ├── App.xaml / Theme/        # Tema negro, tipografía, iconos monoline
│   ├── Shell/                   # Ventana, navegación lateral, paleta de búsqueda
│   ├── Modules/
│   │   ├── Home/                # US2 tarjetas de estado
│   │   ├── Install/             # Catálogo, perfiles, guías, informe
│   │   ├── Updates/             # US3
│   │   ├── Maintenance/         # US5 limpieza, reparación, salud, informe del equipo
│   │   ├── System/              # Ajustes, pantalla, energía
│   │   ├── Remote/              # Acceso remoto, vincular equipos
│   │   └── Security/            # Defender
│   ├── Engine/                  # Cliente del contrato engine.md (procesos, JSONL)
│   └── Probes/                  # Lecturas rápidas en C# (disco, batería, reinicio)
├── engine/                      # Motor PowerShell
│   ├── iwin-engine.ps1          # Punto de entrada único del contrato
│   ├── Iwin.Catalog.psm1
│   ├── Iwin.Batch.psm1          # Lotes, reanudación (hoy en lifecycle.ps1)
│   ├── Iwin.Packages.psm1       # WinGet/Store/directos, detección
│   ├── Iwin.Tweaks.psm1         # Ajustes reversibles y snapshots
│   ├── Iwin.Remote.psm1
│   ├── Iwin.Security.psm1
│   ├── Iwin.Maintenance.psm1    # US5
│   ├── Iwin.Updates.psm1        # US3 exclusiones y programación
│   └── Iwin.Report.psm1
├── launcher/                    # Lanzador/instalador nativo (hoy native/)
└── catalog/                     # Catálogo por categorías + schema/*.json
tests/
├── unit/engine/                 # Pester
├── unit/app/                    # MSTest (iWinInstaller.App.Tests.csproj)
└── check-*.ps1                  # Integración/aceptación existentes
```

**Structure Decision**: un único repositorio con interfaz (`src/app`), motor (`src/engine`),
lanzador (`src/launcher`) y datos (`src/catalog`). Los archivos raíz actuales (`iWinInstaller.ps1`,
`lifecycle.ps1`, `install.ps1`, `native/`) se mantienen funcionando hasta que su sustituto llega a
paridad y se retiran en la versión indicada en la hoja de ruta, con nota en el CHANGELOG.

## Hoja de ruta por versiones

Cada versión es publicable por sí sola y no rompe lo existente.

| Versión | Contenido | Historias / FR | Retira |
|---|---|---|---|
| **v4.1** | Puertas de CI sin `continue-on-error`; verificación posterior a la release; JSON Schema del catálogo; Pester en CI; licencia MIT y página de política de firma; solicitud a SignPath (usuario) | US1 · FR-003, FR-004 | — |
| **v4.2** | Motor dividido en módulos `src/engine` sin cambio de comportamiento; `iwin-engine.ps1` con el contrato; CLI documentada | US1 · FR-005 | Lógica duplicada de `lifecycle.ps1` |
| **v4.3** | Instalación en Program Files con migración; actualizador verificado; firma integrada si SignPath aprobó | US1 · FR-001, FR-002 | Instalación por usuario |
| **v4.4** | Interfaz C#: ventana, tema, navegación y **Inicio** con tarjetas de estado; los módulos aún no portados abren la ventana actual | US2 · FR-010–FR-013 | — |
| **v4.5** | Módulo **Actualizaciones** con lista, exclusiones y programación | US3 · FR-020–FR-022 | Botón «Actualizar todo» antiguo |
| **v4.6** | Módulo **Instalar** portado: catálogo virtualizado, subsecciones, perfiles, guías, informe | Paridad | Pantalla de catálogo PowerShell |
| **v4.7** | Sistema, Pantalla/Energía, Remoto, Vincular equipos y Seguridad portados | Paridad | Ventana WPF de PowerShell |
| **v4.8** | **Paleta de búsqueda** con sinónimos; repaso de accesibilidad y teclado | US4 · FR-014 | — |
| **v4.9** | **Mantenimiento y salud**: limpieza, reparación, discos, batería, temperaturas, informe del equipo | US5 · FR-030–FR-033 | — |
| **v5.0** | Cierre: verificación de SC-001…SC-007, aceptación completa x86/x64/ARM64, documentación, release | Todas | Archivos raíz heredados |

US6–US9 se planifican después en especificaciones propias (5.x).

## Riesgos

| Riesgo | Mitigación |
|---|---|
| SignPath tarda o rechaza la solicitud | FR-001 permite publicar sin firma; el resto de la hoja de ruta no depende de ello |
| Portar el catálogo (v4.6) introduce regresiones | Mismas suites `check-*` contra el nuevo EXE; comparación de inventario y plan de instalación entre motor antiguo y nuevo |
| Migración a Program Files falla a mitad | Copia nueva verificada antes de borrar la antigua; los datos del usuario no se mueven |
| Interfaz híbrida (v4.4–v4.6) confusa | Botones de módulos no portados indican «se abre en la ventana clásica»; periodo limitado a tres versiones |
| Actualizador como SYSTEM | Solo con firma verificada; sin firma, pide UAC |

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| SDK de .NET en CI (dependencia de compilación nueva) | Compilar XAML de WPF y pruebas MSTest; el `csc.exe` incluido en Windows no compila XAML ni admite C# moderno | Cargar XAML en tiempo de ejecución con `csc` pierde validación en compilación y limita a C# 5 |
| Interfaz híbrida temporal (dos ventanas) en v4.4–v4.6 | Publicar valor (Inicio, Actualizaciones) sin esperar a portar todo | Una única versión «big bang» retrasaría meses cualquier entrega y concentraría el riesgo |
