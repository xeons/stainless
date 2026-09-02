# Stainless

> **An extreme rough draft.** Stainless is an experiment, not a product.
> Nothing here is stable, plenty is missing, and the parts that work were
> reached by trying things rather than by planning them. Vibe coded with Claude.

A systems language reaching for **the performance of C and C++ with the
flexibility of something higher level**.

It is a deliberate mongrel. The syntax, namespaces and attributes come from C#;
the value semantics, layout and ABI from C and C++; reference counting and the
borrowed-parameter convention from Swift; monomorphized generics from C++ and
Rust; runtime metadata as plain tables in the binary from Swift and Go. Where
those ideas disagree, the choice is written down in the docs along with the
reason, because the interesting part of the experiment is which combinations
hold together.

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

## The four ideas it is built around

**1. No header files.** Declarations are order-independent within *and across*
modules, so there are no include guards, no forward declarations, no ODR
violations, and no preprocessor. Every name in the program is resolved before
any body is checked — the thing a header file exists to fake.

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
module and nowhere else, the way C#'s `internal` works. `import` only shortens
names, since a fully qualified name reaches any public member without one, and
imports are per file as `using` is. See [§1 of the spec](docs/language-spec.md)
and [samples/shop](samples/shop) for a worked multi-file example.

**2. Native code via LLVM.** The compiler emits textual LLVM IR and hands it to
clang. Startup cost is a C program's startup cost.

**3. ARC, not GC.** `class` types are reference counted and destroyed
deterministically. No collector, no pauses, no tracing thread — the entire
runtime is [seven small C files](runtime/): reference counting, text, UTF-16,
a string builder, arrays, reflection metadata, and console output.

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

### Arrays and generics

```csharp
var numbers = new int[5];
numbers[2] = 9;                     // bounds checked, unsigned compare

public class Box<T> {
    T value;
    public Box(T initial) { value = initial; }
    public T Get() { return value; }
}

var boxed = new Box<String>("text");    // a real type, compiled for String
```

Generics **monomorphize**: `Box<int>` and `Box<String>` are two separate types
with no boxing and no indirection, so `Box<int>` stores a bare `int`. Type
arguments on a call are inferred from the values passed.

Type parameters can be constrained by interface, including F-bounded ones:

```csharp
public interface IComparable<T> { int CompareTo(T other); }

public class Money : IComparable<Money> { ... }

T Largest<T>(T[] values) where T : IComparable<T> { ... }
public class Ranked<T> where T : IComparable<T>, IDescribable { ... }
```

A violated constraint is caught where the generic is instantiated:

```
error[SL0328]: 'Half' cannot be used as 'T' in 'Ranked' because it does not
implement 'IDescribable'; it implements 'IComparable<Half>'
```

### Collections

`Standard.Collections` is written in Stainless and compiled with your program,
so importing it costs nothing until you instantiate something:

```csharp
import Standard.Collections;

public class Money : IComparable<Money>, IEquatable<Money> {
    public int  CompareTo(Money other) { ... }
    public bool EqualTo(Money other)   { ... }
}

var prices = new List<Money>();
prices.Add(new Money(250));

Sort(prices);              // where T : IComparable<T>
Largest(prices);           // takes an IReadOnlyList<T>, so it cannot mutate
```

`IList<T>` extends `IReadOnlyList<T>`, and interfaces are named with a leading
`I` as in C#.

### Attributes and reflection

Reflection is not a managed-language feature — it is **tables in the binary**,
the way Swift and Go do it. A type carries field metadata only when it asks:

```csharp
public attribute JsonName { String Name; }
public attribute JsonIgnore { }

[Reflect]
public class Person {
    [JsonName("full_name")] public String Name;
    [JsonName("age")]       public int    Years;
    [JsonIgnore]            public int    Internal;
}
```

`typeof(T)` is a constant handle to that data, so one serializer covers every
reflected type:

```csharp
public String ToJson<T>(T value) {
    var type = typeof(T);
    for (nuint i = 0; i < type.FieldCount(); i = i + 1) {
        var field = type.FieldAt(i);
        if (field.Has("JsonIgnore")) { continue; }
        ...
    }
}
```

```
{"full_name":"Ada Lovelace","age":36,"Active":true,"Rating":9.5}
```

Attribute arguments must be constants, since they are written into the binary.
Types without `[Reflect]` emit nothing, and `typeof` on them is an error.

### Interfaces

```csharp
public interface IShape {
    double Area();
    String Describe();
}

public class Circle : IShape {
    double radius;
    public Circle(double r) { radius = r; }
    public double Area() { return 3.14159 * radius * radius; }
    public String Describe() { return "circle"; }
}

double TotalArea(IShape a, IShape b) { return a.Area() + b.Area(); }
```

An interface reference **is an ordinary object pointer** — the vtable is reached
through the object rather than carried beside it. So `IShape?`, `weak IShape?`,
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
dotnet run --project tests/Stainless.Tests      # 48 end-to-end tests
```

The compiler finds clang on `PATH`, at `C:\Program Files\LLVM\bin`, or wherever
`STAINLESS_CLANG` points.

## Using it

```
stainless build <paths...>     compile to a native executable
stainless run   <paths...>     compile, then run it
stainless emit-ir <paths...>   print the generated LLVM IR

  -o, --out <path>   output file
  --shared           build a shared library instead of an executable
  --header <path>    write a C header for the exported surface
  -O<0-3>            optimization level (default -O2)
  --keep             keep the generated .ll
```

Paths may be `.sl` files or directories (searched recursively), in any order.
C sources and object files can be listed alongside them and are passed straight
to the linker:

```
stainless run samples/interop/interop.sl samples/interop/native.c
```

### Building a library

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
own copy of the runtime. Pass C types across the boundary and keep managed
objects on one side of it.

---

## How it works

```
  .sl sources
      |
      v   Lexer -> Parser                       one file at a time, no #include
   syntax trees
      |
      v   Binder, in nine whole-program passes:
      |     1. declare modules        6. fold attributes to constants
      |     2. declare types          7. compute C-compatible layouts
      |     3. resolve imports        8. check bodies
      |     4. resolve signatures     9. check whatever those instantiated
      |        and field types
      |     5. check that classes implement what they claim
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
| [Binding/Binder.cs](src/Stainless.Compiler/Binding/Binder.cs) | the nine passes, type checking, conversions, generic instantiation |
| [Binding/TypeSystem.cs](src/Stainless.Compiler/Binding/TypeSystem.cs) | types and C-rule layout |
| [Binding/Builtins.cs](src/Stainless.Compiler/Binding/Builtins.cs) | `String`, `StringBuilder` and the rest of `Standard.Text` |
| [Binding/Mangler.cs](src/Stainless.Compiler/Binding/Mangler.cs) | symbol names |
| [Emit/Win64Abi.cs](src/Stainless.Compiler/Emit/Win64Abi.cs) | struct passing: register, `byval`, or `sret` |
| [Emit/LlvmEmitter.cs](src/Stainless.Compiler/Emit/LlvmEmitter.cs) | IR, retain/release insertion, metadata tables |
| [Emit/CHeaderWriter.cs](src/Stainless.Compiler/Emit/CHeaderWriter.cs) | the C header for a shared library |
| [runtime/](runtime/) | the whole runtime, split by feature |
| [stdlib/](stdlib/) | the standard library, written in Stainless |

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

- Modules like C# namespaces: several files may share one, imports are per file,
  `public` exports and an unmarked declaration is module-wide
- Aliases, qualified names without an import, full order independence
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
- `T[]`: counted arrays, always bounds checked, elements released with the array
- Generics: generic classes, interfaces and functions, monomorphized, with
  inference at call sites and interface constraints (`where T : IComparable<T>`)
- Interfaces: several per class, dynamic dispatch, checked at compile time, and
  extending one another with free conversion to the base
- `Standard.Collections`: `IComparable<T>`, `IEquatable<T>`, `IReadOnlyList<T>`,
  `IList<T>`, `List<T>`, and `Sort`/`Largest`/`Smallest`/`IndexOf`
- `StringBuilder`: mutable text with amortised O(1) appends
- `Standard.Text` (imported everywhere), `Standard.Console`, `Standard.Reflection`
- Raw pointers, `sizeof`, `typeof`, casts, `new`, `this`
- Integer literals that fit convert implicitly, as in C#
- Shared libraries: `--shared` with a generated C header, and an export table
  containing exactly the `export "C"` functions
- Attributes and opt-in reflection: field names, offsets, kinds and attribute
  values readable at run time, from `const` tables in the binary
- Diagnostics with source excerpts and caret runs

## What does not exist yet

Being straight about the edges, roughly in the order they are worth adding:

- **Constraints are checked at the instantiation, not the declaration.**
  `where T : IShape` is verified where the generic is used, but the body is
  still checked per instantiation, so an unused template is never checked and
  a mistake inside one is reported against its use. Definition-site checking
  would need constraints on operators too, which is a larger step.
- **Only interfaces constrain.** No `where T : SomeClass`, no `class`/`struct`
  kind constraints, no `new()`.
- **Type arguments cannot be written at a call.** `Pick<int>(...)` is rejected,
  because `<` in expression position is ambiguous with less-than; inference
  reads argument types only.
- **No generic methods**, only generic types and generic free functions.
- **No `foreach`, `switch`, or `enum`.** Iterating a list means an index and a
  `for`; there is no pattern matching and no enumerated type.
- **No exceptions or error type.** A failure aborts through the runtime; there
  is no way to recover from one.
- **`String` has a thin API.** No `IndexOf`, `Split`, `Trim`, case mapping or
  formatting; `Substring` counts bytes, not characters, so it can slice a
  multi-byte character in half.
- **No flow narrowing for `C?`.** Optionals can be stored, compared to `null`,
  and unwrapped with an explicit cast, but `if (x != null)` does not yet make
  `x` usable as non-optional. `weak` has the same gap, though the runtime side
  is fully implemented.
- **No class inheritance.** Interfaces extend one another, but classes do not,
  and there is no downcast from an interface back to a class.
- **Reflection reads but does not write.** Fields can be read from an instance,
  not set, so a deserializer cannot be written yet; nor can an instance be made
  from a `Type`. Methods and interfaces carry no metadata — fields only.
- **No overloading by parameter type on methods** (module-level functions do
  overload).
- **Unoptimized ARC.** Retain/release traffic is correct but redundant; a
  +0/+1 dataflow pass would remove most of it.
- **Non-atomic reference counts.** Single-threaded only.
- **Win64 only** for struct passing; the SysV classifier is not written.
- **Whole-program compilation.** Modules make separate compilation possible, but
  the driver does not do it yet, so a Stainless library cannot be consumed by
  Stainless — only by C.
- **The runtime is linked statically into every binary.** Managed objects
  therefore should not cross a shared-library boundary; C types are fine.
- `Main` takes no arguments. Field initializers are rejected — assign in a
  constructor. `delete` is reserved but unused.

## Repository layout

```
docs/                  language specification and ABI
runtime/               the runtime, split by feature, embedded in the compiler
stdlib/                the standard library written in Stainless, also embedded
samples/               example programs
src/Stainless.Compiler front end, binder, emitter, driver
src/Stainless.Cli      the `stainless` command
tests/cases/           one directory per end-to-end test
tests/Stainless.Tests  the test runner
```
