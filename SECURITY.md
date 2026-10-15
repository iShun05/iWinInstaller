# Seguridad

## Informar de un fallo
Abre un aviso privado en **Security → Report a vulnerability** de este repositorio. No publiques el detalle en un issue abierto.

## Qué comprueba iWinInstaller antes de ejecutar algo
- **Descarga de la app y actualizaciones:** SHA256 publicado por GitHub para cada archivo de la Release; si no coincide, no se instala.
- **Instalador de doble clic:** el paquete incrustado lleva su SHA256 y se comprueba antes de descomprimirlo.
- **winget incluido:** huellas SHA256 fijadas en `native/prerequisites.json` (archivos oficiales de Microsoft).
- **Chrome:** firma Authenticode válida de Google LLC.
- **Instaladores directos (HoYoPlay, Riot):** firma Authenticode válida **del fabricante esperado** (campo `signer`).
- **Guest Additions de VirtualBox:** SHA256 contra el `SHA256SUMS` de Oracle.
- **Resto de apps:** winget/Microsoft Store, que verifican el hash de cada instalador según su manifiesto.

## Verificar una descarga
Desde v2.2 cada archivo de la Release tiene procedencia firmada por GitHub Actions:

```
gh attestation verify iWinInstaller-Setup.exe --repo iShun05/iWinInstaller
```

## Límites conocidos
- Los ejecutables no llevan firma Authenticode propia (requiere un certificado de pago), así que SmartScreen puede avisar.
- La app se instala por usuario en `%LOCALAPPDATA%\Programs\iWinInstaller`. Un programa malicioso que ya se ejecute con tu usuario podría modificarla antes de que aceptes un aviso de administrador. Es el mismo modelo que otros instaladores por usuario.
