@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "NODE=node"
if exist "%~dp0node.exe" set "NODE=%~dp0node.exe"
where node >nul 2>&1 || if not exist "%~dp0node.exe" (
  echo [오류] Node.js 없음. nodejs.org 에서 LTS 설치 후 이 창 닫고 다시 실행.
  echo        설치 못 하면 node.exe 를 이 폴더에 넣어도 된다.
  pause & exit /b
)
"%NODE%" launch.js list
"%NODE%" launch.js identify
pause
