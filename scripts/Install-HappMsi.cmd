@echo off
setlocal
set "happ_msi=%~dp0..\installers\HappSetup.msi"
set "happ_runtime=%~dp0..\installers\Happ-VC-runtime-x64.exe"

if not exist "%happ_msi%" (
    echo Happ MSI not found: "%happ_msi%"
    exit /b 2
)
if not exist "%happ_runtime%" (
    echo Happ VC++ runtime not found: "%happ_runtime%"
    exit /b 2
)

rem The EXE installation owns the same HappService. Avoid replacing it silently.
if exist "%ProgramFiles%\FlyFrogLLC\Happ\unins000.exe" (
    echo Remove the existing Happ EXE installation before installing the MSI.
    exit /b 1638
)

start "" /wait "%happ_runtime%" /install /quiet /norestart
set "happ_runtime_result=%errorlevel%"
if not "%happ_runtime_result%"=="0" if not "%happ_runtime_result%"=="3010" if not "%happ_runtime_result%"=="1638" (
    echo VC++ runtime installation failed with exit code %happ_runtime_result%.
    exit /b %happ_runtime_result%
)

start "" /wait "%SystemRoot%\System32\msiexec.exe" /i "%happ_msi%" /qn /norestart
set "happ_msi_result=%errorlevel%"
if not "%happ_msi_result%"=="0" exit /b %happ_msi_result%
if "%happ_runtime_result%"=="3010" exit /b 3010
exit /b 0
