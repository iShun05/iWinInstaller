# Contrato interfaz ↔ motor

La interfaz C# nunca ejecuta lógica de instalación ni de ajustes: lanza el motor y lee su
resultado. Generaliza el modo actual `-WorkerMode/-PlanFile/-ResultFile/-SharedLog`.

## Invocación

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File iWinInstaller.ps1 \
  -EngineCommand <comando> -EngineRequest <ruta.json> -EngineResponse <ruta.json> -EngineEvents <ruta.jsonl>
```

El punto de entrada es el propio `iWinInstaller.ps1` (carga `src/engine/*.ps1` en orden); la
implementación está en `src/engine/09-Contract.ps1`. Disponibles desde v4.2: `catalog.inventory`,
`batch.pending` y `report.last`; el resto se añade en la versión que indica el plan.

- Rutas en `%LOCALAPPDATA%\iWinInstaller\engine\<id-de-operación>\`, creadas por la interfaz.
- En x86 sobre x64 se usa el PowerShell nativo (Sysnative), como hace hoy el lanzador.
- Comandos que requieren administrador se lanzan con `Verb = runas`, una sola vez por operación
  agrupada (lote, limpieza de sistema, reparación).

## Comandos

| Comando | Admin | Request | Response |
|---|---|---|---|
| `catalog.inventory` | No | `{ ids?: [] }` | `{ items: [{ id, installed, version?, checkable }] }` |
| `batch.start` | Según plan | `{ operation: install\|upgrade\|uninstall, ids: [], resume?: id }` | `{ batchId, results: [{ id, outcome, code?, reboot }] }` |
| `batch.pending` | No | `{}` | `{ batches: [...] }` |
| `updates.list` | No | `{}` | `{ items: [AvailableUpdate] }` |
| `updates.schedule` | No | `UpdateSchedule` | `{ applied: bool }` |
| `status.collect` | No | `{ areas?: [] }` | `{ cards: [StatusCard] }` (solo áreas de motor) |
| `tweak.apply` / `tweak.undo` | Según ajuste | `{ id }` | `{ outcome, snapshotSaved }` |
| `maintenance.estimate` | No | `{ categories: [] }` | `{ categories: [CleanupCategory] }` |
| `maintenance.clean` | Según categoría | `{ categories: [] }` | `{ categories: [CleanupCategory] }` |
| `maintenance.repair` | Sí | `{}` | `{ outcome, details }` |
| `health.collect` | No | `{}` | `{ disks: [DiskHealth], battery?: BatteryHealth, temperatures: [] }` |
| `report.machine` | No | `{ includeSensitive: bool, path }` | `{ path }` |
| `report.last` | No | `{}` | Informe de instalación actual |

Las entidades se describen en [data-model.md](../data-model.md).

## Valores de `outcome`

`success`, `failed`, `manual` (requiere intervención), `pending` (lote pausado), `skipped`
(excluida/omitida), `blocked` (directivas), `unknown` (no se pudo comprobar), `rebootRequired`.
Nunca se infiere `success` solo del código de salida (constitución II).

## Eventos (JSONL, una línea por evento)

```json
{"t":"2026-11-08T10:00:00Z","type":"progress","id":"Git.Git","phase":"download","percent":40}
{"t":"…","type":"log","level":"info","text":"…"}
{"t":"…","type":"item","id":"Git.Git","outcome":"success","durationMs":51234}
{"t":"…","type":"done","outcome":"success"}
```

- La interfaz lee el archivo de forma incremental; un evento mal formado se ignora y se registra.
- `done` es siempre el último evento. Si el proceso termina sin `done`, la operación queda como
  `unknown` y el lote es reanudable.

## Códigos de salida del proceso motor

| Código | Significado |
|---|---|
| 0 | Operación completada (los resultados por elemento están en Response) |
| 2 | Request inválido |
| 3 | Cancelado por el usuario |
| 4 | Elevación rechazada |
| 10 | Error interno (detalle en eventos `log` nivel `error`) |
| 12 | Entorno bloqueado: PowerShell en modo restringido (AppLocker/WDAC) o directiva de ejecución impuesta (v5.2) |

## Compatibilidad

- `Request`/`Response` llevan `"contract": 1`. El motor rechaza versiones mayores con código 2.
- Los comandos existentes por línea de comandos (ver [cli.md](cli.md)) se implementan sobre estos
  mismos comandos.
