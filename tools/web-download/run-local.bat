@echo off
cd /d "%~dp0"
echo Harmony Music is available at http://127.0.0.1:8000
python -m http.server 8000 --bind 127.0.0.1
pause