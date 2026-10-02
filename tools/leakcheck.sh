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

# Builds every sample and application with the allocation tracker on, runs
# each, and checks what it never freed against tools/leaks.baseline.txt.
#
#   tools/leakcheck.sh [--update] [--filter text] [--list]
#
# tools/leakcheck.ps1 is the same on Windows and says why it exists. This one
# is for Linux and macOS. --update rewrites the baseline entries this machine
# measured and keeps the rest; --list prints what would be built and stops.

set -uo pipefail

repository="$(cd "$(dirname "$0")/.." && pwd)"
compiler="$repository/src/Stainless.Cli/bin/Debug/net10.0/stainless"
baseline="$repository/tools/leaks.baseline.txt"
work="${TMPDIR:-/tmp}/stainless-leakcheck"
update=0
filter=""
list=0

while [ $# -gt 0 ]; do
    case "$1" in
        --update) update=1 ;;
        --list) list=1 ;;
        --filter) shift; filter="${1:-}" ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done

system="$(uname -s)"
case "$system" in
    Linux)
        gtk="-l :libgtk-3.so.0 -l :libgdk-3.so.0 -l :libgobject-2.0.so.0 -l :libglib-2.0.so.0 -l :libcairo.so.2 -l :libgdk_pixbuf-2.0.so.0"
        ;;
    Darwin)
        gtk="-l gtk-3 -l gdk-3 -l gobject-2.0 -l glib-2.0 -l cairo -l gdk_pixbuf-2.0"
        # Homebrew's libraries are not on the default search path.
        if command -v brew > /dev/null; then
            export LIBRARY_PATH="$(brew --prefix)/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
        fi
        ;;
    *) echo "error: $system is neither Linux nor macOS; tools/leakcheck.ps1 is for Windows" >&2; exit 2 ;;
esac

# One line per program: name, whether it has --selftest, and its build
# arguments. Forms is compiled into each program rather than linked.
programs=()
for sample in "$repository"/samples/*.sl; do
    name="$(basename "$sample" .sl)"
    programs+=("samples/$name|0|$sample")
done
for sample in "$repository"/samples/forms/*.sl; do
    name="$(basename "$sample" .sl)"
    programs+=("samples/forms/$name|1|$sample $repository/forms/src $repository/bindings/gtk $gtk")
done
programs+=("ide|1|$repository/ide")
programs+=("sldb|0|$repository/debug")

if [ "$list" = 1 ]; then
    for entry in "${programs[@]}"; do
        printf '  %s\n' "${entry%%|*}"
    done
    exit 0
fi

if [ ! -x "$compiler" ]; then
    echo "error: the compiler is not built: $compiler" >&2
    exit 2
fi

mkdir -p "$work"
measured="$work/measured.txt"
: > "$measured"
problems=()

for entry in "${programs[@]}"; do
    name="${entry%%|*}"
    rest="${entry#*|}"
    selftest="${rest%%|*}"
    sources="${rest#*|}"

    case "$name" in *"$filter"*) ;; *) continue ;; esac

    executable="$work/$(echo "$name" | tr '/' '-')"
    rm -f "$executable"

    # Unquoted on purpose: the sources and the -l flags are separate words.
    # shellcheck disable=SC2086
    "$compiler" build $sources --leak-check -o "$executable" > "$work/build.log" 2>&1
    if [ ! -x "$executable" ]; then
        printf '  %-34s did not build\n' "$name"
        problems+=("$name: did not build"$'\n'"$(cat "$work/build.log")")
        continue
    fi

    rm -f "$work/run.log"
    if [ "$selftest" = 1 ]; then
        "$executable" --selftest < /dev/null > "$work/run.log" 2>&1 &
    else
        "$executable" < /dev/null > "$work/run.log" 2>&1 &
    fi
    process=$!

    # Thirty seconds, polled: macOS has no timeout(1).
    for _ in $(seq 1 300); do
        kill -0 "$process" 2> /dev/null || break
        sleep 0.1
    done
    if kill -0 "$process" 2> /dev/null; then
        kill -9 "$process" 2> /dev/null
        wait "$process" 2> /dev/null
        printf '  %-34s did not finish in 30s\n' "$name"
        problems+=("$name: did not reach exit, so it never reported")
        continue
    fi
    wait "$process" 2> /dev/null

    report="$(grep -m 1 '^stainless-leak:' "$work/run.log")"
    if [ -z "$report" ]; then
        printf '  %-34s no report (did not reach exit)\n' "$name"
        problems+=("$name: the program printed no allocation report")
        continue
    fi

    live="$(echo "$report" | sed -n 's/.*live=\([0-9]*\).*/\1/p')"
    bytes="$(echo "$report" | sed -n 's/.*bytes=\([0-9]*\).*/\1/p')"
    untracked="$(echo "$report" | sed -n 's/.*untracked=\([0-9]*\).*/\1/p')"

    printf '%s\t%s\n' "$name" "$live" >> "$measured"
    printf '  %-34s live=%-6s bytes=%s\n' "$name" "$live" "$bytes"

    if [ "${untracked:-0}" != 0 ]; then
        problems+=("$name: freed $untracked object(s) it never recorded, so an allocation site is missing its hook")
    fi
done

# The baseline's number for a program, or nothing when it has none.
find_baseline() {
    [ -f "$baseline" ] || return 0
    tr -d '\r' < "$baseline" | awk -F '\t' -v name="$1" '$1 == name { print $2; exit }'
}

if [ "$update" = 1 ]; then
    updated="$work/baseline.txt"
    {
        echo "# What each program still had allocated when it ended, as of the last"
        echo "# -Update. What a mutable static holds is released before the count is"
        echo "# taken, so anything here is either a 'readonly' static -- immortal by"
        echo "# construction -- or a cycle. See runtime/leak.c."
        echo ""
        # Every program in the old baseline's order, then any new one.
        if [ -f "$baseline" ]; then
            tr -d '\r' < "$baseline" | while IFS=$'\t' read -r name count; do
                case "$count" in '' | *[!0-9]*) continue ;; esac
                now="$(awk -F '\t' -v name="$name" '$1 == name { print $2; exit }' "$measured")"
                printf '%s\t%s\n' "$name" "${now:-$count}"
            done
        fi
        while IFS=$'\t' read -r name count; do
            [ -n "$(find_baseline "$name")" ] || printf '%s\t%s\n' "$name" "$count"
        done < "$measured"
    } > "$updated"
    mv "$updated" "$baseline"
    echo
    echo "baseline written to $baseline"
    exit 0
fi

if [ ! -f "$baseline" ]; then
    echo
    echo "no baseline yet; run with --update to record one"
    exit 0
fi

while IFS=$'\t' read -r name live; do
    allowed="$(find_baseline "$name")"
    if [ -z "$allowed" ]; then
        problems+=("$name: no baseline; run with --update")
    elif [ "$live" -gt "$allowed" ]; then
        problems+=("$name: $live alive, and the baseline is $allowed")
    fi
done < "$measured"

if [ ${#problems[@]} -gt 0 ]; then
    echo
    for problem in "${problems[@]}"; do
        echo "$problem" >&2
    done
    exit 1
fi

echo
echo "nothing leaks more than it did"
exit 0
