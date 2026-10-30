@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "NODE=node"
if exist "%~dp0node.exe" set "NODE=%~dp0node.exe"
call 3_screens_close.bat >nul
"%NODE%" launch.js span fruit-vr.html
timeout /t 3 >nul
