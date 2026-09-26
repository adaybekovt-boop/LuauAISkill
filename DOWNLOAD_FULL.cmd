@echo off
setlocal
cd /d "%~dp0"
python -c "import sys; assert sys.version_info >= (3,10), 'Python 3.10+ is required'"
if errorlevel 1 goto fail
python tools\fetch_corpus.py
if errorlevel 1 goto fail
python tools\release_pack.py --require-corpus --out ..\LuauAISkill-Full.zip
if errorlevel 1 goto fail
echo Full source download and ZIP checks completed. Read upstream\DOWNLOAD-REPORT.json and qa\BUILD-REPORT.json.
pause
exit /b 0
:fail
echo INCOMPLETE. Read the error above. No complete official mirror is claimed.
pause
exit /b 1
