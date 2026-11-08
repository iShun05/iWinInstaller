# Constitución de iWinInstaller

Resume las normas globales de los agentes (bóveda Obsidian **Notas → Rules**, v0.7) aplicadas a este
proyecto. Si una norma global cambia, prevalece la norma y se enmienda esta constitución.

## Principios fundamentales

### I. Seguridad verificable antes que comodidad

- Nada se ejecuta sin una comprobación de origen: SHA256 fijado, firma Authenticode del fabricante
  esperado o la verificación de WinGet/Microsoft Store. Un instalador sin comprobación no entra.
- Ningún secreto, credencial, correo ni ajuste personal del autor en el repositorio, los
  diagnósticos ni las releases. Los diagnósticos ocultan rutas de perfil y patrones de secretos.
- Cada acción con privilegios se pide de forma explícita (UAC) y se explica antes. La app no
  reinicia, no actualiza otras apps ni ejecuta lotes por su cuenta salvo ajuste activado por el
  usuario.
- Sin telemetría propia ni servicio propio. Las únicas conexiones son a los orígenes oficiales de
  los paquetes y a GitHub para la actualización de la app.

Motivo: la app instala software con permisos de administrador; un fallo de procedencia compromete
el equipo entero.

### II. Reversible y honesto con el resultado

- Todo ajuste de sistema guarda el estado anterior (valores y tipos) y ofrece **Deshacer** que
  restaura ese estado, no valores genéricos. Lo que no se puede deshacer se avisa antes.
- Un código de salida no basta para dar algo por correcto: se comprueba el resultado real
  (inventario, servicio, archivo). «No se pudo comprobar» es un estado distinto de «ausente».
- Los fallos se explican en lenguaje claro con código, motivo y qué hacer. Nunca se afirma «sin
  fallos» sin prueba que lo respalde.

Motivo: el usuario confía en la app para dejar su PC listo; un éxito falso es peor que un fallo
visible.

### III. Calidad comprobada en Windows real (NO NEGOCIABLE)

- Cada cambio de comportamiento tiene prueba automática. La lógica pura se prueba con pruebas
  unitarias; la interfaz, el instalador y el EXE se prueban en los runners Windows de CI (x64,
  ARM64 y proceso x86).
- Las puertas de CI que deciden la publicación no pueden tener `continue-on-error`. Una release
  solo se publica si toda la matriz pasa en el mismo commit.
- Las pruebas que instalan o desinstalan programas solo se ejecutan en runners desechables, nunca
  en un PC o VM con datos del usuario.
- Tras publicar se verifica que el tag tiene release, que `releases/latest` apunta a él y que los
  archivos descargables coinciden con sus SHA256.

Motivo: el desarrollo se hace desde macOS; la única validación válida es la de Windows real.

### IV. Modular, declarativo y mantenible

- El catálogo, los perfiles y las guías son datos validados por esquema, no código.
- Cada módulo (motor de lotes, catálogo, sistema, remoto, seguridad, mantenimiento, interfaz)
  vive en su propio archivo con responsabilidades claras; ningún archivo de código supera ~1.500
  líneas sin justificación escrita en el plan.
- Código limpio y legible: comentarios en español, identificadores en inglés.
- Se crece en funciones útiles, no en volumen de catálogo: cada entrada nueva debe justificar su
  valor frente a las existentes.

Motivo: un único archivo de miles de líneas frena cada cambio y multiplica las regresiones.

### V. Interfaz negra, minimalista y accesible

- Modo oscuro absoluto, diseño minimalista con base Pixel/Material y Liquid Glass selectivo según
  la nota **Diseño Apple y Pixel**; iconos monoline sobre fondo negro.
- La ventana se adapta a cualquier pantalla (portátiles pequeños, monitores grandes, máquinas
  virtuales), con zoom de 70 % a 200 % y navegación completa por teclado.
- Interfaz y documentación en español. La versión actual es visible en la app junto al enlace de
  Instagram.

Motivo: es una herramienta de uso frecuente; tiene que ser cómoda a la vista y rápida de usar.

## Restricciones técnicas y de plataforma

- Windows 10 y 11 en x86, x64 y ARM64. Todo arreglo o cambio se aplica y documenta para las tres
  arquitecturas; si un paquete del proveedor no existe para alguna, se declara.
- Componentes incluidos en Windows siempre que sea posible (PowerShell 5.1, .NET Framework 4.8 y
  su compilador C#). Una dependencia nueva requiere justificación en el plan.
- Paquetes desde WinGet, Microsoft Store o instaladores oficiales con firma del fabricante.
- Servicios de pago (firma de código, hospedaje) solo con aprobación expresa del usuario.

## Flujo de desarrollo y publicación

- Cambios grandes (varias pantallas, nueva arquitectura, datos o integraciones) pasan por Spec Kit:
  constitución → especificación → aclaraciones → plan → tareas → implementación. No se programa
  hasta revisar especificación y plan.
- Versionado incremental `+0.1` (v4.0 → v4.1 … v4.9 → v5.0). Cada versión: commit
  `🔖 vX.X — …`, tag anotado, push, CHANGELOG con secciones Añadido/Mejorado/Cambiado/Corregido/
  Eliminado/Archivos y pruebas, README actualizado y release Latest con `iWinInstaller-Setup.exe`
  e `iWinInstaller.zip` adjuntos.
- Una sola copia de trabajo en `/Users/david/Documents/Desarrollo/Windows/PowerShell/iWinInstaller`
  y rama `main`. Sin worktrees ni copias paralelas.
- Antes de intervenir se consultan la Bitácora técnica y el Registro de cambios en Obsidian; después
  se registran cambios, diagnósticos, pruebas y pendientes.

## Gobierno

- Esta constitución prevalece sobre cualquier otra práctica del repositorio; las normas globales
  de Obsidian prevalecen sobre ella.
- Cada plan incluye una comprobación explícita contra estos principios; una excepción se justifica
  por escrito en la sección de complejidad del plan.
- Enmiendas: se proponen en un commit propio, con versión semántica de la constitución (MAYOR si
  se retira o redefine un principio, MENOR si se añade uno, PARCHE para aclaraciones) y entrada en
  la Bitácora técnica.

**Versión**: 1.0.0 | **Ratificada**: 2026-11-08 | **Última enmienda**: 2026-11-08
