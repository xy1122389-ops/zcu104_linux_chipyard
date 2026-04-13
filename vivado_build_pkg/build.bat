@echo off
REM ============================================================
REM ZCU104 Bitstream Build (UART1 + SLIP networking)
REM Run this from the vivado_build_pkg directory.
REM Vivado must be in PATH (run settings64.bat first if needed).
REM ============================================================
echo.
echo ========================================
echo  ZCU104 Bitstream Build - UART1 + SLIP
echo  FPGA: xczu7ev-ffvc1156-2-e
echo  Estimated time: 1.5 - 3 hours
echo ========================================
echo.

where vivado >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: vivado not found in PATH.
    echo Please run: "C:\Xilinx\Vivado\2023.2\settings64.bat" first
    echo  or add Vivado to PATH manually.
    pause
    exit /b 1
)

echo Starting Vivado synthesis...
vivado -nojournal -mode batch -source build_bitstream.tcl 2>&1 | tee build.log

if exist obj\ZCU104FPGATestHarness.bit (
    echo.
    echo ========================================
    echo  SUCCESS! Bitstream generated:
    echo  obj\ZCU104FPGATestHarness.bit
    echo ========================================
    echo.
    echo Copy this file back to the Linux server.
) else (
    echo.
    echo ========================================
    echo  FAILED! Check build.log for errors.
    echo ========================================
)
pause
