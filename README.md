# Stainless

> **An extreme rough draft.** Stainless is an experiment, not a product.
> Nothing here is stable, plenty is missing, and the parts that work were
> reached by trying things rather than by planning them. Vibe coded with Claude.

A systems language reaching for **the performance of C and C++ with the
flexibility of something higher level**.

It is a deliberate mongrel. The syntax, namespaces and attributes come from C#;
the value semantics, layout and ABI from C and C++; reference counting and the
borrowed-parameter convention from Swift; monomorphized generics from C++ and
Rust; variants from the ML family by way of Swift and Rust; runtime metadata as
plain tables in the binary from Swift and Go. Where
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
module and nowhere else, the way C#'s `internal` works. `import` only shortens
names, since a fully qualified name reaches any public member without one, and
imports are per file as `using` is. See [§1 of the spec](docs/language-spec.md)
and [samples/shop](samples/shop) for a worked multi-file example.

**2. Native code via LLVM.** The compiler emits textual LLVM IR and hands it to
clang. Startup cost is a C program's startup cost.

**3. ARC, not GC.** `class` types are reference counted and destroyed
deterministically. No collector, no pauses, no tracing thread — the entire
runtime is [ten small C files](runtime/): reference counting, text, UTF-16, a
string builder, arrays, reflection metadata, console output, threads, ordering
and hashing, and files.

**4. C and C++ ABI compatible.** A `struct` of plain data *is* a C struct, byte
for byte. `extern "C"` calls into C and `export "C"` exposes functions back,
with no bindings, marshalling, or generated glue. Even `String` hands its bytes
to C without a copy. `extern "C++"` and `export "C++"` do the same for C++ free
functions, by mangling their signatures the way the target's compiler does —
Itanium for gcc and clang, Microsoft's for MSVC. A struct that holds a reference
is counted rather than copied raw, and the compiler stops that one at either
boundary.

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

### Variants

A `variant` is the choice between its cases. It is a value — a tag and enough
room for the widest case, with the payloads overlapping — so nothing allocates
and `Shape` below is 24 bytes rather than 32.

```csharp
public variant Shape {
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

double Area(Shape shape) {
    switch (shape) {
        case Circle c: return 3.14159 * c.Radius * c.Radius;
        case Rect r:   return r.Width * r.Height;
        case Empty:    return 0.0;
    }
}
```

A switch that covers every case needs no `default`, and is a way out of the
function — `Area` above needs no `return` after it. Leaving one out says which:

```
error[SL0436]: this switch over 'Shape' does not cover 'Rect' and 'Empty'; a
variant is the choice between its cases, so a switch that leaves one out has no
answer for it. Add the case, or a 'default'
```

Outside a switch, `shape.Circle` asks the tag and reading a payload needs the
answer first — the same proof a `Result` has always needed, because that is now
the same machinery:

```csharp
if (shape.Circle) { return shape.Radius; }   // fine
return shape.Radius;                         // error[SL0286]
```

Reference counting asks the tag too. A case may hold a `String`, a class or an
array; copying the variant retains what the case actually present holds, and
dropping it releases the same. The bytes of a case that is not there are never
counted, which is what lets them overlap.

### Failure

There is no `throw` and no unwinding. A function that can fail says so in its
return type, and the compiler will not let the answer be read before the
question is asked.

```csharp
Result<Config, IOError> Load(String path) {
    var text = File.ReadAllText(path);
    if (!text.Ok) { return Fail(text.Error); }     // now the rest holds a value
    return Ok(Parse(text.Value));
}
```

`Result<T, E>` is an ordinary variant — `Ok(T Value)` and `Fail(E Error)` — and
every rule it appears to have is a rule variants have. It allocates nothing, and
only one case is ever present, so a `Result<String, IOError>` is a tag and one
pointer rather than a flag and both halves. `Ok` and `Fail` are written without
type arguments and take their type from where they are going, the way a lambda
takes its type from what it is assigned to. Reading `Value` before checking `Ok`
is a compile error rather than a wrong answer:

```
error[SL0286]: 'read.Value' is not readable here, because nothing has
established that 'read' is 'Ok'; check 'if (read.Ok)' first, or switch over
'read'
```

The check can be an `if`, an early return, a ternary arm, an `&&`, or a switch.
A caller that would rather carry on writes `ValueOr(fallback)` and needs no
check at all.

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

The way back matters as much, because a wide API answers by writing into a
buffer the caller owns rather than by returning an object:

```csharp
GetCurrentDirectoryW(capacity, buffer);
String here = Text.FromUtf16(buffer, units);   // or FromNullTerminatedUtf16
```

Both directions replace anything malformed with U+FFFD, so a `String` is always
valid UTF-8 no matter what the filesystem or the clipboard held.

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

### Slices

A slice names part of an array, as a value. The bounds are half-open, and
either end may be left out.

```csharp
var numbers = new int[6];

int[:] all    = numbers;          // an array is a slice of the whole of itself
int[:] middle = numbers[1:4];     // elements 1, 2 and 3
int[:] tail   = numbers[3:];      // to the end

Sort(numbers[2:5]);               // three of them, in place, nothing copied
```

It is a view rather than a copy: writing through one writes the array it came
from, `Length` is the slice's own, and an index is checked against that. Slicing
a slice narrows it instead of nesting, so a slice is one indirection deep
however many times it has been cut.

Three words — the array, where it starts, how far it runs — and it holds the
array the way any struct field holds a reference. **A slice cannot dangle**: what
it points into is alive for as long as it is.

```csharp
Trace[:] Middle() {
    var traces = new Trace[3];
    ...
    return traces[1:2];           // the array outlives the function
}
```

That is the trade. A slice costs a reference count per copy and is not a value C
can be handed. What it buys is that there are no lifetimes to explain.

### Collections

`Standard.Collections` is written in Stainless and compiled with your program.
A generic costs nothing until you instantiate it; a non-generic declaration is
emitted either way — see the note on dead code below.

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

`List<T>`, `Dictionary<K, V>`, `HashSet<T>`, `Queue<T>`, `Stack<T>`,
`LinkedList<T>` and `SortedList<K, V>`. A primitive, an enum and a `String`
satisfy `IComparable<T>`, `IEquatable<T>` and `IHashable` without declaring it,
which is what lets them be keys and be sorted:

```csharp
var ages = new Dictionary<String, int>();
ages.Set("ada", 36);

var numbers = new List<int>();
Sort(numbers);
```

`IList<T>` extends `IReadOnlyList<T>`, and interfaces are named with a leading
`I` as in C#.

### Passing by reference

A parameter is a copy unless it says otherwise. `ref` passes the caller's
storage and may write it; `in` passes the same storage and promises not to.

```csharp
void Bump(ref int n) { n = n + 1; }
double LengthSquared(in Point p) { return p.X * p.X + p.Y * p.Y; }

int count = 1;
Bump(ref count);              // count is 2
LengthSquared(origin);        // no copy, and origin cannot change
```

`ref` is written at the call too, because a reader should be able to see that
the value may come back changed. A `ref` argument has to name storage and is not
converted on the way in - the callee writes back through it, and a converted
copy would have nowhere to put the result.

Both are exactly a `T*` at the ABI, so they cross a language boundary with
nothing in between:

```csharp
extern "C" double modf(double value, ref double integral);

double whole = 0.0;
double fraction = modf(3.75, ref whole);      // 3 and 0.75
```

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
                            public bool   Active;
                            public double Rating;
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

| | `struct` | `variant` | `class` | `interface` |
|---|---|---|---|---|
| Storage | value, inline | value, inline | heap | a reference to one |
| Assignment | copies bytes | copies the live case | copies the reference, retains | same as class |
| Lifetime | scope | scope | reference count reaches zero | same as class |
| Destructor | no | no | yes, `~Name()` | n/a |
| C compatible | **yes, bit-identical** | **yes, tag plus payload** | pointer-compatible only | pointer-compatible only |

Primitive names and sizes match C# exactly: `sbyte short int long nint`,
`byte ushort uint ulong nuint`, `float double`, `bool`, `char`, `void`.
Pointers are `T*`, optional class references are `C?`, and `weak C?` breaks
cycles.

### Layout control

A struct is laid out by the platform C rules; two markers change them.

```csharp
[Packed]
public struct Wire {          // 6 bytes, not 12: no padding anywhere
    public byte Tag;
    public int Value;
    public byte Trailer;
}

[Align(16)]
public struct Wide {          // always on a 16-byte boundary
    public double X;
    public double Y;
}
```

`[Packed]` is what an on-disk header or a wire format looks like; `[Align(N)]`
raises the alignment and never lowers it, as C's `alignas` does. They combine.
N is capped at 16, which is what `malloc` guarantees for anything the type ends
up inside.

A generated C header states both, and a test compares every size, alignment and
field offset against what the target's C compiler makes of that header.

### Bit-fields

A field may be some of the bits of its type.

```csharp
public struct Header {
    public uint Version : 4;
    public uint Kind    : 4;
    public uint Length  : 24;
}
```

Which bits it gets is the target's decision, and the two C ABIs genuinely
disagree — `struct { int a : 1; byte b : 1; }` is four bytes to gcc and eight to
MSVC. Both rules are implemented, chosen the way the C++ mangler chooses a
scheme, and every size in the test suite was read off clang built for the
matching target. `--abi microsoft|itanium` picks one; the default is the host's.
It reaches name mangling and bit-fields and nothing else — struct passing is
Win64 either way, so this is not a cross-compilation.

A signed bit-field sign-extends from its own width, so a three-bit `int` holding
7 reads back as -1. A bit-field has no address, so it cannot be passed by `ref`.

### Unions

C's, and here for the reason `extern "C"` is here: a great many headers describe
a value that is one of several things and record the choice somewhere else.

```csharp
public union Word {
    public int Signed;
    public uint Unsigned;
    public float Real;
}

Word word;
word.Signed = -1;
word.Unsigned          // 4294967295: the same four bytes, read differently
```

A member may also have no name, which is how the Windows headers write
`SYSTEM_INFO` and `LARGE_INTEGER`. Its members are then reached as though they
belonged to the type outside, so an access path matches the one the header
documents:

```csharp
public struct SystemInfo {
    public union {
        public uint OemId;
        public struct { public ushort Architecture; public ushort Reserved; }
    }
    public uint PageSize;
}

info.Architecture       // the low half of the first word
info.OemId              // the whole of it
```

Every member is at offset zero, and the size and alignment are the ones C
computes. **No member may hold a counted reference** — which one is live is
exactly what a union does not record, so a copy could not know what to retain.
That is the question a union cannot be asked, and it is why `variant` exists:
a variant records the case and will not let you read another.

### Conditional compilation

Directives, as in C#: no macros, no textual substitution, no `#include`.

```csharp
#if WINDOWS
extern "C" void* VirtualAlloc(void* at, nuint size, uint type, uint protect);
#elif UNIX
extern "C" void* mmap(void* at, nuint size, int prot, int flags, int fd, long offset);
#else
#error this platform has no page allocator here
#endif
```

A branch that is not taken is never lexed, so it need not parse — a platform you
have never built on is text until the day you do. `WINDOWS`, `LINUX`, `MACOS`,
`UNIX`, `X64`, `ARM64` and `STAINLESS` are defined for you; everything else
comes from `-D`:

```
stainless build src -D FASTMATH
```

There is one pragma, and it is MSVC's: a file names a library it needs, rather
than every program that compiles it repeating `-l` on the command line.

```csharp
#pragma comment(lib, "user32")
```

### The Win32 API

[bindings/win32](bindings/win32) is what all of the above adds up to: 259
Windows entry points, 460 constants and 27 structs, unions, enums and delegates,
with 145 convenience functions over them. There is no marshalling layer and nothing is generated — a `WNDCLASSEXW` is a
Stainless `struct` whose `sizeof` is 80 as it is in C, and a `WNDPROC` is a
`delegate`, which is the bare function pointer Windows calls.

It comes in two layers, and the module name says which is which. **A DLL name is
the declarations**, spelled as Windows spells them:

```csharp
import Win32.User32;

long Procedure(void* window, uint message, ulong wParam, long lParam) {
    if (message == WmDestroy) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(window, message, wParam, lParam);
}
```

**A task name is the conveniences** built on those — the message loop, the
directory walk, the registry as a `Result`, the buffer a wide API writes into:

```csharp
import Win32.Ui;

int code = RunMessageLoop();
```

Both are source you compile with your program rather than part of the standard
library, because compiling a *wrapper* is what makes its library necessary — an
undefined symbol is an error before the dead-strip that would have removed it.
The raw layer has no such cost, and links with nothing named at all:

```
stainless build app.sl bindings/win32/api                        # free
stainless build gui.sl bindings/win32 -l user32 -l gdi32 \
    -l advapi32 -l shell32 -l comdlg32                           # with the conveniences
```

Every file is `#if WINDOWS`, so elsewhere the modules exist and are empty rather
than failing to build. [samples/win32/window.sl](samples/win32/window.sl) is a
working window — class, message loop, double-buffered GDI painting, keyboard —
and [bindings/win32/README.md](bindings/win32/README.md) is the guide.

Full details: **[docs/language-spec.md](docs/language-spec.md)**,
**[docs/abi.md](docs/abi.md)** and, for where threading is going,
**[docs/concurrency.md](docs/concurrency.md)**.

---

## Building the compiler

Requires the [.NET 10 SDK](https://dotnet.microsoft.com/download) and
[LLVM/clang](https://llvm.org) (`winget install LLVM.LLVM`).

```
dotnet build Stainless.slnx
dotnet run --project tests/Stainless.Tests      # 153 end-to-end tests
```

The compiler finds clang on `PATH`, at `C:\Program Files\LLVM\bin`, or wherever
`STAINLESS_CLANG` points.

## Using it

```
stainless build <paths...>     compile to a native executable
stainless run   <paths...>     compile, then run it
stainless emit-ir <paths...>   print the generated LLVM IR

  -o, --out <path>       output file
  --shared               build a shared library instead of an executable
  --header <path>        write a C header for the exported surface
  --metadata <path>      write module metadata for a Stainless consumer
  -r, --reference <path> bind against a library's module metadata
  -O<0-3>                optimization level (default -O2)
  -g                     describe the program to a debugger
  -D <name>              define a symbol for '#if' to test
  -l <name>              link a library the linker finds by name
                         (a source file can name one itself, with
                          '#pragma comment(lib, "user32")')
  --abi <microsoft|itanium>  which C and C++ ABI to agree with (names and
                         bit-fields; struct passing is Win64 either way)
  --keep                 keep the generated .ll
```

Paths may be `.sl` files or directories (searched recursively), in any order.
C and C++ sources and object files can be listed alongside them and are passed
straight to the linker:

```
stainless run samples/interop/interop.sl samples/interop/native.c
```

A library the linker can find for itself is named with `-l` rather than by path,
which is how a platform library is reached:

```
stainless run samples/win32/window.sl bindings/win32/api/Kernel32.sl \
    bindings/win32/api/User32.sl bindings/win32/api/Gdi32.sl \
    bindings/win32/Win32.sl bindings/win32/Ui.sl bindings/win32/Drawing.sl \
    -l user32 -l gdi32
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
own copy of the runtime. Pass C types across a *C* boundary and keep managed
objects on one side of it.

### A library for Stainless

A Stainless consumer is a different matter, because both sides are Stainless and
the compiler can describe one to the other:

```
stainless build lib --shared -o build/shapes.dll --metadata build/shapes.slmod
stainless build app.sl --reference build/shapes.slmod build/shapes.lib -o app.exe
```

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

Classes cross with their fields, properties, methods, constructors and
destructors, and so do structs, enums and free functions. Reference counting
reaches across too: the object is allocated through the library's own TypeInfo,
so it is destroyed by the destructor the library compiled for its layout, when
the consumer drops the last reference.

Generics and classes implementing interfaces do not cross, and the compiler says
so where the library is built rather than leaving the consumer to find a public
type missing. See [§8.4 of the spec](docs/language-spec.md) for why each is a
decision about the language rather than a gap in the metadata.

---

## How it works

```
  .sl sources
      |
      v   Lexer -> Parser                       one file at a time, no #include
   syntax trees
      |
      v   Binder, in eleven whole-program passes:
      |     1. declare modules        7. compute C-compatible layouts
      |     2. declare types          8. check what crosses a language boundary
      |     3. resolve imports        9. check bodies
      |     4. resolve signatures    10. order and check static initializers
      |        and field types       11. check whatever those instantiated
      |     5. check that classes implement what they claim
      |     6. fold attributes to constants
      |
      |   A referenced library's declarations are loaded before pass 1, so a
      |   module from a binary is named exactly like one from source.
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
| [Syntax/Lexer.cs](src/Stainless.Compiler/Syntax/Lexer.cs) | tokens, and `#if` deciding which of them exist |
| [Syntax/Parser.cs](src/Stainless.Compiler/Syntax/Parser.cs) | recursive descent + precedence climbing |
| [Binding/Binder.cs](src/Stainless.Compiler/Binding/Binder.cs) | the eleven passes, type checking, conversions, generic instantiation |
| [Binding/TypeSystem.cs](src/Stainless.Compiler/Binding/TypeSystem.cs) | types and C-rule layout |
| [Binding/Builtins.cs](src/Stainless.Compiler/Binding/Builtins.cs) | `String`, `StringBuilder`, `[Flags]`, and the ordering and hashing a primitive gets for free |
| [Binding/Mangler.cs](src/Stainless.Compiler/Binding/Mangler.cs) | symbol names |
| [Binding/CppMangler.cs](src/Stainless.Compiler/Binding/CppMangler.cs) | C++ symbol names, in the Itanium and Microsoft schemes |
| [Binding/MetadataLoader.cs](src/Stainless.Compiler/Binding/MetadataLoader.cs) | symbols for a referenced library, from its metadata |
| [Emit/Win64Abi.cs](src/Stainless.Compiler/Emit/Win64Abi.cs) | struct passing: register, `byval`, or `sret` |
| [Emit/LlvmEmitter.cs](src/Stainless.Compiler/Emit/LlvmEmitter.cs) | IR, retain/release insertion, metadata tables |
| [Emit/CHeaderWriter.cs](src/Stainless.Compiler/Emit/CHeaderWriter.cs) | the C header for a shared library |
| [Emit/MetadataWriter.cs](src/Stainless.Compiler/Emit/MetadataWriter.cs) | the module metadata a Stainless consumer binds against |
| [Driver/ModuleMetadata.cs](src/Stainless.Compiler/Driver/ModuleMetadata.cs) | what that metadata contains, and how it is read back |
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
A parameter the body *writes to* is the one exception — it is retained on entry
and released on exit, because otherwise its store would release a reference the
caller still owns.

---

## What works today

Everything below is covered by [the test suite](tests/cases).

- Modules like C# namespaces: several files may share one, imports are per file,
  `public` exports and an unmarked declaration is module-wide
- Aliases, qualified names without an import, full order independence
- Bit-fields: `public uint Kind : 4;` in a struct or a union, with the width a
  constant from one to the width of the declared type. Both C ABIs are
  implemented — Microsoft opens a new storage unit when the declared type's size
  changes, Itanium packs across — and `--abi` chooses, defaulting to the host's.
  A signed field sign-extends from its own width; writing one leaves its
  neighbours alone; one has no address, so no `ref` to it
- `[Packed]` and `[Align(N)]`: no padding at all, and a raised alignment. Both
  are rules about layout rather than library features, so neither needs an
  import; they combine, N is a power of two capped at 16, and both apply to a
  `struct` and nothing else. The generated C header states them with
  `#pragma pack` and an `SL_ALIGN` macro, and the sizes, alignments and offsets
  are checked against the target's own C compiler
- `struct` with fields and methods; exact C layout; value copy semantics. A
  struct may hold a reference, and copying one then retains what it holds — the
  cost is that it is no longer a value C can be handed, which the compiler
  checks at every `extern "C"` and `export "C"`
- `union`: C's, every member at offset zero, with the size and alignment C
  computes. No member may hold a counted reference, because a union does not
  record which one is live. `[Packed]` and `[Align]` apply as they do to a
  struct, and a generated C header writes it as a C `union`, member for member
- `variant`: a value that is exactly one of its cases and says which. A tag
  plus the widest case's payload, with the cases overlapping, so nothing
  allocates and the size is the maximum rather than the sum. Cases carry named
  fields; `v.Case` asks the tag; a payload is readable only where the compiler
  has already established its case. `switch` over one names cases rather than
  values, binds a payload with `case Circle c:`, needs no `default` once every
  case is covered, and counts as a way out of the function when it is.
  Reference counting consults the tag, so a case may hold a `String`, a class
  or an array and only what is really there is ever counted. Generic variants
  monomorphize like anything else
- `Result<T, E>`: the language's answer to an exception, and now an ordinary
  variant — `Ok(T Value)` and `Fail(E Error)` — with no machinery of its own.
  A call that succeeds allocates nothing; `Ok(x)` and `Fail(e)` are written
  without type arguments and take their type from what they are returned or
  assigned into, the way a lambda does. `Value` and `Error` are readable only
  where the compiler has already seen which case is there — after `if (r.Ok)`,
  in the arm of a ternary, after an early `if (!r.Ok) { return ...; }`, or in a
  `switch` arm — and `ValueOr(fallback)` needs no proof because it supplies one
- `class` with fields, constructors, destructors, methods; ARC with correct
  nested destruction
- Properties, on classes, structs and interfaces: `{ get; set; }` with a
  compiler-generated backing field, `{ get; private set; }`, get-only ones a
  constructor fills in, and written accessors with block or `=>` bodies. They
  lower to a pair of ordinary methods, so an interface property dispatches like
  any other member
- `extern "C"` and `export "C"`, including variadics and structs by value in
  both directions
- `extern "C++"` and `export "C++"` for free functions, in both directions and
  with no shim between: the signature is mangled the way the target's compiler
  mangles it, in the Itanium scheme for gcc and clang or Microsoft's for MSVC.
  A namespace is written on the declaration — `extern "C++" double
  geometry::Area(double, double)` — and decides the linker name and nothing
  else. Both schemes are checked against clang's own output for the same
  signatures. C++ *classes* are not reachable yet; that needs object and vtable
  layout, and an answer for exceptions crossing a boundary nothing unwinds
- Win64 struct ABI: register coercion, `byval`, `sret`
- `if` / `while` / `for` / `foreach` / `break` / `continue` / `return`, recursion
- `switch` over integers, `char`, `bool`, enums, `String` and variants, with
  stacked labels and no fall-through. An ordinal switch is one LLVM `switch`, so
  a jump table is LLVM's decision rather than the programmer's; `break` belongs
  to the switch while `continue` passes through it to the enclosing loop
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
  conditional `a ? b : c`. The arithmetic C leaves undefined is defined here:
  a shift count is reduced modulo the operand's width as in C#, so `1 << 40` is
  256 rather than garbage, and an integer division by zero — or the one signed
  division that overflows — aborts the way an out-of-range index does, rather
  than being folded to whatever the optimiser likes. A divisor that is zero at
  compile time is an error instead
- `var`, `const`, explicit locals, compound assignment
- `String`: UTF-8, immutable, reference counted, `+` and `==`, zero-copy
  `ToPointer()`, `ToUtf16()`, and literals that never allocate. UTF-16 converts
  back with `ToText()` or, from a buffer a platform API filled, with
  `Text.FromUtf16`; anything malformed becomes U+FFFD in both directions, so a
  `String` is UTF-8 by invariant
- `T[]`: counted arrays, always bounds checked, elements released with the array
- `T[N]`: an inline fixed-size array, which is C's and not C#'s — it *is* its
  elements rather than a reference to them, so a struct holding one is exactly
  as wide as the C struct it mirrors. The length is part of the type, so
  `.Length` is a constant and an out-of-range constant index is a compile error
  rather than an abort. `WIN32_FIND_DATAW` is 592 bytes here as it is there
- `T[:]`: slices. `a[1:4]`, `a[3:]`, `a[:2]` and `a[:]` over an array or another
  slice, with half-open bounds; three words, so nothing allocates. A view rather
  than a copy — writing through one writes the array, and an index is checked
  against the slice's own length. Slicing a slice narrows it rather than nesting.
  It holds the array it came from, so it cannot dangle: what it points into is
  alive for as long as it is. An array converts to a slice of the whole of
  itself implicitly, and `foreach` walks one like an array
- Generics: generic classes, interfaces, functions and methods, monomorphized, with
  inference at call sites and interface constraints (`where T : IComparable<T>`)
- `enum`, strongly typed: a distinct type over an integer that never converts
  implicitly in either direction, with an optional underlying type
  (`enum Level : byte`)
- `[Flags]` enums: `|`, `&`, `^` and `~` on an enum whose members are bits,
  producing that same enum rather than its number, plus `HasFlag`. The marker
  needs no import, because it is a rule about enums rather than a library
- `ref` and `in` parameters: the caller's storage rather than a copy of it,
  writable through the first and not the second. `ref` is written at the call
  as well as the declaration; a `ref` argument must name storage and is not
  converted; writing to an `in`, or passing one on as a `ref`, is refused. The
  mode is part of a signature, so overloads may not differ only in it and a
  class does not implement `ref int` with `int`. Both are a `T*` at the ABI, so
  `extern "C" double modf(double, ref double)` needs no shim, and a generated
  header writes them `T*` and `const T*`
- `delegate`: a named function pointer, one word, C ABI compatible in both
  directions, and storable in a `struct`
- Lambdas and closures: `value => value * factor` becomes a generated class
  implementing a single-method interface, capturing **by value** so it may
  outlive the scope that built it; a non-capturing one becomes a `delegate`. A
  lambda written in a method reaches its object too — a field, a property,
  `this`, or a method called without a receiver — and captures what it reads by
  the same rule
- `weak C?`: assignable, so a reference cycle can be broken. A weak reference
  costs the object nothing while it lives and reads back as `null` once it is
  gone, rather than as a pointer into freed memory
- `foreach` over arrays and over anything with a `GetEnumerator()`, plus
  `IEnumerable<T>` / `IEnumerator<T>` in `Standard.Collections`
- Interfaces: several per class, dynamic dispatch, checked at compile time, and
  extending one another with free conversion to the base. A class may implement
  two instantiations of one generic interface — `IEq<int>` and `IEq<String>` —
  because each interface has its own dispatch table and the overloads land in
  different slots
- Overloading by parameter type, on methods as well as module-level functions;
  a return type alone does not distinguish two of them
- `Standard.Collections`: `List<T>`, `Dictionary<K, V>`, `HashSet<T>`,
  `Queue<T>`, `Stack<T>`, `LinkedList<T>` and `SortedList<K, V>`, plus
  `IComparable<T>`, `IEquatable<T>`, `IHashable`, `IReadOnlyList<T>`,
  `IList<T>`, `IEnumerable<T>`, `IEnumerator<T>` and
  `Sort`/`Largest`/`Smallest`/`IndexOf`, plus `Sort` and `Reverse` over a
  `T[:]`. Every container is array-backed —
  ARC cannot collect a cycle, so the linked list links by index rather than by
  reference
- Primitives, enums and `String` satisfy `IComparable<T>`, `IEquatable<T>` and
  `IHashable` without declaring it, so `Sort(numbers)` works on a `List<int>`
  and `Dictionary<String, V>` needs nothing extra
- `StringBuilder`: mutable text with amortised O(1) appends
- `Standard.Threading`: `Mutex<T>` and its `Guard<T>` (the lock owns what it
  guards, and a destructor releases it), `AtomicLong`, `AtomicBool`, and
  `TaskScope` for running `Job` delegates on the pool. **`Mutex<T>` is sound
  only for a plain `T`** — see the thread-safety note below
- `Standard.Math`: the C library's floating point, plus `Abs`/`Min`/`Max`/
  `Clamp`/`Sign` overloaded across `int`, `long`, `nuint` and `double`,
  `IsNaN`/`IsInfinite`/`IsFinite`, `GreatestCommonDivisor`, and the bit
  functions. A module is a scope, so `Math.Sqrt(x)` needs no static class
- `Standard.Concurrent`: `ConcurrentQueue<T>`, `ConcurrentStack<T>`,
  `ConcurrentDictionary<K, V>` and a blocking `Channel<T>`. Each owns its
  collection in a field and never hands out a reference to it, because a lock
  protects what it guards and not the reference *count* of what it guards
- `Standard.IO`, `Standard.File`, `Standard.Directory`, `Standard.Path`:
  `IStream` with `FileStream` and `MemoryStream`, whole-file reads and writes,
  directory listing, and textual path handling. Failure is a returned value —
  a `Result<T, IOError>`, or a bare `IOError` where nothing is produced. Paths
  are UTF-8 and are widened to UTF-16 before they reach Windows
- `Standard.Text` (imported everywhere), `Standard.Console`, `Standard.Reflection`
- Raw pointers, `sizeof`, `alignof`, `offsetof`, `typeof`, casts, `new`, `this`.
  The three layout questions answer exactly what C's do, which is how a binding
  checks itself against a header; `offsetof` on a class counts from the
  allocation, so the number is what to add to the reference you hold
- Integer literals that fit convert implicitly, as in C#
- Shared libraries: `--shared` with a generated C header, and an export table
  containing exactly the `export "C"` functions
- Stainless libraries consumed by Stainless: `--metadata` writes a `.slmod`
  describing a library's public surface, and `--reference` binds another
  compilation against it. Classes cross with their fields, properties, methods,
  constructors and destructors; so do structs, enums and free functions, and
  reference counting reaches across, because an object is allocated through the
  library's own TypeInfo. Generics and classes implementing interfaces do not
  cross, and the compiler says so where the library is built
- Attributes and opt-in reflection: field names, offsets, kinds and attribute
  values readable at run time, from `const` tables in the binary
- `-g`: debug information, in CodeView on Windows and DWARF elsewhere. Every
  instruction carries a source location, every function is named as it was
  written and as the linker sees it, and every local and parameter is described
  with its type and its stack slot. The standard library is written to
  `obj/stdlib/` and the runtime's C compiled `-O0 -g`, so a stack trace through
  `List.Add` and into `sl_retain` names real files and real lines rather than
  addresses. See [§7 of the ABI notes](docs/abi.md)
- [bindings/win32](bindings/win32): the Windows API — 259 entry points, 460
  constants and 27 structs, unions, enums and delegates — as declarations
  rather than a marshalling layer, in two layers a module name apart:
  `Win32.User32` is what the DLL exports, `Win32.Ui` is the conveniences on top.
  Source a program compiles rather than part of the standard library, because
  compiling a wrapper is what makes its library necessary; the raw layer needs
  no library at all
- Conditional compilation: `#if`, `#elif`, `#else`, `#endif`, `#define`,
  `#undef`, `#error`, `#warning`, `#region` and `#endregion`, with C#'s
  condition grammar, plus `#pragma comment(lib, "...")` so a file can name the
  library it needs. A branch that is not taken is never lexed, so it need not
  parse. `WINDOWS`, `LINUX`, `MACOS`, `FREEBSD`, `UNIX`, `X64`, `ARM64`, `X86`,
  `ARM` and `STAINLESS` describe the target; `-D` adds the rest. No macros and
  no `#include`: a name always means itself
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
- **No `switch` expression, and the only pattern is a variant's case.** A
  switch over a variant covers cases and may bind a payload; everywhere else
  `switch` is the C# statement and only that. No type patterns, no constants
  inside a case pattern, no guards, no `goto case`, and no exhaustiveness
  requirement on an enum, whose value need not be one of its members.
- **A lambda needs something to be.** It is typed by what it is assigned to, so
  `var f = x => x;` has nothing to infer from. Capture is by value only, and a
  capturing lambda cannot become a `delegate` — a function pointer has nowhere
  to keep what was captured. A lambda that captures `this` keeps its object
  alive, so an object holding its own closure is a cycle; `weak` is how that is
  broken.
- **Narrowing is for variants only.** The compiler tracks which case a variant
  is holding through `if`, `!`, `&&`, `||`, a ternary, an early return and a
  `switch`, and only for one held in a local or a parameter. It does not yet do
  the same for `C?`, so an optional still cannot be unwrapped by testing it.
  The two want the same machinery and the second is the obvious next step.
- **No zero-width or unnamed bit-fields.** C's `int : 0;` closes a storage unit
  and `int : 3;` pads without naming anything; neither is written (SL0473).
  `[Packed]` together with bit-fields is refused rather than guessed (SL0470),
  because gcc packs the bits and MSVC keeps the unit and nothing here yet says
  which this language means. `[Reflect]` is refused on a type with bit-fields
  (SL0475): the field tables describe a byte offset, and a bit-field has none.
- **`[Align(N)]` stops at 16.** `malloc` guarantees `max_align_t` and nothing
  more, so a class holding a more-aligned field would be handed memory that did
  not honour it. Lifting the cap means allocating by a type's alignment as well
  as by its size, which the runtime does not do yet. There is also no alignment
  on a single field, only on a whole type.
- **A slice is owning, and there is no borrowed one.** It retains the array it
  came from, which is what makes it impossible to dangle and also what makes it
  cost a reference count per copy and keep a large array alive for a small view
  of it. A raw `(pointer, length)` view would do neither, and would need a
  lifetime story the language does not have.
- **`String` has a thin API.** No `IndexOf`, `Split`, `Trim`, case mapping or
  formatting; `Substring` counts bytes, not characters, so it can slice a
  multi-byte character in half.
- **No flow narrowing for `C?`.** Optionals can be stored, compared to `null`,
  and unwrapped with an explicit cast, but `if (x != null)` does not yet make
  `x` usable as non-optional. It is why `LinkedList<T>` links by index — a
  structure that walks `next` cannot be written at all.
- **No class inheritance.** Interfaces extend one another, but classes do not,
  and there is no downcast from an interface back to a class.
- **Reflection reads but does not write.** Fields can be read from an instance,
  not set, so a deserializer cannot be written yet; nor can an instance be made
  from a `Type`. Methods and interfaces carry no metadata — fields only.
- **An interface method may not be overloaded.** Dispatch gives each one a
  single slot, so two of a name in one interface would be a call the receiver
  could not resolve. Methods on classes and structs overload freely, and a
  class may implement two interfaces whose methods share a name.
- **A property is not an indexer, and not initialized where it is declared.**
  There is no `this[i]`, and `{ get; set; } = 5;` is rejected for the same
  reason a field initializer is. `p.X += 1` also needs a receiver that is a
  plain load, since the getter and the setter each evaluate it.
- **The compiler prunes no dead code; the linker does.** Every stdlib module is
  compiled with your program whether or not it is imported, and only generics
  are free — an uninstantiated template emits nothing, but a non-generic
  function or class is emitted either way. What saves it is that everything is
  emitted into its own section and the linker discards what nothing reached,
  which takes hello-world from 290 KB to 124 KB. The IR is still the full size,
  so compile time still pays for all of it; a reachability pass from `Main`
  would fix that and is the real answer.
- **Unoptimized ARC, and it now costs more.** Retain/release traffic is correct
  but redundant, and since the counts became atomic each redundant pair costs
  about 5.7ns rather than about 1.2ns. A loop that does nothing but ARC traffic
  runs roughly 3x slower than it did. The +0/+1 dataflow pass that removes the
  pair around a borrow was a nicety before and is the obvious next piece of work
  now.
- **The remaining thread-safety gaps are about lifetimes.** What crosses a
  thread is checked by type, so an unsynchronized class cannot reach a second
  thread at all. What is unchecked is how long a borrowed thing lives: a
  `Guard` can outlive the lock it proves, and a job could store an array it was
  only lent. `[Shared]` is also an assertion rather than a proof, the same
  bargain as Rust's `unsafe impl Sync`. See
  [docs/concurrency.md](docs/concurrency.md).
- **No cancellation beyond a shared flag.** An `AtomicBool` a job polls is the
  whole story; a `parallel` block always joins, and always will. See §9 of the
  concurrency notes for what is worth adding and what never will be.
- **Debug information describes data, not sequences.** `-g` covers functions,
  locations, locals, parameters, structs, class bodies and enums. It does not
  describe an array's or a `String`'s elements — DWARF wants a static bound and
  there is none — and it puts every local in the function's scope rather than in
  the block it was declared in, so a debugger will show one that is not in scope
  yet. Neither is a lie about a value; both are less than a C compiler emits.
- **A variant does not cross a library boundary or carry `[Reflect]`.** Both
  are reported where they are written (SL0441, SL0442) rather than left to be
  discovered. The metadata describes layouts and the reflection tables describe
  fields, and a variant's shape is neither — it is its cases, which nothing yet
  writes down. Its tag is also one byte, so 255 cases is the limit.
- **Statics are module-level only**, and a `--shared` library cannot have one:
  there is no entry point to initialize it from. No `static` members on a type,
  and no per-thread storage.
- **Win64 only** for struct passing; the SysV classifier is not written, so
  `--abi itanium` reaches name mangling and bit-field packing and not the
  calling convention.
- **No calling conventions.** `__stdcall`, `__fastcall` and `__vectorcall`
  cannot be written. On x64 that costs almost nothing — there is one convention
  and only `__vectorcall` differs — but it is the whole story on x86, where
  `__stdcall` is what Win32 uses.
- **No type aliases.** There is no `using Handle = void*;`, so a binding spells
  `HANDLE`, `HWND` and `HDC` all as `void*` and nothing catches passing one
  where another belongs. Opaque struct types would make those distinct at no
  cost, and the two want doing together.
- **An enum does not cross `extern "C"`.** A `[Flags] enum : uint` will not pass
  to a `uint` parameter without a cast, which is why
  [bindings/win32](bindings/win32) spells 460 constants as bare `const uint`
  rather than as the typed sets they are.
- **An inline array holds plain data only** and cannot be passed by value
  (SL0486, SL0491). The first is the same question a union cannot answer; the
  second is because C decays an array parameter to a pointer and Stainless has
  no decay, so `ref T[N]` is the spelling that lines up.
- **No COM**, and so nothing reached through it: `SHGetKnownFolderPath`,
  Direct2D, WIC, the modern shell. A COM interface is binary-identical to a
  pointer to a vtable pointer, so this needs no C++ object model — only
  `IUnknown` discipline and a struct of `delegate`s.
- **A library's surface is narrower than a module's.** `--metadata` lets a
  Stainless library be consumed by Stainless, but a generic, a class that
  implements an interface, a variant and a slice all stay behind: a template
  emits nothing until it is instantiated, a dispatch table is indexed by an id
  assigned across a whole program, a variant's cases are not a layout, and a
  slice is a type the compiler builds rather than one the source declared.
  Anything reaching one of those through a field or a signature is reported too
  (SL0419, SL0420, SL0441, SL0477), all of them where the library is built
  rather than where the consumer trips over them.
- **The runtime is linked statically into every binary.** Each side of a library
  boundary therefore has its own allocator and its own C stdio buffer, so output
  written from inside a library does not interleave with its consumer's in the
  order it was written. Shipping the runtime as its own shared library would
  close both, and is the next thing worth doing about libraries.
- **No `out`, no `ref` locals and no `ref` returns.** `out` would need
  definite-assignment analysis to be worth having over `ref`; the other two
  would need a lifetime story the language does not have.
- `Main` takes no arguments, and arguments after `--` are accepted and then
  dropped. Field initializers are rejected — assign in a constructor. `delete`
  is reserved but unused.

What is being worked on next, and the known bugs, are in **[TODO.md](TODO.md)**.

## Repository layout

```
docs/                  language specification, ABI, concurrency design
runtime/               the runtime, split by feature, embedded in the compiler
stdlib/                the standard library written in Stainless, also embedded
bindings/win32/        the Windows API, compiled only by a program that asks
samples/               example programs
src/Stainless.Compiler front end, binder, emitter, driver
src/Stainless.Cli      the `stainless` command
tests/cases/           one directory per end-to-end test
tests/Stainless.Tests  the test runner
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
