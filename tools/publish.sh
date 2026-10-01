#!/usr/bin/env bash
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

# Publishes the compiler as one self-contained file, smoke-tests it, and
# packages it as artifacts/stainless-<version>-<rid>.tar.gz.
#
#   tools/publish.sh [rid] [--no-archive]
#
# The rid defaults to this machine's: linux-x64, linux-arm64, osx-arm64 or
# osx-x64. tools/publish.ps1 is the same on Windows,
# and says what the binary and the archive are; docs/releasing.md is the whole
# process.

set -euo pipefail

repository="$(cd "$(dirname "$0")/.." && pwd)"
runtime=""
archive=1

for argument in "$@"; do
    case "$argument" in
        --no-archive) archive=0 ;;
        -*) echo "error: unknown option '$argument'" >&2; exit 2 ;;
        *) runtime="$argument" ;;
    esac
done

case "$(uname -s)" in
    Darwin) system="osx" ;;
    *) system="linux" ;;
esac
case "$(uname -m)" in
    x86_64) native="$system-x64" ;;
    aarch64 | arm64) native="$system-arm64" ;;
    *) native="$system-$(uname -m)" ;;
esac
runtime="${runtime:-$native}"

case "$runtime" in
    linux-* | osx-*) ;;
    *) echo "error: this publishes for Linux and macOS; tools/publish.ps1 is the one for Windows" >&2; exit 2 ;;
esac

artifacts="$repository/artifacts"
publish="$artifacts/$runtime/publish"
compiler="$publish/stainless"

version_project="$repository/tools/Version.proj"
version="$(dotnet msbuild "$version_project" -nologo -t:ComputeStainlessVersion -getProperty:StainlessVersion | tr -d '[:space:]')"
informational="$(dotnet msbuild "$version_project" -nologo -t:ComputeStainlessVersion -getProperty:StainlessInformationalVersion | tr -d '[:space:]')"
if [ -z "$version" ]; then
    echo "error: tools/Version.proj did not say what version this is" >&2
    exit 1
fi

rm -rf "$publish"

echo "publishing $informational for $runtime"
dotnet publish "$repository/src/Stainless.Cli/Stainless.Cli.csproj" \
    -c Release -r "$runtime" --self-contained \
    -p:PublishSingleFile=true -p:PublishReadyToRun=true \
    -o "$publish"

# ---- smoke test

if [ "$runtime" != "$native" ]; then
    echo "warning: $runtime is not this machine, so the binary is packaged untested" >&2
else
    said="$("$compiler" --version)"
    if [ "$said" != "stainless $informational" ]; then
        echo "error: the published compiler answered --version with '$said', not 'stainless $informational'" >&2
        exit 1
    fi

    # A clean directory, so ./obj and the runtime objects are built from what
    # is embedded in the binary and nothing left over.
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    (cd "$work" && "$compiler" build "$repository/samples/hello.sl" -o "$work/hello")

    said="$("$work/hello")"
    if [ "$said" != "Hello from Stainless." ]; then
        echo "error: samples/hello.sl built with the published compiler said '$said'" >&2
        exit 1
    fi

    echo "  --version and samples/hello.sl both answered"
fi

# ---- the IDE

# Built by the published compiler, which is a harder test of it than hello.sl,
# and shipped beside it: the IDE looks for `stainless` next to itself first.
# Its debugger is written for Windows and Linux, so macOS ships without it.
ide="$publish/stainless-ide"
if [ "$runtime" != "$native" ]; then
    echo "warning: $runtime is not this machine, so the archive carries no IDE" >&2
elif [ "$system" = osx ]; then
    echo "warning: the IDE does not build for macOS yet, so the archive carries none" >&2
else
    echo "building the IDE with the published compiler"
    "$compiler" build --project "$repository/ide" -o "$ide"

    # The self test opens a window, so it needs a display; Xvfb stands in.
    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        "$ide" --selftest
    elif command -v xvfb-run >/dev/null; then
        xvfb-run -a "$ide" --selftest
    else
        echo "error: the IDE's self test needs a display or xvfb-run" >&2
        exit 1
    fi
    echo "  the IDE built and passed its self test"
fi

[ "$archive" = 1 ] || exit 0

# ---- package

name="stainless-$version-$runtime"
stage="$artifacts/$runtime/$name"
rm -rf "$stage"
mkdir -p "$stage"

cp "$compiler" "$stage/"
[ -f "$ide" ] && cp "$ide" "$stage/"
cp "$repository/tools/release-install.txt" "$stage/INSTALL.txt"

# A tar pipe keeps each file's directory, which BSD cp has no flag for.
(cd "$repository" && git ls-files -z -- README.md LICENSE LICENSE.RUNTIME docs samples bindings forms |
    tar -cf - --null -T -) |
    tar -xf - -C "$stage"

tarball="$artifacts/$name.tar.gz"
tar -czf "$tarball" -C "$artifacts/$runtime" "$name"

echo "  $(basename "$tarball"): $(du -h "$tarball" | cut -f1), binary $(du -h "$compiler" | cut -f1)"
