<sub>[Stainless](../README.md) &rsaquo; The command line</sub>

# The command line

`stainless --help` is the authority; this page is the same ground with room to
explain itself.

```
stainless build [paths...]     compile to a native executable
stainless run   [paths...]     compile, then run it
stainless emit-ir [paths...]   print the generated LLVM IR
stainless doc [paths...]       write reference documentation from /// blocks
stainless init [name]          write a stainless.json here
stainless restore              resolve dependencies and lock them

  -o, --out <path>       output file
  --shared               build a shared library instead of an executable
  --header <path>        write a C header for the exported surface
  --def <path>           a module definition file for the linker, to name
                         exports the declarations cannot. The compiler's
                         own renames are kept as well
  --metadata <path>      write module metadata for a Stainless consumer
  -r, --reference <path> bind against a library's module metadata, and link
                         the library beside it
  --stdlib               (doc) document the standard library itself
  -p, --project <path>   the project file to build, or its directory
  --no-project           ignore any project file and use the paths alone
  --update               re-resolve dependencies, ignoring the lock
  --locked               fail rather than change the lock file
  --offline              use the package cache and never the network
  --runtime <shared|static>
                         whether the runtime is one shared library or a
                         copy in this binary. Shared where two Stainless
                         binaries meet, static everywhere else
  -O<0-3>                optimization level (default -O2)
  -g, --debug            describe the program to a debugger
  -D, --define <name>    define a symbol for '#if' to test
  -l, --library <name>   link a library the linker finds by name
                         (a source file can name one itself, with
                          '#pragma comment(lib, "user32")')
  --abi <microsoft|itanium>  which C and C++ ABI to agree with: names,
                         bit-fields and how a struct is passed
  --target <name>        the machine to build for: x64 (the default), x86 or
                         arm64, optionally with a system -- x86-windows,
                         x86-linux, arm64-windows, arm64-linux
  --keep                 keep the generated .ll
  --obj <dir>            directory for intermediates (default ./obj)
  --                     (run) everything after this is passed to the program
  -h, --help  -v, --version
```

## Paths

Paths may be `.sl` files or directories (searched recursively), in any order.
C and C++ sources and object files can be listed alongside them and are passed
straight to the linker:

```
stainless run samples/interop/interop.sl samples/interop/native.c
```

A library the linker can find for itself is named with `-l` rather than by path,
which is how a platform library is reached:

```
stainless run samples/win32/window.sl bindings/win32 -l user32 -l gdi32
```

A **Windows resource script** (`.rc`) may be listed too. It is compiled with
`llvm-rc` and the linker folds the result into the executable, which is how an
icon, a toolbar's image strip, a string table, a menu, a dialog template or an
application manifest gets *inside* the binary rather than sitting beside it:

```
stainless run samples/win32/resources.sl samples/win32/resources.rc \
    bindings/win32 -l user32
```

**It works on every target**, by two routes: a PE has a resource directory and
the linker fills it, and everything else carries the same compiled script in a
section called `.rsrc` that `Standard.Resources` walks. The two were checked
against each other entry by entry and answer identically, so
[tests/cases/resources-portable](../tests/cases/resources-portable) has one
expected output and no `#if` in it. What does not travel is the *operating
system*: a manifest, an icon and a dialog template are carried and readable
elsewhere and inert, and SL0700 names them when a program has any. See
[§2.3 of packages.md](packages.md#23-resources).

## Diagnostics for a tool

`--diagnostics json` writes each diagnostic as **one object on one line**
instead of the rendered form, which is what an editor should read:

```
{"severity":"error","code":"SL0265","message":"cannot convert 'String' to 'int',
 "file":"C:\\Code\\src\\main.sl","line":5,"column":13,"length":14}
```

(Shown wrapped; it is one line.)

`length` is the span the caret run underlines, so an editor can underline the
same thing rather than guessing at a word. A diagnostic about something with no
source of its own — a type read back from a library's metadata — leaves `file`,
`line`, `column` and `length` out rather than naming a file nothing could open.
Anything that goes wrong which is not about a span, such as a linker that
refused, arrives the same way with an empty `code`.

One object per line rather than one array around the whole build, so a reader
can act on each as it arrives and a build that dies part-way still leaves what
it managed to say readable. Nothing else is written to the error stream in this
mode — the "compilation failed with 3 errors" line is a sentence for a person,
and a reader counting the objects it received already has it.

The IDE used to read the rendered form and take it apart again, deciding a line
was an error because it began with `error` and finding the place by counting
colons from the right so a drive letter would survive. That worked, and it was
a parser for a format never meant to be parsed.

## Reference documentation

`stainless doc` reads the `///` blocks in the source and writes one Markdown
page per module, plus an index:

```
stainless doc src -o docs/api        # a project's own modules
stainless doc --stdlib               # the standard library, into docs/stdlib
```

[docs/stdlib](stdlib/index.md) is that output for the standard library, checked
in so it can be read here. It is generated, so the source is what to edit.

## Export names

A library's export table is exactly its `export "C"` functions, under the names
their declarations wrote. On 32-bit x86 that takes work: a calling convention
decorates the symbol, so `export "C" __stdcall int DllGetClassObject(...)` is
`_DllGetClassObject@12` in the object file. The compiler writes a module
definition file naming those exports properly and hands it to the linker, which
is why a 32-bit COM server built here is one Windows can actually activate.
Nothing is decorated on x64, so nothing is written.

`--def` is for the names a declaration cannot state — an alias, an ordinal, a
data export, a second name for one function:

```
stainless build src --shared -o build/server.dll --def src/server.def
```

```
EXPORTS
    GetFactory = DllGetClassObject
```

**It adds to the compiler's own renames rather than replacing them.** A `.def`
may carry more than one `EXPORTS` section, so the file passed here is kept and
what the compiler needed is appended in a section of its own. Replacing them
would make this a trap: passing a `--def` to add one alias would silently drop
the renaming that makes a decorated export reachable at all.

A module definition file is a PE concept. Nothing reads one on Linux or macOS,
where a symbol is exported by its visibility and no convention decorates it.

## Projects

That command line says everything the build needs, and it cannot be *read*. A
tool that wants to know what a program is made of — an editor, a language
server, a package resolver — can only run a build and watch what happens, and a
Makefile is no better, because a Makefile is a program too.

So a project is a document. `stainless.json` at the root of a package, and
`stainless build` with no paths finds it here or in a parent:

```json
{
  "name": "app",
  "version": "0.1.0",
  "kind": "executable",
  "sources": ["src"],
  "dependencies": {
    "shapes": { "path": "../shapes", "version": "^1.0" }
  }
}
```

```
stainless init app      # writes exactly those four fields
stainless run           # builds the project, and whatever it depends on
```

JSON because both sides can already read it: the compiler has a parser in the
framework it is written in, and [stdlib/Json.sl](../stdlib/Json.sl) is the other
one — so a program written in this language can read its own project file with
nothing new written. A nicer syntax would cost two parsers for ever.

**A field the format does not know is refused**, not ignored. A typo that
silently did nothing is the failure a readable project file exists to prevent:

```
error: 'optimise' is not a field of a project file; did you mean 'optimize'?
```

**What differs by platform goes in a section named after one**, which is what
lets a program with a user interface be one project rather than one shell
script per system:

```json
"windows": { "sources": ["bindings/win32"], "libraries": ["user32", "gdi32"] },
"linux":   { "sources": ["bindings/gtk"],   "libraries": [":libgtk-3.so.0"] }
```

A section adds to the base lists rather than replacing them, and the one that
applies is chosen by what is being built *for* — so `--target x64-linux` takes
the `linux` section wherever it runs, exactly as `#if WINDOWS` follows the same
target. [§2.1 of packages.md](packages.md#21-what-one-platform-adds) has the
whole of it.

## Packages

A dependency comes from a directory or from git, and says which versions will
do. A bare version is a caret — `1.2.0` means "1.2.0 up to but not including
2.0.0" — which follows Cargo rather than npm, because the bare spelling is the
one people type and it should mean what they almost always want.

```json
"dependencies": {
  "geometry": { "path": "../geometry" },
  "json":     { "git": "https://example/json.git", "tag": "v2.1.0", "version": "^2.1" },
  "widgets":  { "path": "../widgets", "link": "shared" }
}
```

**A dependency is compiled in by default**, and that is the interesting choice.
Source is the model this language already has — one program, no headers,
whole-program binding — so generics, interfaces and variants all cross a source
dependency, when none of them can cross a binary one. `"link": "shared"` is the
opt-in for a real boundary: the package is built once as a shared library, bound
against through its metadata, and can be replaced without rebuilding what uses
it.

`stainless.lock` records what resolution decided — the exact commit, and a
digest of the files that were read — and belongs in version control. A tag can
be moved and a branch is expected to; a locked build goes to the commit rather
than to the name, and `--update` is the request to look again.

### A version is a promise; the digest is a fact

Nothing stops 1.2.3 being rebuilt with a field added to the middle of a class,
and nothing about the number says it happened — while everything compiled
against it has that class's offsets baked in. It is not a link error. It is a
program that reads the wrong four bytes and keeps going.

So the metadata also carries a fingerprint taken over the layouts themselves,
and the build compares. Move a field without moving the version and it says so,
by name:

```
note: 'shapes' 1.0.0 describes a different surface than the last build of 1.0.0
      did: Shapes.Canvas. A version number is a promise about exactly this, and
      whatever was compiled against the old surface has those offsets and
      signatures built into it -- the linker cannot tell, because the symbols
      did not change.
```

Adding a function is not a broken promise and says nothing; moving a field is.
A path dependency is told rather than stopped, because being edited in place is
the entire reason to use one.

[samples/packages](../samples/packages) is two packages and one program, and
[docs/packages.md](packages.md) is the whole of it: every field, the
version ranges, what resolution does and what it deliberately does not.

## Building a library

```
stainless build src --shared -o build/math.dll --header build/math.h
```

produces the DLL, its import library, and a C header. A `--shared` build needs
no `Main`, and **the export table is exactly the `export "C"` functions**:

```csharp
export "C" int Add(int a, int b) { return a + b; }   // exported

public int Helper() { return 1; }                    // other modules only
int Secret()        { return 2; }                    // module-private
```

That library's export table holds exactly one name:

```
$ llvm-readobj --coff-exports build/math.dll
Name: Add
```

`public` deliberately does not export: it answers a different question — which
modules may see this — and a library's surface should be stated once rather
than falling out of visibility rules.

Consuming it is ordinary C, because the header restates what the ABI already
guarantees:

```c
#include "math.h"
int main(void) { return Add(40, 2) == 42 ? 0 : 1; }
```

```
clang consumer.c build/math.lib -o consumer.exe
```

One caveat worth knowing: plain C values cross a library boundary freely, but a
`String`, class or array carries a reference count, and each binary links its
own copy of the runtime. Pass C types across a *C* boundary and keep managed
objects on one side of it.

## A library for Stainless

A Stainless consumer is a different matter, because both sides are Stainless and
the compiler can describe one to the other:

```
stainless build lib --shared -o build/shapes.dll --metadata build/shapes.slmod
stainless build app.sl --reference build/shapes.slmod -o app.exe
```

The metadata names its library, and **`--reference` links it** from beside the
`.slmod` — the import library on Windows, the shared object elsewhere. It used
to take the library as a second input, and leaving that off was a link error
about a name nobody had declared. A library moved away from its metadata is
still passed as an ordinary input.

The `.slmod` is generated from the same bound program the library was compiled
from, so it cannot drift from it. The consumer then writes ordinary Stainless
against a module it has no source for:

```csharp
import Library.Shapes;

var counter = new Counter("clicks", tally);
counter.Step = 3;
counter.Bump();
Console.WriteLine(counter.Describe());
```

Classes cross with their fields, properties, methods, constructors, destructors
and **events**, and so do structs, enums, free functions, `closure` types and
`delegate` types. A consumer subscribes to an event declared in a library it has
no source for, with handlers of its own, and the library raises them — and
because the method that raises an event is private, "only the declaring type may
raise it" holds across the boundary without anything checking it there.

Reference counting reaches across too: the object is allocated through the
library's own TypeInfo, so it is destroyed by the destructor the library
compiled for its layout, when the consumer drops the last reference.

**Both sides link one runtime**, which is what makes that count one count. They
share an allocator and a C stdio buffer as well, so what a library prints
interleaves with its consumer's output in the order the two of them wrote it.
The compiler builds `stainless-rt` once and copies it beside each binary, so
`build/` ends up holding it next to the library and the program.

Generics and classes implementing interfaces do not cross, and the compiler says
so where the library is built rather than leaving the consumer to find a public
type missing. See [§8.4 of the spec](spec/08-interop-libraries.md#84-a-stainless-library-consumed-by-stainless) for why each is a
decision about the language rather than a gap in the metadata.

---

<sub>[&larr; README](../README.md) &nbsp;&middot;&nbsp;
[Packages &rarr;](packages.md)</sub>
