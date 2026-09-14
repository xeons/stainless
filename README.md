# Stainless

> **An extreme rough draft.** Stainless is an experiment, not a product.
> Nothing here is stable, plenty is missing, and the parts that work were
> reached by trying things rather than by planning them.

An experimental **general-purpose** language reaching for **the performance of
C and C++ with the flexibility of something higher level**. It goes low enough
to lay out a struct a C header will recognise byte for byte, and high enough to
write the application on top of it in the same language.

It is a deliberate mongrel. The syntax, namespaces and attributes come from C#;
the value semantics, layout and ABI from C and C++; reference counting and the
borrowed-parameter convention from Swift; monomorphized generics from C++ and
Rust; variants from the ML family by way of Swift and Rust; runtime metadata as
plain tables in the binary from Swift and Go. Where those ideas disagree, the
choice is written down in the docs along with the reason, because the
interesting part of the experiment is which combinations hold together.

```csharp
module Hello;

extern "C" int puts(byte* text);

int Main() {
    puts("Hello from Stainless.");
    return 0;
}
```

```
$ stainless run samples/hello.sl
ok: built samples\Hello.exe in 146 ms

Hello from Stainless.
```

That is a real native executable. No VM, no JIT, no assembly loader, no GC.

---

## Why it exists

To build a language I would actually enjoy writing in — the way Visual Basic 6
was enjoyable — and then to find out which borrowed ideas hold together once
they are in the same room.

- **Simple enough to hold in your head.** You should not need a PhD in computer
  science to understand the whole language. Where a feature would buy power at
  the cost of being explainable, it is usually left out.
- **Take what is good from other languages.** Adopt what works, put it next to
  the rest, and see what survives the contact. Where two borrowed ideas
  disagree, the choice and its reason are written down.
- **Natively compiled and as efficient as it can be.** No VM, no JIT, no
  tracing collector. What you write is what runs.
- **Few opinions, some guardrails.** No rigid house style and no design pattern
  the language insists on — but it will still stop you writing the genuinely
  bad thing, and say why.
- **Shed C and C++'s legacy baggage; keep the good parts.** Headers, include
  guards, macros and the ODR are gone. The layout rules, the ABI and the
  performance are not.
- **C and C++ are not obsolete, and not "unsafe".** They are what most of the
  world is written in, so interop is a first-class goal rather than an escape
  hatch: no marshalling layer, no generated glue, no bindings.
- **No `unsafe` keyword.** The concept is dropped. Any code can be unsafe if it
  is written badly enough, and a keyword that pretends otherwise mostly moves
  the argument rather than settling it.
- **No exceptions.** Exception handling is obnoxious to write, annoying to
  read, and often expensive. A function that can fail says so in its return
  type instead, and the compiler will not let the answer be read before the
  question is asked.
- **Cross-platform and modular.** Windows and Linux are both built and tested;
  x64, 32-bit x86 and ARM64 are all targets. The platform bindings are source
  you opt into rather than something every program carries, and what a binary
  never reaches the linker throws away — hello-world links no standard library
  function at all.

---

## The four ideas it is built around

**1. No header files.** Declarations are order-independent within *and across*
modules, so there are no include guards, no forward declarations, no ODR
violations, no `#include` and no macros. Every name in the program is resolved
before any body is checked — the thing a header file exists to fake. `#if` and
its relatives do exist, as in C#, because choosing between two platforms is a
different question from finding a declaration.

```csharp
int Main() {
    return Later();     // fine; Later is declared below
}

int Later() { return 0; }
```

Modules work like C# namespaces. Every file names its own with `module
Shop.Catalog;` — never inferred from the path, so moving a file changes nothing
— and several files may name the same module and merge into it. `public` decides
what other modules may touch; an unmarked declaration is visible throughout its
module and nowhere else, the way C#'s `internal` works. See
[§1 of the spec](docs/spec/01-modules.md) and [samples/shop](samples/shop) for a
worked multi-file example.

**2. Native code via LLVM.** The compiler emits textual LLVM IR and hands it to
clang. Startup cost is a C program's startup cost.

**3. ARC, not GC.** `class` types are reference counted and destroyed
deterministically. No collector, no pauses, no tracing thread — the entire
runtime is [sixteen small C files](runtime/): reference counting, text, UTF-16,
a string builder, arrays, reflection metadata, console output, threads,
ordering and hashing, files, sockets, processes, the environment, time, random
numbers and COM.

**4. C and C++ ABI compatible.** A `struct` of plain data *is* a C struct, byte
for byte. `extern "C"` calls into C and `export "C"` exposes functions back,
with no bindings, marshalling, or generated glue. Even `String` hands its bytes
to C without a copy. `extern "C++"` and `export "C++"` do the same for C++ free
functions, by mangling their signatures the way the target's compiler does —
Itanium for gcc and clang, Microsoft's for MSVC. A struct that holds a reference
is counted rather than copied raw, and the compiler stops that one at either
boundary.

---

## A taste

If you write C#, you can read Stainless on sight. The differences are all
underneath: values instead of objects, refcounts instead of a collector, a
linker instead of an assembly loader.

```csharp
module App.Shapes;

// A value type. Copied by assignment, laid out exactly like the C struct.
public struct Point {
    public double X;
    public double Y;
}

// A value that is exactly one of its cases, and says which. 24 bytes, not 32:
// the payloads overlap, and nothing allocates.
public variant Shape {
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

double Area(Shape shape) {
    switch (shape) {                      // covers every case, so no 'default'
        case Circle c: return 3.14159 * c.Radius * c.Radius;
        case Rect r:   return r.Width * r.Height;
        case Empty:    return 0.0;
    }
}

// No 'throw' and no unwinding. A function that can fail says so, and the
// answer cannot be read before the question is asked.
Result<Config, IOError> Load(String path) {
    return Ok(Parse(try File.ReadAllText(path)));
}

// Callable from C as plain 'sl_scale'.
export "C" Point sl_scale(Point p, double factor) {
    Point result;
    result.X = p.X * factor;
    result.Y = p.Y * factor;
    return result;
}
```

**[A tour of the language](docs/tour.md)** is the rest of it — variants,
failure, text, generics, slices, collections, reflection, properties,
inheritance, interfaces, layout control, bit-fields, unions and the Win32
bindings — in one readable pass.

---

## Getting started

Requires the [.NET 10 SDK](https://dotnet.microsoft.com/download) and
[LLVM/clang](https://llvm.org) — `winget install LLVM.LLVM` on Windows,
`apt install clang` on Debian and Ubuntu.

```
dotnet build Stainless.slnx
dotnet run --project tests/Stainless.Tests      # 289 end-to-end tests
dotnet test tests/Stainless.UnitTests           # 848 compiler unit tests
```

Then run something:

```
stainless run samples/hello.sl
stainless run samples/tour        # every feature, printing what it did
```

[samples/tour](samples/tour) is one program that uses every feature the
documentation describes, so running it says whether the docs are still true and
not only whether they still build.

[Building and internals](docs/internals.md) has the rest: what the two test
suites each prove, which platforms are covered, and how the compiler is put
together.

---

## Documentation

| | |
|---|---|
| **[A tour of the language](docs/tour.md)** | The guided pass. Start here. |
| **[Language specification](docs/spec/index.md)** | The exhaustive one, in ten chapters. |
| **[What is implemented](docs/status.md)** | What works today, and what does not exist yet. |
| **[The command line](docs/cli.md)** | Every command and flag, projects, and building libraries. |
| **[Standard library reference](docs/stdlib/index.md)** | One page per module, generated from the source. |
| **[ABI notes](docs/abi.md)** | Layout, object headers, mangling, calling convention. |
| **[Concurrency](docs/concurrency.md)** | Threading as it is, and where it is going. |
| **[Packages](docs/packages.md)** | `stainless.json`, versions, resolution and the lock file. |
| **[Building and internals](docs/internals.md)** | Building, testing, and how the compiler works. |
| **[TODO.md](TODO.md)** | What is being worked on next, and the known bugs. |

Beyond the language itself:

| | |
|---|---|
| **[forms/](forms/README.md)** | A GUI framework: the LCL's architecture, C#'s names, on Win32 and GTK 3. |
| **[ide/](ide/README.md)** | An IDE for Stainless, written in Stainless: a syntax-highlighting editor on `forms/`. |
| **[bindings/win32/](bindings/win32/README.md)** | The Windows API, in two layers. |
| **[bindings/gtk/](bindings/gtk/README.md)** | GTK 3, and a widget class hierarchy over it. |
| **[bindings/linux/](bindings/linux/README.md)** | The Linux system calls, declared and nothing else. |
| **[samples/](samples/)** | Example programs, including [the tour](samples/tour), [a package](samples/packages) and [a COM server called from C++](samples/com). |

---

## Repository layout

```
docs/                  the specification, ABI, concurrency, packages, the tour
docs/spec/             the language specification, one file per chapter
docs/stdlib/           the standard library reference, generated by 'stainless doc'
runtime/               the runtime, split by feature, embedded in the compiler
stdlib/                the standard library written in Stainless, also embedded
bindings/win32/        the Windows API, compiled only by a program that asks
bindings/linux/        the Linux system calls, on the same terms
bindings/gtk/          GTK 3, and a widget layer over it
forms/                 a GUI framework: the LCL's architecture, C#'s names,
                       on Win32 and GTK 3 behind one seam
ide/                   an IDE for Stainless, written in Stainless
samples/               example programs
src/Stainless.Compiler front end, binder, emitter, driver
src/Stainless.Cli      the `stainless` command
tests/cases/           one directory per end-to-end test
tests/Stainless.Tests  the end-to-end runner
tests/Stainless.UnitTests  the compiler's own tests
```

## License

Stainless is free software under the
[GNU General Public License, version 3](LICENSE).

The runtime library — everything in [runtime/](runtime/), [stdlib/](stdlib/)
and [bindings/](bindings/) — is GPLv3 **with an additional permission**
([LICENSE.RUNTIME](LICENSE.RUNTIME)). It is compiled into every binary the
compiler produces, so without that permission every program anyone wrote in
Stainless would have to be GPLv3 as well. With it:

- **What you write in Stainless is yours.** Licence it however you like, and
  ship it closed if you want to.
- **Changes to the compiler or the runtime are not.** Fork it, modify it and
  distribute the result, and the source goes with it under GPLv3.

The copyleft is on the compiler, not on what you build with it — the same
arrangement GCC uses for `libgcc`.

The example programs in [samples/](samples/) and the test programs in
[tests/cases/](tests/cases/) are [Zero-Clause BSD](samples/LICENSE) instead,
which asks for nothing at all: no attribution, no notice, no copyleft. They
exist to be copied, and the runtime exception would not have covered that — it
permits combining the *runtime* with your code, whereas lifting a sample means
copying GPL'd source into your own program.

The exception is modelled closely on the
[GNU GCC Runtime Library Exception 3.1](https://www.gnu.org/licenses/gcc-exception-3.1.html),
using the same structure and terms of art, but it is a grant made by this
project rather than that document: the GCC text conditions its grant on an
"Eligible Compilation Process" defined in terms of GCC, and may not be
modified. It has not been reviewed by a lawyer — see the note at the top of
[LICENSE.RUNTIME](LICENSE.RUNTIME).
