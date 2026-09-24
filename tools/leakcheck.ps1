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
    Builds every sample and application with the allocation tracker on, runs
    each, and reports what it never freed.

.DESCRIPTION
    The end-to-end suite answers this for its own cases (`--leak-check` there),
    and those are small programs written to make one point. The samples and the
    applications are the ones that hold a window open, keep a document, and
    subscribe an object to something it owns -- which is where a cycle actually
    comes from. This is how those get asked the same question.

    A program is run with --selftest where it has one, because a GUI that waits
    for a person never reaches the report. One that has no such mode and opens a
    window is listed as not runnable rather than hung on.

    The baseline file records what each program leaves behind today, the way a
    case's leaks.txt does. Without -Update a program that leaves more than its
    baseline fails the run, which is the regression this exists to catch.

.PARAMETER Update
    Rewrite the baseline from this run instead of checking against it.

.PARAMETER Filter
    Only programs whose name contains this.
#>
[CmdletBinding()]
param(
    [switch]$Update,
    [string]$Filter = ""
)

$ErrorActionPreference = "Continue"
$repository = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $repository "src\Stainless.Cli\bin\Debug\net10.0\stainless.exe"
$baselinePath = Join-Path $PSScriptRoot "leaks.baseline.txt"
$work = Join-Path ([System.IO.Path]::GetTempPath()) "stainless-leakcheck"

if (-not (Test-Path $compiler)) {
    Write-Error "the compiler is not built: $compiler"
}

New-Item -ItemType Directory -Force -Path $work | Out-Null

# What to build, and what each needs beside its own source. Forms is compiled
# into a program rather than linked, which is why the GUI ones name forms/src
# and the platform binding as sources of their own.
$forms = @("forms\src", "bindings\win32")

$programs = @()

foreach ($sample in Get-ChildItem (Join-Path $repository "samples") -Filter *.sl -File) {
    $programs += [pscustomobject]@{
        Name = "samples/$($sample.BaseName)"; Sources = @($sample.FullName); SelfTest = $false
    }
}

foreach ($sample in Get-ChildItem (Join-Path $repository "samples\forms") -Filter *.sl -File) {
    $programs += [pscustomobject]@{
        Name = "samples/forms/$($sample.BaseName)"
        Sources = @($sample.FullName) + ($forms | ForEach-Object { Join-Path $repository $_ })
        SelfTest = $true
    }
}

$programs += [pscustomobject]@{
    Name = "ide"; Sources = @(Join-Path $repository "ide"); SelfTest = $true
}
$programs += [pscustomobject]@{
    Name = "sldb"; Sources = @(Join-Path $repository "debug"); SelfTest = $false
}

$measured = [ordered]@{}
$problems = @()

foreach ($program in $programs) {
    if ($Filter -and $program.Name -notlike "*$Filter*") { continue }

    $exe = Join-Path $work ((($program.Name) -replace '[\\/]', '-') + ".exe")

    if (Test-Path $exe) { Remove-Item $exe -Force }

    $buildLog = Join-Path $work "build.log"
    $arguments = @("build") + $program.Sources + @("--leak-check", "-o", $exe)
    Start-Process -FilePath $compiler -ArgumentList $arguments -NoNewWindow -Wait `
        -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err" | Out-Null

    if (-not (Test-Path $exe)) {
        Write-Host ("  {0,-34} did not build" -f $program.Name) -ForegroundColor DarkYellow
        $problems += "$($program.Name): did not build`n" + (Get-Content "$buildLog.err" -Raw)
        continue
    }

    # Redirected to files rather than captured through the pipeline: PowerShell
    # 5.1 wraps a native command's stderr in ErrorRecords under 2>&1, and the
    # report is written to stderr.
    # Cleared first: a program that fails to start leaves the last one's log
    # behind, and every number after it is that program's.
    $runLog = Join-Path $work "run.log"
    Remove-Item $runLog, "$runLog.err" -Force -ErrorAction SilentlyContinue

    # -ArgumentList refuses an empty array, so a program with no arguments is
    # started without the parameter at all rather than with nothing in it.
    $process = if ($program.SelfTest) {
        Start-Process -FilePath $exe -ArgumentList @("--selftest") -NoNewWindow -PassThru `
            -RedirectStandardOutput $runLog -RedirectStandardError "$runLog.err"
    } else {
        Start-Process -FilePath $exe -NoNewWindow -PassThru `
            -RedirectStandardOutput $runLog -RedirectStandardError "$runLog.err"
    }

    # A program that waits for a person never reaches its report, and is listed
    # rather than waited on.
    if (-not $process.WaitForExit(30000)) {
        $process.Kill()
        Write-Host ("  {0,-34} did not finish in 30s" -f $program.Name) -ForegroundColor DarkYellow
        $problems += "$($program.Name): did not reach exit, so it never reported"
        continue
    }

    $output = (Get-Content "$runLog.err" -Raw -ErrorAction SilentlyContinue) +
              (Get-Content $runLog -Raw -ErrorAction SilentlyContinue)

    $report = ($output -split "`r?`n" | Where-Object { $_ -match '^stainless-leak:' } |
               Select-Object -First 1)

    if (-not $report) {
        Write-Host ("  {0,-34} no report (did not reach exit)" -f $program.Name) -ForegroundColor DarkYellow
        $problems += "$($program.Name): the program printed no allocation report"
        continue
    }

    $live = [int]([regex]::Match($report, 'live=(\d+)').Groups[1].Value)
    $bytes = [int]([regex]::Match($report, 'bytes=(\d+)').Groups[1].Value)
    $untracked = [int]([regex]::Match($report, 'untracked=(\d+)').Groups[1].Value)

    $measured[$program.Name] = $live

    $colour = if ($live -eq 0) { "Green" } else { "Yellow" }
    Write-Host ("  {0,-34} live={1,-6} bytes={2}" -f $program.Name, $live, $bytes) -ForegroundColor $colour

    if ($untracked -ne 0) {
        $problems += "$($program.Name): freed $untracked object(s) it never recorded, so an allocation site is missing its hook"
    }
}

if ($Update) {
    $lines = @(
        "# What each program still had allocated when it ended, as of the last",
        "# -Update. A static is alive at exit on purpose and a cycle is not, and",
        "# this file does not tell them apart -- it is here so that the number",
        "# stops moving. See runtime/leak.c.",
        ""
    )
    foreach ($entry in $measured.GetEnumerator()) {
        $lines += "{0}`t{1}" -f $entry.Key, $entry.Value
    }
    Set-Content -Path $baselinePath -Value $lines -Encoding utf8
    Write-Host "`nbaseline written to $baselinePath" -ForegroundColor Cyan
    exit 0
}

if (-not (Test-Path $baselinePath)) {
    Write-Host "`nno baseline yet; run with -Update to record one" -ForegroundColor Cyan
    exit 0
}

$baseline = @{}
foreach ($line in Get-Content $baselinePath) {
    if ($line -match '^\s*#' -or -not $line.Trim()) { continue }
    $parts = $line -split "`t"
    if ($parts.Count -ge 2) { $baseline[$parts[0]] = [int]$parts[1] }
}

foreach ($entry in $measured.GetEnumerator()) {
    if (-not $baseline.ContainsKey($entry.Key)) {
        $problems += "$($entry.Key): no baseline; run with -Update"
    }
    elseif ($entry.Value -gt $baseline[$entry.Key]) {
        $problems += "$($entry.Key): $($entry.Value) alive, and the baseline is $($baseline[$entry.Key])"
    }
}

if ($problems.Count -gt 0) {
    Write-Host ""
    foreach ($problem in $problems) { Write-Host $problem -ForegroundColor Red }
    exit 1
}

Write-Host "`nnothing leaks more than it did" -ForegroundColor Green
exit 0
