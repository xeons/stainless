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
    Publishes the compiler as one self-contained file, smoke-tests it, and
    packages it as a release archive.

.DESCRIPTION
    The binary is single-file, ReadyToRun and self-contained, so the archive
    needs no .NET install. It is not compressed inside: that would halve the
    file and add a tenth of a second to every run, and the archive is
    compressed anyway.

    It is run before it is packaged: --version, then samples/hello.sl built and
    run with nothing but the published file. A binary for another machine is
    packaged untested, with a warning.

    The archive holds the binary, the licences, README.md, INSTALL.txt, and the
    tracked files of docs/, samples/, bindings/ and forms/, under one directory
    named stainless-<version>-<rid>. It is written to artifacts/.

    tools/publish.sh is the same on Linux. docs/releasing.md is the whole
    process.

.PARAMETER Runtime
    The .NET runtime identifier to publish for. Defaults to this machine's.

.PARAMETER NoArchive
    Publish and smoke-test, but do not package.
#>
[CmdletBinding()]
param(
    [string]$Runtime = "",
    [switch]$NoArchive
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot

$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
$native = "win-$architecture"
if (-not $Runtime) { $Runtime = $native }

if (-not $Runtime.StartsWith("win-")) {
    throw "this publishes for Windows; tools/publish.sh is the one for Linux"
}

$artifacts = Join-Path $repository "artifacts"
$publish = Join-Path $artifacts "$Runtime\publish"
$compiler = Join-Path $publish "stainless.exe"

$versionProject = Join-Path $PSScriptRoot "Version.proj"
$version = (& dotnet msbuild $versionProject -nologo -t:ComputeStainlessVersion -getProperty:StainlessVersion).Trim()
$informational = (& dotnet msbuild $versionProject -nologo -t:ComputeStainlessVersion -getProperty:StainlessInformationalVersion).Trim()
if ($LASTEXITCODE -ne 0 -or -not $version) { throw "tools/Version.proj did not say what version this is" }

if (Test-Path $publish) { Remove-Item $publish -Recurse -Force }

Write-Host "publishing $informational for $Runtime" -ForegroundColor Cyan
& dotnet publish (Join-Path $repository "src\Stainless.Cli\Stainless.Cli.csproj") `
    -c Release -r $Runtime --self-contained `
    -p:PublishSingleFile=true -p:PublishReadyToRun=true `
    -o $publish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

# ---- smoke test

if ($Runtime -ne $native) {
    Write-Warning "$Runtime is not this machine, so the binary is packaged untested"
}
else {
    $said = (& $compiler --version) -join ""
    if ($LASTEXITCODE -ne 0 -or $said -ne "stainless $informational") {
        throw "the published compiler answered --version with '$said', not 'stainless $informational'"
    }

    # A clean directory, so ./obj and the runtime objects are built from what
    # is embedded in the binary and nothing left over.
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "stainless-publish-$PID"
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Push-Location $work
    try {
        $hello = Join-Path $work "hello.exe"
        & $compiler build (Join-Path $repository "samples\hello.sl") -o $hello
        if ($LASTEXITCODE -ne 0) { throw "the published compiler could not build samples/hello.sl" }

        $said = (& $hello) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $said -ne "Hello from Stainless.") {
            throw "samples/hello.sl built with the published compiler said '$said'"
        }
    }
    finally {
        Pop-Location
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "  --version and samples/hello.sl both answered" -ForegroundColor Cyan
}

if ($NoArchive) { exit 0 }

# ---- package

$name = "stainless-$version-$Runtime"
$stage = Join-Path $artifacts "$Runtime\$name"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Copy-Item $compiler $stage
Copy-Item (Join-Path $PSScriptRoot "release-install.txt") (Join-Path $stage "INSTALL.txt")

$tracked = & git -C $repository ls-files -- README.md LICENSE LICENSE.RUNTIME docs samples bindings forms
if ($LASTEXITCODE -ne 0) { throw "packaging reads the file list from git, and this is not a checkout" }

foreach ($file in $tracked) {
    $target = Join-Path $stage $file
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item (Join-Path $repository $file) $target
}

$archive = Join-Path $artifacts "$name.zip"
if (Test-Path $archive) { Remove-Item $archive -Force }

# Entry by entry, because Compress-Archive and ZipFile.CreateFromDirectory both
# write backslashes into entry names under Windows PowerShell, and an archive
# like that unpacks elsewhere as flat files with backslashes in their names.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($archive, "Create")
try {
    $root = Split-Path -Parent $stage
    foreach ($file in Get-ChildItem $stage -Recurse -File) {
        $entry = $file.FullName.Substring($root.Length + 1).Replace("\", "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entry, "Optimal") | Out-Null
    }
}
finally {
    $zip.Dispose()
}

$size = (Get-Item $compiler).Length / 1MB
$packed = (Get-Item $archive).Length / 1MB
Write-Host ("  {0}: {1:N1} MB, binary {2:N1} MB" -f (Split-Path -Leaf $archive), $packed, $size) -ForegroundColor Green
