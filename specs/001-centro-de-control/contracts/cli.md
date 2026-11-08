# Línea de comandos pública (FR-005)

Se mantiene la compatibilidad con los parámetros actuales y se documenta un contrato estable para
uso desatendido. Ejecutable: `iWinInstaller.exe` (o `iWinInstaller.ps1` mientras exista).

## Parámetros actuales (se conservan)

| Parámetro | Efecto |
|---|---|
| *(sin parámetros)* | Abre la ventana |
| `-Check` | Informe ✓/✗ en consola |
| `-Silent [-Perfil <nombre\|archivo.iwin.json>]` | Instala un perfil sin ventana |
| `-Update` | Actualiza las apps instaladas (respeta exclusiones desde v4.5) |
| `-Resume` | Continúa el lote pendiente más reciente |
| `-AutoUpdate` | Uso interno de la tarea de actualización de iWinInstaller |

## Parámetros nuevos

| Parámetro | Desde | Efecto |
|---|---|---|
| `-Updates -List` | v4.5 | Lista actualizaciones disponibles (texto o `-Json`) |
| `-Updates -Exclude <id>` / `-Include <id>` | v4.5 | Gestiona exclusiones |
| `-Status [-Json]` | v4.4 | Imprime las tarjetas de estado |
| `-Clean [-Categories a,b] [-Yes]` | v4.9 | Limpieza; sin `-Yes` solo estima |
| `-MachineReport <ruta> [-IncludeSensitive]` | v4.9 | Exporta el informe del equipo |
| `-Json` | v4.2 | Salida JSON en cualquier comando de consola |

## Códigos de salida

| Código | Significado |
|---|---|
| 0 | Todo correcto |
| 1 | Al menos un elemento falló |
| 2 | Parámetros inválidos |
| 3 | Cancelado |
| 4 | Elevación rechazada |
| 5 | Requiere acción manual (asistentes, cuentas) |
| 3010 | Correcto, pero requiere reiniciar (convención de Windows Installer) |

La salida JSON sigue las entidades de [data-model.md](../data-model.md). Los códigos son estables
desde v4.2; un cambio incompatible exige nueva versión mayor del contrato.
