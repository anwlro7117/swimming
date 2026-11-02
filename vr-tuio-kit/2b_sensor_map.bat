@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "NODE=node"
if exist "%~dp0node.exe" set "NODE=%~dp0node.exe"
call 3_screens_close.bat >nul
timeout /t 1 >nul
"%NODE%" launch.js sense.html
if errorlevel 1 pause
