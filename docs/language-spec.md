# Stainless Language Specification (v0.1 draft)

Stainless is a systems language with C++'s performance model and C#'s syntax.

**Design pillars**

1. **No header files.** One file is one module. Declarations are order-independent
   within and across modules; the compiler resolves the whole program graph before
   checking any body. There is no preprocessor, no `#include`, no include guards,
   no forward declarations, no ODR.
2. **Native code via LLVM.** No VM, no JIT, no runtime startup cost beyond a
   small ARC runtime.
3. **ARC, not GC.** Reference types are reference-counted and destroyed
   deterministically. No collector, no pauses, no tracing thread.
4. **C/C++ ABI compatible.** `struct` types use the platform C layout,
   `extern "C"` functions use the platform calling convention, and Stainless
   functions are callable from C. Interop needs no marshalling layer.

If you write C#, you can read Stainless on sight. The differences are all
about what happens underneath: values instead of objects, refcounts instead
of a collector, a linker instead of an assembly loader.

---

## 1. Modules

Modules work like C# namespaces, with one addition: an unmarked declaration is
private to its module, so a module is also the unit of encapsulation.

### 1.1 Every file names its module

```csharp
module Shop.Catalog;
```

This is required — a file that does not say which module it belongs to is an
error. The name is never inferred from the file's path:

```
error[SL0332]: this file does not say which module it belongs to; start it with
a declaration such as 'module App.Thing;'
```

The compiler never looks at where a file sits. Folders are a convention for
people, so moving a file cannot change what its code means, and the same
sources compile identically however the build is invoked.

> Dots do not nest. `Shop.Catalog` and `Shop` are unrelated names that happen to
> share a prefix; importing `Shop` would not reach `Shop.Catalog`, and there is
> no such thing as a parent module.

### 1.2 A module may span files

Several files may name the same module and merge into it:

```csharp
// Catalog/Books.sl
module Shop.Catalog;

public class Book { ... }
String Decorate(String text) { ... }        // not public

// Catalog/Subscriptions.sl
module Shop.Catalog;

public class Subscription {
    public String Label() { return Decorate(name); }   // sees it; same module
}
```

Nothing is imported between them, and order does not matter: they are one
module that happens to be written in two places.

This does not compromise the no-header property, which comes from resolving
every name in the program before checking any body — not from any one-file
rule.

### 1.3 `public` is the whole of visibility

| Declaration | Visible to |
|---|---|
| `public class Book` | its module, and anything that can name the module |
| `class Book` | its module only, across all of the module's files |

That second row is C#'s `internal`, with the module playing the part of the
assembly. There is nothing else — no friend declarations, no export lists, and
no file-level privacy (C# only gained `file` in version 11).

Members follow the same rule: a field or method needs `public` for another
module to touch it.

### 1.4 `import` adds names; it never grants access

```csharp
import Shop.Pricing;
```

After that line, every **public** member of `Shop.Pricing` can be named three
ways:

| Form | Example |
|---|---|
| bare | `Money`, `Cents(500)` |
| by last segment | `Pricing.Money`, `Pricing.Cents(500)` |
| fully qualified | `Shop.Pricing.Money`, `Shop.Pricing.Cents(500)` |

**The fully qualified form needs no import at all.** Qualification names the
module directly, so this is legal in a file that imports nothing:

```csharp
var boxed = new Shop.Bundles.Bundle("Starter set", 2);
```

An import is therefore a convenience for shortening names, not a permission
check. What you may touch is decided entirely by `public`.

**Imports are per file, not per module**, exactly as `using` is in C#. Two files
of one module may import different things, and adding an import to one of them
cannot quietly change how the other resolves a name.

### 1.5 Aliases

```csharp
import Shop.Pricing as Money;

Money.Format(total)
```

An alias *adds* a way to name the module. It does not remove the others, so
bare names and the full name still work after aliasing — unlike C#, where
`using X = A.B;` replaces unqualified access rather than adding to it.

### 1.6 Ambiguity

If two imported modules both export a type called `Buffer`, using it bare is an
error rather than a silent pick:

```
error[SL0273]: 'Buffer' is ambiguous between 'Net.Buffer' and 'Disk.Buffer';
qualify it with its module name
```

Qualify it, or alias one of the modules.

### 1.7 What is automatic

`Standard.Text` is imported into every file without being asked for, because a
string literal produces a `String` whether the program mentioned one or not.
That is the only automatic import: `Standard.Console` and everything else must
be requested.

### 1.8 Order never matters

Not within a file, and not across them. The compiler resolves every name in the
program before checking any body, so these are all fine:

```csharp
int Main() {
    return Later();          // declared below
}

int Later() { return 0; }
```

A module may be compiled before the module it depends on, and files may be
given to the compiler in any order.

## 2. Types

### 2.1 Primitives

Names and sizes match C# exactly.

| Stainless | Size | C equivalent |
|---|---|---|
| `sbyte` `short` `int` `long` | 1/2/4/8 | `int8_t` … `int64_t` |
| `byte` `ushort` `uint` `ulong` | 1/2/4/8 | `uint8_t` … `uint64_t` |
| `nint` `nuint` | pointer | `intptr_t` / `size_t` |
| `float` `double` | 4/8 | `float` / `double` |
| `bool` | 1 | `bool` |
| `char` | 1 | `char` (a UTF-8 code unit, not UTF-16) |
| `void` | 0 | `void` |

### 2.2 `struct` — value type, C layout

```csharp
public struct Point {
    public double X;
    public double Y;

    public double LengthSquared() { return X * X + Y * Y; }
}
```

Structs are values: copied on assignment, passed per the platform C ABI, laid
out with C field order and padding. A Stainless `struct` and the corresponding
C `struct` are the same bytes, always. Structs are **not** reference counted.

### 2.3 `class` — reference type, ARC managed

```csharp
public class Buffer {
    byte* data;
    nuint length;

    public Buffer(nuint n) {
        data = Malloc(n);
        length = n;
    }

    ~Buffer() { Free(data); }        // destructor, runs at refcount 0

    public nuint Length() { return length; }
}
```

A class value is a pointer to a heap object preceded by an object header
(see [abi.md](abi.md)). Assignment copies the *reference* and retains it.
`new Buffer(64)` allocates, runs the constructor, and yields a reference with
a count of 1.

### 2.4 Pointers and nullability

| Syntax | Meaning |
|---|---|
| `T*` | raw pointer, unmanaged, C-compatible, nullable, unsafe to dereference |
| `C` (class) | strong reference, never null, ARC-managed |
| `C?` | optional strong reference, may be null |
| `weak C?` | non-owning reference; becomes null when the object dies |

### 2.5 `interface` — a contract, dispatched dynamically

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

An interface declares method signatures and nothing else: no fields, no
constructor, no destructor, no bodies. Every member is public whether or not
the word is written, since the whole point is the contract.

A class lists the interfaces it implements after `:`, and must supply a public
method matching each signature exactly. Conversion from the class to the
interface is implicit and free.

An interface reference **is an ordinary object pointer** — the vtable is
reached through the object rather than carried alongside it. So `Shape?`,
`weak Shape?`, ARC and the calling convention all behave exactly as they do for
a class, and passing a `Shape` costs the same as passing any reference.

A `struct` cannot implement an interface: an interface reference is counted,
and a struct is a plain C value with nowhere to keep a count.

Dispatch is four constant-offset loads with no search and no branch — see
[abi.md](abi.md) for the tables. There is no class inheritance, no interface
inheritance, and no downcasting from an interface back to a class.

### 2.6 `T[]` — a counted array

```csharp
var numbers = new int[5];
for (int i = 0; i < (int)numbers.Length; i = i + 1) {
    numbers[i] = i * i;
}
```

An array is a reference counted object, like a class: `numbers.Length` is O(1),
assignment shares rather than copies, and the elements are released when the
array dies. A new array is always zeroed.

**Every index is bounds checked.** The index is compared unsigned against the
length, so one compare covers both ends — a negative index becomes a very large
unsigned value and fails the same test. Going out of range aborts with the
index and the length rather than corrupting memory.

Arrays hold anything: `int[]`, `Point[]` (structs stored inline), `String[]`
and `Shape[]` (references, each retained). `T[][]` is an array of arrays.

## 3. Text

Stainless has exactly one string type. `String` is immutable, reference
counted, and always UTF-8.

There is deliberately no second encoding-flavoured string type. The
`AnsiString`/`UnicodeString` split that Delphi and Free Pascal carry exists to
serve Win32's parallel `A` and `W` APIs, and it charges for that with implicit
conversions that narrow lossily and transcode invisibly. Stainless keeps one
representation and makes every crossing explicit instead.

```csharp
String greeting = "Hello";          // a literal is a String
String subject  = "Stainless";

String message = greeting + ", " + subject + "!";
bool   matched = message == "Hello, Stainless!";   // compares by value, not identity
```

### 3.1 Representation

A `String` is an ordinary reference counted object whose bytes live inline,
immediately after the object header, with a trailing NUL:

```
offset 0   strong      : nuint          the usual ARC header
offset 8   weak        : nuint
offset 16  type        : TypeInfo*
offset 24  byteLength  : nuint          not counting the NUL
offset 32  bytes       : byte[n + 1]    UTF-8, NUL terminated
```

Three things follow from that shape:

- **Length is O(1).** Nothing ever scans for a terminator.
- **Reaching C copies nothing.** `ToPointer()` is `this + 32`.
- **Literals never allocate.** The compiler emits them as static constants with
  an *immortal* reference count, which `retain` and `release` skip entirely.

Because a `String` owns a reference count, it cannot live in a `struct` —
structs are copied as raw bytes, which is what keeps them C-compatible.

### 3.2 Members

| Member | Result | Cost |
|---|---|---|
| `a + b` | `String` | allocates and copies |
| `a == b`, `a != b` | `bool` | compares bytes, not identity |
| `ByteLength()` | `nuint` | O(1) |
| `CodePointCount()` | `nuint` | O(n) |
| `IsEmpty()` | `bool` | O(1) |
| `Substring(start, length)` | `String` | byte offsets, clamped to the end |
| `ToPointer()` | `byte*` | O(1), no copy |
| `ToUtf16()` | `Utf16String` | allocates and transcodes |

`Standard.Text` is imported into every module automatically, since a literal
produces a `String` whether the program asked for one or not. It also provides
`FromInteger`, `FromDouble`, `FromBool`, `FromBytes` and `FromNullTerminated`,
plus `StringBuilder`.

`Standard.Console` is *not* automatic and provides `Write`, `WriteLine` and
`WriteError`.

### 3.3 Reaching C

`ToPointer()` returns the interior `byte*`, valid for as long as the `String`
is alive:

```csharp
extern "C" int puts(byte* text);

String name = "Ada" + " Lovelace";
puts(name.ToPointer());
```

A `String` never converts to `byte*` implicitly, because the conversion hands
out a pointer whose lifetime the compiler can no longer see. A *literal* is the
exception, and passes straight through, since its bytes are static:

```csharp
puts("this is fine");                       // literal: static bytes
printf("%s\n", name.ToPointer());   // variable: say so explicitly
```

Two things worth knowing: a `String` may contain interior NULs, in which case C
sees a truncated view; and `Substring` counts bytes, so slicing mid-character
is possible.

### 3.4 UTF-16 for platform APIs

`Utf16String` exists so that wide platform APIs can be called. Nothing converts
to it implicitly.

```csharp
extern "C" int MessageBoxW(nuint window, ushort* text, ushort* caption, uint kind);

var wide = message.ToUtf16();       // owned, NUL terminated, released by ARC
MessageBoxW(0, wide.ToPointer(), null, 0);
```

It offers `UnitCount()` and `ToPointer()`, which returns `ushort*`.

### 3.5 StringBuilder

`String` is immutable, so building text by repeated concatenation is O(n^2).
`StringBuilder` is the mutable counterpart, with amortised O(1) appends:

```csharp
var builder = new StringBuilder();
for (int i = 0; i < 5; i = i + 1) {
    builder.AppendInteger(i);
    builder.Append(",");
}
Console.WriteLine(builder.ToText());       // 0,1,2,3,4,
```

| Member | Result |
|---|---|
| `Append(String)` | `void` |
| `AppendLine(String)` | `void`, adds a newline |
| `AppendInteger(long)`, `AppendDouble(double)` | `void` |
| `ByteLength()`, `IsEmpty()` | `nuint`, `bool` |
| `Clear()` | `void`, keeps the capacity |
| `ToText()` | `String`, a snapshot; the builder stays usable |

Unlike `String`, its bytes are a separate growable allocation, so it is not
NUL-terminated and has no `ToPointer()`. Call `ToText().ToPointer()` to reach C.

## 4. Generics

```csharp
public class Box<T> {
    T value;

    public Box(T initial) { value = initial; }

    public T Get() { return value; }
    public void Set(T next) { value = next; }
}

var number = new Box<int>(41);      // T is int
var text   = new Box<String>("hi"); // T is String
```

Functions may be generic too, and their type arguments are **inferred from the
arguments passed**:

```csharp
T Pick<T>(T a, T b, bool first) {
    if (first) { return a; }
    return b;
}

Pick(10, 20, false);            // T is int
Pick("left", "right", true);    // T is String
```

### 4.1 Monomorphization

Stainless **monomorphizes**: `Box<int>` and `Box<String>` are two real types,
compiled separately, with no boxing and no indirection. `Box<int>` stores a
bare `int`, and a `T` parameter of a value type is passed exactly as that value
type would be. This is the C++ and Rust model rather than Java's, and it is
what lets generics keep the performance promise the rest of the language makes.

The price is the usual one. A template is not checked until something
instantiates it, so a mistake inside a generic that nobody uses goes unreported,
and errors are reported against the instantiation. Each distinct instantiation
is separate code.

### 4.2 Constraints

A `where` clause says which interfaces a type argument must implement. It goes
after the parameter list and after any base list, as in C#:

```csharp
public interface Comparable<T> {
    int CompareTo(T other);
}

T Largest<T>(T[] values) where T : Comparable<T> {
    var best = values[0];
    for (nuint i = 1; i < values.Length; i = i + 1) {
        if (values[i].CompareTo(best) > 0) { best = values[i]; }
    }
    return best;
}
```

`where T : Comparable<T>` is F-bounded — T must be comparable *to itself* —
which is how comparison avoids needing a downcast. A parameter may carry several
constraints, and a declaration several clauses:

```csharp
public class Ranked<T> where T : Comparable<T>, Describable { ... }

public class Table<K, V> where K : Comparable<K> where V : Describable { ... }
```

Only interfaces constrain. There is no `where T : SomeClass`, no `class` or
`struct` kind constraint, and no `new()` constraint.

### 4.3 What a constraint does, and does not, do

A constraint is **verified where the generic is instantiated**, and the error
names the type, the parameter and the missing interface:

```
error[SL0328]: 'Half' cannot be used as 'T' in 'Ranked' because it does not
implement 'Describable'; it implements 'Comparable<Half>'
```

It does **not** cause the template body to be checked once against the
constraint, the way Rust and Swift do. Because Stainless monomorphizes, bodies
are still checked per instantiation, so a template nobody uses is never checked
at all, and a mistake inside one is reported against the instantiation rather
than the declaration.

The reason is that definition-site checking is all or nothing. It would require
that an unconstrained `T` support *nothing* — no `+`, no `<`, no indexing — and
so it would need constraints on operators as well as on methods, which is a
larger design step than adding `where`. What `where` buys today is a precise
error at the use site and a signature that states its requirements.

### 4.4 What is and is not supported

Supported: generic classes, generic interfaces (including implementing them,
as in `class Money : Comparable<Money>`), generic functions with inference,
interface constraints, generic types nested in one another (`List<Box<int>>`),
and self-referential templates such as `class Node<T> { Node<T>? next; }`.

Not yet:

- **Type arguments are inferred, never written, at a call.** `Pick<int>(...)`
  is not accepted, because `<` in expression position is ambiguous with
  less-than. Inference reads only the argument types, so a type parameter used
  solely in the return type cannot be determined.
- **No generic methods**, only generic types and generic free functions.

### 4.5 A worked example

```csharp
public class List<T> {
    T[] items;
    nuint count;

    public List() {
        items = new T[2];
        count = 0;
    }

    public nuint Count() { return count; }

    public void Add(T item) {
        if (count == items.Length) {
            var bigger = new T[count * 2];
            for (nuint i = 0; i < count; i = i + 1) { bigger[i] = items[i]; }
            items = bigger;
        }
        items[count] = item;
        count = count + 1;
    }

    public T At(nuint index) { return items[index]; }
}
```

## 5. Functions and members

```csharp
public int Add(int a, int b) { return a + b; }

void NoReturn() { }
```

Top-level functions are permitted — a module is a scope, so there is no need
to wrap free functions in a static class the way C# requires.

## 6. C interoperability

```csharp
extern "C" int puts(byte* s);

extern "C" {
    byte* malloc(nuint n);
    void  free(byte* p);
}
```

`extern "C"` declarations are not name-mangled and use the C calling
convention. Conversely, a Stainless function marked `export "C"` is emitted
with an unmangled name so C and C++ can call it:

```csharp
export "C" int stainless_add(int a, int b) { return a + b; }
```

### 6.1 Building a shared library

```
stainless build src --shared -o build/math.dll --header build/math.h
```

produces `math.dll`, the import library `math.lib`, and a C header. A
`--shared` build needs no `Main`.

**The export table is exactly the `export "C"` functions.** Nothing else is
reachable from outside, and that is the only control there is:

| Declaration | In the library |
|---|---|
| `export "C" int Add(int, int)` | exported, unmangled, as `Add` |
| `public int Helper()` | visible to other Stainless modules, **not** exported |
| `int Secret()` | module-private |

`public` deliberately does not export. It answers a different question — which
modules may see this — and a library's surface should be stated once,
deliberately, rather than falling out of visibility rules.

The generated header restates what the ABI already guarantees:

```c
typedef struct Library_Math_Point { double X; double Y; } Library_Math_Point;

int32_t            Add(int32_t a, int32_t b);
Library_Math_Point Scale(Library_Math_Point p, double by);
```

so a consumer is an ordinary C program:

```c
#include "math.h"
int main(void) { return Add(40, 2) == 42 ? 0 : 1; }
```

```
clang consumer.c build/math.lib -o consumer.exe
```

### 6.2 What may cross a library boundary

Plain C values — primitives, pointers and `struct`s — cross freely. That is the
ABI guarantee, and it holds across a DLL exactly as it does within one binary.

**Managed objects are a different matter.** A `String`, class instance or array
carries a reference count, and each binary that links Stainless gets its own
copy of the runtime. An object allocated inside the library and released by the
caller therefore crosses two copies of `malloc` and `free`. It happens to work
when both sides are built by the same toolchain against the same C runtime, but
it is not something to rely on.

The rule is: **hand C types across a library boundary, and keep managed objects
on one side of it.** A managed reference appears in a generated header as
`void*` for that reason — it is a handle to pass back in, not something to
dereference or free.

Lifting that restriction means shipping the Stainless runtime as its own shared
library, so both sides count against the same allocator. That is not done yet.

Neither is the other direction: a Stainless library consumed by *Stainless*.
Importing a module from a compiled binary needs module metadata that does not
exist, since compilation is whole-program today.

## 7. Statements and expressions

```csharp
int x = 10;             // explicitly typed local
var y = x + 1;          // inferred
const int Limit = 64;   // compile-time constant

if (y > 10) { ... } else { ... }
while (y > 0) { y = y - 1; }
for (int i = 0; i < 10; i = i + 1) { ... }
return y;
```

Operators, by descending precedence: unary `- ! ~ * &` · `* / %` · `+ -` ·
`<< >>` · `< <= > >=` · `== !=` · `&` · `^` · `|` · `&&` · `||` · assignment.

Conditions must be `bool`; there is no implicit int-to-bool conversion.
There are no implicit narrowing conversions. Widening integer conversions and
`int` -> `float`/`double` are implicit, as in C#; everything else needs a
cast: `(byte)x`.

An integer literal converts implicitly to any integer type that can hold its
value, as in C#: `byte level = 200;` and `nuint size = 64;` need no cast, while
anything computed still does.

A string literal has type `String`; see section 3.
