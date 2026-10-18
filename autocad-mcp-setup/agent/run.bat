@echo off
cd /d "%~dp0"
if not exist .env ( copy .env.example .env >nul & echo Da tao .env - hay mo va dien CETRIX_API_KEY, CETRIX_MODEL, MCP_PYTHON roi chay lai. & notepad .env & pause & exit /b )
if not exist .venv ( py -3 -m venv .venv || (echo Can Python 3.10+ & pause & exit /b 1) )
.venv\Scripts\python.exe -m pip install -q -r requirements.txt || (pause & exit /b 1)
start "" http://127.0.0.1:8765
.venv\Scripts\python.exe server.py
pause
