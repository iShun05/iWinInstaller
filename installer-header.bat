@echo off
setlocal
set "IWIN_SETUP_FILE=%~f0"
rem Desde v4.3 se instala en Program Files: el instalador se reabre con permiso de administrador.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "try { Start-Process -FilePath $env:IWIN_SETUP_FILE -Verb RunAs } catch { exit 1 }"
  if errorlevel 1 (echo Se necesita permiso de administrador para instalar iWinInstaller. & pause)
  exit /b
)
rem iWinInstaller - instalador de doble clic. El PowerShell de install.ps1 va incrustado debajo de la marca.
echo Instalando iWinInstaller...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = [IO.File]::ReadAllText($env:IWIN_SETUP_FILE); $i = $s.IndexOf('#INSTALL' + '_PS1#'); $e = $s.IndexOf('#PAYLOAD' + '_ZIP#'); if ($e -lt 0) { $e = $s.Length }; & ([scriptblock]::Create($s.Substring($i, $e - $i)))"
if errorlevel 1 (echo. & echo No se pudo instalar. Revisa el mensaje de arriba. & pause & exit /b 1)
exit /b 0
#INSTALL_PS1#
