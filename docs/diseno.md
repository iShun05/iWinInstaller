# Sistema de diseño (v5.7)

Fluent / Windows 11 sobre negro. Fuente única: `src/app/Theme/Theme.xaml`. Las vistas **no** escriben colores hex, radios ni tamaños sueltos: usan estos recursos.

## Tokens
- **Fondos por capas:** `Background` (ventana) < `Sidebar` < `Surface` (tarjeta) < `SurfaceRaised` (controles, paneles internos) < `SurfaceOverlay` (menús, popups). `SurfaceInput` para cajas de texto. `Scrim` para velos modales.
- **Bordes:** `BorderSubtle` (separadores de lista), `Border` (tarjetas), `BorderStrong` (controles), `BorderHover`.
- **Texto:** `TextStrong` (títulos) · `Text` (cuerpo) · `TextMuted` (secundario) · `TextFaint` (pies y notas).
- **Acento:** `Accent`, `AccentHover`, `AccentSoft` (fondo), `AccentBorder`, `AccentText` (texto sobre acento).
- **Estados:** `Ok` / `Attention` / `Danger` / `Unknown`, cada uno con `*Soft` (fondo) y `*Border` (Ok, Attention, Danger).
- **Radios:** `RadiusSmall` 4 · `RadiusControl` 6 · `RadiusCard` 10 · `RadiusOverlay` 12 · `RadiusPill`.
- **Espaciado** (múltiplos de 4): `PageMargin` 40,32 · `CardPadding` 20,18 · tarjetas separadas 12 · controles separados 8 · `PageMaxWidth` 960 · `ControlHeight` 32.

## Tipografía (estilos de TextBlock)
`PageTitle` (28, Display) · `PageSubtitle` (13.5, muted, máx. 760) · `SectionTitle` (16) · `CardTitle` (14.5) · `Overline` (12 semibold muted) · `Body` · `Muted` · `Caption` (12 faint) · `Glyph` (icono Segoe Fluent).

## Componentes
- **Página:** `ScrollViewer` › `StackPanel Margin={StaticResource PageMargin} MaxWidth={StaticResource PageMaxWidth} HorizontalAlignment=Left`. Cabecera: `DockPanel` con `PageTitle` + `PageSubtitle` a la izquierda y las acciones de página a la derecha (como mucho una `Primary`). Debajo, `ContentControl Style=InfoBar Content={Binding Message}` (se oculta vacío y toma color e icono según el texto: error, aviso, éxito o info).
- **Tarjeta:** `Border Style=Card`. Cabecera opcional: `IconTile` con `Glyph` + `CardTitle` + `Muted`. Paneles internos: `CardInset`. Filas de lista: `Border Style=ListRow`.
- **Botones:** `Primary` (una acción principal por zona) · `Btn` (estándar) · `Ghost`/`CommandButton` (barras de comandos, secundarias) · `IconButton` (solo icono; con `ToolTip` y `AutomationProperties.Name`) · `DangerBtn` / `DangerGhost` (destructivas) · `LinkButton` (enlace con flecha). Icono: `core:Ui.Icon="&#xE710;"`. Menú de desbordamiento: `core:Ui.OpensMenu="True"` + `Button.ContextMenu` con `MenuItem` (`Icon` = glifo como texto), `Separator` y `MenuHeader`.
- **Estado:** `Pill` (sin fondo) con `StatusGlyph` (icono de línea: E930 correcto, E7BA atención, E783 error, EA3A sin dato, E895 en curso) coloreado con el token de estado, y `PillText` en gris. Nunca cápsulas de color. **Etiqueta neutra:** `Tag` (contorno fino).
- **Entrada:** `TextBox` (Tag = texto de ayuda), `SearchBox`, `ComboBox`, `CheckBox`, `ProgressBar` con estilo implícito.

## Movimiento
Hover en 120 ms, salida en 180 ms; indicador de la navegación que crece (220 ms); entrada de página con fundido y 10 px (`core:Ui.Entrance`). Si Windows tiene las animaciones desactivadas, las páginas entran sin animación.

## Iconos usados (Segoe Fluent Icons)
Añadir E710 · Guardar E74E · Abrir/Importar E8E5 · Exportar/Compartir E72D · Borrar E74D · Actualizar E72C · Comprobar E73E · Ajustes E713 · Más E712 · Carpeta E838 · Nube subir E898 · Nube bajar E896 · Código E943 · Vincular E71B · PC E7F4 · Perfil E77B · Filtrar E71C · Copiar E8C8 · Cerrar E711 · Escudo EA18 · Juego E7FC · Velocímetro EC4A · Info E946 · Aviso E7BA · Error E783 · Hecho E930.
