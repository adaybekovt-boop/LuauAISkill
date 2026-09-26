@echo off
setlocal
cd /d "%~dp0"
python -c "import sys; assert sys.version_info >= (3,10), 'Python 3.10+ is required'"
if errorlevel 1 goto fail
python tools\publish_github.py
if errorlevel 1 goto fail
echo Publication verified. See the branch and commit printed above.
pause
exit /b 0
:fail
echo Publication was not confirmed. Read the message above. No force push was used.
pause
exit /b 1
