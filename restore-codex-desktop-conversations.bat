@echo off
setlocal
chcp 65001 >nul
title Restore Codex Desktop Conversations

set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%restore-codex-desktop-conversations.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo Finished with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
endlocal
