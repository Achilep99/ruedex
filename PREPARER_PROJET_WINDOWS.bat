@echo off
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo.
  echo ERREUR : Flutter n'est pas installe ou n'est pas dans le PATH.
  echo Ouvre le fichier README.md, section Installation Windows.
  echo.
  pause
  exit /b 1
)

echo [1/4] Sauvegarde du code RueDex...
set "BACKUP=%TEMP%\ruedex_backup_%RANDOM%"
mkdir "%BACKUP%"
xcopy /E /I /Y lib "%BACKUP%\lib" >nul
xcopy /E /I /Y assets "%BACKUP%\assets" >nul
xcopy /E /I /Y test "%BACKUP%\test" >nul
copy /Y README.md "%BACKUP%\README.md" >nul
copy /Y pubspec.yaml "%BACKUP%\pubspec.yaml" >nul
copy /Y analysis_options.yaml "%BACKUP%\analysis_options.yaml" >nul

echo [2/4] Generation de la plateforme Android compatible avec ton Flutter...
call flutter create --platforms=android --org com.ruedex .
if errorlevel 1 goto :error

echo [3/4] Restauration du code et configuration Android...
rmdir /S /Q lib
rmdir /S /Q assets
rmdir /S /Q test
xcopy /E /I /Y "%BACKUP%\lib" lib >nul
xcopy /E /I /Y "%BACKUP%\assets" assets >nul
xcopy /E /I /Y "%BACKUP%\test" test >nul
copy /Y "%BACKUP%\README.md" README.md >nul
copy /Y "%BACKUP%\pubspec.yaml" pubspec.yaml >nul
copy /Y "%BACKUP%\analysis_options.yaml" analysis_options.yaml >nul
powershell -NoProfile -ExecutionPolicy Bypass -File tools\configure_android.ps1
if errorlevel 1 goto :error

echo [4/4] Telechargement des dependances...
call flutter pub get
if errorlevel 1 goto :error

rmdir /S /Q "%BACKUP%"
echo.
echo PROJET PRET.
echo Lance maintenant LANCER_APPLICATION.bat avec un emulateur Android ouvert.
echo.
pause
exit /b 0

:error
echo.
echo La preparation a echoue. Copie l'erreur affichee et envoie-la moi.
echo Sauvegarde temporaire : %BACKUP%
pause
exit /b 1
