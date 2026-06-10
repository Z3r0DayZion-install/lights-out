@echo off
cd /d "%~dp0"
set SLEEPTIMER_DRY_RUN=1
set SLEEPTIMER_CI=
start "" "%~dp0SleepTimer.exe" -SteamUi -DryRun -NoAutoStart
