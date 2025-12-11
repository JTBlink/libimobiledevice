@echo off
chcp 65001 >nul 2>&1
REM libimobiledevice Windows Build Script Launcher
REM For MSYS2/MinGW environment

setlocal EnableDelayedExpansion

echo ========================================
echo libimobiledevice Windows Build Tool
echo ========================================
echo.

REM Detect MSYS2 installation path
set "MSYS2_PATH="

REM Common MSYS2 installation locations
set "PATHS[0]=C:\msys64"
set "PATHS[1]=C:\msys2"
set "PATHS[2]=D:\msys64"
set "PATHS[3]=D:\msys2"
set "PATHS[4]=%USERPROFILE%\msys64"
set "PATHS[5]=%USERPROFILE%\msys2"

echo [INFO] Detecting MSYS2 installation...

for /L %%i in (0,1,5) do (
    if exist "!PATHS[%%i]!\msys2_shell.cmd" (
        set "MSYS2_PATH=!PATHS[%%i]!"
        echo [SUCCESS] Found MSYS2: !MSYS2_PATH!
        goto :found_msys2
    )
)

REM MSYS2 not found
echo [ERROR] MSYS2 installation not found
echo.
echo Please install MSYS2 first:
echo 1. Visit https://www.msys2.org/
echo 2. Download and install MSYS2
echo 3. Run this script again
echo.
pause
exit /b 1

:found_msys2
echo.

REM Get script directory (windows-build folder)
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Get project root directory (parent of windows-build)
for %%I in ("%SCRIPT_DIR%") do set "PROJECT_DIR=%%~dpI"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

REM Convert Windows path to MSYS2 path
set "MSYS2_PROJECT_DIR=%PROJECT_DIR:\=/%"
set "MSYS2_PROJECT_DIR=%MSYS2_PROJECT_DIR::=%"
set "MSYS2_PROJECT_DIR=/%MSYS2_PROJECT_DIR%"

echo [INFO] Project directory: %PROJECT_DIR%
echo [INFO] MSYS2 path: %MSYS2_PROJECT_DIR%
echo.

REM Show menu
echo Select operation:
echo 1. Full build (Install dependencies + Build + Install)
echo 2. Build only (Skip dependency installation)
echo 3. Clean build files
echo 4. Open MSYS2 terminal (Manual operation)
echo 5. Exit
echo.

set /p choice="Enter option (1-5): "

if "%choice%"=="1" goto :full_build
if "%choice%"=="2" goto :build_only
if "%choice%"=="3" goto :clean
if "%choice%"=="4" goto :open_shell
if "%choice%"=="5" goto :exit

echo [ERROR] Invalid option
pause
exit /b 1

:full_build
echo.
echo [INFO] Starting full build...
"%MSYS2_PATH%\msys2_shell.cmd" -mingw64 -defterm -no-start -here -c "cd '%MSYS2_PROJECT_DIR%' && chmod +x windows-build/build-windows.sh && ./windows-build/build-windows.sh"
goto :end

:build_only
echo.
echo [INFO] Build only (skip dependencies)...
"%MSYS2_PATH%\msys2_shell.cmd" -mingw64 -defterm -no-start -here -c "cd '%MSYS2_PROJECT_DIR%' && ./autogen.sh --prefix=/mingw64 --without-cython && make -j$(nproc) && echo 'Build complete! Install now?' && read -p 'y/n: ' answer && if [ \"\$answer\" = 'y' ]; then make install; fi"
goto :end

:clean
echo.
echo [INFO] Cleaning build files...
"%MSYS2_PATH%\msys2_shell.cmd" -mingw64 -defterm -no-start -here -c "cd '%MSYS2_PROJECT_DIR%' && make distclean 2>/dev/null || make clean 2>/dev/null || true && rm -rf deps-build && echo 'Clean complete!'"
goto :end

:open_shell
echo.
echo [INFO] Opening MSYS2 MinGW64 terminal...
echo [TIP] In terminal run: cd windows-build && ./build-windows.sh
"%MSYS2_PATH%\msys2_shell.cmd" -mingw64 -here -c "cd '%MSYS2_PROJECT_DIR%'"
goto :end

:exit
echo.
echo Goodbye!
exit /b 0

:end
echo.
echo ========================================
echo Operation complete
echo ========================================
pause