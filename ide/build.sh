#!/usr/bin/env bash
# Builds the IDE into ide/build, which .gitignore covers.
#
#   ide/build.sh                  build it
#   ide/build.sh --test           build, then run the scanner tests and --selftest
#   ide/build.sh --run [file.sl]  build, then open the window
#
# build.ps1 is the same on Windows. This one is for Linux, where the IDE is
# drawn with GTK, and macOS, where it is drawn with AppKit; ide/stainless.json
# names each platform's bindings. A self test opens a window, so on Linux it
# needs a display; xvfb-run is used when there is none.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repository="$(cd "$here/.." && pwd)"
compiler="$repository/src/Stainless.Cli/bin/Debug/net10.0/stainless"
output="$here/build"
test=0
run=0
open=""

while [ $# -gt 0 ]; do
    case "$1" in
        --test) test=1 ;;
        --run) run=1; if [ $# -gt 1 ]; then shift; open="$1"; fi ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done

if [ ! -x "$compiler" ]; then
    echo "error: no compiler at $compiler -- run 'dotnet build Stainless.slnx' first" >&2
    exit 1
fi

fail() {
    echo "$1" >&2
    exit 1
}

echo "building the IDE"
"$compiler" build --project "$here" || fail "the IDE failed to build"
echo "built $output/stainless-ide"

# Each test program gets its own output: built beside its sources it would be
# named after its module, `Tests`, which a case-blind file system finds is the
# `tests` directory.
run_test() {
    local what="$1"
    shift
    echo
    echo "$what"
    "$compiler" run "$@" -o "$output/tests" || fail "the $what tests failed"
}

if [ "$test" = 1 ]; then
    mkdir -p "$output"
    run_test "scanner" "$here/tests/lextest.sl" "$here/src/Lang"
    run_test "diagnostic" "$here/tests/buildtest.sl" "$here/src/Build"
    run_test "project reader" "$here/tests/projecttest.sl" "$here/src/Project"
    # One file rather than the directory: the other one is the controls.
    run_test "docking layout" "$here/tests/docktest.sl" "$here/src/Shell/Layout.sl"
    run_test "breakpoint" "$here/tests/debugtest.sl" "$here/src/Debug/Breakpoints.sl" \
        "$repository/debug/src/Paths.sl"
    run_test "form file" "$here/tests/formtest.sl" "$here/src/Designer"

    # A checked-in generated half MUST match its form file, or what is built
    # is not what the form says.
    echo
    echo "generated halves"
    "$compiler" build --project "$here/slforms" || fail "slforms failed to build"
    "$here/slforms/build/slforms" --check "$repository/samples" || fail "a generated half is stale"

    echo
    echo "the window"
    launch=()
    if [ "$(uname -s)" = Linux ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        launch=(xvfb-run -a)
    fi
    # The `+` form, since macOS's bash 3.2 calls an empty array unbound.
    ${launch[@]+"${launch[@]}"} "$output/stainless-ide" --selftest || fail "the IDE self test failed"
fi

if [ "$run" = 1 ]; then
    if [ -n "$open" ]; then
        "$output/stainless-ide" "$open"
    else
        "$output/stainless-ide"
    fi
fi
