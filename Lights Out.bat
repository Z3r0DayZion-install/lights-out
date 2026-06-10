@echo off
cd /d "%~dp0"
set SLEEPTIMER_DRY_RUN=
set SLEEPTIMER_CI=
start "" "%~dp0SleepTimer.exe" -SteamUi -NoAutoStart
