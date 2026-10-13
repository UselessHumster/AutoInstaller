@echo off
setlocal
pushd "%~dp0..\installers\MSOffice2019" || exit /b 1
if not exist "setup.exe" (popd & exit /b 2)
if not exist "office2019.xml" (popd & exit /b 2)
"setup.exe" /configure "office2019.xml"
set "result=%errorlevel%"
popd
exit /b %result%
