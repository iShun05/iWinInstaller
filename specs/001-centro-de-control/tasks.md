---

description: "Lista de tareas: centro de control del PC (camino a v5.0)"
---

# Tasks: Centro de control del PC (camino a v5.0)

**Input**: Documentos de diseño en `specs/001-centro-de-control/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: obligatorios por la constitución (principio III). Cada fase escribe primero sus pruebas
y comprueba que fallan antes de implementar.

**Organization**: las fases siguen la hoja de ruta de versiones del plan (v4.1 → v5.0); las tareas
de cada historia llevan su etiqueta `[USn]`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: se puede hacer en paralelo (archivos distintos, sin dependencias pendientes)
- **[Story]**: historia a la que pertenece (US1…US5)
- Cada versión termina con su tarea de publicación (CHANGELOG, README, tag, release, Obsidian)

---

## Phase 1: Setup — base de calidad (v4.1)

**Purpose**: puertas de CI estrictas, pruebas unitarias y catálogo validado.

- [x] T001 Añadir licencia MIT en `LICENSE` y mencionarla en `README.md` (requisito de SignPath, R1)
- [x] T002 [P] Crear `tests/unit/engine/` y el ejecutor de Pester 5 `tests/unit/run.ps1`
- [x] T003 [P] Escribir el esquema del catálogo en `src/catalog/schema/apps.schema.json` a partir de los campos usados en `apps.json` (`id`, `interactive`, `detectPaths`, `signer`, arquitecturas…)
- [x] T004 [P] Escribir el esquema de perfiles en `src/catalog/schema/profiles.schema.json`
- [x] T005 Prueba Pester que valida `apps.json` y `profiles.json` contra los esquemas en `tests/unit/engine/Catalog.Schema.Tests.ps1`
- [x] T006 Revisar `continue-on-error`: las 7 puertas de publicación ya no lo tenían; `windows.yml` y `arm.yml` son diagnósticos y quedan documentados como tales en su cabecera. Se añade `release-check.yml` programado para detectar tags sin release
- [x] T007 Añadir el job de Pester en `.github/workflows/unit.yml` (no en `windows.yml`) y exigirlo en la puerta de `.github/workflows/release.yml`
- [x] T008 Publicar la página de política de firma en `docs/code-signing-policy.md` y enlazarla desde `README.md` y `SECURITY.md`

---

## Phase 2: User Story 1 (parte A) — releases verificadas (v4.1)

**Goal**: ningún tag sin release; descargas comprobadas tras publicar.

**Independent Test**: en un repositorio de pruebas, un tag sin release hace fallar la verificación.

- [x] T009 [US1] Prueba de la verificación posterior en `tests/check-release.ps1` (release Latest = tag, dos descargas, SHA256 coinciden)
- [x] T010 [US1] Job `verify-release` en `.github/workflows/release.yml` que ejecuta `tests/check-release.ps1` tras publicar y falla con aviso si algo no cuadra
- [x] T011 [US1] Publicar **v4.1**: versión en `iWinInstaller.ps1`, `install.ps1`, `native/Launcher.cs`; `CHANGELOG.md`, `README.md`, tag, release y registro en Obsidian

**Checkpoint**: la CI bloquea entradas de catálogo inválidas y releases incompletas. El usuario
envía la solicitud a SignPath (acción manual, R1).

---

## Phase 3: Foundational — motor modular y contrato (v4.2)

**Purpose**: separar la lógica de la interfaz sin cambiar el comportamiento. Bloquea US2–US5.

- [ ] T012 Pruebas Pester de caracterización del comportamiento actual (plan de instalación, códigos, informe, detección) en `tests/unit/engine/Characterization.Tests.ps1`
- [ ] T013 [P] Extraer catálogo y perfiles a `src/engine/Iwin.Catalog.psm1`
- [ ] T014 [P] Extraer lotes y reanudación de `lifecycle.ps1` a `src/engine/Iwin.Batch.psm1`
- [ ] T015 [P] Extraer instalación/desinstalación WinGet, Store y directos a `src/engine/Iwin.Packages.psm1`
- [ ] T016 [P] Extraer ajustes reversibles y snapshots a `src/engine/Iwin.Tweaks.psm1`
- [ ] T017 [P] Extraer acceso remoto, SSH y vincular equipos a `src/engine/Iwin.Remote.psm1`
- [ ] T018 [P] Extraer Defender a `src/engine/Iwin.Security.psm1`
- [ ] T019 [P] Extraer informes y diagnóstico a `src/engine/Iwin.Report.psm1`
- [ ] T020 Crear `src/engine/iwin-engine.ps1` con el contrato de `contracts/engine.md` (Request/Response/Events, códigos de salida) para `catalog.inventory`, `batch.*`, `tweak.*` y `report.last`
- [ ] T021 Pruebas del contrato (Request inválido → 2, `done` siempre último, versión de contrato mayor rechazada) en `tests/unit/engine/EngineContract.Tests.ps1`
- [ ] T022 Hacer que `iWinInstaller.ps1` y `lifecycle.ps1` importen los módulos en lugar de definir las funciones; añadir `-Json` según `contracts/cli.md`
- [ ] T023 Documentar la línea de comandos en `docs/cli.md` a partir de `contracts/cli.md`
- [ ] T024 Incluir `src/engine/` en el paquete en `scripts/build_exe.ps1` y `scripts/build_installer.py`
- [ ] T025 Publicar **v4.2** (CHANGELOG, README sección Estructura, tag, release, Obsidian)

**Checkpoint**: `-Check -Json` y todas las suites `check-*` dan el mismo resultado que en v4.1.

---

## Phase 4: User Story 1 (parte B) — instalación protegida y firma (v4.3)

**Goal**: app en ubicación protegida, migración sin pérdida y ejecutables firmados.

**Independent Test**: instalar sobre una v4.2 por usuario con perfiles y notas (ver quickstart).

- [ ] T026 [US1] Prueba de migración en `tests/check-migration.ps1` (datos intactos, carpeta antigua eliminada solo tras verificar la nueva, permisos de escritura denegados sin elevación)
- [ ] T027 [US1] Instalación en `%ProgramFiles%\iWinInstaller` con una UAC y migración desde `%LOCALAPPDATA%\Programs\iWinInstaller` en `native/Launcher.cs` e `install.ps1`
- [ ] T028 [US1] Registro en Aplicaciones instaladas por equipo y accesos del menú Inicio para todos los usuarios en `native/Launcher.cs`
- [ ] T029 [US1] Actualizador: tarea como SYSTEM solo con firma verificada; sin firma, pide UAC (R4) en `lifecycle.ps1` → `src/engine/Iwin.Batch.psm1` (función de actualización)
- [ ] T030 [US1] Paso de firma con SignPath en `.github/workflows/release.yml` para `iWinInstaller.exe`, `iWinInstaller-Setup.exe` y lanzador; omitido con aviso si la solicitud no está aprobada
- [ ] T031 [US1] Comprobación de firma de los artefactos en `tests/check-release.ps1`
- [ ] T032 [US1] Actualizar `SECURITY.md` (nuevo modelo de instalación y firma) y la sección Descargar e instalar de `README.md`
- [ ] T033 [US1] Publicar **v4.3** (CHANGELOG, README, tag, release, Obsidian)

**Checkpoint**: US1 completa.

---

## Phase 5: Foundational — interfaz C# (v4.4)

**Purpose**: ventana nueva, tema y navegación. Bloquea US2–US5.

- [ ] T034 Crear `src/app/iWinInstaller.App.csproj` (SDK, `UseWPF`, `net48`, AnyCPU) y `tests/unit/app/iWinInstaller.App.Tests.csproj` (MSTest)
- [ ] T035 [P] Tema negro, tipografía, iconos monoline y estilos en `src/app/Theme/` según la nota Diseño Apple y Pixel
- [ ] T036 [P] Cliente del motor (lanzar proceso, elevación, lectura incremental de JSONL, cancelación) en `src/app/Engine/EngineClient.cs` con pruebas en `tests/unit/app/EngineClientTests.cs`
- [ ] T037 Ventana principal con navegación lateral por módulos, zoom 70–200 %, teclado y Acerca de (versión + Instagram) en `src/app/Shell/`
- [ ] T038 Botones de módulos aún no portados que abren la ventana clásica con aviso en `src/app/Shell/LegacyBridge.cs`
- [ ] T039 Compilar la interfaz con el SDK de .NET en `.github/workflows/native.yml` y empaquetarla en `scripts/build_exe.ps1`
- [ ] T040 Prueba de apertura de la ventana nueva en x64, ARM64 y x86 en `tests/check-native.ps1`

---

## Phase 6: User Story 2 — estado del PC de un vistazo (v4.4)

**Goal**: inicio con tarjetas de estado accionables.

**Independent Test**: equipo con actualización pendiente y poco espacio muestra ambos avisos.

- [ ] T041 [P] [US2] Pruebas del ViewModel de tarjetas (estados `ok/attention/unknown/notApplicable`, motivo obligatorio en `unknown`) en `tests/unit/app/HomeViewModelTests.cs`
- [ ] T042 [P] [US2] Comando `status.collect` (Windows Update, antivirus, actualizaciones de apps, lotes) en `src/engine/Iwin.Status.psm1` con pruebas en `tests/unit/engine/Status.Tests.ps1`
- [ ] T043 [P] [US2] Sondas en C# para espacio, reinicio pendiente, salud básica de discos y batería en `src/app/Probes/`
- [ ] T044 [US2] Modelo `StatusCard` y `HomeViewModel` en `src/app/Modules/Home/` (carga progresiva: inicio utilizable < 2 s)
- [ ] T045 [US2] Vista del inicio con tarjetas y acción asociada en `src/app/Modules/Home/HomeView.xaml`
- [ ] T046 [US2] `-Status [-Json]` en la CLI sobre `status.collect` en `src/engine/iwin-engine.ps1`
- [ ] T047 [US2] Medir el tiempo hasta inicio utilizable en `tests/check-native.ps1` (SC-002)
- [ ] T048 [US2] Publicar **v4.4** (CHANGELOG, README Funciones/Tecnología/Estructura, tag, release, Obsidian)

**Checkpoint**: US2 completa; el resto de módulos se abre en la ventana clásica.

---

## Phase 7: User Story 3 — apps al día con control (v4.5)

**Goal**: lista de actualizaciones, exclusiones persistentes y programación opcional.

**Independent Test**: excluir una de dos apps desactualizadas y actualizar; solo cambia la otra.

- [ ] T049 [P] [US3] Pruebas Pester de exclusiones y filtrado de interactivas en `tests/unit/engine/Updates.Tests.ps1`
- [ ] T050 [P] [US3] Pruebas del ViewModel en `tests/unit/app/UpdatesViewModelTests.cs`
- [ ] T051 [US3] `updates.list` y `updates.schedule`, archivo `exclusiones.json` en `src/engine/Iwin.Updates.psm1`
- [ ] T052 [US3] Respetar exclusiones en `batch.start` con `operation: upgrade` y en `-Update` en `src/engine/Iwin.Batch.psm1`
- [ ] T053 [US3] Tarea programada opcional (usuario, sin reiniciar, omite interactivas, deja informe) en `src/engine/Iwin.Updates.psm1`
- [ ] T054 [US3] Módulo Actualizaciones (lista con versiones, marcar, excluir, programar) en `src/app/Modules/Updates/`
- [ ] T055 [US3] `-Updates -List/-Exclude/-Include` en `src/engine/iwin-engine.ps1` y `docs/cli.md`
- [ ] T056 [US3] Prueba de aceptación excluir → actualizar en `tests/check-acceptance.ps1`
- [ ] T057 [US3] Publicar **v4.5**

**Checkpoint**: US3 completa.

---

## Phase 8: Paridad — módulo Instalar (v4.6)

**Purpose**: portar catálogo, perfiles, guías e informe a la interfaz C#.

- [ ] T058 Pruebas de ViewModel (filtros, búsqueda, selección, perfiles, dependencias) en `tests/unit/app/InstallViewModelTests.cs`
- [ ] T059 Catálogo virtualizado con secciones, 84 subsecciones y recuadros «Cuál elegir» en `src/app/Modules/Install/`
- [ ] T060 Perfiles: elegir, guardar, importar y exportar `.iwin.json` en `src/app/Modules/Install/Profiles/`
- [ ] T061 Resumen previo del lote, progreso por eventos, pausar y reanudar en `src/app/Modules/Install/Batch/`
- [ ] T062 Pasos y notas de postinstalación (122 guías) en `src/app/Modules/Install/Guides/`
- [ ] T063 Informe al terminar (reintentar, copiar, guardar diagnóstico) en `src/app/Modules/Install/Report/`
- [ ] T064 Ejecutar `tests/check-acceptance.ps1` y `tests/check-reliability.ps1` contra el nuevo EXE y comparar con la interfaz anterior
- [ ] T065 Publicar **v4.6** (retira la pantalla de catálogo de PowerShell)

---

## Phase 9: Paridad — Sistema, Remoto y Seguridad (v4.7)

- [ ] T066 [P] Ajustes del sistema con Deshacer en `src/app/Modules/System/`
- [ ] T067 [P] Resolución, frecuencia y energía en `src/app/Modules/System/Display/`
- [ ] T068 [P] Acceso remoto y Vincular equipos en `src/app/Modules/Remote/`
- [ ] T069 [P] Panel de Defender en `src/app/Modules/Security/`
- [ ] T070 Prueba aplicar → deshacer → estado idéntico de cada ajuste reversible en `tests/check-acceptance.ps1` (SC-005)
- [ ] T071 Retirar la ventana WPF de `iWinInstaller.ps1` (queda solo la CLI) y `src/app/Shell/LegacyBridge.cs`
- [ ] T072 Publicar **v4.7**

---

## Phase 10: User Story 4 — paleta de búsqueda (v4.8)

**Goal**: llegar a cualquier acción en ≤ 3 pulsaciones tras el atajo.

**Independent Test**: «frecuencia» abre el panel de resolución y Hz.

- [ ] T073 [P] [US4] Pruebas de búsqueda (sin tildes, sinónimos, orden por relevancia, no ejecuta acciones con confirmación) en `tests/unit/app/PaletteTests.cs`
- [ ] T074 [US4] Registro de acciones `PaletteAction` por módulo y catálogo en `src/app/Shell/Palette/ActionRegistry.cs`
- [ ] T075 [US4] Sinónimos en español en `src/app/Shell/Palette/synonyms.es.json`
- [ ] T076 [US4] Ventana de paleta con atajo global en la app y navegación por teclado en `src/app/Shell/Palette/`
- [ ] T077 [US4] Repaso de accesibilidad (nombres automáticos, foco visible, contraste) en `src/app/Theme/` y vistas
- [ ] T078 [US4] Prueba de las búsquedas de referencia (SC-003) en `tests/check-native.ps1`
- [ ] T079 [US4] Publicar **v4.8**

**Checkpoint**: US4 completa.

---

## Phase 11: User Story 5 — mantenimiento y salud (v4.9)

**Goal**: limpiar, reparar, revisar salud y exportar el informe del equipo.

**Independent Test**: limpieza con temporales de prueba muestra estimación y resultado.

- [ ] T080 [P] [US5] Pruebas Pester de limpieza con lista blanca y carpeta simulada (nada fuera de la lista se toca) en `tests/unit/engine/Maintenance.Tests.ps1`
- [ ] T081 [P] [US5] Pruebas del informe del equipo (sin datos sensibles por defecto) en `tests/unit/engine/MachineReport.Tests.ps1`
- [ ] T082 [US5] `maintenance.estimate`, `maintenance.clean` y `maintenance.repair` en `src/engine/Iwin.Maintenance.psm1`
- [ ] T083 [US5] `health.collect` (discos, batería, temperaturas con «no disponible») en `src/engine/Iwin.Maintenance.psm1`
- [ ] T084 [US5] `report.machine` en `src/engine/Iwin.Report.psm1`
- [ ] T085 [US5] Módulo Mantenimiento (limpieza con confirmación, reparación con progreso, salud, informe) en `src/app/Modules/Maintenance/`
- [ ] T086 [US5] Enlazar las tarjetas del inicio a Mantenimiento en `src/app/Modules/Home/`
- [ ] T087 [US5] `-Clean` y `-MachineReport` en `src/engine/iwin-engine.ps1` y `docs/cli.md`
- [ ] T088 [US5] Publicar **v4.9**

**Checkpoint**: US5 completa.

---

## Phase 12: Polish — cierre v5.0

- [ ] T089 Retirar archivos raíz heredados (`lifecycle.ps1`, lógica sobrante de `iWinInstaller.ps1`) y mover `native/` a `src/launcher/`, actualizando workflows y scripts
- [ ] T090 Comprobar que ningún archivo de código supera ~1.500 líneas (SC-007) con una prueba en `tests/unit/engine/Size.Tests.ps1`
- [ ] T091 Recorrer `quickstart.md` completo en la matriz x86/x64/ARM64 y registrar resultados de SC-001…SC-007 en Obsidian
- [ ] T092 Pruebas físicas en el equipo del usuario (batería, sensores, SMART, monitores) y registro en la Bitácora técnica
- [ ] T093 Revisión de seguridad final (procedencia, firma, rutas, secretos en diagnósticos) contra `SECURITY.md`
- [ ] T094 README completo para v5.0 (Funciones, Tecnología, Estructura, Compilar e instalar) y descripción/temas del repositorio
- [ ] T095 Publicar **v5.0**

---

## Dependencies & Execution Order

- **Phase 1 → Phase 2** (v4.1) → **Phase 3** (v4.2) → **Phase 4** (v4.3) → **Phase 5** (v4.4).
- **Phase 6 (US2)** depende de las fases 3 y 5.
- **Phase 7 (US3)** depende de la fase 6 (tarjeta de actualizaciones) y del motor modular.
- **Phases 8–9** (paridad) dependen de la fase 5; pueden empezar en paralelo con la fase 7.
- **Phase 10 (US4)** depende de que todos los módulos estén portados (fase 9) para registrar sus
  acciones.
- **Phase 11 (US5)** depende de las fases 3 y 5; puede hacerse en paralelo con la fase 10.
- **Phase 12** depende de todo lo anterior.
- La firma (T030) depende de la aprobación de SignPath; si no llega, se publica sin firma y T030
  queda pendiente sin bloquear nada.

### Parallel Opportunities

- Fase 1: T002, T003 y T004.
- Fase 3: extracción de módulos T013–T019 (archivos distintos, tras T012).
- Fase 5: T035 y T036.
- Fase 6: T041, T042 y T043.
- Fase 9: T066–T069.
- Fases 10 y 11 entre sí.

## Implementation Strategy

1. **MVP = v4.1–v4.3 (US1)**: base fiable, releases verificadas, instalación protegida y firma.
   Valor inmediato y sin cambiar la interfaz.
2. **v4.4–v4.5**: primera entrega visible (Inicio y Actualizaciones) con interfaz híbrida.
3. **v4.6–v4.7**: paridad completa y retirada de la interfaz antigua.
4. **v4.8–v4.9**: paleta y mantenimiento.
5. **v5.0**: verificación de criterios y cierre.

Cada versión se detiene en su checkpoint para validar con `quickstart.md` antes de seguir.
