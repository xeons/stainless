# Projects and packages

## 1. Why there is a file at all

Every build has always been sayable on a command line, and for one program in
one file that is still the shorter way to say it. What a command line cannot do
is be *read*. A tool that wants to know what a program is made of — an editor,
a language server, the resolver in §4 — can only run a build and watch what
happens, and a Makefile is no better: it is a program, so the only way to find
out what it builds is to run it.

A project file is a document. That is the whole of the reason it exists, and it
is the reason it is JSON rather than something nicer to type: the framework the
compiler is written in has a parser for it, and so does the standard library
this language ships, so a program written in Stainless can read its own project
file without anything new being written. A better syntax would cost two parsers
for ever.

It is `stainless.json`, it sits at the root of a package, and every path in it
is relative to it — never to wherever the build happened to be started, so a
build from three directories down is the same build.

## 2. The file

```json
{
  "name": "shapes",
  "version": "1.0.0",
  "kind": "library",
  "sources": ["src"],
  "dependencies": {
    "geometry": { "path": "../geometry", "version": "^1.2" }
  }
}
```

Four of those are all a project needs; `stainless init` writes exactly those and
nothing else.

| Field | Means | Default |
| --- | --- | --- |
| `name` | what the package is called | required |
| `version` | what it publishes itself as (§3) | required |
| `kind` | `executable` or `library` | `executable` |
| `sources` | files and directories to compile | `["src"]` |
| `dependencies` | what it needs, by name (§4) | none |
| `output` | where the binary goes | `<buildDirectory>/<name>` |
| `buildDirectory` | where binaries and metadata land | `build` |
| `objectDirectory` | where intermediates land | `obj` |
| `header` | a C header for the exported surface | none |
| `libraries` | libraries the linker finds by name, like `-l` | none |
| `defines` | symbols `#if` can test, like `-D` | none |
| `optimize` | 0 to 3 | 2 |
| `debug` | describe the program to a debugger | false |
| `abi` | `microsoft` or `itanium` | the host's |
| `runtime` | `shared` or `static` | whatever the build needs |
| `format` | the version of this file format | 1 |

`sources` takes whatever a command line takes: `.sl` files, directories searched
recursively, C sources or object files that belong to the same program, and a
Windows resource script (§2.2).
Directories rather than a list of files, because where a file sits has no bearing
on which module it joins — that is stated in the file — so a project never has a
file list to keep up to date, and neither does anything reading it.

**A field that is not in this table is refused.** A typo that silently did
nothing is precisely the failure a readable project file exists to prevent, so
the build names the field and, where it can, guesses what was meant:

```
error: 'optimise' is not a field of a project file; did you mean 'optimize'?
```

### 2.1 Finding it

```
stainless build                 # this directory, or the nearest parent with one
stainless build ../shapes       # a directory that holds one
stainless build --project x.json
stainless build src/*.sl        # no project: the paths mean what they always meant
```

Named paths win. Someone who names a file means that file, even from inside a
project, and `--no-project` says so explicitly.

### 2.2 Resources

A `.rc` among the sources is a **Windows resource script**. The build compiles
it with `llvm-rc` — which ships beside the clang that is already driving the
build — and the linker folds the result into the executable, so what it names
travels *inside* the binary rather than beside it:

```json
{ "name": "editor", "version": "1.0.0", "sources": ["src", "editor.rc"] }
```

```
101 BITMAP  "toolbar.bmp"
1   ICON    "app.ico"
1   24      "app.manifest"      // 24 is RT_MANIFEST

STRINGTABLE BEGIN
    201 "Ready"
END
```

That is where an icon, a toolbar's image strip, a string table, a menu, a
dialog template, an accelerator table and an application manifest live.
`Standard.Resources` reads them back on any target, `Win32.Resources` adds the
Windows-only half — icons, menus, accelerators, enumeration — and
`Bitmap.FromResource` in `forms/` is the same thing one layer up, on both
backends. clang takes the compiled `.res` on its command line
directly, so there is no `cvtres` step and no dependency on a particular
linker.

**Relative paths inside the script resolve against the script's own
directory**, not the working directory — so a script keeps its bitmaps and its
`#include`d header beside it and a build started from anywhere finds them.
This is the one place `llvm-rc` deliberately differs from Microsoft's `rc.exe`,
and it is the better rule: it is what makes a project relocatable.

**It works on every target, by two routes.** A PE has a resource directory and
the linker fills it from the `.res`, so a Windows build reads the real thing
through `FindResourceW`. ELF has no such section, so the compiler puts the same
`.res` in a section called `.rsrc` as ordinary data and `Standard.Resources`
walks it. The two were checked against each other on the same script, entry by
entry, and answer identically — which is why
[tests/cases/resources-portable](../tests/cases/resources-portable) has one
`expected.txt` and no `#if` in its source.

Because the section holds the `.res` unchanged, the ordinary tools still work on
a Linux binary:

```
readelf -x .rsrc app
llvm-objcopy --dump-section .rsrc=out.res app     # byte-identical to llvm-rc's
```

**What does not travel is the operating system.** Bytes travel; an OS that acts
on them does not. `RT_MANIFEST` selects comctl32 version 6, `RT_GROUP_ICON`
becomes a window's icon, `RT_DIALOG` becomes a window full of controls — all by
machinery that exists only on Windows. Those types are carried and readable
elsewhere, and inert. The build says so, naming what is actually in the program
rather than firing on every script:

```
warning[SL0700]: this program's resources include RT_MANIFEST, which only
Windows acts on: x86_64-pc-linux-gnu carries them and 'Standard.Resources' can
read them, but nothing here turns one into a window icon, a menu or a manifest
```

A script of string tables and RCDATA draws no warning at all, because nothing
about it is lost.

## 3. Versions

A version is semver: three numbers, an optional `-prerelease` and an optional
`+build`. A prerelease sorts *below* the release it leads to, and build metadata
has no bearing on which version is newer.

A dependency says which versions will do:

| Written | Accepts |
| --- | --- |
| `1.2.0`, `^1.2.0` | ≥ 1.2.0 and < 2.0.0 |
| `^0.2.3` | ≥ 0.2.3 and < 0.3.0 |
| `^0.0.3` | 0.0.3 only |
| `~1.2.3`, `~1.2` | ≥ 1.2.3 and < 1.3.0 |
| `~1` | ≥ 1.0.0 and < 2.0.0 |
| `=1.2.0` | 1.2.0 exactly |
| `>=1.2, <2.0` | both bounds |
| `*` | anything |

**A bare version is a caret**, which follows Cargo rather than npm. The bare
spelling is the one people type, so it should mean the thing they almost always
want rather than pinning a patch release for ever by accident; `=1.2.0` is how
to say the other thing.

Below 1.0 the caret keeps the minor, because below 1.0 the minor is doing the
major's job — a convention every registry has converged on.

A prerelease is only ever matched by a requirement that named one with the same
three numbers. Without that rule `^1.0.0` would quietly take `2.0.0-alpha`,
which compares below 2.0.0 and is not what anybody means.

## 4. Dependencies

```json
"dependencies": {
  "geometry": { "path": "../geometry" },
  "json":     { "git": "https://example/json.git", "tag": "v2.1.0", "version": "^2.1" },
  "widgets":  { "path": "../widgets", "link": "shared" }
}
```

The name on the left has to be the dependency's own `name`. Two names for one
package is how a lock file starts describing something that is not there.

Exactly one source is named — `path` or `git`. There is no registry, so there is
no shorthand that could mean one; the day there is one it becomes a third field
rather than a change of meaning for these two.

A `git` dependency takes one of `tag`, `branch` or `rev`, and `subdirectory` for
a repository holding more than one package. A tag is the one worth using: it is
the only one of the three that means the same thing next week, and even then §5
is what makes that true.

### 4.1 Source or shared

```json
"link": "source"    // the default
"link": "shared"
```

A **source** dependency's files join this program's compilation, exactly as
though they had been listed on the command line. That is the model this language
already has — one program, no headers, whole-program binding — and it is why
generics, interfaces and variants all cross a source dependency when they cannot
cross a binary one. It is the default because it is the form with no caveats.

A **shared** dependency is built once as a real shared library and bound against
through its metadata. That buys a boundary: the package is compiled separately,
ships separately, and can be replaced without rebuilding what uses it. It costs
what a boundary costs — see §8.4 of the language spec — and it is the only form
where the digest in §5 has anything to check.

A class from a shared dependency can be **derived from**: its layout, its
dispatch table, its destroy hook and its protected members all cross, so the
derived class puts its own fields after fields it never saw laid out and hands
the object back to the library when its destructor is done. What that costs is
the rule in §5 about adding a virtual method.

One package cannot be linked both ways in one program. Doing so would compile
its code into the program and load a second copy of it beside the program.

### 4.2 What resolution does, and what it does not

It walks the graph, unifies each name to one package, checks that every
requirement accepts what is there, and orders the result so that nothing is ever
built before something it needs.

What it does not do is *choose* between versions, and the reason is worth being
straight about: with no registry, nothing can offer an alternative. A path is
whatever is in the directory and a git tag is whatever that tag points at — each
source pins exactly one version, so resolving is unifying sources rather than
searching versions. An impossible set of requirements is still a message rather
than a mystery; the searching goes in here the day there is something to search.

## 5. The digest

A version number is a promise a person makes, and people are wrong about them.
Nothing stops 1.2.3 being rebuilt with a field added to the middle of a class,
and nothing about the number says it happened — while the consumer's compilation
has that class's offsets baked into its own code. It is not a link error. It is
a program that reads the wrong four bytes and keeps going.

So a library's metadata also carries a fingerprint of what it describes: every
layout, every offset, every dispatch slot, every symbol, and — because this
language has named arguments — every parameter name. Two builds agree there
exactly when something compiled against one can be linked against the other.

```json
"AbiDigest": "e4a5b7a8e6311892072c07cf6fd30f20"
```

Each type carries its own as well, which is what lets a mismatch name what
moved rather than only that something did:

```
note: 'shapes' 1.0.0 describes a different surface than the last build of 1.0.0
      did: Shapes.Canvas. A version number is a promise about exactly this, and
      whatever was compiled against the old surface has those offsets and
      signatures built into it -- the linker cannot tell, because the symbols
      did not change.
```

Two things about when it fires. **An addition is not a break**: a surface that
only grew cannot invalidate anything already compiled, so a new function or a
new type says nothing.

One addition is the exception, and it is the reason the dispatch table is in the
digest slot by slot. A class derived across a library boundary copies its base's
table and appends its own methods after it, so **adding a virtual method to a
public, non-sealed class wants a slot a derived class elsewhere is already
using**. That is a breaking change by definition; the digest is what turns it
from a program calling the wrong function into a message naming the class.
 And a **path** dependency is told rather than stopped —
being edited in place is the entire reason to use one — where anything pinned to
a fixed commit is an error, because the same version describing two surfaces
means the two builds were not the same build.

The digest also makes the metadata self-checking. It is readable JSON, which
makes it editable JSON, and editing one is another way to compile against a
layout the library does not have:

```
error: 'shapes.slmod' does not match its own digest, so it has been edited since
       it was written.
```

## 6. The lock file

`stainless.lock` is what resolution decided, written down so the next build
decides the same. It belongs in version control: two people with the same lock
build the same program, and two people with only the project file build whatever
was newest on the day.

```json
{
  "format": 1,
  "root": "app",
  "packages": [
    {
      "name": "geometry",
      "version": "1.3.0",
      "source": "git:https://example/geometry.git#v1.3.0",
      "revision": "193e7e8f198ca8305c8291a2502f8afd490947ac",
      "link": "shared",
      "sourceDigest": "53d9814d0be2fd2b1ae2aa74a663ebcb",
      "abiDigest": "e4a5b7a8e6311892072c07cf6fd30f20",
      "dependencies": []
    }
  ]
}
```

`revision` is the point of locking a git dependency: a tag can be moved and a
branch is expected to, and a locked build goes to the commit rather than to the
name. `stainless restore --update` is the request to look again.

`sourceDigest` is the same question for a dependency with no commit and no
release — is the directory I am building today the directory I resolved? For a
path into a sibling checkout the answer is often no, and that is worth saying
out loud rather than discovering. For a fixed commit it is an error: a commit
does not change, so a cache that disagrees with one has been damaged.

The two digests answer different questions at different moments. `sourceDigest`
is about the files that were read; `abiDigest` is about the library that came
out. Neither can be computed from the other, and a package can have the first
without the second — a source dependency never produces a library to fingerprint.

## 7. Commands

```
stainless init [name]           write a stainless.json here
stainless restore               resolve dependencies and write the lock
stainless restore --update      re-resolve, ignoring what is locked
stainless build                 build the project here
stainless run                   build it and run it
```

| Option | Means |
| --- | --- |
| `--project <path>` | the project file, or the directory holding it |
| `--no-project` | ignore any project file; the paths mean what they always meant |
| `--update` | re-resolve, ignoring the lock |
| `--locked` | fail rather than change the lock file |
| `--offline` | use the package cache and never the network |

`--locked` is for a build machine: it turns "the lock is out of date" from
something a build quietly fixes into something a build refuses, which is what
makes the committed lock the one that was actually built.

Fetched packages live in a cache — `%LOCALAPPDATA%\stainless\cache` on Windows
and `$XDG_CACHE_HOME/stainless` (usually `~/.cache/stainless`) elsewhere, or
under `STAINLESS_HOME` if that is set. A git dependency needs `git` on `PATH`,
and only then: a path dependency needs nothing at all.

## 7.1 What gets rebuilt

A shared dependency is built once and then left alone. Beside its intermediates
is a stamp recording everything that decided what the last build produced, and a
build that would produce the same thing does not run:

```
ok: built build/app in 996 ms
  up to date: shapes
```

The rule is **every input, or rebuild**. There is no per-file dependency graph
and no attempt to work out that some change could not have mattered, because the
cost of being wrong is not a slow build — it is a program linked against a
library that no longer matches its source, which links perfectly and reports
nothing. What counts as an input:

- the compiler itself, by version
- the package's own files, as a digest of their bytes
- every package compiled *into* it, on the same terms
- every library it was bound against, by the surface that library described
- the optimisation level, debug flag, ABI, runtime and defines
- where the output goes

Timestamps are deliberately not among them. A file restored from an archive, a
clock that went backwards, a checkout that rewrote mtimes — each makes a
timestamp say "unchanged" about different bytes.

Deleting anything the build produced brings the build back, and so does a
missing or unreadable stamp: every way of failing to read one means "build it".

The root project is not stamped. It is what was asked for, and it is rebuilt
every time.

## 8. What a dependency inherits

A dependency is built for the program that needs it, so the answers that have to
match across a boundary are the root's: **one ABI and one runtime**, whatever
the dependency's own project file says about either. Two ABIs would disagree
about bit-fields and struct passing; two runtimes would mean two allocators and
two sets of reference counts, and an object could not cross between them.

Optimisation and debug info are inherited too, for consistency rather than for
correctness — a dependency built at `-O0` inside a program built at `-O3` is
legitimate and surprising.

Its own `defines`, `libraries` and `sources` stay its own. A binding knows which
platform library it needs; the program using it should not have to.
