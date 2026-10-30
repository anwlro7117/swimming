@echo off
cd /d "%~dp0"
node launch.js list
node launch.js identify
pause
