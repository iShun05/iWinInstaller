# Modelo de datos

Todos los archivos viven en `%LOCALAPPDATA%\iWinInstaller` salvo que se indique otra cosa. Cada
archivo JSON lleva `format` y `version` para poder migrar sin perder datos.

## StatusCard (Tarjeta de estado) — en memoria

| Campo | Tipo | Reglas |
|---|---|---|
| `area` | enum | `appUpdates`, `windowsUpdate`, `antivirus`, `diskSpace`, `diskHealth`, `battery`, `temperature`, `reboot`, `pendingBatch` |
| `state` | enum | `ok`, `attention`, `unknown`, `notApplicable` |
| `summary` | texto | Frase corta en español («3 actualizaciones») |
| `reason` | texto | Obligatorio si `state = unknown` |
| `action` | id de acción | Acción de paleta que resuelve el aviso; vacío si no hay |
| `checkedAt` | fecha-hora | Momento de la comprobación |

Transiciones: `unknown → ok|attention` al completar; cualquier estado → `unknown` si la
comprobación falla. `notApplicable` es definitivo en la sesión (p. ej. sin batería).

## AvailableUpdate (Actualización disponible) — en memoria

| Campo | Tipo | Reglas |
|---|---|---|
| `appId` | id del catálogo o id de WinGet | Obligatorio |
| `name` | texto | |
| `installedVersion`, `availableVersion` | texto | `availableVersion` ≠ `installedVersion` |
| `source` | enum | `winget`, `msstore` |
| `interactive` | bool | Si el instalador requiere intervención; se omite en programadas |
| `excluded` | bool | Derivado de `UpdateExclusions` |

## UpdateExclusions — `exclusiones.json`

```json
{ "format": "iWinInstaller-exclusiones", "version": 1,
  "items": [ { "id": "Mozilla.Firefox", "since": "2026-11-08" } ] }
```

Reglas: ids únicos; se conserva al actualizar o desinstalar iWinInstaller.

## UpdateSchedule — dentro de `preferencias.json`

| Campo | Tipo | Reglas |
|---|---|---|
| `updates.scheduled` | bool | `false` por defecto |
| `updates.frequency` | enum | `daily`, `weekly` |
| `updates.time` | `HH:mm` | Hora local |
| `updates.lastRun` | fecha-hora | Escrito por la tarea |

## PaletteAction (Acción de paleta) — registro en código + catálogo

| Campo | Tipo | Reglas |
|---|---|---|
| `id` | texto | Único (`module.action`) |
| `title` | texto | Español |
| `module` | enum | Módulos de navegación |
| `synonyms` | lista de texto | Español, sin tildes para la búsqueda |
| `requiresConfirmation` | bool | La paleta nunca ejecuta estas, solo abre |
| `requiresAdmin` | bool | Se muestra un escudo |

Las 427 entradas del catálogo se registran automáticamente como acciones de tipo «app».

## CleanupCategory (Categoría de limpieza) — en memoria

| Campo | Tipo | Reglas |
|---|---|---|
| `id` | enum | `userTemp`, `systemTemp`, `wuCache`, `deliveryOptimization`, `recycleBin`, `thumbnails`, `crashDumps`, `browserCaches` |
| `estimatedBytes` | número | Calculado antes de confirmar |
| `freedBytes`, `skippedFiles` | número | Tras ejecutar |
| `requiresAdmin` | bool | |

Regla: solo rutas de una lista blanca fija; nunca carpetas de documentos ni del perfil fuera de
cachés conocidas.

## DiskHealth / BatteryHealth — en memoria

- `DiskHealth`: `diskName`, `mediaType`, `healthStatus` (`healthy`, `warning`, `unhealthy`,
  `unknown`), `temperatureC?`, `wearPercent?`, `readErrors?`, `recommendation`.
- `BatteryHealth`: `designCapacityMWh`, `fullChargeCapacityMWh`, `wearPercent` (calculado),
  `cycleCount?`.

## MachineReport (Informe del equipo) — archivo exportado

```json
{ "format": "iWinInstaller-informe-equipo", "version": 1, "createdAt": "…",
  "includeSensitive": false,
  "system": { "edition": "…", "build": "…", "architecture": "…" },
  "hardware": { "cpu": "…", "gpu": ["…"], "ramGB": 32, "board": "…", "disks": [ … ] },
  "health": { "disks": [ … ], "battery": { … } } }
```

Regla: `serialNumber`, nombre del equipo y usuario solo aparecen si `includeSensitive = true`.

## Entidades existentes que se conservan

Perfiles `.iwin.json`, lotes (`iWinInstaller-lote` v1), estado de postinstalación, snapshots de
ajustes reversibles e informes de instalación mantienen su formato actual; la interfaz C# los lee a
través del motor, no directamente, salvo preferencias y exclusiones.
