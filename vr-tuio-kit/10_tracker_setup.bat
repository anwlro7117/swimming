@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"
if not defined PY (
  echo [오류] 파이썬 없음. python.org 에서 Python 3 설치. 설치 첫 화면 "Add python.exe to PATH" 체크 필수.
  pause & exit /b
)
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
echo 트래커 부품 설치 (인터넷 필요, 1회만)
%PY% -m pip install --upgrade opencv-python numpy
echo.
echo 끝. 오류 없으면 11_tracker_start.bat 사용.
pause
