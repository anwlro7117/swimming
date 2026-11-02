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
echo 카메라별 실제 fps 측정. YTS 끄고 실행. 1분쯤 걸림.
%PY% tracker.py --probe
pause
