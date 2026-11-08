# Política de firma de código

iWinInstaller solicita firma gratuita para código abierto a [SignPath Foundation](https://signpath.org).
Hasta que la solicitud se apruebe, los ejecutables se publican sin firma Authenticode y con la
procedencia firmada de GitHub (`gh attestation verify`).

## Qué se firma

- `iWinInstaller.exe` (lanzador de la app)
- `iWinInstaller-Setup.exe` (instalador de doble clic)

Solo se firman archivos compilados en GitHub Actions a partir de un tag `vX.X` de la rama `main`,
después de que pasen todas las pruebas que deciden la publicación. Nunca se firma un archivo
compilado en un equipo personal.

Certificado: «Free code signing provided by SignPath.io, certificate by SignPath Foundation».

## Funciones del equipo

- **Autor y aprobador**: [iShun05](https://github.com/iShun05). Revisa cada cambio antes de
  fusionarlo y aprueba cada solicitud de firma.
- Todas las cuentas con permiso de escritura usan verificación en dos pasos.

## Componentes de terceros incluidos

El instalador incluye los paquetes oficiales de Microsoft para preparar WinGet
(`Microsoft.DesktopAppInstaller` y sus dependencias), descargados de
[microsoft/winget-cli](https://github.com/microsoft/winget-cli) y comprobados con las huellas
SHA256 fijadas en [`native/prerequisites.json`](../native/prerequisites.json). Esos archivos
conservan la firma de Microsoft y no se vuelven a firmar.

## Privacidad

Ver la sección «Privacidad y límites» del [README](../README.md): la app no tiene telemetría
propia y solo se conecta a los orígenes oficiales de los paquetes, a Microsoft y a GitHub.

## Informar de un problema

Usa **Security → Report a vulnerability** en este repositorio ([SECURITY.md](../SECURITY.md)).
