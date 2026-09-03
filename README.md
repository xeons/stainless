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
runtime is [eight small C files](runtime/): reference counting, text, UTF-16,
a string builder, arrays, reflection metadata, console output, and threads.

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

### Properties

```csharp
public class Person {
    public String Name { get; set; }         // automatic: the compiler owns the storage
    public int Visits { get; private set; }  // read anywhere, write in this module
    public int Id { get; }                   // set by a constructor, then fixed

    public String Label => Name + "#" + Text.FromInteger(Id);   // computed

    public Person(String name, int id) { Name = name; Id = id; Visits = 0; }
    public void Visit() { Visits = Visits + 1; }
}
```

A property is **a pair of methods that reads like a field**, and that is the
whole implementation: `get_Name` and `set_Name` are ordinary methods, so a
property costs nothing new in the ABI, dispatches through an interface the way
a method does, and comes out of a generic instantiation with everything else.
Written bare, `{ get; set; }` also generates the field to keep the value in —
laid out, destroyed and reflected like any other, but with no name the source
can reach, because the property is that name.

Written out, an accessor names storage the type already has, with a block body
or `=>` and an expression:

```csharp
public int Fahrenheit {
    get { return celsius * 9 / 5 + 32; }
    set { celsius = (value - 32) * 5 / 9; }
}
```

### Interfaces

```csharp
public interface IShape {
    double Area();
    String Describe();
    String Name { get; }        // one vtable slot per accessor
}

public class Circle : IShape {
    double radius;
    public Circle(double r) { radius = r; }
    public double Area() { return 3.14159 * radius * radius; }
    public String Describe() { return "circle"; }
    public String Name { get; set; }
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

Full details: **[docs/language-spec.md](docs/language-spec.md)**,
**[docs/abi.md](docs/abi.md)** and, for where threading is going,
**[docs/concurrency.md](docs/concurrency.md)**.

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
- Properties, on classes, structs and interfaces: `{ get; set; }` with a
  compiler-generated backing field, `{ get; private set; }`, get-only ones a
  constructor fills in, and written accessors with block or `=>` bodies. They
  lower to a pair of ordinary methods, so an interface property dispatches like
  any other member
- `extern "C"` and `export "C"`, including variadics and structs by value in
  both directions
- Win64 struct ABI: register coercion, `byval`, `sret`
- `if` / `while` / `for` / `foreach` / `break` / `continue` / `return`, recursion
- `switch` over integers, `char`, `bool`, enums and `String`, with stacked
  labels and no fall-through. An ordinal switch is one LLVM `switch`, so a jump
  table is LLVM's decision rather than the programmer's; `break` belongs to the
  switch while `continue` passes through it to the enclosing loop
- `parallel { spawn f(x); }` — a fork-join scope whose closing brace waits, so
  a job writes its result straight into the parent's local; and `parallel for`,
  which splits a counted loop across the pool
- `static readonly` module storage, initialized before `Main` in an order the
  compiler computes from the dependency graph — no lazy guard, and a compile
  error on a cycle. There is no `static` without `readonly`
- A checked rule for what may cross a thread: plain data, a `String`, a
  `[Shared]` type, or an array of plain data. Anything else is rejected at the
  `spawn`, the `parallel for` capture, or the static that would share it
- Full operator set with C# precedence, short-circuit `&&` and `||`, and the
  conditional `a ? b : c`
- `var`, `const`, explicit locals, compound assignment
- `String`: UTF-8, immutable, reference counted, `+` and `==`, zero-copy
  `ToPointer()`, `ToUtf16()`, and literals that never allocate
- `T[]`: counted arrays, always bounds checked, elements released with the array
- Generics: generic classes, interfaces, functions and methods, monomorphized, with
  inference at call sites and interface constraints (`where T : IComparable<T>`)
- `enum`, strongly typed: a distinct type over an integer that never converts
  implicitly in either direction, with an optional underlying type
  (`enum Level : byte`)
- `[Flags]` enums: `|`, `&`, `^` and `~` on an enum whose members are bits,
  producing that same enum rather than its number, plus `HasFlag`. The marker
  needs no import, because it is a rule about enums rather than a library
- `delegate`: a named function pointer, one word, C ABI compatible in both
  directions, and storable in a `struct`
- Lambdas and closures: `value => value * factor` becomes a generated class
  implementing a single-method interface, capturing **by value** so it may
  outlive the scope that built it; a non-capturing one becomes a `delegate`
- `foreach` over arrays and over anything with a `GetEnumerator()`, plus
  `IEnumerable<T>` / `IEnumerator<T>` in `Standard.Collections`
- Interfaces: several per class, dynamic dispatch, checked at compile time, and
  extending one another with free conversion to the base
- `Standard.Collections`: `List<T>`, `Dictionary<K, V>`, `HashSet<T>`,
  `Queue<T>`, `Stack<T>`, `LinkedList<T>` and `SortedList<K, V>`, plus
  `IComparable<T>`, `IEquatable<T>`, `IHashable`, `IReadOnlyList<T>`,
  `IList<T>`, `IEnumerable<T>`, `IEnumerator<T>` and
  `Sort`/`Largest`/`Smallest`/`IndexOf`. Every container is array-backed —
  ARC cannot collect a cycle, so the linked list links by index rather than by
  reference
- Primitives, enums and `String` satisfy `IComparable<T>`, `IEquatable<T>` and
  `IHashable` without declaring it, so `Sort(numbers)` works on a `List<int>`
  and `Dictionary<String, V>` needs nothing extra
- `StringBuilder`: mutable text with amortised O(1) appends
- `Standard.Threading`: `Mutex<T>` and its `Guard<T>` (the lock owns what it
  guards, and a destructor releases it), `AtomicLong`, `AtomicBool`, and
  `TaskScope` for running `Job` delegates on the pool
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
  reads argument types only. That holds for generic methods too, and an
  interface method cannot be generic at all, since dispatch gives it one slot.
- **No pattern matching, and no `switch` expression.** `switch` is the C#
  statement and only that: constant labels, no `goto case`, no exhaustiveness
  requirement on enums.
- **A lambda needs something to be.** It is typed by what it is assigned to, so
  `var f = x => x;` has nothing to infer from. Capture is by value only, and a
  capturing lambda cannot become a `delegate` — a function pointer has nowhere
  to keep what was captured.
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
- **A property is not an indexer, and not initialized where it is declared.**
  There is no `this[i]`, and `{ get; set; } = 5;` is rejected for the same
  reason a field initializer is. `p.X += 1` also needs a receiver that is a
  plain load, since the getter and the setter each evaluate it.
- **Unoptimized ARC.** Retain/release traffic is correct but redundant; a
  +0/+1 dataflow pass would remove most of it.
- **Two thread-safety gaps remain, and both are about lifetimes.** What crosses
  a thread is now checked by type, so an unsynchronized class cannot reach a
  second thread at all. What is still unchecked is how long a borrowed thing
  lives: a `Guard` can outlive the lock it proves, and a job could store an
  array it was only lent. `[Shared]` is also an assertion rather than a proof,
  the same bargain as Rust's `unsafe impl Sync`. Reference counts stay
  non-atomic by design — see [docs/concurrency.md](docs/concurrency.md).
- **No cancellation beyond a shared flag.** An `AtomicBool` a job polls is the
  whole story; a `parallel` block always joins, and always will. See §9 of the
  concurrency notes for what is worth adding and what never will be.
- **Statics are module-level only**, and a `--shared` library cannot have one:
  there is no entry point to initialize it from. No `static` members on a type,
  and no per-thread storage.
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
docs/                  language specification, ABI, concurrency design
runtime/               the runtime, split by feature, embedded in the compiler
stdlib/                the standard library written in Stainless, also embedded
samples/               example programs
src/Stainless.Compiler front end, binder, emitter, driver
src/Stainless.Cli      the `stainless` command
tests/cases/           one directory per end-to-end test
tests/Stainless.Tests  the test runner
```

## License

Stainless is free software under the
[GNU General Public License, version 3](LICENSE).

The runtime library — everything in [runtime/](runtime/) and
[stdlib/](stdlib/) — is GPLv3 **with an additional permission**
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
[tests/cases/](tests/cases/) are [Zero-Clause BSD](samples/LICENSE) instead, which asks for nothing at all: no
attribution, no notice, no copyleft. They exist to be copied, and the runtime
exception would not have covered that — it permits combining the *runtime* with
your code, whereas lifting a sample means copying GPL'd source into your own
program.

The exception is modelled closely on the
[GNU GCC Runtime Library Exception 3.1](https://www.gnu.org/licenses/gcc-exception-3.1.html),
using the same structure and terms of art, but it is a grant made by this
project rather than that document: the GCC text conditions its grant on an
"Eligible Compilation Process" defined in terms of GCC, and may not be
modified. It has not been reviewed by a lawyer — see the note at the top of
[LICENSE.RUNTIME](LICENSE.RUNTIME).
