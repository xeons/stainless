@echo off
rem SPDX-License-Identifier: 0BSD
rem
rem Builds the Stainless COM server and the C++ host, then runs the host.
rem
rem Nothing is registered and nothing needs admin rights: the host loads the
rem DLL by path and calls DllGetClassObject itself, which is what COM's own
rem activation does once the registry has told it which file to open.

setlocal
cd /d "%~dp0"

rem Prefer an installed compiler; fall back to this repository's own, so the
rem sample runs from a fresh clone with nothing on PATH.
set STAINLESS=stainless
where /q stainless || set STAINLESS=dotnet run --project ..\..\src\Stainless.Cli -c Debug --

if not exist build mkdir build

echo === building the COM server (Stainless) ===
%STAINLESS% build greeter.sl --shared -o build\greeter.dll
if errorlevel 1 exit /b 1

echo.
echo === building the host (C++) ===
rem Where the compiler itself looks for clang, for the same reason.
set CLANGXX=clang++
where /q clang++ || set CLANGXX="C:\Program Files\LLVM\bin\clang++.exe"

%CLANGXX% -std=c++17 host.cpp -o build\host.exe -lole32
if errorlevel 1 exit /b 1

echo.
echo === running ===
build\host.exe build\greeter.dll
