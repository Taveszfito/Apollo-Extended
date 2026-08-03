@echo off
setlocal enabledelayedexpansion

echo ========================================
echo Virtual Audio Driver Build Script
echo ========================================
echo.

:: Check if MSBuild is available in PATH first
where msbuild >nul 2>&1
if %errorlevel% equ 0 (
    echo Found MSBuild in PATH
    goto msbuild_found
)

:: MSBuild not in PATH, search common locations
echo MSBuild not found in PATH, searching common locations...

set MSBUILD_PATHS[0]=C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe
set MSBUILD_PATHS[1]=C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe
set MSBUILD_PATHS[2]=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe
set MSBUILD_PATHS[3]=C:\Program Files\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe
set MSBUILD_PATHS[4]=C:\Program Files\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\MSBuild.exe
set MSBUILD_PATHS[5]=C:\Program Files\Microsoft Visual Studio\2019\Enterprise\MSBuild\Current\Bin\MSBuild.exe
set MSBUILD_PATHS[6]=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe
set MSBUILD_PATHS[7]=C:\Program Files (x86)\MSBuild\14.0\Bin\MSBuild.exe

set MSBUILD_EXE=
for /L %%i in (0,1,7) do (
    call set CURRENT_PATH=%%MSBUILD_PATHS[%%i]%%
    if exist "!CURRENT_PATH!" (
        set MSBUILD_EXE=!CURRENT_PATH!
        echo Found MSBuild at: !CURRENT_PATH!
        goto msbuild_found
    )
)

:: If we get here, MSBuild wasn't found
echo ERROR: MSBuild not found in PATH or common installation locations
echo.
echo Searched locations:
echo   - System PATH
echo   - Visual Studio 2022 Community/Professional/Enterprise
echo   - Visual Studio 2019 Community/Professional/Enterprise/BuildTools
echo   - Legacy MSBuild locations
echo.
echo Please ensure Visual Studio or Build Tools are installed
echo or add MSBuild to your PATH manually
echo.
echo Press any key to close...
pause >nul
exit /b 1

:msbuild_found
:: If MSBuild was found in a specific location, use that path for all builds
if defined MSBUILD_EXE (
    echo Using MSBuild from: %MSBUILD_EXE%
    set MSBUILD_CMD=%MSBUILD_EXE%
) else (
    echo Using MSBuild from PATH
    set MSBUILD_CMD=msbuild
)

:: Default values
set CONFIG=Release
set PLATFORM=x64
set BUILD_ALL=0

:: Parse command line arguments
:parse_args
if "%1"=="" goto build_start
if /i "%1"=="debug" set CONFIG=Debug
if /i "%1"=="release" set CONFIG=Release
if /i "%1"=="x64" set PLATFORM=x64
if /i "%1"=="arm64" set PLATFORM=ARM64
if /i "%1"=="all" set BUILD_ALL=1
if /i "%1"=="help" goto show_help
if /i "%1"=="-h" goto show_help
if /i "%1"=="--help" goto show_help
shift
goto parse_args

:show_help
echo Usage: build.bat [options]
echo.
echo Options:
echo   debug       Build Debug configuration (default: Release)
echo   release     Build Release configuration
echo   x64         Build for x64 platform (default)
echo   arm64       Build for ARM64 platform
echo   all         Build all configurations and platforms
echo   help        Show this help message
echo.
echo Examples:
echo   build.bat                    # Build Release x64
echo   build.bat debug x64          # Build Debug x64
echo   build.bat release arm64      # Build Release ARM64
echo   build.bat all                # Build all configurations
echo.
echo Press any key to close...
pause >nul
exit /b 0

:build_start
if %BUILD_ALL%==1 goto build_all

echo Building Virtual Audio Driver...
echo Configuration: %CONFIG%
echo Platform: %PLATFORM%
echo.

if /i "%PLATFORM%"=="ARM64" (
    echo Building ARM64 with validation disabled...
    call "%MSBUILD_CMD%" "VirtualAudioDriver.sln" ^
        /p:Configuration=%CONFIG% ^
        /p:Platform=ARM64 ^
        /p:RunCodeAnalysis=false ^
        /p:DriverTargetPlatform=Universal ^
        /p:UseInfVerifierEx=false ^
        /p:ValidateDrivers=false ^
        /p:StampInf=false ^
        /p:ApiValidator_Enable=false ^
        /p:InfVerif_Enable=false ^
        /p:DisableVerification=true ^
        /p:SignMode=Off ^
        /p:ApiValidator_ExcludedTargets=ARM64 ^
        /p:EnableInf2cat=false
) else (
    echo Building x64 with full validation...
    call "%MSBUILD_CMD%" "VirtualAudioDriver.sln" /p:Configuration=%CONFIG% /p:Platform=%PLATFORM%
)

if %errorlevel% neq 0 (
    echo.
    echo ERROR: Build failed with exit code %errorlevel%
    echo.
    echo Press any key to close...
    pause >nul
    exit /b %errorlevel%
)

echo.
echo Build completed successfully!
echo Output directory: %PLATFORM%\%CONFIG%\package
goto show_output

:build_all
echo Building all configurations...
echo.

set CONFIGS=Debug Release
set PLATFORMS=x64 ARM64

for %%c in (%CONFIGS%) do (
    for %%p in (%PLATFORMS%) do (
        echo.
        echo ========================================
        echo Building %%c %%p
        echo ========================================
        
        if /i "%%p"=="ARM64" (
            echo Building ARM64 with validation disabled...
            call "%MSBUILD_CMD%" "VirtualAudioDriver.sln" ^
                /p:Configuration=%%c ^
                /p:Platform=ARM64 ^
                /p:RunCodeAnalysis=false ^
                /p:DriverTargetPlatform=Universal ^
                /p:UseInfVerifierEx=false ^
                /p:ValidateDrivers=false ^
                /p:StampInf=false ^
                /p:ApiValidator_Enable=false ^
                /p:InfVerif_Enable=false ^
                /p:DisableVerification=true ^
                /p:SignMode=Off ^
                /p:ApiValidator_ExcludedTargets=ARM64 ^
                /p:EnableInf2cat=false
        ) else (
            echo Building x64 with full validation...
            call "%MSBUILD_CMD%" "VirtualAudioDriver.sln" /p:Configuration=%%c /p:Platform=%%p
        )
        
        if !errorlevel! neq 0 (
            echo.
            echo ERROR: Build failed for %%c %%p with exit code !errorlevel!
            echo.
            echo Press any key to close...
            pause >nul
            exit /b !errorlevel!
        )
        
        echo Build %%c %%p completed successfully!
    )
)

echo.
echo ========================================
echo All builds completed successfully!
echo ========================================

:show_output
echo.
echo Built files can be found in:
if %BUILD_ALL%==1 (
    echo   x64\Debug\package\
    echo   x64\Release\package\
    echo   ARM64\Debug\package\
    echo   ARM64\Release\package\
) else (
    echo   %PLATFORM%\%CONFIG%\package\
)
echo.
echo Key files:
echo   - VirtualAudioDriver.sys  (driver binary)
echo   - VirtualAudioDriver.inf  (installation file)
echo   - virtualaudiodriver.cat  (catalog file)

echo.
echo Press any key to close...
pause >nul
exit /b 0