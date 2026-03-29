@echo off
setlocal

pushd "%~dp0" >nul

set "JLINK_DIR=C:\Program Files\SEGGER\JLink"
set "JLINK_GDB_SERVER=%JLINK_DIR%\JLinkGDBServerCL.exe"
set "SPEED=%~1"

if "%SPEED%"=="" set "SPEED=1000"

if not exist "%JLINK_GDB_SERVER%" (
  echo Error: JLinkGDBServerCL.exe not found at:
  echo   %JLINK_GDB_SERVER%
  echo Update JLINK_DIR in this file if SEGGER J-Link is installed elsewhere.
  popd >nul
  exit /b 1
)

echo [info] Close J-Link Commander before starting J-Link GDB Server.
echo [info] Starting J-Link GDB Server for Rocket RISC-V debug...
echo [info] Speed     : %SPEED% kHz
echo [info] Port      : 2331
echo [info] Interface : JTAG
echo [info] Accepting remote connections from WSL.
echo.

"%JLINK_GDB_SERVER%" -device RISC-V -if JTAG -speed %SPEED% -port 2331 -localhostonly 0
set "EC=%ERRORLEVEL%"

echo.
echo [info] J-Link GDB Server exited with code %EC%.
pause
popd >nul
exit /b %EC%
