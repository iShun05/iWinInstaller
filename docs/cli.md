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
| `-DevEnv list\|node\|python\|java [-Yes]` | sin publicar | Estado de un entorno de desarrollo con versiones fijadas; con `-Yes` instala lo que falta y lo configura |
| `-Sync status\|connect\|push\|pull\|disconnect [-SyncRepo <url>] [-Yes]` | sin publicar | Sincroniza la configuración entre PC con un repo **privado** de GitHub (ver «Entorno de desarrollo y sincronización») |
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
| `-DevEnv <plantilla>` (sin `-Yes`) | Número de apps que faltan |
| `-DevEnv <plantilla> -Yes` | Apps que fallaron |
| `-Sync` | 0 correcto, 1 error (`pull -Yes`: apps que fallaron + secciones con error) |
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

## Entorno de desarrollo y sincronización

### `-DevEnv`

Tres plantillas (`node`, `python`, `java`) definidas en `src/engine/18-DevEnv.ps1`. Cada una es **solo datos**:
ids del catálogo (con la versión ya fijada en `apps.json`: Python 3.13, Temurin 21…), la versión esperada
(`pins`) y pasos de configuración de una lista cerrada (`corepack`, `pip`, `javahome`). Si una herramienta
está instalada pero en otra versión que la fijada, se marca ✗ aunque la app esté. Ejemplos:

```powershell
iWinInstaller.ps1 -DevEnv list          # resumen de las tres
iWinInstaller.ps1 -DevEnv java          # qué falta y si la versión coincide
iWinInstaller.ps1 -DevEnv java -Yes     # instala lo que falta (Git, VS Code, JDK 21) y fija JAVA_HOME
```

Comandos del contrato: `devenv.list`, `devenv.status` (`template`), `devenv.configure` (`template`).
La interfaz instala `missing` con `batch.run` y después llama a `devenv.configure`.

### `-Sync`

Complementa Exportar/Importar: el mismo documento de configuración (`config.export`), guardado en
`iwininstaller-config.json` de un clon local (`%LOCALAPPDATA%\iWinInstaller\sync\repo`) de un repo
**privado** tuyo.

```powershell
iWinInstaller.ps1 -Sync connect -SyncRepo https://github.com/usuario/mi-config
iWinInstaller.ps1 -Sync push            # en el PC de origen
iWinInstaller.ps1 -Sync pull            # en el otro PC: describe el plan
iWinInstaller.ps1 -Sync pull -Yes       # lo aplica e instala lo que falte
iWinInstaller.ps1 -Sync disconnect      # borra el clon local
```

- Usa el `git` y las credenciales **del propio usuario** (Git Credential Manager o `gh auth login`); iWinInstaller no guarda tokens ni pide contraseñas (`GIT_TERMINAL_PROMPT=0`).
- Solo se aceptan direcciones `https://github.com/usuario/repo`. **Se rechaza un repo público** (al conectar y antes de cada subida).
- Nunca se suben notas personales ni el servidor del juego (equivale a exportar sin `-IncludePersonal`).
- Importar suma, igual que `-ImportConfig`. Comandos del contrato: `sync.status`, `sync.connect`, `sync.push`, `sync.pull` (`apply`), `sync.disconnect`.

## Salud del catálogo (CI)

`.github/workflows/catalog-health.yml` se ejecuta cada lunes (y a mano) con `scripts/catalog_health.py`: descarga el
instalador de la última versión de cada app `winget` y compara su SHA-256 con el manifiesto de `winget-pkgs`
(una huella distinta es el error `0x8A150011` de un PC real) y comprueba las URLs propias del catálogo
(`page`, `url`, `fallback.url`, `postInstall.link`). Los errores (huella desfasada, 404/410, DNS) hacen fallar el
trabajo y avisan por correo; los avisos (403, 429, 5xx, tiempos de espera, instaladores de más de 400 MB) solo
se listan en el resumen. Para una app con huella desfasada, añade un `fallback` en `apps.json` (ver v5.5).
Local: `python scripts/catalog_health.py --solo "git wget"` (con `GITHUB_TOKEN` para listar versiones).
