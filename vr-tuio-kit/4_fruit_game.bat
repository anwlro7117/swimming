@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "NODE=node"
if exist "%~dp0node.exe" set "NODE=%~dp0node.exe"
curl -s -f -o nul http://localhost:8080/fruit-vr.html
if errorlevel 1 (
  echo [멈춤] 브리지가 안 켜졌거나 옛 폴더 브리지가 켜져 있다.
  echo        "VR TUIO bridge" 창을 모두 닫고, 이 폴더의 1_bridge_start.bat 을 실행한 뒤 다시 한다.
  pause & exit /b
)
call 3_screens_close.bat >nul
timeout /t 1 >nul
"%NODE%" launch.js span fruit-vr.html
if errorlevel 1 pause
