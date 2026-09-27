# Stainless - an experimental general-purpose language.
# Copyright (C) 2026 Brandon Scott
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

<#
.SYNOPSIS
    Counts the retains and releases the compiler emits, and the ones a
    program makes when it runs.

.DESCRIPTION
    Static: the calls to sl_retain and sl_release in the IR of the standard
    library (everything hello.sl pulls in), of the end-to-end cases (their
    own functions only, so the library is not counted once per case), of the
    IDE and of one Forms sample.

    Dynamic: what the runtime counted under --leak-check, for tools/arcbench.sl,
    the samples, the IDE's --selftest and a Forms sample's --selftest, and the
    wall time of the benchmark and of the IDE's --selftest built without the
    tracker. The end-to-end suite prints its own total under --leak-check.

.PARAMETER Runs
    How many times each timed program is run; the fastest is reported.
#>
[CmdletBinding()]
param(
    [int]$Runs = 5
)

$ErrorActionPreference = "Continue"
$repository = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $repository "src\Stainless.Cli\bin\Debug\net10.0\stainless.exe"
$work = Join-Path ([System.IO.Path]::GetTempPath()) "stainless-arccount"

if (-not (Test-Path $compiler)) {
    Write-Error "the compiler is not built: $compiler"
    exit 1
}

New-Item -ItemType Directory -Force -Path $work | Out-Null

$forms = @(
    (Join-Path $repository "samples\forms\common.sl"),
    (Join-Path $repository "forms\src"),
    (Join-Path $repository "bindings\win32")
)

# Retains and releases in an IR file, optionally only in functions whose
# symbol does not name the standard library.
function Measure-Ir([string]$path, [bool]$ownOnly) {
    $retains = 0
    $releases = 0
    $counting = -not $ownOnly

    foreach ($line in [System.IO.File]::ReadLines($path)) {
        if ($line.StartsWith("define ")) {
            $counting = -not $ownOnly -or -not $line.Contains("Standard")
            continue
        }
        if (-not $counting) { continue }
        if ($line.Contains("call void @sl_retain(")) { $retains++ }
        elseif ($line.Contains("call void @sl_release(")) { $releases++ }
    }

    return [pscustomobject]@{ Retains = $retains; Releases = $releases }
}

function Write-Ir([string[]]$arguments, [string]$out) {
    $all = @("emit-ir") + $arguments
    Start-Process -FilePath $compiler -ArgumentList $all -NoNewWindow -Wait `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err" | Out-Null
    return (Test-Path $out) -and (Get-Item $out).Length -gt 0
}

function Show([string]$name, $counts) {
    Write-Host ("  {0,-28} retains={1,-9} releases={2}" -f $name, $counts.Retains, $counts.Releases)
}

Write-Host "static: calls in the IR" -ForegroundColor Cyan

$ir = Join-Path $work "stdlib.ll"
if (Write-Ir @((Join-Path $repository "samples\hello.sl")) $ir) {
    Show "stdlib (hello.sl)" (Measure-Ir $ir $false)
}

$corpus = [pscustomobject]@{ Retains = 0; Releases = 0 }
$cases = 0
foreach ($case in Get-ChildItem (Join-Path $repository "tests\cases") -Directory) {
    if (-not (Test-Path (Join-Path $case.FullName "expected.txt"))) { continue }
    if (Test-Path (Join-Path $case.FullName "target.txt")) { continue }
    if (Test-Path (Join-Path $case.FullName "sources.txt")) { continue }
    if (Test-Path (Join-Path $case.FullName "library")) { continue }

    $arguments = @(Get-ChildItem $case.FullName -Filter *.sl -File -Recurse | ForEach-Object { $_.FullName })
    if ($arguments.Count -eq 0) { continue }

    $defines = Join-Path $case.FullName "defines.txt"
    if (Test-Path $defines) {
        foreach ($define in Get-Content $defines) {
            if ($define.Trim()) { $arguments += @("-D", $define.Trim()) }
        }
    }

    $ir = Join-Path $work "case.ll"
    Remove-Item $ir -ErrorAction SilentlyContinue
    if (-not (Write-Ir $arguments $ir)) { continue }

    $counts = Measure-Ir $ir $true
    $corpus.Retains += $counts.Retains
    $corpus.Releases += $counts.Releases
    $cases++
}
Show "cases ($cases, own code)" $corpus

$ir = Join-Path $work "ide.ll"
if (Write-Ir @("-p", (Join-Path $repository "ide")) $ir) { Show "ide" (Measure-Ir $ir $false) }

$ir = Join-Path $work "forms.ll"
if (Write-Ir $forms $ir) { Show "forms (common.sl)" (Measure-Ir $ir $false) }

Write-Host ""
Write-Host "dynamic: calls the runtime counted" -ForegroundColor Cyan

# Builds with the tracker, runs, and reads the counts off its report.
function Measure-Run([string]$name, [string[]]$sources, [string[]]$arguments) {
    $exe = Join-Path $work (($name -replace '[\\/ ()]', '-') + ".exe")
    Remove-Item $exe -ErrorAction SilentlyContinue

    $build = @("build") + $sources + @("--leak-check", "-o", $exe)
    Start-Process -FilePath $compiler -ArgumentList $build -NoNewWindow -Wait `
        -RedirectStandardOutput "$exe.build" -RedirectStandardError "$exe.build.err" | Out-Null
    if (-not (Test-Path $exe)) {
        Write-Host ("  {0,-28} did not build" -f $name) -ForegroundColor DarkYellow
        return
    }

    $log = "$exe.log"
    $process = if ($arguments.Count -gt 0) {
        Start-Process -FilePath $exe -ArgumentList $arguments -NoNewWindow -PassThru `
            -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    } else {
        Start-Process -FilePath $exe -NoNewWindow -PassThru `
            -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    }
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        Write-Host ("  {0,-28} did not finish" -f $name) -ForegroundColor DarkYellow
        return
    }

    $report = Get-Content "$log.err" | Where-Object { $_ -match '^stainless-leak:' } | Select-Object -First 1
    if (-not $report) {
        Write-Host ("  {0,-28} no report" -f $name) -ForegroundColor DarkYellow
        return
    }

    Show $name ([pscustomobject]@{
        Retains = [long]([regex]::Match($report, 'retains=(\d+)').Groups[1].Value)
        Releases = [long]([regex]::Match($report, 'releases=(\d+)').Groups[1].Value)
    })
}

$bench = Join-Path $PSScriptRoot "arcbench.sl"
Measure-Run "arcbench" @($bench) @()

foreach ($sample in Get-ChildItem (Join-Path $repository "samples") -Filter *.sl -File) {
    Measure-Run "samples/$($sample.BaseName)" @($sample.FullName) @()
}

Measure-Run "ide --selftest" @("-p", (Join-Path $repository "ide")) @("--selftest")
Measure-Run "forms common --selftest" $forms @("--selftest")

Write-Host ""
Write-Host "time: fastest of $Runs, built without the tracker" -ForegroundColor Cyan

function Measure-Time([string]$name, [string[]]$sources, [string[]]$arguments) {
    $exe = Join-Path $work (($name -replace '[\\/ ()-]', '_') + "-timed.exe")
    Remove-Item $exe -ErrorAction SilentlyContinue

    $build = @("build") + $sources + @("-o", $exe)
    Start-Process -FilePath $compiler -ArgumentList $build -NoNewWindow -Wait `
        -RedirectStandardOutput "$exe.build" -RedirectStandardError "$exe.build.err" | Out-Null
    if (-not (Test-Path $exe)) {
        Write-Host ("  {0,-28} did not build" -f $name) -ForegroundColor DarkYellow
        return
    }

    $best = [double]::MaxValue
    for ($i = 0; $i -lt $Runs; $i++) {
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        if ($arguments.Count -gt 0) {
            Start-Process -FilePath $exe -ArgumentList $arguments -NoNewWindow -Wait `
                -RedirectStandardOutput "$exe.log" -RedirectStandardError "$exe.log.err" | Out-Null
        } else {
            Start-Process -FilePath $exe -NoNewWindow -Wait `
                -RedirectStandardOutput "$exe.log" -RedirectStandardError "$exe.log.err" | Out-Null
        }
        $clock.Stop()
        $best = [Math]::Min($best, $clock.Elapsed.TotalMilliseconds)
    }

    Write-Host ("  {0,-28} {1:N0} ms" -f $name, $best)
}

Measure-Time "arcbench" @($bench) @()
Measure-Time "ide --selftest" @("-p", (Join-Path $repository "ide")) @("--selftest")
