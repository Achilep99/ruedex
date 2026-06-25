@echo off
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter est introuvable. Consulte README.md.
  pause
  exit /b 1
)

if not exist android\app\src\main\AndroidManifest.xml (
  echo Le projet Android n'est pas encore prepare.
  call PREPARER_PROJET_WINDOWS.bat
  if errorlevel 1 exit /b 1
)

echo Appareils disponibles :
call flutter devices
echo.
echo Lancement de RueDex...
call flutter run
pause
