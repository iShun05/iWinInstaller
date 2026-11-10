# 002 · Segundo plano, Windows a mano y resiliencia (v5.2)

Petición del usuario (2026-11-10): profesionalizar la app, tener a mano los ajustes de Windows, que pueda
quedarse en segundo plano vigilando el equipo, animaciones, Brave limpio con Google y marcadores visibles,
y más aplicaciones útiles. Se implementó en la misma sesión por indicación expresa del usuario; este
documento recoge el alcance y lo que queda, sin duplicar el CHANGELOG.

## Historias

1. **Segundo plano**: al cerrar la ventana la app sigue en la bandeja, muestra el uso del equipo y avisa
   cuando algo pasa a requerir atención. Opcional y desactivado al principio (constitución I).
2. **Windows a mano**: abrir cualquier ajuste o herramienta habitual de Windows en un clic o desde `Ctrl + K`.
3. **Resiliencia**: una sola instancia, errores registrados, registros acotados y mensajes claros en
   equipos con PowerShell restringido.
4. **Brave limpio**: barra de marcadores visible; Google como buscador queda como paso guiado.

## Criterios de aceptación

- Con el segundo plano desactivado la app se comporta como en v5.1 (cerrar la ventana cierra la app).
- Ningún aviso se repite mientras la tarjeta siga en «Requiere atención»; la primera comprobación no avisa.
- Los atajos solo abren destinos de una lista fija validada por prueba (`QuickLinks.IsSafeTarget`).
- Las animaciones se omiten si Windows tiene desactivados los efectos de animación o el usuario las apaga.
- Deshacer «Brave limpio» restaura el valor anterior de la barra de marcadores.

## Decisiones

- **Google en Brave no se fuerza.** `DefaultSearchProviderEnabled` es una política «sensible» que Chromium
  bloquea fuera de dominio/MDM (`components/policy/core/common/policy_loader_common.cc`,
  `AsyncPolicyLoader::ShouldFilterSensitivePolicies`), y la preferencia está protegida por firma. Simular
  un MDM en el registro rebajaría la seguridad de todos los navegadores Chromium del equipo: descartado.
- **Monitor sin contadores de rendimiento**: `GetSystemTimes` y `GlobalMemoryStatusEx` no fallan con
  contadores dañados ni dependen del idioma.
- **Arranque con Windows** mediante la clave `Run` del usuario y `iWinInstaller.App.exe --tray`.
  Pendiente de decidir si debe pasar por el lanzador para repetir la comprobación de integridad.
- **Catálogo**: solo tres entradas con id comprobado. Avast, AVG y Avira no se añadieron: sus ids no se
  pudieron confirmar en `microsoft/winget-pkgs` desde esta sesión.

## Pendiente

- [ ] Compilación y pruebas en los runners Windows (x64, ARM64, x86).
- [ ] Revisión en pantalla real: bandeja, avisos, animaciones, zoom al 200 % y ventana pequeña.
- [ ] Decidir si el arranque con Windows pasa por el lanzador.
- [ ] Firma Authenticode (T030), PSScriptAnalyzer, CodeQL y manifiesto WinGet.
- [ ] Pruebas de extremo a extremo de la interfaz (FlaUI) y T070/T077.
