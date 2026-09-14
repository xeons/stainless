# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Stainless is an experimental compiled language: a C#-shaped syntax over C's
layout and ABI, with ARC instead of a collector and no header files. The
compiler is C# and emits textual LLVM IR; everything above it — the standard
library, the GUI framework, the IDE — is written in Stainless itself.

[README.md](README.md) is the introduction, [docs/internals.md](docs/internals.md)
has the pipeline and a component-by-component table, and
[docs/spec/](docs/spec/index.md) is the language in ten chapters. Read
internals before changing the compiler; this file is the operational half.

## Commands

```
dotnet build Stainless.slnx                     # the compiler; needed before almost anything
dotnet run --project tests/Stainless.Tests      # end-to-end: compile, link, run
dotnet test tests/Stainless.UnitTests           # the front end alone
```

One end-to-end case, by name fragment — the first non-dash argument is a
filter, and `-v` shows the command and the output:

```
dotnet run --project tests/Stainless.Tests --no-build -- hello
dotnet run --project tests/Stainless.Tests --no-build -- x86 -v
```

The compiler itself, once built, is
`src/Stainless.Cli/bin/Debug/net10.0/stainless[.exe]`:

```
stainless run samples/hello.sl
stainless build src --shared -o build/lib.dll --header build/lib.h
stainless emit-ir samples/hello.sl              # the .ll, for reading
stainless doc --stdlib                          # regenerates docs/stdlib/
```

**Run both suites before committing.** They ask different questions, and the
unit tests hold rules the end-to-end suite cannot see — see *Tests that fail for
reasons unrelated to your change* below.

### The things that are not .NET projects

`forms/` and `ide/` are Stainless source compiled by the built compiler, not by
`dotnet`. Each has a script that names the library sources its program needs:

```
.\samples\forms\build.ps1 -Test         # build the Forms samples, run each --selftest
.\ide\build.ps1 -Test                   # build the IDE, run the scanner tests and --selftest
.\ide\build.ps1 -Run -Open samples\shapes.sl
```

Forms is compiled into each program rather than linked, which is why every
command names `forms/src` and `bindings/win32` alongside the program's own
source. On Linux the equivalent needs the GTK libraries by name —
[bindings/gtk/README.md](bindings/gtk/README.md) has the exact list, and leaving
them off does not fail cleanly (see below).

## Layout

`src/Stainless.Compiler` (front end, binder, emitter, driver) and
`src/Stainless.Cli` are the only C#. Everything else is Stainless or C:

| | |
|---|---|
| `runtime/` | sixteen C files, embedded in the compiler as resources |
| `stdlib/` | the standard library, in Stainless, also embedded |
| `bindings/win32`, `bindings/gtk`, `bindings/linux` | platform APIs, compiled only by a program that asks |
| `forms/` | a GUI framework, one control layer over a Win32 and a GTK backend |
| `ide/` | an editor for Stainless, written in Stainless, on `forms/` |
| `tests/cases/` | one directory per end-to-end case |

**A test case is a directory**, holding the `.sl` files of one program plus
exactly one expectation: `expected.txt` (it must compile, run, and print this)
or `errors.txt` (it must fail, and every `SL####` the file names must be
reported). Optional beside them: `args.txt`, `stdin.txt`, `warnings.txt`,
`defines.txt`, `abi.txt`, `target.txt`, and `expected.linux.txt` for a case
whose subject genuinely differs by platform.

**The whole-program rule is the thing to understand first.** Every name in the
program is resolved before any body is checked, in eleven binder passes. That is
what removes header files, and it is why a change to name resolution is never
local.

## Tests that fail for reasons unrelated to your change

These are rules held by the unit tests, and each has caught a real commit:

- **A new sample must be listed in `SampleTests`**, or `EverySampleOnDiskIsListed`
  fails. A `UnixOnly` sample is skipped on Windows, so this can pass locally and
  fail on Linux.
- **A documented `SL####` needs an `errors.txt` case pinning it**, or
  `DiagnosticTests.EveryDocumentedCodeIsPinnedByACase` fails.
- **A test that looks a function up by name fragment will eventually match the
  standard library.** `AbiTests` once matched `Standard.Xml.Cursor.Take` instead
  of its own; qualify with the mangled prefix (`4Test4Take`).

## Things that will cost you an hour

**Rebuild after editing `runtime/*.c` or adding a `stdlib/*.sl` file.** Both are
embedded resources picked up by a wildcard, so no Stainless program sees the
change until `dotnet build` has run. A new stdlib file cannot even be imported
before that.

**Two end-to-end runs at once corrupt each other.** The harness builds every
case under one shared `%TEMP%/stainless-tests/`, so a second run overwrites the
first's object files mid-compile. It looks like a scatter of unrelated failures
that all pass when the suite is run alone.

**A locked output file reports as a compiler bug.** If a program built here is
still running, the link fails with `permission denied` followed by "this is a
compiler bug, not a bug in your program". Kill the process and rebuild.

**Omitting the `-l` libraries on a GTK build hangs rather than failing.** It
leaves a partial, non-ELF file at the output path and never returns. Take the
library list from `bindings/gtk/README.md`.

**`-o /dev/null` does not work on Windows**; the linker wants a real path. And
Windows reserves `COM1`–`COM9` even with an extension, so a scratch file named
`com2.sl` does not exist as far as any program is concerned.

**`STAINLESS_CLANG` names the clang to use and always wins.** Otherwise the
first on `PATH`, then the usual install directories.

## Editing this repository

**Heredocs mangle backslashes.** A `\n` inside `bash <<'EOF'` arrives as a
literal newline, which has silently reverted edits to C#, C and Stainless source
more than once. Backticks inside a double-quoted shell string are command
substitution and will eat the text. Use the Write or Edit tool, or a Python
script written to a file, for anything containing escapes or backticks.

**The prose uses em dashes, not `--`.** A patch script matching on `--` will
fail its own assertion against text that uses `—`. Check which is there before
writing the pattern.

**A patch script should assert what it expects to match**, and read before it
writes — `io.open(p, 'wb').write(io.open(p, 'rb').read())` truncates the file,
because Python evaluates the callee first.

**A mechanical rewrite needs a test that fails first.** A script turning
`x = x + 1` into `x++` also turned `value = value * 10 + digit` into
`value *= 10 + digit`, and exactly one test noticed. A script that cannot see
precedence has no business deciding what an expression meant.

**Two name collisions are easy to walk into**, because the standard library puts
short verbs at module level and `import Standard.Collections` brings in twenty of
them (`Take`, `Skip`, `Map`, `Filter`, `Find`, `Any`, `All`, `ForEach`, …):

- A method of your own named after one of them resolves to the free function
  **inside a lambda body** and to your method everywhere else. Writing `this.`
  fixes it; so does not using the name.
- `Fail(...)` and `Ok(...)` are `Result`'s case constructors and are in scope
  everywhere. A method named `Fail` will silently never be called — the only
  sign is SL0222, "this expression has no effect".

**`where` cannot be a parameter name** — it is read as a generic constraint, and
the error lands far from the cause.

**Match the surrounding prose.** Documentation and commit messages here explain
*why*, name the alternative that was rejected, and say what a thing costs. A
`///` block states what a caller must know before using the declaration; a `//`
note beside a line describes that line. Commit messages are a sentence-shaped
subject and then paragraphs of reasoning — read `git log` before writing one.

## The Linux box

`ssh brandon@geekom-a7` — Ubuntu, GTK 3 and its development packages, clang,
dotnet, Xvfb and `broadwayd`. It is where the GTK backend and the 32-bit Linux
cases are actually run.

There is no `rsync` on the Windows side. Tar over ssh, and let `git ls-files`
decide what goes — `-c -o --exclude-standard` is tracked files *and* new ones
that are not ignored, which is what a work-in-progress tree needs. A stale
`obj/` from the other platform is what makes a synced tree fail confusingly:

```sh
tar -czf - $(git ls-files -c -o --exclude-standard) | ssh brandon@geekom-a7 "mkdir -p ~/sl-sync && tar -xzf - -C ~/sl-sync"
```

The 32-bit cases need the multilib development packages, which the box does not
have; `tests/linux-x86.Dockerfile` supplies them. Run the container as yourself
(`-u "$(id -u):$(id -g)"` with `HOME` set), or the `bin/` and `obj/` it leaves in
the bind-mounted tree belong to root and the next sync cannot overwrite them.

The first `dotnet build` after a sync onto Linux sometimes dies with
`Internal CLR error (0x80131506)`. It is transient; run it again.

### Running a GUI with no screen

```sh
Xvfb :9 -screen 0 1024x768x24 &
DISPLAY=:9 ./Program
DISPLAY=:9 import -window root shot.png         # ImageMagick, for a screenshot

broadwayd :5 &                                  # GTK 3 in a browser, no X at all
GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 ./Program
```

Xvfb has no window manager, so nothing is decorated and nothing gets focus from
one — a control can still be given the focus programmatically, but a test that
expects the window manager's behaviour will not see it.

**Watch stderr.** GTK reports a bad signal name or a failed cast there and
nowhere else, so a clean stderr is most of what a headless run is worth. And a
program killed with `SIGKILL` loses whatever it had buffered on stdout, so
redirect to a file or use `stdbuf -o0` when a run is going to be terminated.
