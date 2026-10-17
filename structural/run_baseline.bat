@echo off
REM ============================================================
REM  SAFRDO CPU baseline -- compile and run (5-run average)
REM  Double-click this file, or run it from a terminal in this
REM  folder. It builds cpu_baseline.c and runs it against the
REM  table_A_text.csv / table_B_text.csv in this folder.
REM ============================================================
set PATH=C:\msys64\mingw64\bin;%PATH%

echo Building cpu_baseline.exe ...
gcc -O2 -static -o cpu_baseline.exe cpu_baseline.c
if errorlevel 1 (
  echo.
  echo BUILD FAILED. Check that MSYS2 gcc exists at C:\msys64\mingw64\bin
  echo.
  pause
  exit /b 1
)

echo.
cpu_baseline.exe
echo.
pause
