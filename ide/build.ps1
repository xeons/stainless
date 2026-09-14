# Builds the IDE into ide/build, which .gitignore covers.
#
#   .\ide\build.ps1              build it
#   .\ide\build.ps1 -Test        build, then run the scanner tests and --selftest
#   .\ide\build.ps1 -Run         build, then open the window
#   .\ide\build.ps1 -Run -Open path\to\file.sl
#
# Forms is compiled in rather than linked, so the command names the library's
# sources along with the IDE's own -- see forms/README.md for why.

param(
    [switch] $Test,
    [switch] $Run,
    [string] $Open = ""
)

$ErrorActionPreference = "Stop"

$repository = Resolve-Path (Join-Path $PSScriptRoot "..")
$compiler   = Join-Path $repository "src\Stainless.Cli\bin\Debug\net10.0\stainless.exe"
$output     = Join-Path $PSScriptRoot "build"
$exe        = Join-Path $output "stainless-ide.exe"

if (-not (Test-Path $compiler)) {
    Write-Error "no compiler at $compiler -- run 'dotnet build Stainless.slnx' first"
}

if (-not (Test-Path $output)) { New-Item -ItemType Directory $output | Out-Null }

# The IDE's own source, the Forms library, and the Windows bindings Forms
# reaches -- the whole binding directory rather than only `api`, because the
# backend uses `Win32.Dialogs` for the file choosers and `Win32.Com` under it.
$sources = @(
    (Join-Path $PSScriptRoot "src"),
    (Join-Path $repository "forms\src"),
    (Join-Path $repository "bindings\win32")
)

# The comctl32 v6 manifest, so the common controls are the themed ones. Shared
# with the Forms samples rather than copied.
$resources = Join-Path $repository "samples\forms\forms.rc"

$libraries = @("-l", "user32", "-l", "gdi32", "-l", "comctl32",
               "-l", "comdlg32", "-l", "ole32", "-l", "shell32",
               "-l", "advapi32")

Write-Host "building the IDE" -ForegroundColor Cyan
& $compiler build $sources[0] $resources $sources[1] $sources[2] -o $exe @libraries
if ($LASTEXITCODE -ne 0) { Write-Error "the IDE failed to build" }

Write-Host "built $exe" -ForegroundColor Green

if ($Test) {
    Write-Host ""
    Write-Host "the scanner" -ForegroundColor Cyan
    & $compiler run (Join-Path $PSScriptRoot "tests\lextest.sl") (Join-Path $PSScriptRoot "src\Lang")
    if ($LASTEXITCODE -ne 0) { Write-Error "the scanner tests failed" }

    Write-Host ""
    Write-Host "the window" -ForegroundColor Cyan
    & $exe --selftest
    if ($LASTEXITCODE -ne 0) { Write-Error "the IDE self test failed" }
}

if ($Run) {
    if ($Open -ne "") { & $exe $Open } else { & $exe }
}
