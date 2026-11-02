@echo off
rem MoonMod animation editor: starts its local server and opens it in your browser. Close this window to stop it.
cd /d "%~dp0..\..\.."
start "" cmd /c "timeout /t 2 >nul & start http://127.0.0.1:8765/"
python tools\anim\editor\server.py %*
pause
