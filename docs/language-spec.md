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

```csharp
module App.Math;          // optional; inferred from path if omitted

import Standard.Console;              // brings its public members into scope
import Standard.Console as Terminal;  // aliased
```

A module is exactly one source file. A file with no `module` declaration takes
its module name from its path relative to the package root
(`src/App/Math.sl` -> `App.Math`).

> Stainless says `module`, not `namespace`, because the two differ: a C#
> namespace may span any number of files, while a Stainless module *is* a
> file. That one-to-one rule is what lets the compiler retire header files.

Top-level declarations are private to their module unless marked `public`:

```csharp
public double Area(double r) { return 3.14159 * r * r; }
double Helper() { return 1; }        // module-private
```

Because there are no headers, `public` is the *only* thing that controls
visibility, and a module's public surface is derived from its own source.
Order never matters:

```csharp
int Main() {
    return Later();     // fine: Later is declared below
}

int Later() { return 0; }
```

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
