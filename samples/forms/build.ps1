# Builds the Forms samples into samples/forms/build, which .gitignore already
# covers ("samples/**/build/"), so the binaries never reach a commit.
#
#   .\samples\forms\build.ps1            build them
#   .\samples\forms\build.ps1 -Test      build, then run each --selftest
#   .\samples\forms\build.ps1 -Run demo  build, then open that one's window
#
# Forms is compiled into each program rather than linked, so every sample names
# the library's sources along with its own -- see forms/README.md for why.

param(
    [switch] $Test,
    [string] $Run = ""
)

$ErrorActionPreference = "Stop"

$repository = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$compiler   = Join-Path $repository "src\Stainless.Cli\bin\Debug\net10.0\stainless.exe"
$output     = Join-Path $PSScriptRoot "build"

if (-not (Test-Path $compiler)) {
    Write-Error "no compiler at $compiler -- run 'dotnet build Stainless.slnx' first"
}

if (-not (Test-Path $output)) { New-Item -ItemType Directory $output | Out-Null }

# What every Forms program is built from: its own source and the library.
#
# The whole binding directory, not only the declarations under `api`: the
# backend reaches `Win32.Dialogs` for the file choosers and `Win32.Com`
# underneath it. Compiling a wrapper is what makes its library necessary, which
# is why the list below is longer than user32 and gdi32.
$library = @(
    (Join-Path $repository "forms\src"),
    (Join-Path $repository "bindings\win32")
)

$libraries = @("-l", "user32", "-l", "gdi32", "-l", "comctl32",
               "-l", "comdlg32", "-l", "ole32", "-l", "shell32",
               "-l", "advapi32")

# What every sample carries inside its .exe: the comctl32 v6 manifest that
# selects the themed common controls, and a string table. The build compiles
# this to a .res and the linker folds it in, so there is nothing to copy beside
# the binary and nothing to lose when one is moved.
$resources = Join-Path $PSScriptRoot "forms.rc"

$samples = Get-ChildItem $PSScriptRoot -Filter *.sl | Sort-Object Name

foreach ($sample in $samples) {
    $name = [IO.Path]::GetFileNameWithoutExtension($sample.Name)
    $exe  = Join-Path $output "$name.exe"

    Write-Host "building $name" -ForegroundColor Cyan
    & $compiler build $sample.FullName $resources @library -o $exe @libraries
    if ($LASTEXITCODE -ne 0) { Write-Error "$name failed to build" }
}

Write-Host ""
Write-Host "built into $output" -ForegroundColor Green
Get-ChildItem $output -Filter *.exe | ForEach-Object { Write-Host "  $($_.Name)" }

if ($Test) {
    Write-Host ""
    foreach ($sample in $samples) {
        $name = [IO.Path]::GetFileNameWithoutExtension($sample.Name)
        $exe  = Join-Path $output "$name.exe"
        Write-Host "--selftest $name" -ForegroundColor Cyan
        & $exe --selftest
        if ($LASTEXITCODE -ne 0) { Write-Error "$name self test failed" }
    }
}

if ($Run -ne "") {
    $exe = Join-Path $output "$Run.exe"
    if (-not (Test-Path $exe)) { Write-Error "no sample called '$Run' in $output" }
    & $exe
}
