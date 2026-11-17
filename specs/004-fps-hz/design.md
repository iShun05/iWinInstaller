# Diseño · FPS/Hz: Fortnite 240 y límites en HoYo/Endfield

Estado: **pendiente de aprobación** de David. Base: `main` (v5.3, página Juegos). Sin cambio de versión aquí (lo hace el paso de publicación, tag v5.4).

## 1. Objetivo
Monitor de 240 Hz. Fortnite: 240 FPS constantes (competitivo, calidad secundaria). HoYo y Endfield: subir el límite de FPS más allá de los presets solo si es seguro. Mismas reglas de seguridad que `specs/003-juegos`: solo ajustes de usuario (`.ini` en `%LOCALAPPDATA%`, `HKCU`), con el juego cerrado; nada de memoria, unlockers ni archivos del juego/anticheat.

## 2. Qué ya hace v5.3
- Fortnite: límite de FPS = Hz actuales (o Hz−3, o sin límite), VSync off, modo Rendimiento, mallas/texturas bajas, contador de FPS.
- Star Rail: `FPS=120` en `HKCU` (desmarcado, «No oficial · riesgo bajo»).
- ZZZ, Endfield, Genshin: solo GPU + guía.

## 3. Hallazgos (investigación)
| Juego | Realidad | Decisión |
|---|---|---|
| Star Rail | El valor `FPS` del registro solo admite **30, 60 o 120**; otro valor se resetea (r/HonkaiStarRail, PCGamingWiki) | **120 es el techo seguro.** En 240 Hz son 2 fotogramas por refresco: lo ideal. Se deja y se explica |
| Genshin | Máximo oficial 60. Pasar de ahí = unlocker (escribe memoria) | **No se hace.** Se mantiene el aviso |
| ZZZ | Su menú ya ofrece 30/60/**Ilimitado** | Nada que desbloquear. Guía: Ilimitado |
| Endfield | Su menú ya ofrece 120; sin formato de ajustes documentado | No se toca. Guía |
Conclusión: **en HoYo/Endfield no existe una vía segura por encima de lo que ya hay.** Lo único que cambia es la experiencia (valores por defecto y textos).

## 4. Cambios

### 4.1 Fortnite · perfil «Competitivo 240»
En `BuildFortnite` (`GameTweaks.cs`), sin nuevas pantallas:
1. **Límite de FPS**: nueva opción «**Máximo del monitor** (240 FPS)» que usa `DisplaySettings.MaxRefreshFor` (ya existe) en vez de los Hz *actuales*. Motivo: si Windows está ahora a 60 Hz, «Hz actuales» escribiría 60. Es la opción por defecto cuando Hz actuales < máximo, con aviso: «Tu pantalla está a X Hz pero admite 240: súbela en Sistema».
2. **Menús al mismo límite**: `MenuFrameRateLimit` = mismo valor (solo si la clave ya existe en el `.ini`; no se añade).
3. **Fotogramas estables**: `bMotionBlur=False` y `bUseDynamicResolution=False` (solo si la clave ya existe). La resolución dinámica varía la carga y estropea la constancia.
4. **Pantalla completa exclusiva**: pasa a marcada cuando el perfil es competitivo (hoy desmarcada).
5. Se mantiene el tope a Hz y no «sin límite» por defecto: un tope estable da mejores tiempos de fotograma y menos calor que ir sin límite.
6. «Hazlo tú» ampliado: Reflex Activado + Boost; «si no llegas a 240 constantes, el cuello es la CPU: cierra Chrome/Discord overlay, y baja Distancia de visión a Alta».
7. Honestidad en la UI: **ninguna clave del `.ini` garantiza 240**; depende de CPU/GPU. La app no mide FPS (se usa el contador del juego).

Claves nuevas **por verificar** en una build real (las dos de `bMotionBlur`/`bUseDynamicResolution`/`MenuFrameRateLimit`); por eso solo se editan si existen y se muestran con su valor actual.

### 4.2 HoYo y Endfield
- Star Rail: casilla de 120 FPS **marcada por defecto** si el FPS actual es < 120 (hoy desmarcada), manteniendo la etiqueta «No oficial». Texto: «120 es el máximo que admite el juego por esta vía; otros valores se resetean». Si el juego ya está en 120, «Ya está».
- ZZZ / Endfield / Genshin: texto de «Hazlo tú» con la recomendación explícita para 240 Hz (ZZZ: Ilimitado; Endfield: 120; Genshin: 60 y por qué no más) y botón «Subir pantalla a 240 Hz en Sistema» ya existente.

## 5. Archivos
`src/app/Modules/Games/GameTweaks.cs` (opción de FPS y claves nuevas), `GameDefinitions.cs` (textos), `GameCardViewModel.cs` (si la opción necesita el Hz máximo, ya expuesto por la pantalla), `tests/unit/app/GamesTests.cs`, `README.md`/`CHANGELOG.md` (entrada «sin publicar»).

## 6. Pruebas
MSTest: `FortniteFpsValue` con máximo vs actual; `.ini` con y sin las claves nuevas (no se añaden); opción por defecto según Hz; Star Rail 120 marcado/«Ya está». CI de Windows. Prueba física (David): Fortnite 240 en el contador; Star Rail en 120 desde el juego.

## 7. Fuera de alcance
Unlockers, tocar ZZZ (su menú ya basta), perfiles del driver, HAGS (otro hilo: Latencia/Sistema), subir versión.
