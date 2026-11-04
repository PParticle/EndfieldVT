@echo off
setlocal
cd /d "%~dp0"
if not defined QT_DIR set QT_DIR=D:\QT\6.12.0\msvc2022_64
if not exist "%QT_DIR%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo [ERROR] Qt not found at %QT_DIR%. Set QT_DIR to the msvc2022_64 folder.
    exit /b 1
)
if /i "%VSCMD_ARG_TGT_ARCH%"=="x64" goto compiler_ready
if not exist "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" (
    echo [ERROR] Install MSVC C++ Build Tools and Windows SDK, or use an x64 Developer Command Prompt.
    exit /b 1
)
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do call "%%i\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1

:compiler_ready
rem Qt's own CMake and Ninja, ahead of any other toolchain on PATH.
set PATH=%QT_DIR%\..\..\Tools\CMake_64\bin;%QT_DIR%\..\..\Tools\Ninja;%PATH%
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="%QT_DIR%"
if errorlevel 1 exit /b 1
cmake --build build
if errorlevel 1 exit /b 1
"%QT_DIR%\bin\windeployqt.exe" --release --qmldir qml --no-translations --no-compiler-runtime --no-system-d3d-compiler --no-system-dxc-compiler --no-opengl-sw --no-ffmpeg bin\EndfieldVT.exe >nul
if errorlevel 1 exit /b 1
rem windeployqt copies every Qt Quick Controls style; the UI only uses Basic
rem (all qml files import QtQuick.Controls.Basic). Drop the others.
for %%s in (FluentWinUI3 Fusion Imagine Material Native Universal Windows) do (
    if exist "bin\qml\QtQuick\Controls\%%s" rmdir /s /q "bin\qml\QtQuick\Controls\%%s"
    if exist "bin\Qt6QuickControls2%%s.dll" del /q "bin\Qt6QuickControls2%%s.dll"
    if exist "bin\Qt6QuickControls2%%sStyleImpl.dll" del /q "bin\Qt6QuickControls2%%sStyleImpl.dll"
)
if exist "bin\qml\QtQuick\NativeStyle" rmdir /s /q "bin\qml\QtQuick\NativeStyle"
echo [OK] %CD%\bin\EndfieldVT.exe
