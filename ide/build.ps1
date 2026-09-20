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

# `Stop` applies to cmdlets, and native commands are handled by checking
# `$LASTEXITCODE` after each one -- which every call below does.
#
# **Not `Stop` for the compiler.** Windows PowerShell 5.1 wraps each line a
# native program writes to stderr in an ErrorRecord, and under `Stop` that makes
# the first *warning* a terminating error: `stainless` prints one SL0377 today,
# so `-Test` died before running a single test and reported it as
# NativeCommandError. An exit code is what says whether a build failed; a line
# on stderr is not.
$ErrorActionPreference = "Continue"

# Says what went wrong and stops, which `Write-Error` no longer does now that
# the preference above is `Continue`. A failing build has to end in a non-zero
# exit code, or a caller -- CI, or another script -- reads a red page as a pass.
function Fail([string] $why)
{
    Write-Host $why -ForegroundColor Red
    exit 1
}

$repository = Resolve-Path (Join-Path $PSScriptRoot "..")
$compiler   = Join-Path $repository "src\Stainless.Cli\bin\Debug\net10.0\stainless.exe"
$output     = Join-Path $PSScriptRoot "build"
$exe        = Join-Path $output "stainless-ide.exe"

if (-not (Test-Path $compiler)) {
    Fail "no compiler at $compiler -- run 'dotnet build Stainless.slnx' first"
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
if ($LASTEXITCODE -ne 0) { Fail "the IDE failed to build" }

Write-Host "built $exe" -ForegroundColor Green

if ($Test) {
    Write-Host ""
    Write-Host "the scanner" -ForegroundColor Cyan
    & $compiler run (Join-Path $PSScriptRoot "tests\lextest.sl") (Join-Path $PSScriptRoot "src\Lang")
    if ($LASTEXITCODE -ne 0) { Fail "the scanner tests failed" }

    Write-Host ""
    Write-Host "reading what the compiler said" -ForegroundColor Cyan
    & $compiler run (Join-Path $PSScriptRoot "tests\buildtest.sl") (Join-Path $PSScriptRoot "src\Build")
    if ($LASTEXITCODE -ne 0) { Fail "the diagnostic tests failed" }

    Write-Host ""
    Write-Host "the project reader" -ForegroundColor Cyan
    & $compiler run (Join-Path $PSScriptRoot "tests\projecttest.sl") (Join-Path $PSScriptRoot "src\Project")
    if ($LASTEXITCODE -ne 0) { Fail "the project tests failed" }

    Write-Host ""
    Write-Host "the docking layout" -ForegroundColor Cyan
    # One file rather than the directory: `Ide.Shell` is two files, and the
    # other one is the controls -- which would drag in a widget set and a
    # display for a test that needs neither.
    & $compiler run (Join-Path $PSScriptRoot "tests\docktest.sl") (Join-Path $PSScriptRoot "src\Shell\Layout.sl")
    if ($LASTEXITCODE -ne 0) { Fail "the docking tests failed" }

    Write-Host ""
    Write-Host "breakpoints" -ForegroundColor Cyan
    # Two files rather than either directory. `Ide.Debugging` is two files and
    # the other one launches a process; `debug/src` is sixteen and most of them
    # need a platform binding.
    & $compiler run (Join-Path $PSScriptRoot "tests\debugtest.sl") `
        (Join-Path $PSScriptRoot "src\Debug\Breakpoints.sl") `
        (Join-Path $repository "debug\src\Paths.sl")
    if ($LASTEXITCODE -ne 0) { Fail "the breakpoint tests failed" }

    Write-Host ""
    Write-Host "the window" -ForegroundColor Cyan
    & $exe --selftest
    if ($LASTEXITCODE -ne 0) { Fail "the IDE self test failed" }
}

if ($Run) {
    if ($Open -ne "") { & $exe $Open } else { & $exe }
}
