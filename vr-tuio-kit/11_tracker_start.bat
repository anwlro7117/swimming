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
tasklist /fi "imagename eq YTS.exe" 2>nul | find /i "YTS.exe" >nul && (
  echo YTS 켜져 있음. 카메라를 같이 못 쓴다. YTS 를 끄고 계속한다.
  echo  ^(YTS 설정·보정 파일은 건드리지 않음. 다시 YTS 쓰려면 YTS 켜면 됨^)
  pause
  taskkill /im YTS.exe /f >nul 2>&1
  timeout /t 2 >nul
)
title VR tracker
%PY% tracker.py
pause
