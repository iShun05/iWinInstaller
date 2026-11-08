# Línea de comandos

iWinInstaller se puede usar sin ventana para instalar perfiles, comprobar el equipo o automatizar
tareas. Los ejemplos usan la instalación por defecto:

```powershell
$iwin = "$env:LOCALAPPDATA\Programs\iWinInstaller\iWinInstaller.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $iwin -Check
```

## Parámetros

| Parámetro | Desde | Qué hace |
|---|---|---|
| *(ninguno)* | — | Abre la ventana |
| `-Check` | anterior a v4.2 | Lista cada app del catálogo con ✓ (instalada), ✗ (falta) o – (opcional) |
| `-Check -Json` | v4.2 | Lo mismo en JSON (ver abajo) |
| `-Silent [-Perfil <nombre o archivo.iwin.json>]` | anterior a v4.2 | Instala un perfil sin ventana |
| `-Update` | anterior a v4.2 | Actualiza las apps instaladas |
| `-Resume` | anterior a v4.2 | Continúa el lote pendiente más reciente |
| `-EngineCommand <comando> -EngineRequest <json> -EngineResponse <json> -EngineEvents <jsonl>` | v4.2 | Contrato con la interfaz (uso interno; ver `specs/001-centro-de-control/contracts/engine.md`) |

`-AutoUpdate`, `-WorkerMode`, `-PlanFile`, `-ResultFile`, `-SharedLog`, `-UpgradePackages` y
`-RemovePackages` son internos: los usa la propia app para la actualización programada y los
lotes con o sin administrador.

## Códigos de salida

| Modo | Código |
|---|---|
| `-Check` | Número de apps no opcionales que faltan (0 = todo instalado) |
| `-Silent`, `-Resume` | Número de apps que fallaron (0 = todo correcto) |
| `-Update` | 0 correcto, 1 con fallos |
| `-EngineCommand` | 0 correcto, 2 petición no válida, 3 cancelado, 4 elevación rechazada, 10 error interno |

Estos códigos son estables desde v4.2.

## `-Check -Json`

La salida estándar es solo el documento JSON (sin líneas de registro):

```json
{
  "contract": 1,
  "version": "v4.2",
  "winget": true,
  "total": 120,
  "missing": 3,
  "items": [
    { "id": "git", "name": "Git", "section": "Terminal", "group": "Lenguajes y entornos",
      "installed": true, "optional": false }
  ]
}
```

- `total`: apps no opcionales del catálogo. `missing`: cuántas de ellas faltan (igual que el código
  de salida).
- `items` incluye todo el catálogo, también las opcionales, con `installed` y `optional`.

```powershell
$estado = powershell -NoProfile -File $iwin -Check -Json | ConvertFrom-Json
$estado.items | Where-Object { -not $_.installed -and -not $_.optional } | Select-Object name
```
