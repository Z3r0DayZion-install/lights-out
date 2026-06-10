@echo off
cd /d "%~dp0"
set SLEEPTIMER_DRY_RUN=
set SLEEPTIMER_CI=
start "" "%~dp0SleepTimer.exe" -ClassicUi -ForceShutdown -Action Shutdown -Minutes 58 -Start
