# Stainless

A systems programming language with **C++'s performance model and C#'s syntax**.

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
ok: built samples\hello.exe in 146 ms

Hello from Stainless.
```

That is a real native executable. No VM, no JIT, no assembly loader, no GC.

---

## The four pillars

**1. No header files.** One file is one module. Declarations are order-independent
within *and across* modules, so there are no include guards, no forward
declarations, no ODR violations, and no preprocessor. A module's public surface
is derived from its own source — the thing a header file exists to fake.

```csharp
int Main() {
    return Later();     // fine; Later is declared below
}

int Later() { return 0; }
```

**2. Native code via LLVM.** The compiler emits textual LLVM IR and hands it to
clang. Startup cost is a C program's startup cost.

**3. ARC, not GC.** `class` types are reference counted and destroyed
deterministically. No collector, no pauses, no tracing thread — the entire
runtime is [one 80-line C file](runtime/stainless_rt.c).

**4. C/C++ ABI compatible.** A Stainless `struct` *is* a C struct, byte for byte.
`extern "C"` calls into C and `export "C"` exposes functions back, with no
bindings, marshalling, or generated glue. Even `String` hands its bytes to C
without a copy.

---

## Language at a glance

If you write C#, you can read Stainless on sight. The differences are all
underneath: values instead of objects, refcounts instead of a collector, a
linker instead of an assembly loader.

```csharp
module App.Shapes;

import App.Math;

extern "C" int printf(byte* format, ...);

// A value type. Copied by assignment, laid out exactly like the C struct.
public struct Point {
    public double X;
    public double Y;

    public double Length2() { return X * X + Y * Y; }
}

// A reference type. Heap allocated, reference counted, destroyed at zero.
public class Buffer {
    byte* data;
    nuint length;

    public Buffer(nuint n) {
        data = Allocate(n);
        length = n;
    }

    ~Buffer() { Free(data); }

    public nuint Length() { return length; }
}

// Callable from C as plain `sl_scale`.
export "C" Point sl_scale(Point p, double factor) {
    Point result;
    result.X = p.X * factor;
    result.Y = p.Y * factor;
    return result;
}
```

### Text

One string type. `String` is immutable, reference counted, and always UTF-8 —
no `AnsiString`/`UnicodeString` split, and no implicit transcoding anywhere.

```csharp
import Standard.Console;

String greeting = "Hello";
String message  = greeting + ", " + "Stainless" + "!";

Console.WriteLine(message);
Console.WriteLine(Text.FromInteger(message.ByteLength()));

bool matched = message == "Hello, Stainless!";   // compares by value
```

The bytes live inline, right after the object header, and are always NUL
terminated. So length is O(1), and handing text to C copies nothing:

```csharp
extern "C" int puts(byte* text);

puts(message.ToPointer());     // zero copy
puts("literals too");          // and a literal never allocates at all
```

A literal is emitted as a static constant with an *immortal* reference count,
which `retain` and `release` skip — so `"Hello"` costs nothing at run time.
Wide platform APIs get an explicit conversion, never an implicit one:

```csharp
var wide = message.ToUtf16();                  // owned, NUL terminated, ARC'd
MessageBoxW(0, wide.ToPointer(), null, 0);
```

### Interfaces

```csharp
public interface Shape {
    double Area();
    String Describe();
}

public class Circle : Shape {
    double radius;
    public Circle(double r) { radius = r; }
    public double Area() { return 3.14159 * radius * radius; }
    public String Describe() { return "circle"; }
}

double TotalArea(Shape a, Shape b) { return a.Area() + b.Area(); }
```

An interface reference **is an ordinary object pointer** — the vtable is reached
through the object rather than carried beside it. So `Shape?`, `weak Shape?`,
ARC and the calling convention all behave exactly as they do for a class, and a
class can implement any number of interfaces at no per-object cost. Dispatch is
four constant-offset loads with no search and no branch.

| | `struct` | `class` | `interface` |
|---|---|---|---|
| Storage | value, inline | heap | a reference to one |
| Assignment | copies bytes | copies the reference, retains | same as class |
| Lifetime | scope | reference count reaches zero | same as class |
| Destructor | no | yes, `~Name()` | n/a |
| C compatible | **yes, bit-identical** | pointer-compatible only | pointer-compatible only |

Primitive names and sizes match C# exactly: `sbyte short int long nint`,
`byte ushort uint ulong nuint`, `float double`, `bool`, `char`, `void`.
Pointers are `T*`, optional class references are `C?`, and `weak C?` breaks
cycles.

Full details: **[docs/language-spec.md](docs/language-spec.md)** and
**[docs/abi.md](docs/abi.md)**.

---

## Building the compiler

Requires the [.NET 10 SDK](https://dotnet.microsoft.com/download) and
[LLVM/clang](https://llvm.org) (`winget install LLVM.LLVM`).

```
dotnet build Stainless.slnx
dotnet run --project tests/Stainless.Tests      # 29 end-to-end tests
```

The compiler finds clang on `PATH`, at `C:\Program Files\LLVM\bin`, or wherever
`STAINLESS_CLANG` points.

## Using it

```
stainless build <paths...>     compile to a native executable
stainless run   <paths...>     compile, then run it
stainless emit-ir <paths...>   print the generated LLVM IR

  -o, --out <path>   output executable
  -O<0-3>            optimization level (default -O2)
  --keep             keep the generated .ll
```

Paths may be `.sl` files or directories (searched recursively), in any order.
C sources and object files can be listed alongside them and are passed straight
to the linker:

```
stainless run samples/interop/interop.sl samples/interop/native.c
```

---

## How it works

```
  .sl sources
      |
      v   Lexer -> Parser                       one file at a time, no #include
   syntax trees
      |
      v   Binder, in six whole-program passes:
      |     1. declare modules       4. resolve signatures and field types
      |     2. declare types         5. compute C-compatible layouts
      |     3. resolve imports       6. check bodies
      |
      |   Nothing may depend on declaration order, so every name in the
      |   program is known before any body is checked. That single rule is
      |   what lets header files go away.
      v
   bound tree  (fully typed; ARC and ABI decisions already made)
      |
      v   LlvmEmitter + Win64Abi
   textual LLVM IR
      |
      v   clang
   native .exe
```

| Component | Role |
|---|---|
| [Syntax/Lexer.cs](src/Stainless.Compiler/Syntax/Lexer.cs) | tokens; no preprocessor |
| [Syntax/Parser.cs](src/Stainless.Compiler/Syntax/Parser.cs) | recursive descent + precedence climbing |
| [Binding/Binder.cs](src/Stainless.Compiler/Binding/Binder.cs) | the six passes, type checking, conversions |
| [Binding/TypeSystem.cs](src/Stainless.Compiler/Binding/TypeSystem.cs) | types and C-rule layout |
| [Binding/Mangler.cs](src/Stainless.Compiler/Binding/Mangler.cs) | symbol names |
| [Emit/Win64Abi.cs](src/Stainless.Compiler/Emit/Win64Abi.cs) | struct passing: register, `byval`, or `sret` |
| [Emit/LlvmEmitter.cs](src/Stainless.Compiler/Emit/LlvmEmitter.cs) | IR, plus retain/release insertion |
| [runtime/stainless_rt.c](runtime/stainless_rt.c) | the whole runtime |

### Why textual IR

Emitting `.ll` text rather than calling the LLVM C API means the compiler has no
native dependency, builds anywhere .NET does, and produces output you can read
and diff. `stainless emit-ir hello.sl` prints it.

### Why ownership works the way it does

Stainless uses **borrowed parameters and owned returns**, the same choice Swift
makes, because it removes most retain/release traffic: passing a reference to a
function costs nothing. Locals and fields own their references; assigning to one
retains the new value *before* releasing the old, so self-assignment is safe.

---

## What works today

Everything below is covered by [the test suite](tests/cases).

- Modules, imports, aliases, `public` visibility, full order independence
- `struct` with fields and methods; exact C layout; value copy semantics
- `class` with fields, constructors, destructors, methods; ARC with correct
  nested destruction
- `extern "C"` and `export "C"`, including variadics and structs by value in
  both directions
- Win64 struct ABI: register coercion, `byval`, `sret`
- `if` / `while` / `for` / `break` / `continue` / `return`, recursion
- Full operator set with C# precedence, short-circuit `&&` and `||`
- `var`, `const`, explicit locals, compound assignment
- `String`: UTF-8, immutable, reference counted, `+` and `==`, zero-copy
  `ToPointer()`, `ToUtf16()`, and literals that never allocate
- `StringBuilder`: mutable text with amortised O(1) appends
- `interface`: multiple implementation, dynamic dispatch, checked at compile time
- `Standard.Text` (imported everywhere) and `Standard.Console`
- Raw pointers, `sizeof`, casts, `new`, `this`
- Integer literals that fit convert implicitly, as in C#
- Diagnostics with source excerpts and caret runs

## What does not exist yet

Being straight about the edges, roughly in the order they are worth adding:

- **No arrays.** Indexing works on pointers only.
- **`String` has a thin API.** No `IndexOf`, `Split`, `Trim`, case mapping or
  formatting; `Substring` counts bytes, not characters, so it can slice a
  multi-byte character in half.
- **No flow narrowing for `C?`.** Optionals can be stored, compared to `null`,
  and unwrapped with an explicit cast, but `if (x != null)` does not yet make
  `x` usable as non-optional. `weak` has the same gap, though the runtime side
  is fully implemented.
- **No class inheritance and no generics.** Interfaces exist, but they do not
  extend one another, and there is no downcast from an interface back to a
  class.
- **No overloading by parameter type on methods** (module-level functions do
  overload).
- **Unoptimized ARC.** Retain/release traffic is correct but redundant; a
  +0/+1 dataflow pass would remove most of it.
- **Non-atomic reference counts.** Single-threaded only.
- **Win64 only** for struct passing; the SysV classifier is not written.
- **Whole-program compilation.** Modules make separate compilation possible, but
  the driver does not do it yet.
- `Main` takes no arguments. Field initializers are rejected — assign in a
  constructor. `delete` is reserved but unused.

## Repository layout

```
docs/                  language specification and ABI
runtime/               the ARC runtime (one C file, embedded in the compiler)
samples/               example programs
src/Stainless.Compiler front end, binder, emitter, driver
src/Stainless.Cli      the `stainless` command
tests/cases/           one directory per end-to-end test
tests/Stainless.Tests  the test runner
```
