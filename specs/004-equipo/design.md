# 004 · Equipo: perfiles de hardware y panel de salud

Estado: implementado, sin publicar. Objetivo del usuario: un Windows muy fluido para **desarrollar y jugar en competitivo a la vez**, sin procesos residentes.

## Decisiones

1. **Una página nueva, «Equipo»**, entre Sistema y Juegos. Hardware y preset arriba, salud debajo. El Inicio ya tiene tarjetas de Defender, Windows Update, disco, batería y reinicio; Equipo no las sustituye, añade el detalle (inicio y temperaturas) y la lectura del hardware.
2. **Lógica pura y probada** (`EquipoModel.cs`, `HealthRules.cs`) separada de las lecturas del sistema (`EquipoProbes.cs`, WMI y registro con permisos de usuario). Las pruebas no necesitan Windows.
3. **El preset marca, no instala.** `PresetPlanner.Plan(hardware)` devuelve ids de `apps.json` y avisos con acción; `InstallViewModel.SelectPreset` los marca (menos lo ya instalado) y el usuario pulsa Instalar con el plan de confirmación de siempre.
4. **Perfil equivalente en `profiles.json`** («Dev + Gaming competitivo», con `@hardware`) para elegirlo a mano. Una prueba exige que el perfil cubra la base del preset y que todos los ids existan.
5. **Honestidad ante lo desconocido**: lo que Windows no da queda vacío o «sin datos»; una lectura fallida es «No se pudo comprobar», nunca «correcto». Sin sensores de temperatura, la fila no aplica y no se inventa un valor.
6. **Sin residentes**: nada de PowerShell, temporizadores ni tareas; solo al entrar o al pulsar Comprobar.

## Reglas del preset

| Hardware | Efecto |
| --- | --- |
| Portátil | sin `power` (alto rendimiento gasta batería) + `wifiperf` |
| Sobremesa o desconocido | `power`, sin `wifiperf` |
| RAM < 12 GB | sin `wsl`, con aviso |
| Gráfica NVIDIA, AMD o Intel (dedicada, o integrada si no hay dedicada) | `nvidiaapp`, `amdsoftware`, `inteldsa` |
| Portátil ASUS | `ghelper` |
| Integrada + dedicada | aviso hacia Juegos (GPU por juego) |
| Pantalla con más Hz disponibles | aviso hacia Sistema; si ya está al máximo (≥ 100 Hz), límite de FPS = Hz − 3 |

Gama: **Básica** con menos de 8 GB, o sin dedicada y 4 hilos o menos; **Alta** con dedicada, 16 GB y 12 hilos; **Media** el resto. Los datos ausentes no penalizan.

## Salud

Defender (tiempo real y firmas ≤ 3 días, u otro antivirus), Windows Update (búsqueda con éxito en 7 días, desde el registro), disco del sistema (reglas del Inicio), apps de inicio (activas según `StartupApproved`; aviso > 12) y temperatura (contador térmico de Windows y, si no hay, ACPI; aviso ≥ 85 °C).

## Pendiente de prueba física

Lecturas WMI y de registro en un portátil y un sobremesa reales, maquetación de la página y si el equipo del usuario expone zonas térmicas.
