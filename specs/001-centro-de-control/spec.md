# Feature Specification: Centro de control del PC (camino a v5.0)

**Feature Branch**: `main` (rama única del proyecto; la carpeta de la especificación es `specs/001-centro-de-control`)

**Created**: 2026-11-08

**Status**: Clarified

**Input**: User description: "Mejorar y profesionalizar iWinInstaller para que sea un todo en uno: algo que se pueda usar para absolutamente todo lo que se necesite en el PC."

## Visión

iWinInstaller deja de ser «un instalador con extras» y pasa a ser el **centro de control del PC
con Windows**: instalar, mantener al día, revisar la salud, proteger, ajustar y trasladar el
equipo desde una sola app. El crecimiento es en **funciones**, no en número de apps del catálogo
(decisión vigente en la Bitácora técnica). Antes de añadir funciones se refuerza la base: que la
descarga inspire confianza, que la app esté protegida y que cada versión publicada esté verificada.

Se entrega en versiones incrementales `+0.1` desde v4.0 hasta v5.0; cada historia de usuario es
publicable por separado.

## Clarifications

### Session 2026-11-08

- Q: ¿Qué historias entran en v5.0? → A: Núcleo US1–US5; US6–US9 pasan a 5.x.
- Q: ¿Cómo se firma el ejecutable? → A: SignPath Foundation (gratis para código abierto; editor
  mostrado «SignPath Foundation»). Azure Artifact Signing no admite particulares fuera de EE. UU.
  o Canadá.
- Q: ¿Tecnología de la interfaz? → A: interfaz WPF en C# sobre .NET Framework 4.8; PowerShell queda
  como motor (decisión técnica, se desarrolla en el plan).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Descargar e instalar con confianza (Priority: P1)

Quien descarga iWinInstaller por primera vez lo abre sin advertencias alarmantes, comprueba quién
lo publica y la app queda instalada en una ubicación que otros programas de su usuario no pueden
alterar. Cada versión anunciada está realmente publicada y descargable.

**Why this priority**: es la primera impresión y la base de seguridad de todo lo demás. Hoy
SmartScreen avisa en cada descarga, la app vive en una carpeta modificable por el usuario y ya
ocurrió que la última release se quedó semanas atrás respecto al código.

**Independent Test**: descargar la release en un Windows limpio, abrirla y comprobar editor
identificado, ubicación protegida y que la versión publicada coincide con el último tag.

**Acceptance Scenarios**:

1. **Given** un Windows 11 limpio, **When** el usuario abre el instalador descargado, **Then**
   Windows muestra el editor del ejecutable en lugar de «Editor desconocido».
2. **Given** una instalación anterior por usuario con perfiles, notas y lotes, **When** se instala
   la nueva versión, **Then** la app pasa a la ubicación protegida y conserva todos esos datos.
3. **Given** que se crea un tag de versión, **When** termina la publicación, **Then** existe su
   release marcada como última, con sus dos descargas, y sus huellas coinciden con lo publicado;
   si algo falta, la publicación se marca como fallida y avisa.

---

### User Story 2 - Estado del PC de un vistazo (Priority: P1)

Al abrir la app, el usuario ve una pantalla de inicio con el estado del equipo: actualizaciones
pendientes de apps y de Windows, protección antivirus, espacio en disco, salud de discos y batería,
reinicio pendiente y lotes sin terminar. Cada aviso trae su botón para resolverlo.

**Why this priority**: es lo que convierte la app en algo que se abre a diario y no solo al
formatear. Reúne funciones que ya existen (Defender, lotes, reinicios) y les da sentido.

**Independent Test**: abrir la app en un equipo con una actualización pendiente y poco espacio;
la pantalla de inicio muestra ambos avisos y cada botón lleva a resolverlos.

**Acceptance Scenarios**:

1. **Given** un equipo con 3 apps con versión nueva, **When** se abre la app, **Then** el inicio
   muestra «3 actualizaciones» y su botón abre la lista.
2. **Given** un disco del sistema con menos del 10 % libre, **When** se abre la app, **Then**
   aparece un aviso de espacio con acceso directo a la limpieza.
3. **Given** que una comprobación no puede completarse (sin red, sin permisos), **When** se muestra
   el inicio, **Then** esa tarjeta dice «no se pudo comprobar» y por qué, nunca «todo correcto».

---

### User Story 3 - Mantener las apps al día con control (Priority: P1)

El usuario ve qué apps tienen versión nueva (versión actual y nueva), elige cuáles actualizar,
excluye las que quiere mantener fijas y, si lo desea, programa la actualización periódica.

**Why this priority**: «Actualizar todo» ya existe pero es a ciegas; ver y elegir es lo que
espera una herramienta profesional y es la tarea recurrente más frecuente.

**Independent Test**: con dos apps desactualizadas, excluir una y actualizar; solo cambia la otra
y la exclusión se recuerda en la siguiente apertura.

**Acceptance Scenarios**:

1. **Given** apps con versión nueva, **When** el usuario abre Actualizaciones, **Then** ve cada una
   con versión instalada y disponible, y puede marcar o desmarcar.
2. **Given** una app excluida, **When** se ejecuta «Actualizar todo» (manual o programado),
   **Then** esa app no se toca y figura como excluida en el resultado.
3. **Given** la actualización programada activada, **When** llega la hora con la app cerrada,
   **Then** actualiza solo lo que no requiere intervención, no reinicia y deja informe para la
   próxima apertura.

---

### User Story 4 - Encontrar cualquier acción al momento (Priority: P2)

Con un atajo de teclado se abre una paleta de búsqueda: el usuario escribe «resolución», «limpiar»,
«SSH», «Brave» o «Defender» y salta a la acción, ajuste o app correspondiente.

**Why this priority**: con cientos de entradas y cada vez más módulos, la paleta es lo que hace
la app usable «para todo» sin perderse en menús.

**Independent Test**: abrir la paleta, escribir «frecuencia» y llegar al panel de resolución y Hz
en dos pulsaciones.

**Acceptance Scenarios**:

1. **Given** cualquier pantalla, **When** el usuario pulsa el atajo y escribe parte de un nombre,
   **Then** aparecen acciones, módulos, ajustes y apps coincidentes, también por sinónimos.
2. **Given** resultados, **When** se elige uno con el teclado, **Then** la app abre esa acción sin
   ejecutar nada que requiera confirmación.

---

### User Story 5 - Mantenimiento y salud del equipo (Priority: P2)

El usuario libera espacio (temporales, caché de actualizaciones, papelera), repara archivos de
sistema, consulta la salud de sus discos, la batería y las temperaturas, y exporta un informe del
equipo (componentes, salud, sistema) para soporte, garantía o venta.

**Why this priority**: es el segundo motivo más común para abrir una herramienta de PC después de
instalar; hoy obliga a usar varias apps distintas.

**Independent Test**: ejecutar la limpieza en un equipo con temporales; muestra cuánto liberará
antes de borrar y cuánto liberó al terminar.

**Acceptance Scenarios**:

1. **Given** archivos temporales, **When** el usuario pide limpiar, **Then** ve el espacio estimado
   por categoría y confirma antes de borrar; nunca se tocan documentos ni carpetas personales.
2. **Given** un disco con avisos de salud, **When** se abre Salud, **Then** se indica el disco, el
   problema en lenguaje claro y la recomendación (copia de seguridad).
3. **Given** un portátil, **When** se pide el informe de batería, **Then** se muestra capacidad
   original, actual y desgaste.
4. **Given** el informe del equipo, **When** el usuario lo exporta, **Then** obtiene un archivo
   legible sin números de serie, salvo que marque incluirlos.

---

### User Story 6 - Controlar lo que arranca con Windows (Priority: P3 · versión 5.x)

El usuario ve las apps, tareas y servicios que se inician con Windows, con su editor e impacto, y
desactiva lo que no quiere. Todo cambio se puede deshacer.

**Why this priority**: mejora mucho el arranque y encaja con el modelo reversible de la app, pero
es menos frecuente que las anteriores.

**Independent Test**: desactivar una app de inicio, reiniciar y comprobar que no arranca; deshacer
y comprobar que vuelve.

**Acceptance Scenarios**:

1. **Given** apps de inicio, **When** el usuario desactiva una, **Then** deja de arrancar y aparece
   como «desactivada por iWinInstaller» con opción de deshacer.
2. **Given** un servicio del sistema esencial, **When** se lista, **Then** no se ofrece
   desactivarlo.

---

### User Story 7 - Mudarse a otro PC (Priority: P3 · versión 5.x)

El usuario exporta en un archivo sus apps instaladas que están en el catálogo, sus ajustes de
iWinInstaller aplicados, perfiles WiFi y preferencias; en el PC nuevo lo importa y la app marca e
instala todo y reaplica los ajustes.

**Why this priority**: amplía los perfiles exportables que ya existen; aporta mucho al estrenar
equipo, pero se usa pocas veces.

**Independent Test**: exportar en un equipo, importar en otro limpio y comprobar que se marcan las
mismas apps y ajustes.

**Acceptance Scenarios**:

1. **Given** un archivo de mudanza, **When** se importa, **Then** la app muestra el resumen previo
   (apps, ajustes, redes) y el usuario puede quitar elementos antes de instalar.
2. **Given** la exportación de redes WiFi, **When** el usuario no marca «incluir contraseñas»,
   **Then** el archivo no contiene ninguna clave.

---

### User Story 8 - Red bajo control (Priority: P3 · versión 5.x)

El usuario elige un DNS (automático, Cloudflare, Quad9, Google, personalizado), diagnostica la
conexión en un paso (adaptador, puerta de enlace, DNS, internet, Tailscale) y recibe la causa
probable en lenguaje claro.

**Why this priority**: útil y frecuente en soporte, pero no imprescindible para el resto.

**Independent Test**: cambiar el DNS, comprobar que se usa y deshacer al valor anterior.

**Acceptance Scenarios**:

1. **Given** un DNS automático, **When** el usuario elige otro, **Then** se aplica al adaptador
   activo y Deshacer recupera exactamente el anterior.
2. **Given** que falla la resolución de nombres, **When** se diagnostica, **Then** se señala el DNS
   como causa probable y se propone la solución.

---

### User Story 9 - Catálogo siempre al día sin esperar versión (Priority: P3 · versión 5.x)

Cuando un paquete cambia de identificador o se retira, la app recibe un catálogo actualizado y
verificado sin tener que publicar una versión nueva del programa.

**Why this priority**: reduce fallos por paquetes retirados entre versiones; depende de que la
base de seguridad (US1) esté hecha.

**Independent Test**: publicar un catálogo con una corrección; la app lo descarga, comprueba su
firma o huella y lo usa; uno alterado se rechaza y se mantiene el anterior.

**Acceptance Scenarios**:

1. **Given** un catálogo nuevo publicado y verificado, **When** se abre la app, **Then** lo usa y lo
   indica en Acerca de.
2. **Given** un catálogo alterado o incompatible, **When** se descarga, **Then** se descarta y la
   app sigue con el incluido.

---

### Edge Cases

- Sin conexión: el inicio, la paleta, la salud y el arranque funcionan; actualizaciones y catálogo
  avisan de que no hay red.
- Usuario sin permisos de administrador: las funciones que lo requieren lo indican antes y piden
  elevación una sola vez por operación agrupada.
- Equipo de empresa con directivas que bloquean cambios: se informa «bloqueado por directivas»,
  no «falló».
- Windows 10 o ARM64 donde una herramienta de salud o temperatura no tiene datos: se muestra
  «no disponible en este equipo», sin errores.
- Máquina virtual sin batería, SMART ni sensores: las tarjetas correspondientes se ocultan o
  indican que no aplican.
- Actualización programada con una app abierta que bloquea su instalador: se pospone esa app y se
  informa, sin cerrarla a la fuerza.
- Migración desde la instalación por usuario con la app abierta o con un lote pendiente: no se
  pierde el lote ni los datos.
- Limpieza mientras otra app usa un temporal: se omite ese archivo y se cuenta como omitido.

## Requirements *(mandatory)*

### Functional Requirements

**Base y confianza**

- **FR-001**: Los ejecutables publicados MUST llevar firma de código que Windows reconozca como
  editor identificado, mediante el programa gratuito para código abierto de SignPath Foundation
  (editor mostrado: SignPath Foundation). Requisitos previos: licencia abierta aprobada por OSI en
  el repositorio, verificación en dos pasos en la cuenta de GitHub y página pública de política de
  firma. Mientras no se apruebe la solicitud, se publica sin firma y se indica en README.
- **FR-002**: La app MUST instalarse en una ubicación del sistema que un proceso del usuario sin
  elevación no pueda modificar, y MUST migrar automáticamente perfiles, notas, lotes, informes y
  preferencias desde la instalación por usuario.
- **FR-003**: La publicación MUST fallar si cualquier comprobación de la matriz (x64, ARM64, x86)
  falla en el mismo commit, y MUST verificar tras publicar que la release es la última, tiene sus
  dos descargas y sus huellas coinciden.
- **FR-004**: El catálogo, los perfiles y las guías MUST validarse contra un esquema antes de
  publicar; una entrada inválida bloquea la publicación.
- **FR-005**: La app MUST ofrecer una línea de comandos documentada (instalar, actualizar, aplicar
  perfil, informe) con códigos de salida estables para uso desatendido.

**Inicio y navegación**

- **FR-010**: La app MUST abrir en una pantalla de inicio con tarjetas de estado: actualizaciones
  de apps, Windows Update, antivirus, espacio, salud de discos, batería (si existe), reinicio
  pendiente y lotes sin terminar.
- **FR-011**: Cada tarjeta MUST distinguir «correcto», «requiere atención» y «no se pudo
  comprobar», con el motivo en este último caso.
- **FR-012**: El inicio MUST mostrarse utilizable en menos de 2 s; las comprobaciones lentas
  completan después sin bloquear la ventana.
- **FR-013**: La app MUST ofrecer navegación por módulos (Inicio, Instalar, Actualizaciones,
  Mantenimiento, Sistema, Arranque, Red, Remoto, Seguridad, Mudanza) y una paleta de búsqueda
  accesible por atajo desde cualquier pantalla.
- **FR-014**: La paleta MUST encontrar acciones, módulos, ajustes y apps por nombre, descripción y
  sinónimos en español, y abrirlos sin ejecutar acciones que requieran confirmación.

**Actualizaciones**

- **FR-020**: La app MUST listar las apps con versión nueva mostrando versión instalada y
  disponible, con selección individual.
- **FR-021**: Los usuarios MUST poder excluir apps de forma persistente; las exclusiones se
  respetan en actualizaciones manuales, programadas y por línea de comandos.
- **FR-022**: La actualización programada MUST ser opcional, estar desactivada por defecto,
  ejecutarse con el usuario, omitir instaladores interactivos, no reiniciar y dejar informe.

**Mantenimiento y salud**

- **FR-030**: La limpieza MUST mostrar el espacio estimado por categoría antes de borrar, pedir
  confirmación, limitarse a ubicaciones temporales y de caché del sistema y de las apps, y mostrar
  lo liberado y lo omitido.
- **FR-031**: La app MUST ofrecer reparación de archivos del sistema con progreso y resultado
  explicado.
- **FR-032**: La app MUST mostrar la salud de cada disco, la capacidad y desgaste de la batería y
  las temperaturas disponibles, indicando «no disponible» cuando el equipo no lo expone.
- **FR-033**: La app MUST exportar un informe del equipo legible; los números de serie y nombres de
  equipo se excluyen salvo que el usuario los incluya expresamente.

**Arranque, red y mudanza**

- **FR-040**: La app MUST listar apps, tareas y servicios de inicio con editor e impacto, permitir
  desactivarlos y deshacer exactamente, y MUST impedir desactivar servicios esenciales.
- **FR-041**: La app MUST permitir elegir DNS por adaptador con deshacer al valor anterior exacto, y
  un diagnóstico de conexión con causa probable.
- **FR-042**: La app MUST exportar e importar un archivo de mudanza con apps del catálogo, ajustes
  aplicados, perfiles WiFi y preferencias, con resumen editable antes de importar; las contraseñas
  WiFi solo se incluyen si el usuario lo marca y con aviso.

**Catálogo**

- **FR-050**: La app MUST poder recibir catálogos actualizados entre versiones, verificar su
  integridad y procedencia antes de usarlos y volver al catálogo incluido si la verificación falla.

**Alcance**

- **FR-060**: La versión 5.0 incluye las historias US1–US5. US6–US9 (arranque, red, mudanza y
  catálogo actualizable) quedan para versiones 5.x posteriores y no bloquean la 5.0.

**Transversales**

- **FR-070**: Todo ajuste nuevo MUST guardar el estado anterior y ofrecer Deshacer, o avisar antes
  si no es reversible.
- **FR-071**: Toda función nueva MUST funcionar o declarar su límite en Windows 10 y 11, x86, x64 y
  ARM64.
- **FR-072**: Ninguna función nueva MUST enviar datos a servicios distintos de los orígenes de los
  paquetes, Microsoft y GitHub.

### Key Entities

- **Tarjeta de estado**: área (actualizaciones, disco, antivirus…), estado (correcto, atención,
  no comprobado), motivo, acción asociada, momento de la comprobación.
- **Actualización disponible**: app, versión instalada, versión disponible, origen, si requiere
  intervención, si está excluida.
- **Exclusión**: app y fecha; persiste entre versiones de iWinInstaller.
- **Acción de paleta**: nombre, módulo, sinónimos, si requiere confirmación o administrador.
- **Elemento de arranque**: nombre, tipo (app, tarea, servicio), editor, impacto, estado y estado
  anterior para deshacer.
- **Informe del equipo**: componentes, sistema, salud y fecha; campos sensibles opcionales.
- **Archivo de mudanza**: versión del formato, apps, ajustes, redes (con o sin claves),
  preferencias.
- **Catálogo publicado**: versión, fecha, huella o firma, versión mínima de la app compatible.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: El 100 % de las versiones publicadas desde v4.1 tiene release, descargas y huellas
  verificadas automáticamente; ningún tag queda sin release más de 1 hora.
- **SC-002**: Abrir la app y ver el estado del PC lleva menos de 2 s en un equipo de gama media;
  todas las tarjetas completan en menos de 15 s con red.
- **SC-003**: Llegar a cualquier acción de la app con la paleta requiere como máximo 3 pulsaciones
  de teclado tras el atajo en el 90 % de las búsquedas de prueba.
- **SC-004**: Actualizar las apps con exclusiones lleva menos de 3 clics desde el inicio.
- **SC-005**: Ninguna función nueva deja el sistema en un estado sin Deshacer documentado; el 100 %
  de los ajustes nuevos supera la prueba aplicar → deshacer → estado idéntico.
- **SC-006**: El usuario deja de necesitar al menos 4 herramientas externas habituales (gestor de
  actualizaciones, limpiador, monitor de salud de discos, gestor de inicio).
- **SC-007**: Ningún archivo de código del proyecto supera ~1.500 líneas al llegar a v5.0.

## Assumptions

- Usuarios: particulares y entusiastas que preparan y mantienen sus PC; uso empresarial (Intune,
  políticas) queda fuera de v5.0 salvo la línea de comandos (FR-005).
- Se mantiene la interfaz en español, el diseño negro minimalista y las funciones actuales; nada
  existente se retira sin indicarlo en el CHANGELOG.
- La instalación protegida implica pedir permiso de administrador una vez al instalar o migrar.
- Las temperaturas y la salud de discos dependen de lo que exponga cada equipo; no se instalan
  controladores de terceros para leer sensores.
- La limpieza no incluye «optimizadores» de registro ni borrados agresivos; solo ubicaciones
  temporales conocidas.
- El catálogo sigue creciendo solo cuando una entrada aporta valor frente a las existentes.
- Desarrollo desde macOS; la validación es la CI de Windows y un equipo real del usuario para lo
  físico (batería, sensores, RGB).
