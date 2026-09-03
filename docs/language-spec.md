# Stainless Language Specification (v0.1 draft)

> **An extreme rough draft.** This describes an experiment rather than a settled
> design; anything here may change, and several sections describe behaviour that
> was arrived at by trying it rather than by deciding it in advance.

Stainless reaches for the performance of C and C++ with the flexibility of a
higher-level language, by combining ideas that do not usually appear together:
C#'s syntax and namespaces, C's layout and ABI, Swift's reference counting,
monomorphized generics as in C++ and Rust, and reflection as static tables in
the binary as in Swift and Go.

**The four ideas it is built around**

1. **No header files.** Declarations are order-independent within and across
   modules; the compiler resolves the whole program graph before checking any
   body. There is no preprocessor, no `#include`, no include guards, no forward
   declarations, no ODR.
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

    public nuint Length { get { return length; } }
}
```

Members are fields, methods, properties (§7.2), one destructor and any number
of constructors.

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
public interface IShape {
    double Area();
    String Describe();
    String Name { get; }
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

An interface declares method and property signatures and nothing else: no
fields, no constructor, no destructor, no bodies. Every member is public
whether or not the word is written, since the whole point is the contract.

A class lists the interfaces it implements after `:`, and must supply a public
member matching each signature exactly. A property is a pair of methods
(§7.2), so an interface property is one vtable slot per accessor and a class
satisfies it with a property of its own; a field of the right name does not,
because a field is not a call. Conversion from the class to the interface is
implicit and free.

An interface reference **is an ordinary object pointer** — the vtable is
reached through the object rather than carried alongside it. So `IShape?`,
`weak IShape?`, ARC and the calling convention all behave exactly as they do for
a class, and passing a `IShape` costs the same as passing any reference.

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
and `IShape[]` (references, each retained). `T[][]` is an array of arrays.

### 2.7 `enum` — a distinct type over an integer

```csharp
public enum Color { Red, Green, Blue }
public enum Level : byte { Low = 1, Warning = 10, Severe, Fatal = 200 }
```

Members number from zero unless given a value, and a member without one
continues from the member before it, so `Severe` above is 11. The underlying
type is `int` unless another integer type is named, and the representation is
*exactly* that type — a Stainless enum is the same bytes as the C enum or
integer it lines up with, and crosses `extern "C"` with no conversion.

**An enum never converts implicitly, in either direction.**

```csharp
int n = Color.Red;          // rejected
Color c = 0;                // rejected
int n = (int)Color.Red;     // fine
Color c = (Color)raw;       // fine
```

This is the whole reason to declare one. C# spells the type but then lets it
decay to its number at the first opportunity, so a `Level` and a `byte` end up
interchangeable and the type stops carrying meaning. Here it does not decay,
and the cast is where you say you meant it — which is also where a reader
looks when something went wrong.

The cost is real and worth stating: array indexing, serialization, and C
interop all need that cast written out. That is the trade, made deliberately.

Enums compare and do not compute:

```csharp
if (level >= Level.Warning) { ... }     // fine; a severity is ordered
var mixed = Color.Red + Color.Green;    // rejected; colours do not add
```

Comparison is allowed because an ordered enum — a severity, a log level — is
the common case, and `level >= Level.Warning` is what people write. Arithmetic
is not, because adding two colours means nothing.

**`[Flags]` says the members are bits rather than alternatives.**

```csharp
[Flags]
public enum Access : byte {
    None = 0, Read = 1, Write = 2, Execute = 4, All = 7,
}

var mode = Access.Read | Access.Write;
var readOnly = mode & ~Access.Write;
mode ^= Access.Execute;

if (mode.HasFlag(Access.Read)) { ... }
```

`|`, `&`, `^` and `~` are available on a `[Flags]` enum and on no other, and
they produce that same enum rather than its number — so a set of flags stays as
strongly typed as a single one. On an enum without the marker they are rejected,
and the error suggests the marker.

`HasFlag(f)` is `(value & f) == f` written out, which is why it means *all* the
named bits and not any of them. It is the one member an enum has: enums declare
no methods, so this is the language spelling the test rather than a call.

`[Flags]` needs no import. It is a rule about enums rather than a library to opt
into, unlike `[Reflect]` and `[Shared]`, which come with the subsystems they
belong to.

### 2.8 `delegate` — a named function pointer

```csharp
public delegate int Transform(int value);

int Double(int value) { return value * 2; }

Transform t = Double;
int result = t(21);                     // 42
```

A delegate is **one pointer** with the platform C calling convention — the same
value a C function pointer is, and nothing more. It crosses `extern "C"` in
both directions with no glue:

```c
typedef int (*Transform)(int value);
int c_apply(Transform f, int value) { return f(value); }
```

Because it holds no reference count it may live in a `struct`, unlike every
other indirection in the language. A `--shared` build writes the matching
`typedef` into the generated header.

Which overload a bare name refers to is decided by the delegate it is stored
in, since that is the only context a name on its own has:

```csharp
int  Pick(int value)    { return value + 1; }
double Pick(double value) { return value + 1.0; }

Transform picked = Pick;      // the int one
```

`null` is a delegate's null function pointer, and compares as you would expect:

```csharp
Transform none = null;
if (none == null) { ... }
```

**A delegate captures nothing.** It refers to a function, not to a function
plus an environment. A lambda that captures becomes a closure instead — see
§2.9 — and only a non-capturing one can be a delegate, because there is nowhere
in a single pointer to keep what was captured.

### 2.9 Lambdas and closures

A lambda has no type of its own. What it becomes is decided by what it is
assigned to: an **interface with exactly one method**, or a **delegate**.

```csharp
public interface ITransform { int Apply(int value); }

int factor = 3;

ITransform scale = (int value) => value * factor;   // a closure
ITransform shift = value => value + factor;         // parameter type inferred
ITransform back  = (int value) => { return value - factor; };

Transform plain = (int value) => value * 2;         // captures nothing: a delegate
```

Converting to an interface generates a class implementing it, with one field per
captured value — the same shape C# uses for delegates and Rust for `Fn`. It is
an ordinary class, so it is reference counted, it lives in a `List<T>` like
anything else, and its destructor releases what it captured.

**Capture is by value, taken when the closure is made.**

```csharp
int factor = 3;
ITransform scale = value => value * factor;

factor = 100;
scale.Apply(7);         // still 21: the closure copied 3
```

That is C++'s `[=]` and Rust's `move`, not C#'s capture-by-reference. It costs a
copy and buys the thing that matters: a closure may outlive the scope that built
it, with no lifetime question to answer.

```csharp
ITransform MakeAdder(int amount) {
    return value => value + amount;     // fine; `amount` was copied
}
```

Parameter types may be written or left out; left out, they come from the target,
which is the only thing that knows them. A lambda with no target is an error —
`var f = x => x;` has nothing to infer from.

A closure is a class, so it may not cross a thread boundary unless it is marked
`[Shared]` (§9.5). That is the correct answer rather than an oversight: a
closure holds captured state, and nothing synchronizes it.

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
public interface IComparable<T> {
    int CompareTo(T other);
}

T Largest<T>(T[] values) where T : IComparable<T> {
    var best = values[0];
    for (nuint i = 1; i < values.Length; i = i + 1) {
        if (values[i].CompareTo(best) > 0) { best = values[i]; }
    }
    return best;
}
```

`where T : IComparable<T>` is F-bounded — T must be comparable *to itself* —
which is how comparison avoids needing a downcast. A parameter may carry several
constraints, and a declaration several clauses:

```csharp
public class Ranked<T> where T : IComparable<T>, IDescribable { ... }

public class Table<K, V> where K : IComparable<K> where V : IDescribable { ... }
```

Only interfaces constrain. There is no `where T : SomeClass`, no `class` or
`struct` kind constraint, and no `new()` constraint.

### 4.3 What a constraint does, and does not, do

A constraint is **verified where the generic is instantiated**, and the error
names the type, the parameter and the missing interface:

```
error[SL0328]: 'Half' cannot be used as 'T' in 'Ranked' because it does not
implement 'IDescribable'; it implements 'IComparable<Half>'
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
as in `class Money : IComparable<Money>`), generic functions with inference,
interface constraints, generic types nested in one another (`List<Box<int>>`),
and self-referential templates such as `class Node<T> { Node<T>? next; }`.

**Generic methods** are supported too, including inside a generic type, where
the enclosing type's arguments are already fixed and only the method's own are
inferred:

```csharp
public class Pair<A> {
    A left;
    public A KeepLeft<B>(B other) { return left; }
}

var pair = new Pair<String>("outer");
pair.KeepLeft(7);           // A is String already; B is inferred as int
```

Not yet:

- **Type arguments are inferred, never written, at a call.** `Pick<int>(...)`
  is not accepted, because `<` in expression position is ambiguous with
  less-than. Inference reads only the argument types, so a type parameter used
  solely in the return type cannot be determined. This applies to generic
  methods exactly as it does to generic functions.
- **An interface method cannot be generic.** Dispatch gives a method one vtable
  slot, and a generic method has a body per instantiation.

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

## 5. The standard library

### 5.1 What ships, and how

`Standard.Text` is built into the compiler, because `String` and
`StringBuilder` need runtime support. Everything else is ordinary Stainless
compiled alongside your program, which means a generic that nobody instantiates
and a type that nobody names emit no code at all — importing a module costs
nothing by itself.

| Module | Contents | Imported |
|---|---|---|
| `Standard.Text` | `String`, `StringBuilder`, `Utf16String`, conversions | automatically |
| `Standard.Console` | `Write`, `WriteLine`, `WriteError` | on request |
| `Standard.Collections` | interfaces below, and `List<T>` | on request |

### 5.2 `Standard.Threading`

Locks, atomics and a job pool, over the runtime in
[runtime/thread.c](../runtime/thread.c). It needed no new syntax: generic
classes carry the lock, destructors release it, and `delegate` carries the work.

```csharp
import Standard.Collections;
import Standard.Threading;

static readonly Mutex<List<String>> Registry =
    new Mutex<List<String>>(new List<String>());

void Record(String name) {
    var guard = Registry.Lock();
    guard.Value().Add(name);
}                                   // ~Guard() unlocks, including on a return
```

The mutex **owns what it guards**, so there is no way to reach the value
without holding the lock and no way to forget which lock guards what. `lock
(obj) { }` was rejected for the opposite reason: it would put a lock word in
every object header and charge every single-threaded program for it.

`AtomicLong` and `AtomicBool` are sequentially consistent counters and flags.
They are concrete rather than `Atomic<T>` because atomics are not generic — that
would need a constraint saying `T` is an integer, and Stainless constrains by
interface only.

`TaskScope` runs `Job` delegates on the pool and joins them:

```csharp
var scope = new TaskScope();
scope.Run(Work, (byte*)shared);
scope.Join();                       // ~TaskScope() joins too, as a backstop
```

**Two things this is not.** A job takes a `byte*` and casts it back, so nothing
checks what crosses a thread; and keeping a `Guard` alive is a discipline, not a
guarantee. See [concurrency.md](concurrency.md) for the model these are aiming
at and which parts of it the compiler does not yet enforce.

Unlike `Standard.Collections`, this module is not free when unused: `AtomicLong`,
`AtomicBool` and `TaskScope` are ordinary classes, not templates, so their code
is emitted whether or not a program mentions them. It costs about half a
kilobyte.

### 5.3 Interfaces are named with a leading I

`IComparable<T>`, `IReadOnlyList<T>`, `IWritable` — the C# convention, and the
one the standard library follows. It is a convention, not a rule the compiler
enforces.

### 5.4 `Standard.Collections`

```csharp
public interface IEquatable<T>     { bool EqualTo(T other); }
public interface IComparable<T>    { int CompareTo(T other); }

public interface IReadOnlyList<T>  { nuint Count(); T At(nuint index); }

public interface IList<T> : IReadOnlyList<T> {
    void Add(T item);
    void Set(nuint index, T item);
    void Clear();
}
```

`CompareTo` returns a negative number, zero, or a positive number when the
value orders before, with, or after the argument.

`List<T>` implements `IList<T>` over a single array that doubles when it fills.
Alongside the interfaces are `Largest`, `Smallest`, `IndexOf` and `Sort`, each
constrained to what it actually needs:

```csharp
import Standard.Collections;

public class Money : IComparable<Money>, IEquatable<Money> {
    int cents;
    public int CompareTo(Money other) { ... }
    public bool EqualTo(Money other)  { ... }
}

var prices = new List<Money>();
prices.Add(new Money(250));
prices.Add(new Money(40));

Sort(prices);                       // needs IComparable<Money>
Largest(prices);                    // and works on any IReadOnlyList
```

`Sort` takes an `IList<T>`; `Largest`, `Smallest` and `IndexOf` take an
`IReadOnlyList<T>`, so they accept a mutable list without being able to change
it.

### 5.5 Interfaces may extend interfaces

```csharp
public interface IWritable : IReadable { void Write(String text); }
```

An `IWritable` answers `IReadable`'s methods and converts to it for free: a
reference is a plain pointer either way, and a class implementing the derived
interface carries a dispatch table for both. Implementing `IWritable` therefore
obliges a class to implement `IReadable` as well, and the compiler checks it.

## 6. Attributes and reflection

Reflection in a natively compiled language is not a virtual machine feature. It
is **tables in the binary**: the compiler writes down a type's fields, and a
library reads them. Swift and Go work the same way. The only cost is size, and
only for types that ask.

### 6.1 Attributes

An attribute is its own kind of declaration, holding fields and nothing else:

```csharp
public attribute JsonName { String Name; }
public attribute JsonIgnore { }
```

It is written in brackets before a declaration, with **constant** arguments —
they are stored in the binary, not evaluated:

```csharp
[JsonName("full_name")] public String Name;
```

Attributes go on classes, structs and fields. An attribute type is never a
value: it cannot be instantiated, named as a type, or passed around.

### 6.2 `[Reflect]` opts a type in

```csharp
[Reflect]
public class Person {
    [JsonName("full_name")] public String Name;
    [JsonName("age")]       public int    Years;
    [JsonIgnore]            public int    Internal;
}
```

Only a type marked `[Reflect]` carries field metadata. Everything else emits
nothing at all, and `typeof` on it is an error:

```
error[SL0346]: 'Plain' carries no metadata, so 'typeof' cannot name it; mark
its declaration '[Reflect]'
```

### 6.3 `typeof` and `Standard.Reflection`

`typeof(T)` yields a `Type` — a one-pointer handle to static data, so it costs
a constant and no work:

```csharp
import Standard.Reflection;

var type = typeof(Person);
type.Name();                       // "App.Person"
type.FieldCount();

var field = type.FieldAt(0);
field.Name();                      // "Name"
field.Offset();                    // 24, past the object header
field.Kind();                      // KindString
field.Has("JsonName");
field.Get("JsonName").AsText(0);   // "full_name"
```

Values are read from an instance by offset. That needs the object as a raw
pointer, which is an explicit cast — the result is uncounted, so the reference
must outlive it:

```csharp
var raw = (byte*)person;
ReadText(raw, field);
ReadInteger(raw, field);
ReadDouble(raw, field);
ReadBool(raw, field);
```

### 6.4 A serializer, written once

Because `T` is concrete by the time a generic is compiled, `typeof(T)` inside
one is still a constant:

```csharp
public String ToJson<T>(T value) {
    var type = typeof(T);
    var text = new StringBuilder();
    ...
    for (nuint i = 0; i < type.FieldCount(); i = i + 1) {
        var field = type.FieldAt(i);
        if (field.Has("JsonIgnore")) { continue; }
        ...
    }
}
```

See [samples/json.sl](../samples/json.sl) for the whole thing.

### 6.5 What is emitted

A reflected type's `TypeInfo` gains four entries — a field count and table, and
an attribute count and table — and each `SlFieldInfo` records a name, offset,
kind, nested type and its own attributes. All of it is `const`, so it lands in
read-only data and is shared, never allocated. See [abi.md](abi.md).

A struct has no object header, so its metadata is reachable only through
`typeof`, never from an instance.

### 6.6 What is not there yet

- **No writing.** Fields can be read, not set, so a deserializer cannot be
  written yet.
- **No construction.** There is no way to make an instance from a `Type`.
- **No method or interface metadata** — fields only.
- **No enumeration of types**: `typeof` needs the type named at compile time.

## 7. Functions and members

### 7.1 Functions

```csharp
public int Add(int a, int b) { return a + b; }

void NoReturn() { }
```

Top-level functions are permitted — a module is a scope, so there is no need
to wrap free functions in a static class the way C# requires.

### 7.2 Properties

```csharp
public class Person {
    public String Name { get; set; }         // automatic: the compiler owns the storage
    public int Visits { get; private set; }  // read anywhere, write in this module
    public int Id { get; }                   // set by a constructor, then fixed

    public String Label => Name + "#" + Text.FromInteger(Id);   // computed
}
```

A property is **a pair of methods that reads like a field**. `person.Name`
calls the getter, `person.Name = "Ada"` calls the setter, and that is the whole
of it: the accessors are ordinary methods. So a property costs nothing new in
the ABI, dispatches through an interface the way a method does, and comes out
of a generic instantiation with everything else.

**An automatic property owns storage.** Written bare, `{ get; set; }` makes the
compiler generate a field of the property's type together with the two
accessors that read and write it. That field is laid out, destroyed and
reflected exactly like any other; it simply has no name the source can use,
because the property is that name.

**Written accessors own nothing.**

```csharp
public class Thermostat {
    int celsius;

    public int Fahrenheit {
        get { return celsius * 9 / 5 + 32; }
        set { celsius = (value - 32) * 5 / 9; }
    }

    public int Kelvin {
        get => celsius + 273;
        set => celsius = value - 273;
    }
}
```

A setter's parameter is called `value` because that is what it is: an ordinary
parameter of an ordinary method, found by ordinary name lookup. Either form of
body works — a block, or `=>` and one expression — and `T Name => expression;`
with no braces at all is a property with only a getter.

**What may be narrowed, and what may not**

| Written | Getter | Setter |
|---|---|---|
| `public int X { get; set; }` | public | public |
| `public int X { get; private set; }` | public | this module only |
| `int X { get; set; }` | this module only | this module only |

There is no `private get`. The getter is what the word `public` on the property
means, so letting the two disagree would only make the declaration lie.

**A get-only automatic property is still storage.** `public int Id { get; }` may
be assigned in a constructor of the class that declares it, and nowhere else —
the rule C# arrived at, for the reason C# arrived at it. A *computed* get-only
property has nothing to assign to at all, and the error says so.

**On an interface**

```csharp
public interface INamed {
    String Name { get; }
    int Rank { get; set; }
}
```

Accessors and no bodies, exactly as an interface method is a signature and no
body. A class implements it with a property of its own; whether that property is
automatic or written makes no difference to the caller.

**What a property is not**

- **Not a field.** `get_Name` and `set_Name` exist as symbols, and naming one
  directly is an error: they are the lowering, not the language.
- **Not free of evaluation order.** `p.X += 1` calls the getter and then the
  setter, so the receiver is evaluated twice. A receiver that is not a plain
  load — `Make().X += 1` — is rejected rather than quietly evaluated twice.
- **Not initialized at the declaration.** `public int X { get; set; } = 5;` is
  not supported, for the same reason a field initializer is not: assign it in a
  constructor.
- **Not indexed.** There is no `this[i]`.

## 8. C interoperability

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

### 8.1 Building a shared library

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

### 8.2 What may cross a library boundary

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

## 9. Statements and expressions

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
`<< >>` · `< <= > >=` · `== !=` · `&` · `^` · `|` · `&&` · `||` ·
`?:` · assignment.

The conditional `a ? b : c` evaluates only the arm it selects, and groups to
the right, so `a ? b : c ? d : e` reads as `a ? b : (c ? d : e)`. Its arms must
meet at one type: the same type, a common numeric type, or one that the other
converts to implicitly.

Conditions must be `bool`; there is no implicit int-to-bool conversion.
There are no implicit narrowing conversions. Widening integer conversions and
`int` -> `float`/`double` are implicit, as in C#; everything else needs a
cast: `(byte)x`.

An integer literal converts implicitly to any integer type that can hold its
value, as in C#: `byte level = 200;` and `nuint size = 64;` need no cast, while
anything computed still does.

A string literal has type `String`; see section 3.

### 9.1 `switch`

```csharp
switch (level) {
    case Level.Low:     return "low";
    case Level.Warning: return "warning";
    case Level.Severe:  return "severe";
    default:            return "fatal";
}
```

The value may be an integer, a `char`, a `bool`, an enum or a `String`; every
label must be a constant of that type, and no two may name the same value.
An enum, integer, char or bool switch becomes one LLVM `switch` instruction,
which decides for itself whether a jump table beats a chain of comparisons.
A `String` switch compares in order against the runtime's string equality.

**Sections do not fall through.** Each one has to end by leaving — `break`,
`return` or `continue` — and running off the end is an error rather than a
silent jump into the next section. Values that share a body stack their labels:

```csharp
case 0:
case 2:
case 4:
    return "even";
```

**`break` belongs to the switch, `continue` passes through it.** A `continue`
written inside a switch inside a loop continues the loop, as in C#; a `break`
leaves the switch and not the loop. With no enclosing loop, `continue` in a
switch has nothing to continue and is rejected.

```csharp
for (nuint i = 0; i < values.Length; i = i + 1) {
    switch (values[i]) {
        case -1: continue;      // next iteration, skipping the rest of the body
        case 0:  break;         // out of the switch, into the rest of the body
        default: total = total + values[i]; break;
    }
    total = total + 100;
}
```

A `default` is optional; without one, a value that matches nothing simply falls
past the whole statement. There is no exhaustiveness requirement on an enum, and
no `goto case`. Each section has its own scope, so two sections may declare the
same local name — which C# does not allow, having put the whole switch in one
scope.

There is no `switch` *expression* and no pattern matching; this is the C#
statement, and only that.

### 9.2 `parallel`, `spawn` and `parallel for`

```csharp
int left  = 0;
int right = 0;

parallel {
    spawn left  = Sum(values, 0, half);
    spawn right = Sum(values, half, count);
}                       // every spawned job has finished here

return left + right;
```

`parallel` opens a fork-join scope and its closing brace waits for everything
`spawn` queued inside. There is no `Task` type and no `await`: the brace **is**
the synchronization, so a job writes its result into a local the parent still
owns. That is sound because the parent cannot leave the block before the join,
which is also why a job may borrow the frame it was spawned from rather than
copying everything it needs.

A `spawn` may appear anywhere inside the block, including in a loop, and each
one gets its own copy of the arguments:

```csharp
parallel {
    for (int i = 0; i < 8; i = i + 1) {
        spawn squares[i] = Square(i);
    }
}
```

`parallel for` splits a counted loop across the pool instead:

```csharp
parallel for (int i = 0; i < pixels.Length; i = i + 1) {
    pixels[i] = Shade(pixels[i]);
}
```

The loop has to be counted — `i = start`, `i < limit` or `i <= limit`, and
`i = i + stride` with a positive literal stride — because the iteration space is
divided before the body runs and a general C-style `for` has no trip count.

Three rules are enforced, each for the same reason:

| Rejected | Because |
|---|---|
| `return`, `break` or `continue` out of a `parallel` block | it would skip the join and leave jobs running against a dead frame |
| `spawn f(new Buffer())` | arguments are borrowed, and a temporary dies at the end of the statement, before the job runs |
| assigning an outside variable in a `parallel for` body | every chunk would race on one slot; write through a captured array, or accumulate into an `AtomicLong` |

What is **not** checked is everything else: nothing yet stops a job from sharing
a mutable object with the thread that spawned it. See
[concurrency.md](concurrency.md) for the model that is being aimed at, and
which parts of it the compiler enforces today.

### 9.3 `static readonly`

```csharp
public static readonly int Base = 20;
public static readonly String Greeting = "hello";
public static readonly AtomicLong Hits = new AtomicLong(0);
```

Module-level storage, initialized once before `Main`. **There is no `static`
without `readonly`.** A plainly mutable global is shared state that nothing
synchronizes, so the language does not have one; mutation goes through a type
that says how it is safe, and `static int Counter = 0;` is an error that says so.

Which types are allowed is the rule in §9.5: plain data, a `String`, or a class
marked `[Shared]`. `static readonly List<int>` is rejected, and the error points
at `Mutex<T>`.

**Order is computed, not guessed.** An initializer may read another static, and
the compiler sorts them so nothing runs before what it reads:

```csharp
static readonly int Total   = Doubled + 1;      // written first
static readonly int Doubled = Base * 2;
static readonly int Base    = 20;               // runs first
```

C++ cannot do this and calls the result a fiasco. Swift avoids it by making
every static lazy and paying a guard check on every access — a check that has to
become atomic the moment threads exist. Stainless compiles the whole program at
once, so it simply reads the dependency graph: no guard, no per-access cost, and
a **compile error** on a cycle rather than a zero at run time.

A static reference is made immortal as it is stored, so it is never destroyed
and never has its count touched again. There is no teardown, which sidesteps
C++'s static *destruction* order problem as well.

A `--shared` library has no entry point to initialize statics from, so a static
in one is an error rather than a silently zeroed global.

### 9.4 `foreach`

```csharp
foreach (int n in numbers) { total = total + n; }
foreach (var item in list) { Console.WriteLine(item.Name()); }
```

An **array** iterates by index, with no allocation and no dispatch. Anything
else is asked for a `GetEnumerator()`, found **by name rather than by
interface**, so a type can be iterated without `Standard.Collections` appearing
anywhere in the program:

```csharp
class Countdown {
    public CountdownCursor GetEnumerator() { return new CountdownCursor(3); }
}

class CountdownCursor {
    public bool MoveNext() { ... }
    public int Current() { ... }
}
```

`Current()` is a method rather than a property, because Stainless has no
properties. `Standard.Collections` names the shape as `IEnumerable<T>` and
`IEnumerator<T>` so that a sequence can be passed around, and `List<T>`
implements both — but `foreach` does not require them.

The collection is evaluated once, and the loop variable is declared inside the
loop, so a managed element is released at the end of each iteration rather than
piling up until the loop ends. `break` and `continue` behave as in any other
loop; `continue` advances the enumerator.

### 9.5 What may cross a thread boundary

Checked wherever a value can reach a second thread: a `spawn` argument or
receiver, a `parallel for` capture, and a `static readonly`.

| Allowed | Why it is safe |
|---|---|
| plain data — primitives, enums, pointers, delegates, `struct` | there is no reference count to race over |
| `String` | immutable, and its bytes live inside the object |
| a class marked `[Shared]` | the author asserts it synchronizes itself |
| `T[]` where `T` is plain data | a job borrows it without retaining it |

Everything else is rejected. Reference counts are not atomic, so two threads
retaining one object is a race nothing would report — which is why this is a
rule rather than a warning.

`[Shared]` lives in `Standard.Threading` and is an **assertion, not a proof**:

```csharp
[Shared]
class Accumulator {
    AtomicLong total;
    public void Contribute(int amount) { total.Add(amount); }
}
```

Put it on a type whose state lives behind a lock or an atomic, and nowhere else.
`Mutex<T>`, `AtomicLong` and `AtomicBool` carry it; `Guard<T>` and `TaskScope`
do not, because both belong to one thread. It is the same bargain Rust's
`unsafe impl Sync` makes, and the only place in this design where a human
promise stands in for a check.

Two gaps remain, and both are about lifetimes rather than types: a `Guard` can
outlive the lock it proves, and a job could store an array it was only lent.
Neither is closed yet; see [concurrency.md](concurrency.md).
