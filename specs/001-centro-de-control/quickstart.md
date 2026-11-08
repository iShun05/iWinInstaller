# Guía de validación

Las pruebas que instalan o desinstalan programas solo se ejecutan en runners desechables o en una
VM creada para ello, nunca en un PC con datos personales.

## Requisitos

- Windows 10 22H2 o Windows 11, x64 (y los runners ARM64/x86 de CI).
- Para compilar en local en Windows: Git, SDK de .NET 8 o posterior (solo compilación) y Pester 5.

## Compilar y probar

```powershell
git clone https://github.com/iShun05/iWinInstaller.git; cd iWinInstaller
Invoke-Pester tests/unit/engine                       # motor (desde v4.1)
dotnet test tests/unit/app                            # ViewModel C# (desde v4.4)
./scripts/build_exe.ps1 -OutputDirectory "$env:TEMP/iwin-release"
```

Resultado esperado: todas las pruebas en verde y `iWinInstaller-Setup.exe` en el directorio de
salida.

## Validación por versión

| Versión | Escenario | Resultado esperado |
|---|---|---|
| v4.1 | Introducir una entrada inválida en el catálogo y lanzar CI | La CI falla en la validación de esquema y no se publica |
| v4.1 | Crear un tag de prueba sin release (repositorio de pruebas) | La verificación posterior falla y avisa |
| v4.2 | `iWinInstaller.ps1 -Check -Json` | JSON válido con el inventario; mismo resultado que `-Check` de v4.1 |
| v4.3 | Instalar sobre una v4.2 por usuario con perfiles y notas | App en `%ProgramFiles%\iWinInstaller`, datos intactos, carpeta antigua eliminada |
| v4.3 | Modificar un archivo en `%ProgramFiles%\iWinInstaller` sin elevación | Acceso denegado |
| v4.4 | Abrir la app con una actualización pendiente y sin red | Tarjeta de actualizaciones en «no se pudo comprobar: sin conexión»; inicio en < 2 s |
| v4.5 | Excluir una app y ejecutar `-Update` | La app excluida no cambia y figura como excluida |
| v4.6 | Ejecutar las suites `check-acceptance` contra el nuevo EXE | Mismos resultados que con la interfaz anterior |
| v4.7 | Aplicar y deshacer cada ajuste reversible | Estado final idéntico al inicial (SC-005) |
| v4.8 | Paleta: escribir «frecuencia», «ssh», «defender» | Cada acción alcanzada en ≤ 3 pulsaciones tras el atajo |
| v4.9 | Limpieza con temporales creados por la prueba | Estimación previa ≥ lo liberado; ningún archivo fuera de la lista blanca tocado |
| v4.9 | Informe del equipo sin marcar datos sensibles | Sin número de serie, nombre de equipo ni usuario |
| v5.0 | Matriz completa x86/x64/ARM64 y verificación de release | Todos los criterios SC-001…SC-007 comprobados y registrados |

## Lo que no cubre la CI

Batería real, sensores de temperatura, SMART de discos físicos y monitores reales se comprueban en
el equipo del usuario y se registran en la Bitácora técnica.
