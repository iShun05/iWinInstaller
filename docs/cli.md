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
| `-Updates -List [-Json]` | v4.5 | Lista las apps con versión nueva y si están excluidas |
| `-Updates -Exclude <id>` / `-Include <id>` | v4.5 | Mantiene una app (id de WinGet) en su versión o la vuelve a actualizar |
| `-Update -Scheduled` | v4.5 | Lo que ejecuta la actualización programada: todo salvo excluidas y asistentes |
| `-Clean [-Categories a,b] [-Yes]` | v4.9 | Sin `-Yes` estima cuánto se liberaría; con `-Yes` lo libera (temporales y cachés de más de un día) |
| `-MachineReport <ruta> [-IncludeSensitive]` | v4.9 | Informe del equipo en JSON; sin `-IncludeSensitive` no incluye números de serie, equipo ni usuario |
| `-Status [-Json]` | v4.5 | Tarjetas del Inicio que comprueba el motor (actualizaciones, Windows Update, antivirus, lotes) |
| `-ExportConfig <ruta> [-Perfil <p>] [-IncludePersonal]` | v5.4 | Exporta la configuración de este PC a un JSON (ver «Configuración y plantilla multi-PC») |
| `-ImportConfig <ruta> [-Yes]` | v5.4 | Sin `-Yes` describe qué haría; con `-Yes` aplica las secciones e instala lo que falte |
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
| `-Update -Scheduled` | Número de apps que fallaron |
| `-Updates` | 0 correcto, 1 si WinGet no respondió |
| `-Status` | Número de tarjetas que no están correctas |
| `-ExportConfig` | 0 correcto, 1 error |
| `-ImportConfig` (sin `-Yes`) | Número de secciones con error |
| `-ImportConfig -Yes` | Apps que fallaron + secciones con error (0 = todo correcto) |
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

## Configuración y plantilla multi-PC (v5.4)

Un archivo `.iwin-config.json` guarda lo que hace falta para dejar otro PC igual: apps y ajustes,
exclusiones de actualización, pasos de «Por configurar» y preferencias de la interfaz. Es solo datos
(ids del catálogo, nunca órdenes, rutas ni datos del equipo) y sirve a la vez de copia de seguridad y
de plantilla.

```powershell
# En el PC de referencia: lo instalado y los ajustes aplicados (o -Perfil Gaming para un perfil)
powershell -NoProfile -ExecutionPolicy Bypass -File $iwin -ExportConfig .\mi-pc.iwin-config.json

# En cada PC nuevo: ver el plan y luego aplicarlo sin ventana
powershell -NoProfile -ExecutionPolicy Bypass -File $iwin -ImportConfig .\mi-pc.iwin-config.json
powershell -NoProfile -ExecutionPolicy Bypass -File $iwin -ImportConfig .\mi-pc.iwin-config.json -Yes
```

- Las notas personales y el servidor del juego **no** se exportan salvo con `-IncludePersonal`.
- Al importar, las apps de un fabricante (`hardware` del catálogo) que no corresponden a ese PC se omiten.
- Importar **suma**: une pasos y exclusiones con los del PC; no quita nada. Lo ya instalado no se reinstala.
- Un perfil `.iwin.json` de versiones anteriores también se importa.
- Las secciones se aplican en ese PC con el usuario que ejecuta el comando; los ajustes de sistema piden administrador una sola vez, como al instalar desde la ventana.

### Esquema (`version` 1)

```json
{
  "formato": "iWinInstaller-config",
  "version": 1,
  "nombre": "mi-pc",
  "creado": "2026-11-17",
  "app": "v5.3",
  "secciones": {
    "perfil":      { "apps": ["git", "vscode", "darkmode"] },
    "exclusiones": { "ids": ["VideoLAN.VLC"] },
    "seguimiento": { "tailscale": { "pasos": [0, 1], "guia": "<hash>", "nota": "solo con -IncludePersonal" } },
    "interfaz":    { "zoom": 1.2, "servidorJuego": "solo con -IncludePersonal" }
  }
}
```

Compatibilidad: una `version` mayor que la que entiende la app se rechaza; una sección o un campo
desconocido se ignora (y se avisa), así que un archivo nuevo sigue sirviendo en una app antigua.
Añadir una función = registrar una sección nueva en `src/engine/16-Config.ps1` con
`Register-IwinConfigSection <nombre> {exportar} {importar}`; no hace falta tocar la CLI ni subir `version`.
Los ids de `seguimiento` van con el hash de su guía: si la guía cambió entre versiones, ese paso se omite.

Comandos del contrato para la interfaz: `config.export` (`path`, `name`, `ids`, `includePersonal`),
`config.inspect` (`path`; no cambia nada) y `config.import` (`path`, `sections`; devuelve los `ids` para
instalar con `batch.run`).
