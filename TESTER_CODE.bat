@echo off
setlocal
cd /d "%~dp0"
call flutter pub get
if errorlevel 1 exit /b 1
call flutter test
pause
