#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds the Stainless COM server and the C++ host, then runs the host.
#
# There is no COM runtime here, which is the interesting part: a COM interface
# is a vtable pointer and the platform C calling convention, so the same source
# builds and the same object works. What is missing off Windows is activation
# by registry -- and this sample never used it, because the host opens the
# module itself.

set -e
cd "$(dirname "$0")"
mkdir -p build

# Prefer an installed compiler; fall back to this repository's own, so the
# sample runs from a fresh clone with nothing on PATH.
if command -v stainless >/dev/null 2>&1; then
    STAINLESS="stainless"
else
    STAINLESS="dotnet run --project ../../src/Stainless.Cli -c Debug --"
fi

echo "=== building the COM server (Stainless) ==="
$STAINLESS build greeter.sl --shared -o build/libgreeter.so

echo
echo "=== building the host (C++) ==="
clang++ -std=c++17 host.cpp -o build/host -ldl

echo
echo "=== running ==="
./build/host ./build/libgreeter.so
