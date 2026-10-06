#!/usr/bin/env bash
# Builds the Forms samples into samples/forms/build, which .gitignore already
# covers ("samples/**/build/"), so the binaries never reach a commit.
#
#   samples/forms/build.sh             build them
#   samples/forms/build.sh --test      build, then run each --selftest
#   samples/forms/build.sh --run demo  build, then open that one's window
#
# build.ps1 is the same on Windows. This one is for Linux, where the samples
# are drawn with GTK, and macOS, where they are drawn with AppKit -- or with
# GTK when FORMS_GTK=1 is in the environment, as the define of that name does.
# A self test opens windows, so on Linux it needs a display; xvfb-run is used
# when there is none.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repository="$(cd "$here/../.." && pwd)"
compiler="$repository/src/Stainless.Cli/bin/Debug/net10.0/stainless"
output="$here/build"
test=0
run=""

while [ $# -gt 0 ]; do
    case "$1" in
        --test) test=1 ;;
        --run) shift; run="${1:-}" ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done

if [ ! -x "$compiler" ]; then
    echo "error: no compiler at $compiler -- run 'dotnet build Stainless.slnx' first" >&2
    exit 1
fi

# What every Forms program is built from beside its own source: the library,
# the backend's bindings and the libraries they need. Forms is compiled into
# each program rather than linked -- see forms/README.md for why.
system="$(uname -s)"
case "$system" in
    Linux)
        library=("$repository/forms/src" "$repository/bindings/gtk"
                 -l :libgtk-3.so.0 -l :libgdk-3.so.0 -l :libgobject-2.0.so.0
                 -l :libglib-2.0.so.0 -l :libcairo.so.2 -l :libgdk_pixbuf-2.0.so.0)
        ;;
    Darwin)
        if [ "${FORMS_GTK:-0}" != 0 ]; then
            library=("$repository/forms/src" "$repository/bindings/gtk" -D FORMS_GTK
                     -l gtk-3 -l gdk-3 -l gobject-2.0 -l glib-2.0 -l cairo -l gdk_pixbuf-2.0)
            # Homebrew's libraries are not on the default search path.
            if command -v brew > /dev/null; then
                export LIBRARY_PATH="$(brew --prefix)/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
            fi
        else
            library=("$repository/forms/src" "$repository/bindings/macos")
        fi
        ;;
    *) echo "error: $system is neither Linux nor macOS; build.ps1 is for Windows" >&2; exit 2 ;;
esac

# A file is one program, and so is a directory: `designed` is a form's two
# halves, one of them generated from its `.slfm`.
samples=()
for path in "$here"/*.sl "$here"/*/; do
    path="${path%/}"
    name="$(basename "$path" .sl)"
    [ "$name" = build ] && continue
    if [ -d "$path" ] && ! ls "$path"/*.sl > /dev/null 2>&1; then
        continue
    fi
    samples+=("$path")
done

mkdir -p "$output"
for sample in "${samples[@]}"; do
    name="$(basename "$sample" .sl)"
    echo "building $name"
    if ! "$compiler" build "$sample" "${library[@]}" -o "$output/$name"; then
        echo "$name failed to build" >&2
        exit 1
    fi
done
echo "built into $output"

if [ "$test" = 1 ]; then
    launch=()
    if [ "$system" = Linux ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        launch=(xvfb-run -a)
    fi
    for sample in "${samples[@]}"; do
        name="$(basename "$sample" .sl)"
        echo "--selftest $name"
        # The `+` form, since macOS's bash 3.2 calls an empty array unbound.
        if ! ${launch[@]+"${launch[@]}"} "$output/$name" --selftest; then
            echo "$name self test failed" >&2
            exit 1
        fi
    done
fi

if [ -n "$run" ]; then
    if [ ! -x "$output/$run" ]; then
        echo "error: no sample called '$run' in $output" >&2
        exit 1
    fi
    "$output/$run"
fi
