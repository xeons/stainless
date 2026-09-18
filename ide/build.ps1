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

# Everything about what the IDE is made of now lives in `ide/stainless.json`:
# its own source, the Forms library, the manifest resource, and the bindings
# and libraries each platform needs. That last part is why it could not live
# there before -- one flat `sources` cannot say `bindings/win32` on one system
# and `bindings/gtk` on the other, and a platform section can.
#
# So this script is a convenience for running the tests afterwards rather than
# a second description of the program, and the Linux command in README.md is
# now the same three words as the Windows one.
Write-Host "building the IDE" -ForegroundColor Cyan
& $compiler build --project $PSScriptRoot
if ($LASTEXITCODE -ne 0) { Write-Error "the IDE failed to build" }

Write-Host "built $exe" -ForegroundColor Green

if ($Test) {
    Write-Host ""
    Write-Host "the scanner" -ForegroundColor Cyan
    & $compiler run (Join-Path $PSScriptRoot "tests\lextest.sl") (Join-Path $PSScriptRoot "src\Lang")
    if ($LASTEXITCODE -ne 0) { Write-Error "the scanner tests failed" }

    Write-Host ""
    Write-Host "the project reader" -ForegroundColor Cyan
    & $compiler run (Join-Path $PSScriptRoot "tests\projecttest.sl") (Join-Path $PSScriptRoot "src\Project")
    if ($LASTEXITCODE -ne 0) { Write-Error "the project tests failed" }

    Write-Host ""
    Write-Host "the window" -ForegroundColor Cyan
    & $exe --selftest
    if ($LASTEXITCODE -ne 0) { Write-Error "the IDE self test failed" }
}

if ($Run) {
    if ($Open -ne "") { & $exe $Open } else { & $exe }
}
