@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "NODE=node"
if exist "%~dp0node.exe" set "NODE=%~dp0node.exe"
echo YTS 를 먼저 끄세요 (카메라를 쓰고 있으면 확인 못 함)
pause
"%NODE%" camera_probe.js
pause
