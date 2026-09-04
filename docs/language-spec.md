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
   body. There is no `#include`, no macro, no include guards, no forward
   declarations, no ODR. `#if` and its relatives do exist, as in C# (§10):
   choosing between two platforms is a different question from finding a
   declaration.
2. **Native code via LLVM.** No VM, no JIT, no runtime startup cost beyond a
   small ARC runtime.
3. **ARC, not GC.** Reference types are reference-counted and destroyed
   deterministically. No collector, no pauses, no tracing thread.
4. **C and C++ ABI compatible.** `struct` types use the platform C layout,
   `extern "C"` functions use the platform calling convention, and Stainless
   functions are callable from C. Interop needs no marshalling layer.
   `extern "C++"` and `export "C++"` do the same for C++ free functions, by
   mangling a signature the way the target's compiler does. A C++ *class*
   cannot be named yet.

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

### 1.3 The module is the unit of visibility

| Declaration | Visible to |
|---|---|
| `public class Book` | its module, and anything that can name the module |
| `class Book` | its module only, across all of the module's files |
| `protected int pages` | its class, and anything deriving from it, wherever that is |

The second row is C#'s `internal`, with the module playing the part of the
assembly. There is nothing else — no friend declarations, no export lists, and
no file-level privacy (C# only gained `file` in version 11).

Members follow the same rule: a field or method needs `public` for another
module to touch it. `protected` (§2.4.1) is the one addition, and
the only visibility that crosses a module boundary without being public: a base
class handing something to its derived classes and to nobody else is the whole
of what the word is for. It adds to module privacy rather than replacing it, so
a `protected` member is still reachable inside its own module, and a private one
is not reachable from a derived class in another module however far down.

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

Two modules are imported into every file without being asked for.

`Standard.Text`, because a string literal produces a `String` whether the
program mentioned one or not.

`Standard`, because what lives there is the language's own vocabulary rather
than a library: `Result<T, E>` (§2.8) and the markers `[Flags]`, `[Packed]` and
`[Align]`, each of which is a rule about a declaration rather than a dependency
on one. Requiring an import for them would make a rule look like a library.

Everything else is requested. `Standard.Console` is not automatic — printing is
a choice — and neither is `Standard.Reflection`, so `[Reflect]` needs an import
like any other name.

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
out with C field order and padding. A struct of plain data and the
corresponding C `struct` are the same bytes, and copying one is a `memcpy` and
nothing else. A struct with no fields occupies **one** byte rather than none,
as it does in C++ and Rust, so that `sizeof` and the emitted layout agree about
where the field after it begins.

**A struct may also hold a reference**, and `Result<T, E>` is the reason it may:

```csharp
public struct Holder {
    public String Text;
    public int Tag;
}
```

Copying such a struct retains what it holds, and dropping one releases it —
whether it is a local going out of scope, a field of a class being destroyed,
or an element of an array. That is Swift's model, and it is what lets a value
type own something.

What it costs is the C guarantee, and only for the structs that use it. Such a
struct is still laid out as C would lay it out, but it can no longer be handed
*to* C, because a C caller would copy the bytes and leave the count behind. The
compiler stops it at the boundary:

```
error[SL0284]: 'Holder' holds a reference, so parameter 'h' cannot cross
extern "C"; C would copy its bytes and leave the count behind. Pass a struct of
plain data, or a raw pointer
```

Crossing a thread is a separate question, and the answer follows the fields: a
struct holding only primitives and `String`s crosses freely, and one holding a
`List<T>` does not, because that is what holding a `List<T>` means either way
(§9.5). A struct of plain data is unaffected by both rules and pays for neither.

### 2.3 `[Packed]` and `[Align]`

A struct is laid out by the platform C rules, and two markers change them. Both
are rules about layout rather than library features, so neither needs an import,
exactly as `[Flags]` does not.

```csharp
public struct Plain {          // 12 bytes: 1, three of padding, 4, 1, three more
    public byte Tag;
    public int Value;
    public byte Trailer;
}

[Packed]
public struct Wire {           // 6 bytes: no padding anywhere
    public byte Tag;
    public int Value;
    public byte Trailer;
}

[Align(16)]
public struct Wide {           // 16 bytes, and always on a 16-byte boundary
    public double X;
    public double Y;
}
```

**`[Packed]`** puts each field where the one before it ended and leaves no
padding at the end either, and the type then asks nothing of its own address.
It is what an on-disk header or a wire format looks like.

**`[Align(N)]`** raises the alignment and never lowers it, the way C's `alignas`
does. N must be a power of two.

The two combine: `[Packed] [Align(4)]` means nothing padded inside, and the
whole of it on a four-byte boundary.

**N is capped at 16.** That is `max_align_t` — what `malloc` guarantees — and a
class holding a more-aligned field would be handed memory that does not honour
it. A local could be aligned further and a heap object could too, once the
runtime allocates by a type's alignment as well as by its size; until then a
stated limit is better than a rule that holds in some places and not others
(SL0466).

Both apply to a `struct` and to nothing else. A class's fields sit behind an
object header the compiler owns, and a variant's payload area is not a field the
source arranged, so neither is a layout the programmer is choosing (SL0463,
SL0464).

A generated C header states both — `#pragma pack(push, 1)` around a packed
struct, and `__declspec(align(n))` or `__attribute__((aligned(n)))` behind a
macro for an aligned one — and a test compares every size, alignment and field
offset against what the target's C compiler makes of it.

#### Bit-fields

A field may be some of the bits of its type rather than all of them.

```csharp
public struct Header {
    public uint Version : 4;
    public uint Kind    : 4;
    public uint Length  : 24;
}
```

The width is a constant between one and the number of bits the declared type
has. A signed bit-field sign-extends from its own width, so a three-bit `int`
holding 7 reads back as -1 — which is what C does, warning and all.

**Which bits a field gets is the target's decision, and the two C ABIs
disagree.** For `struct { int a : 1; byte b : 1; }` gcc gives four bytes and
MSVC gives eight: Microsoft opens a new storage unit whenever the declared
type's size changes, and Itanium packs straight across and starts a new unit
only when a field would cross a boundary of its own type. Both rules are
implemented, chosen the way the C++ mangler chooses a scheme, and every size in
the test suite was read off clang built for the matching target. `--abi` picks
one explicitly; the default is the host's. It reaches names and bit-fields and
nothing else — struct passing is Win64 either way, so `--abi` is not a
cross-compilation.

**A bit-field has no address** (SL0443), for the reason C refuses `&s.flags`.
It cannot be passed by `ref` and cannot be pointed at.

Reading one is a load of the storage unit, a shift and a mask; writing one is a
read, a splice and a write, so the neighbours sharing the unit are untouched.

Not here yet: the zero-width field that closes a storage unit (SL0473), and
unnamed padding fields. `[Packed]` together with bit-fields is refused (SL0470)
rather than guessed, because gcc packs the bits and MSVC keeps the unit and
there is nothing yet to say which this language means. `[Reflect]` is refused on
a type with bit-fields (SL0475), because the field tables describe a byte offset
and a bit-field has not got one.

### 2.4 `class` — reference type, ARC managed

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

Members are fields, methods, properties (§7.3), one destructor and any number
of constructors.

A class value is a pointer to a heap object preceded by an object header
(see [abi.md](abi.md)). Assignment copies the *reference* and retains it.
`new Buffer(64)` allocates, runs the constructor, and yields a reference with
a count of 1.

#### 2.4.1 Inheritance

A class may derive from **one** other class, written first in the list after the
colon, before any interfaces:

```csharp
public abstract class Shape : INamed {
    protected int sides;

    Shape(int howMany) { sides = howMany; }

    public abstract double Area();
    public virtual String Describe() { return Name() + " of " + Text.FromDouble(Area()); }
    public virtual String Name() { return "shape"; }
}

public class Polygon : Shape {
    protected double width;

    Polygon(int howMany, double w) {
        base(howMany);                      // first statement, always
        width = w;
    }

    public override double Area() { return width * width; }
    public override String Describe() { return "a " + base.Describe(); }
}

public sealed class Square : Polygon {
    Square(double side) { base(4, side); }

    public sealed override String Name() { return "square"; }
}
```

| Word | On a class | On a member |
|---|---|---|
| `virtual` | — | may be replaced; the call goes through the object |
| `override` | — | replaces what it inherits |
| `abstract` | cannot be instantiated | no body; every concrete class below supplies one |
| `sealed` | nothing may derive from it | on an `override`, nothing may override further |
| `protected` | — | this class and anything deriving from it |

**One base, not several.** A class reference points at the object header and the
fields follow it, so with a single base the base subobject starts at the same
address as the derived object. An upcast is therefore free — no instructions at
all — reference identity stays pointer identity, and `sl_retain` goes on taking
the object's own address. Multiple inheritance would end all three at once; see
[TODO.md](../TODO.md) for the longer argument.

A virtual call is three loads and an indirect call; see
[abi.md](abi.md) §2.0.1.

**`base` is where to look, not a value.** `base.M()` calls the implementation
this class replaced, and is not dispatched — through the vtable an override
would find itself. `base(...)` runs the base constructor, and only as the very
first statement of a constructor: the base is built before this class's body
runs, and a body that had already run would be reading fields nothing had set.
Left out, the base's constructor taking no arguments is called for you, and
there being none is an error rather than a class that skips it.

```
error[SL0516]: 'base(...)' has to be the first statement of the constructor
error[SL0517]: 'Shape' has no constructor that takes no arguments, so 'Circle'
has to say which one to run: write 'base(...)' as the first statement of its
constructor
```

**Hiding is refused.** A method with the same name and parameters as one it
inherits must say `override`, and what it overrides must be `virtual` or
`abstract`. C# allows `new` to hide instead; a language with no way to reach the
hidden member has nothing to say it about.

```
error[SL0503]: 'Derived.Value' has the same name and parameters as
'Base.Value'; write 'override' to replace it
```

An overload is still an overload: the rule is about the parameters, so a method
of the same name taking different ones is a new method and needs no word.

**Constructors are not inherited.** A class that declares none is built by the
nearest constructor up the chain that takes no arguments, and a class with no
such constructor to reach says so where it is declared rather than at each `new`.

**Destructors chain, derived first**, so a derived destructor may read what its
base still holds. Interfaces are inherited too, and an override takes the slot,
so a call through an interface reaches the same body a virtual call would.

**A class from a referenced library may be held, called, tested and cast — but
not derived from.** Its layout is compiled there and its dispatch table would be
built here (SL0513).

#### 2.4.2 `is`, and casting down

An upcast is implicit and free. Downwards the answer is not in the type, so it
is asked of the object:

```csharp
Shape shape = new Square(3.0);

if (shape is Square) {
    Square square = (Square)shape;      // checked; aborts if it were not one
    ...
}

bool named = shape is INamed;           // interfaces too
```

`is` walks the object's base chain for a class and looks in its dispatch table
for an interface, and answers false for a null reference — so a test through a
`C?` asks about null and about the class at once. A cast that does not hold ends
the program, naming what the object really is; there are no exceptions, and `is`
is how the question is asked first.

A test that could never be true is a mistake rather than a constant false:

```
error[SL0518]: no object is both a 'Circle' and a 'Unrelated': neither derives
from the other
```

There is no `as`. It would produce a `C?`, and without flow narrowing for
optionals (see [TODO.md](../TODO.md)) nothing could be done with the result that
`is` plus a cast does not already do.

### 2.5 Pointers and nullability

| Syntax | Meaning |
|---|---|
| `T*` | raw pointer, unmanaged, C-compatible, nullable, unsafe to dereference |
| `C` (class) | strong reference, never null, ARC-managed |
| `C?` | optional strong reference, may be null |
| `weak C?` | non-owning reference; becomes null when the object dies |

A `weak C?` is assigned like any other reference — `child.Owner = parent;` —
and the slot's type is what makes the store count weakly. Reading one yields a
`C?` through a runtime check, so a weak reference to a dead object reads as
`null` rather than as a pointer into freed memory.

**This is the only way to break a cycle.** ARC cannot collect one, so two
objects that refer to each other strongly leak, with neither destructor ever
running. Making one direction weak is the whole of the answer, and it is why
the conversion is implicit: there is no second option to choose between.

```csharp
class Child {
    public weak Parent? Owner;      // up, weakly
}

class Parent {
    public Child? Kid;              // down, strongly
}
```

A lambda that captures `this` holds its object strongly, so an object that
stores its own closure is such a cycle; see §2.14.

**`p->m` and `p.m`.** Both reach through a pointer, and always have. They differ
only in what they refuse: an arrow says a pointer was expected, so writing one
over a value is reported rather than quietly meaning the same thing.

```csharp
int Sum(Point* p) {
    return p->X + p->Y;             // and `p.X` means exactly this
}
```

```
error[SL0494]: 'Point' is not a pointer, so '->' does not apply to it; write '.X'
```

A module, a variant and an enum are names rather than values, so none of them is
reachable through an arrow.

### 2.6 `variant` — a value that is one of several things

A `variant` is the choice between its cases. Each case has a name and the fields
it carries, and a value is exactly one of them and says which.

```csharp
public variant Shape {
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}
```

It is a **value type**, laid out as a tag followed by enough storage for the
widest case (§2 of the ABI notes). Nothing allocates, and the payloads overlap,
so `Shape` above is 24 bytes — a tag, seven bytes of padding and two doubles —
rather than the 32 that keeping every case's fields side by side would cost.

**Building one.** A case may be named through its variant, or on its own where
the surrounding code already says which variant is meant:

```csharp
Shape a = Shape.Circle(2.0);      // named outright
Shape b = Circle(2.0);            // the type of 'b' says which variant
return Rect(3.0, 4.0);            // and so does a return type
Area(Circle(2.0));                // and so does a parameter
```

The bare form is the one `Ok` and `Fail` have always used, and it obeys the same
rule a lambda does: it takes its type from where it is going. It cannot be
inferred *from*, so `var s = Circle(2.0);` is SL0287. A generic variant can only
be built this way, because type arguments cannot be written at a call (§4.4).

Because a bare case name resolves before any function of that name would, **a
module-level function may not be named after a case of a variant its file can
see** (SL0414). A *method* still may: a method is reached through its receiver,
and nothing there is ambiguous.

**Asking which case.** `v.Case` is a bool — one load of the tag and one
comparison:

```csharp
if (shape.Circle) { ... }
```

**Reading what a case carries** needs the compiler to have established which
case is there first. This is the whole point of the type, and it is checked
rather than trusted:

```csharp
shape.Radius                  // error[SL0286]: nothing has established that
                              // 'shape' is 'Circle'
if (shape.Circle) { shape.Radius }    // fine
```

The proof comes from the same shapes that narrow anything else — an `if`, its
negation, `&&`, `||`, a ternary, an early return — and it is taken away again by
anything that could have changed the value. A variant with exactly two cases
narrows on a false test as well as a true one, which is why `if (!r.Ok)` proves
`Fail`. Only a variant held in a local or a parameter can carry a proof (SL0285),
for the reason given in §2.8.

**Switching over one** covers the cases rather than constant values, and needs
no `default` once they are all there:

```csharp
double Area(Shape shape) {
    switch (shape) {
        case Circle c: return 3.14159 * c.Radius * c.Radius;
        case Rect r:   return r.Width * r.Height;
        case Empty:    return 0.0;
    }
}
```

Leaving a case out without a `default` is an error that names what is missing:

```
error[SL0436]: this switch over 'Shape' does not cover 'Rect' and 'Empty'; a
variant is the choice between its cases, so a switch that leaves one out has no
answer for it. Add the case, or a 'default'
```

An exhaustive switch is also a way out of a function, so `Area` above needs no
`return` after it.

`case Circle c:` binds `c` to what the case carries — a struct of that case's
fields, copied like any other struct value. `case Circle:` binds nothing and
narrows the switched value instead, so `shape.Radius` is readable in the arm.
Both are available; the binding is what to reach for when the thing switched on
was not a name to begin with. Labels stack as they do anywhere else, and a
section reached by two cases has proved nothing about which, so neither
narrowing nor a binding is available in it.

**Reference counting asks the tag.** A case may carry a `String`, a class, an
array — anything a struct field may be. Copying the variant retains what the
case actually present holds, and dropping it releases the same; the bytes of a
case that is not there are never counted, which is what lets them overlap at
all. The cost is a switch on the tag at each copy and each drop, and only for a
variant some case of which holds a reference. One that holds none is plain
bytes, and copies with a `memcpy` like any other struct.

**Where a variant may go.** It is a struct, so it goes wherever a struct goes:
across `extern "C"` if no case holds a reference and not at all if one does
(SL0284), into an array, into a field, across a thread when everything every
case carries could cross on its own. Two things it does not do yet: cross a
library boundary as a binary (SL0441 — the metadata carries layouts, and a
variant's cases are what a consumer would switch on), and carry `[Reflect]`
(SL0442 — the field tables would describe the tag and the payload, which are not
fields the program has).

### 2.7 `union` — every member at offset zero

A `union` is C's, and it is here for the reason `extern "C"` is here. A great
many C headers describe a value that is one of several things and record the
choice somewhere else — a tag in the enclosing struct, a length, a protocol —
and none of them can be bound without a type of this shape.

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

Every member starts where the union does. Its size is the widest member rounded
up to its alignment, and its alignment is the strictest of them — the same
arithmetic C does, and checked against the target's own compiler.

**A union is the untagged half of what a `variant` is** (§2.6). A variant knows
which case is present and will not let you read another; a union knows nothing
and will let you read any of them. Reach for a variant unless a C header is
telling you what shape to be.

**No member may hold a counted reference** (SL0468) — nor a struct that holds
one, at any depth. Which member is live is exactly what a union does not record,
so a copy could not know what to retain and a drop could not know what to
release. That is not a restriction added for safety; it is the question a union
cannot be asked. Hold the reference beside the union, or use a variant.

The usual C shape — a tag and a union together — works as it reads:

```csharp
public enum Kind : int { AsInt = 0, AsReal = 1 }

public struct Tagged {
    public Kind Which;
    public Word Value;
}
```

A union has no constructor and no destructor, as a struct has neither, and it
implements no interface, because an interface reference is a counted pointer and
a union is a plain C value (SL0302). `[Packed]` and `[Align]` apply to one as
they do to a struct. A generated C header writes it as a C `union`, member for
member.

### 2.7.1 Nameless members

A `struct` or `union` member may have no name, in which case its members are
reached as though they belonged to the type that holds it. This is C's, and the
Windows headers lean on it: `SYSTEM_INFO`, `OVERLAPPED` and `LARGE_INTEGER` all
begin with one.

```csharp
public struct SystemInfo {
    public union {
        public uint OemId;
        public struct {
            public ushort Architecture;
            public ushort Reserved;
        }
    }
    public uint PageSize;
}

info.Architecture       // reads the low half of the first word
info.OemId              // reads the whole of it
info.PageSize           // at offset 4, as in C
```

The member is real and carries the layout — a nameless `union` overlaps its
members and a nameless `struct` lays them out in order, exactly as a named one
would. Only the *name* is missing, and lookup reaches through it.

Lookup is breadth-first, so a name the outer type declares itself wins over one
further in. Two nameless members at the same depth both declaring it is an
error rather than a guess:

```
error[SL0492]: 'Value' is ambiguous: 2 nameless members of 'Ambiguous' declare
it. Give one of them a name, so that the one you mean can be said
```

A generated C header writes a nameless member back as one, nested where it was
written, so the header says what the source said.

### 2.8 `Result<T, E>` — how a function fails

Stainless does not unwind. There is no `throw`, no stack unwinding and no
`catch`, and there will not be: unwinding needs metadata on every frame and a
personality routine, and a failure that travels invisibly through code that
never mentioned it is the opposite of what the rest of the language does.

A function that can fail says so in its return type instead:

```csharp
Result<Config, IOError> Load(String path) {
    var text = File.ReadAllText(path);
    if (!text.Ok) { return Fail(text.Error); }
    return Ok(Parse(text.Value));
}
```

**`Result<T, E>` is an ordinary variant** (§2.6), declared in `Standard`, which
is imported everywhere:

```csharp
public variant Result<T, E> {
    Ok(T Value);
    Fail(E Error);
}
```

Every rule it appears to have is a rule variants have. `Ok` and `Fail` are its
cases, so `r.Ok` asks the tag; `Value` and `Error` are the fields those cases
carry, so reading one needs the compiler to know which case is there; and both
are written without type arguments because a case takes its variant from where
it is going. Being a variant is also what makes it small: only one case is ever
present, so a `Result<String, IOError>` is a tag and one pointer rather than a
flag and both halves. A call that succeeds allocates nothing.

**`Ok` and `Fail` take their type from where they are going.** Neither can be
written with type arguments — type arguments cannot be written at a call at all
(§4.4) — and one value could not say what both of them are: `Ok(4)` fixes `T`
and says nothing about `E`. So the compiler reads the type being returned,
assigned into, or passed as an argument, exactly as it does for a lambda:

```csharp
Result<int, Why> Doubled(int n) {
    if (n < 0) { return Fail(Why.TooSmall); }   // E from the return type
    return Ok(n * 2);                           // T from the return type
}

Result<int, Why> held = Ok(4);                  // and from a declared local
var loose = Ok(4);                              // error[SL0287]: nothing to infer from
```

For the same reason a module-level function may not be named `Ok` or `Fail`
(SL0414) — the general rule for any variant's case, §2.6. A *method* still may.

**`Value` and `Error` are readable only where it is known which one is there.**
This is the general rule for a variant's payload, and it is what makes a Result
different from a pair of fields that happen to sit together:

```csharp
var read = File.ReadAllText(path);
read.Value                     // error[SL0286]: nothing has established that
                               // 'read' succeeded
```

The proof can come from any of these:

| Shape | What it proves |
|---|---|
| `if (r.Ok) { … } else { … }` | `Value` in the first arm, `Error` in the second |
| `if (!r.Ok) { return …; }` | `Value` for the whole rest of the block |
| `r.Ok ? r.Value : f(r.Error)` | each arm, under its own branch |
| `if (a.Ok && b.Ok)` | both, inside the branch |
| `switch (r) { case Ok: … case Fail: … }` | each arm, and no `default` needed |

The early return is the one most code is written around, and it is why
`AlwaysExits` matters here: a branch that always leaves proves its opposite for
everything after it.

```csharp
var raw = File.ReadAllBytes(path);
if (!raw.Ok) { return Fail(raw.Error); }
use(raw.Value);                              // proved by the line above
```

Anything that could have changed the Result takes the proof away again — an
assignment to it, and, inside a loop, an assignment anywhere in the body:

```csharp
var r = Get();
if (!r.Ok) { return 0; }
r = Get();
return r.Value;               // error[SL0286]: the proof was about the old value
```

**What is not narrowed.** Only a Result held in a local or a parameter can
carry a proof, because that is the only thing a check can be *about*; a field
or a call result is refused with SL0285, and putting it in a local first is
both the fix and what the code wanted to say. A caller with a sensible default
needs no proof at all:

```csharp
int port = ParsePort(text).ValueOr(8080);
```

**What this is not.** A Result is for a failure a caller can do something
about. A bounds violation, a division by zero or a null dereference is a
mistake in the program rather than an outcome of it, and those still abort
through the runtime: threading a Result through every array index would make
every program worse to read in exchange for nothing.

### 2.9 `interface` — a contract, dispatched dynamically

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
(§7.3), so an interface property is one vtable slot per accessor and a class
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
[abi.md](abi.md) for the tables. An interface reference can be asked what it
really is, and cast to it, exactly as a class reference can §2.4.2.

**Interfaces do extend one another**, though, and a class implementing the
derived one implements the base too:

```csharp
public interface IShape { double Area(); }
public interface INamed : IShape { String Name(); }

public class Circle : INamed { ... }        // must supply Area and Name

INamed named = new Circle(2.0);
IShape shape = named;                       // free, and no conversion is emitted
```

The base's table is built for the class alongside the derived one, so a call
through either reference is the same four loads.

**A class may implement two instantiations of one generic interface**, because
each interface it implements gets its own table:

```csharp
public interface IEq<T> { bool Same(T other); }

public class Both : IEq<int>, IEq<String> {
    public bool Same(int other)    { ... }
    public bool Same(String other) { ... }
}
```

The two methods share a name and are told apart by their parameters (§7.1).
`IEq<int>`'s table takes the first and `IEq<String>`'s the second, so a call
through either reference reaches the right one, and a call on `Both` itself
picks by argument type. What may *not* be overloaded is a method of one
interface, since that is one slot.

### 2.10 Arrays

#### 2.10.1 `T[]` — a counted array

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

#### 2.10.2 `T[N]` — an inline array

```csharp
public struct FindData {
    public uint            Attributes;
    public ushort[260]     FileName;
    public ushort[14]      AlternateName;
}                                       // sizeof is 592, as it is in C
```

**This is C's array, and C# has nothing like it.** A `T[]` is a reference to a
counted heap object; a `T[N]` *is* its elements, laid out inside whatever
contains them. So a struct holding one is exactly as wide as the C struct it
mirrors, `sizeof` includes every element, and copying the struct copies the
array with it.

The length is written in the type rather than after the name — `ushort[260]
FileName`, not C's `ushort FileName[260]` — because Stainless writes the type
first everywhere else, and because it puts `T[N]` in a series with `T[]` and
`T[:]` rather than off to one side. A generated C header writes C's order,
outermost length first: `int[3][2]` here is `int32_t x[2][3]` there.

Because the length is part of the type it is known without a value to ask:

```csharp
int[4] counters;
counters.Length         // 4, a constant, not a load
counters[9]             // error[SL0490], at compile time
counters[variable]      // bounds checked, against a constant
```

A length must be an integer literal or a `const` holding one (SL0487) and at
least 1 (SL0488).

**An inline array may not hold a counted reference** (SL0486): every copy of
whatever held it would have to retain each element, which is the question a
union cannot answer either. `T[]` is one counted object rather than N of them.

**An inline array may not be a parameter by value** (SL0491). C decays an array
parameter to a pointer and Stainless has no decay, so passing one by value
would be both a silent copy of every element and a different ABI from the C it
is meant to match. `ref T[N]` is the one that lines up — it is `T (*)[N]` on
both sides:

```csharp
double Total(ref Matrix matrix) { ... }
```

`new T[n]` is unaffected and still builds a counted heap array: under `new`, a
length in brackets is the count rather than part of the type.

### 2.11 `T[:]` — part of an array

A slice names part of an array, as a value.

```csharp
var numbers = new int[6];

int[:] all    = numbers;          // an array is a slice of the whole of itself
int[:] middle = numbers[1:4];     // elements 1, 2 and 3
int[:] tail   = numbers[3:];      // to the end
int[:] head   = numbers[:2];      // from the beginning
```

The bounds are half-open, as everywhere: `numbers[1:4]` has three elements.
Either end may be left out and means the beginning or the length.

**A slice is a view, not a copy.** Writing through one writes the array it came
from, and `Length` is the slice's own rather than the array's — which is also
what an index is checked against:

```csharp
middle[0] = 100;              // numbers[1] is now 100
middle[3]                     // aborts: index 3, length 3
```

**Slicing a slice narrows it** rather than nesting: the result names the same
array, further in. So a slice is one indirection deep however many times it has
been cut.

**It is three words** — the array, where it starts, how far it runs — and it is a
struct, so it copies, is passed and is returned like one. It holds the array the
way any struct field holds a reference: **a slice cannot dangle**, because what
it points into is alive for as long as it is.

```csharp
Trace[:] Middle() {
    var traces = new Trace[3];
    ...
    return traces[1:2];       // the array outlives the function
}
```

That is the trade. A slice costs a reference count per copy and is not a value C
can be handed (SL0284, as for any struct holding a reference). What it buys is
that there are no lifetimes to explain: a slice is safe by the same rule
everything else here is safe by.

**An array converts to a slice implicitly**, because a slice of everything is
what an array already is; the other direction does not, because a slice is
generally of less than the whole. `foreach` walks a slice as it walks an array,
and `Standard.Collections` has `Sort` and `Reverse` over one:

```csharp
Sort(numbers);                // the whole of it
Sort(numbers[2:5]);           // three of them, in place, nothing copied
```

### 2.12 `enum` — a distinct type over an integer

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

### 2.13 `delegate` — a named function pointer

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
§2.14 — and only a non-capturing one can be a delegate, because there is nowhere
in a single pointer to keep what was captured.

### 2.14 Lambdas and closures

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

**A lambda written in a method can reach its object.** A field, a property,
`this` itself, and a method called without a receiver all resolve, and each is
captured by the same by-value rule as a local:

```csharp
class Scaler {
    public int Factor;

    int Triple(int n) { return n * 3; }

    public ITransform ByField()  { return value => value * Factor; }
    public ITransform ByThis()   { return value => value * this.Factor; }
    public ITransform ByMethod() { return value => Triple(value); }
}
```

`this` inside a lambda means the object the lambda was written in, never the
closure the compiler generated for it. A member read is captured as a value, so
`ByField` copies what `Factor` said when the closure was made; a method call
captures the object, because the call needs one.

**Capturing `this` keeps the object alive**, which makes an object that stores
its own closure a reference cycle. ARC cannot collect one, so break it with a
`weak` reference (§2.5) exactly as you would any other.

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

It offers `UnitCount()`, `ToPointer()`, which returns `ushort*`, and `ToText()`,
which transcodes back.

The return direction usually is not a `Utf16String` at all, because a wide API
answers by writing into a buffer the caller owns rather than by producing an
object. Two free functions take that shape directly:

```csharp
GetCurrentDirectoryW(capacity, buffer);
String here = Text.FromUtf16(buffer, units);        // a pointer and a length
String also = Text.FromNullTerminatedUtf16(buffer); // up to the first NUL
```

| Direction | Call | Cost |
|---|---|---|
| UTF-8 to UTF-16 | `text.ToUtf16()` | one allocation, two passes |
| UTF-16 to UTF-8 | `wide.ToText()` | one allocation, two passes |
| a buffer to UTF-8 | `Text.FromUtf16(units, count)` | one allocation, two passes |
| a buffer to UTF-8 | `Text.FromNullTerminatedUtf16(units)` | as above, plus the scan |

**Anything malformed becomes U+FFFD** in both directions, rather than being
rejected or passed through. That is not politeness: a `String` is UTF-8 by
invariant and everything downstream relies on it, and what a wide API hands back
is whatever was in the filesystem or on the clipboard — an unpaired surrogate is
a real thing to receive. A null pointer reads as the empty string, because a
wide call that failed leaves the caller holding one.

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

**Generic functions overload on the shape of their parameters.** Two templates
may share a name, and a call tries each one of the right arity, keeping those
that both infer and would accept the arguments; two survivors is an ambiguity
(SL0453) and none is the inference error. `Standard.Collections` has both
`Sort<T>(T[:])` and `Sort<T>(IList<T>)`, and `Sort(numbers)` and `Sort(list)`
each reach the right one.

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
compiled alongside your program.

**A generic that nobody instantiates costs nothing**, because there is nothing
to emit until it is instantiated. That covers `List<T>`, `Dictionary<K, V>`,
`Mutex<T>`, every container and every concurrent one.

**A non-generic function or class is emitted whether or not it is used**, and
that is a real cost the compiler should not be charging: every stdlib module is
compiled with your program whether you import it or not, so a hello-world
binary today carries 228 stdlib functions it never calls — 56 from
`Standard.Math`, 52 from `Standard.IO`, and so on. Nothing prunes them: there
is no reachability pass, and the emitted module is one object file, so the
linker cannot drop them either. Compiling with `-ffunction-sections` and
`/OPT:REF` recovers about a quarter of the binary, and a reachability pass from
`Main` would recover the rest. Neither is done.

| Module | Contents | Imported |
|---|---|---|
| `Standard.Text` | `String`, `StringBuilder`, `Utf16String`, conversions | automatically |
| `Standard.Console` | `Write`, `WriteLine`, `WriteError` | on request |
| `Standard.Collections` | the interfaces below, and every container | on request |
| `Standard.Concurrent` | the containers several threads may share | on request |
| `Standard.Threading` | `Mutex<T>`, atomics, the job pool | on request |
| `Standard.Math` | arithmetic that is not an operator | on request |
| `Standard.Reflection` | `[Reflect]`, `typeof`, the field tables | on request |
| `Standard.IO` | streams and `IOError` | on request |
| `Standard.File` | whole-file operations | on request |
| `Standard.Directory` | making, removing and listing | on request |
| `Standard.Path` | taking paths apart, textually | on request |
| `Standard` | `Result<T, E>`, `[Flags]`, and the rest of what the language itself reads | automatically |

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

**What `Value()` still does not promise.** It hands out what the lock protects,
and nothing stops the caller keeping it after the guard has gone. That is a
lifetime question, and Stainless does not answer it yet; C# has the same hole
and Rust closes it with lifetimes.

It used to be worse than a discipline. `Value()` retains what it returns and the
caller releases it, usually outside the lock, so two threads performed an
unsynchronized read-modify-write on the count — it drifted down and the object
was freed while the mutex still held it. Reference counts are atomic now, which
closes that half; see [concurrency.md](concurrency.md) §10 for why the narrower
fix of "atomic counts for `[Shared]` types" would not have.

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

**Two things this is not.** A `TaskScope` job takes a `byte*` and casts it back,
so nothing checks what crosses that particular boundary — unlike `spawn`, where
§9.5 applies; and keeping a `Guard` alive is a discipline, not a guarantee. See [concurrency.md](concurrency.md) for the model these are aiming
at and which parts of it the compiler does not yet enforce.

This module is not free when unused: `AtomicLong`, `AtomicBool` and `TaskScope`
are ordinary classes rather than templates, so their code is emitted whether or
not a program mentions them. That is true of every non-generic declaration in
the standard library, and §5.1 says what it costs and why nothing prunes it.

### 5.3 Interfaces are named with a leading I

`IComparable<T>`, `IReadOnlyList<T>`, `IWritable` — the C# convention, and the
one the standard library follows. It is a convention, not a rule the compiler
enforces.

### 5.4 `Standard.Collections`

```csharp
public interface IEquatable<T>     { bool EqualTo(T other); }
public interface IComparable<T>    { int CompareTo(T other); }
public interface IHashable         { nuint HashCode(); }

public interface IReadOnlyList<T>  { nuint Count(); T At(nuint index); }

public interface IList<T> : IReadOnlyList<T> {
    void Add(T item);
    void Set(nuint index, T item);
    void Clear();
}
```

`CompareTo` returns a negative number, zero, or a positive number when the
value orders before, with, or after the argument.

**A primitive, an enum and a String implement all three without saying so.**
None of them can carry a declaration — a primitive is not a class, an enum is
its integer, and `String` belongs to the runtime — but they are exactly the
types people sort by and use as keys, so a rule that excluded them would
exclude the point of having constraints. The compiler recognises `CompareTo`,
`EqualTo` and `HashCode` on those types and lowers each to a comparison or a
runtime call:

```csharp
var numbers = new List<int>();
Sort(numbers);                          // int satisfies IComparable<int>

var ages = new Dictionary<String, int>();
ages.Set("ada", 36);                    // String satisfies IEquatable + IHashable

3.CompareTo(5);                         // -1
"apple".CompareTo("banana");            // -1, by bytes, which for UTF-8 is by code point
```

A class still says what it implements, and a declared member always wins over
the built-in one.

**The containers**

| Type | Backed by | Notes |
|---|---|---|
| `List<T>` | one array, doubling | `IList<T>`, `IEnumerable<T>` |
| `Dictionary<K, V>` | open addressing | `K : IEquatable<K>, IHashable`; iterates `Pair<K, V>` |
| `HashSet<T>` | open addressing | `UnionWith`, `IntersectWith`, `ExceptWith` |
| `Queue<T>` | circular buffer | `Enqueue`, `Dequeue`, `Peek` |
| `Stack<T>` | one array | `Push`, `Pop`, `Peek` |
| `LinkedList<T>` | an index pool | handles, not references — see below |
| `SortedList<K, V>` | two sorted arrays | `K : IComparable<K>`; binary search, ordered iteration |

Every one of them is array-backed, which for the last two is not the usual
choice. It is the right one here: ARC cannot collect a cycle, so a doubly
linked list of objects would leak unless every back-link were weak, and a weak
reference is not usable without a way to prove it is still there. Links as
indices into a pool have neither problem.

`Dictionary` and `HashSet` probe linearly and **shift the following cluster
back on removal rather than leaving a tombstone**, so a table that is added to
and removed from for a long time does not slowly fill with markers that only a
rehash could clear.

`LinkedList<T>` names each node with a **handle**: a `nint` that stays valid
until that node is removed, and is `-1` for "no node". Handles are what make
the middle of the list reachable in constant time, which is the only reason to
choose it over a `List<T>`:

```csharp
var line = new LinkedList<String>();
var first = line.AddLast("a");
line.AddLast("c");
line.InsertAfter(first, "b");

for (nint at = line.First(); at >= 0; at = line.After(at)) {
    Console.WriteLine(line.ValueAt(at));
}
```

Asking a container for something it does not have — `Get` with an absent key,
`Dequeue` on an empty queue — aborts, the same way an out-of-range index does.
Use `GetOr`, `ContainsKey` or `IsEmpty` where a miss is an ordinary outcome.

Alongside the containers are `Largest`, `Smallest`, `IndexOf` and `Sort`, each
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

### 5.5 `Standard.Math`

```csharp
import Standard.Math;

Math.Sqrt(2.0);
Math.Clamp(x, 0, 10);
Math.GreatestCommonDivisor(48, 18);
```

A module is a scope, so this needs no static class to live in: `Math.Sqrt(x)`
is a module-qualified call. The floating-point functions are the C library's,
declared and called directly — there is no wrapper layer and no conversion,
because a Stainless `double` *is* a C `double`.

`Abs`, `Min`, `Max`, `Clamp` and `Sign` are overloaded across `int`, `long`,
`nuint` and `double`, resolved by argument type. Alongside them are the usual
transcendentals, `Floor`/`Ceiling`/`Round`/`Truncate`, `IsNaN`/`IsInfinite`/
`IsFinite`, `Lerp` and `Near`, the integer `GreatestCommonDivisor` and
`DivideCeiling`, and the bit functions `PopCount`, `LeadingZeros`,
`TrailingZeros`, `IsPowerOfTwo` and `NextPowerOfTwo`.

`Round` takes halves away from zero, which is C's rule rather than the banker's
rounding C# uses by default.

### 5.6 `Standard.Concurrent`

```csharp
import Standard.Concurrent;

var work = new ConcurrentQueue<int>();
parallel {
    spawn Fill(work, 0, 500);
    spawn Fill(work, 500, 1000);
}

var got = work.TryDequeue();
if (got.Ok) { use(got.Value); }
```

`ConcurrentQueue<T>`, `ConcurrentStack<T>`, `ConcurrentDictionary<K, V>` and
`Channel<T>`, each `[Shared]` and each safe for several threads at once.

Every operation that can fail returns a `Taken<T>` — whether there was
anything, and what it was — rather than answering in two calls. There is no
`Peek` and then `Dequeue`, because between the two another thread may have
taken it. `DequeueOr(fallback)` is the same answer without the allocation.

`Channel<T>` is the producer-consumer hand-off: `Take` **blocks** until
something arrives or the channel is closed, and `Close` wakes every waiter.
What was already sent is still delivered; once it is drained, every `Take`
returns at once with `Ok` false.

**Each of these owns an ordinary collection in a field and never hands out a
reference to it.** That began as a correctness requirement: reference counts
were not atomic, so an object returned out of a lock was retained and released
by several threads at once and its count drifted down until it was freed while
still in use. Counts are atomic now and the hazard is gone, but the shape is
still the right one — reading a field to call a method on it borrows, and a
container that never hands its collection out cannot be used wrongly by a caller
who keeps what it lent.

### 5.7 `Standard.IO`, `File`, `Directory` and `Path`

```csharp
import Standard.File;
import Standard.IO;

var read = File.ReadAllText("config.json");
if (read.Ok) { use(read.Value); }
else         { Console.WriteError(IO.Describe(read.Error)); }
```

Stainless has no static classes, so what C# spells `File.ReadAllText` is a
module-qualified call to a module-level function. That is the mapping
throughout: a module is the static class.

**How failure is reported.** Stainless does not unwind (§2.8), so the outcome
comes back as a value, in one of three shapes:

| Shape | Used by | Reads as |
|---|---|---|
| `Result<T, IOError>` | anything that produces a value | `if (r.Ok) { r.Value }` |
| `IOError` | anything that does not | `if (File.Delete(p) != IOError.None)` |
| the stream's own `Error()` | streams | checked after a loop, not each step |

Three shapes rather than one is deliberate: a single shape makes the common
cases read worse than the rare one. There is no failed value to read by
mistake — `Value` does not compile until the check has happened — and a caller
that would rather carry on writes `read.ValueOr("")`.

**Streams.** `IStream` is `Read`/`Write`/`Seek`/`Length`/`Position`/`Flush`/
`Close` plus `CanRead`/`CanWrite`/`CanSeek`. `FileStream` and `MemoryStream`
implement it.

```csharp
var file = File.OpenRead("data.bin");
if (file.IsOpen()) {
    var whole = IO.ReadToEnd(file);
    file.Close();
}
```

A `FileStream`'s construction *is* the open, so one always exists and
`IsOpen()` says whether it holds a file — which avoids handing back a null the
caller could not unwrap. Closing is also the destructor's job, so a stream that
goes out of scope releases its handle either way.

Opening takes a `FileMode` (`Open`, `Create`, `Append`) and a `[Flags]`
`FileAccess` (`Read`, `Write`, `ReadWrite`).

**`File`** has `Exists`, `Size`, `Modified`, `Delete`, `Rename`, `Copy`, the
openers, and the whole-file pairs `ReadAllText`/`WriteAllText`,
`ReadAllBytes`/`WriteAllBytes`, `ReadAllLines`/`WriteAllLines`, and
`AppendText`.

**`Directory`** has `Exists`, `Create`, `CreateAll`, `Delete`, and the listings
`Entries`, `Files`, `Directories` and `AllFiles`. Listings return full paths
rather than bare names, in the platform's order.

**`Path`** is purely textual and touches no disk: `Join`, `FileName`,
`DirectoryName`, `Extension`, `WithoutExtension`, `WithExtension`, `IsRooted`
and `Split`. Both `/` and `\` are accepted when reading a path apart, because
Windows accepts both and a path from a config file may use either.

**Paths are UTF-8, and stay correct.** A Stainless `String` is already UTF-8,
and on Windows the runtime widens every path to UTF-16 before it reaches the
operating system — the narrow CRT entry points would read those bytes in the
active code page, which works by accident for ASCII and fails for everything
else.

### 5.8 Interfaces may extend interfaces

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

**Overloading is by parameter type**, for methods as much as for free
functions. A return type alone does not distinguish two of them, because a call
does not always say what it wants back:

```csharp
class Printer {
    public String Show(int n)    { return "int"; }
    public String Show(String s) { return "text"; }
    public String Show(double d) { return "double"; }
}
```

Which one a call means is decided from the arguments, exactly as it is for a
module-level function: a call that fits none is SL0263 and one that fits
several equally is SL0264.

**An interface method may not be overloaded.** An interface gives each of its
methods a dispatch slot by position, so two of a name in one interface would be
a call the receiver could not resolve:

```
error[SL0416]: 'IBad' already declares 'Same'; an interface method may not be
overloaded, because dispatch gives each one a single slot
```

A *class* implementing two interfaces whose methods share a name is a different
matter, and it works — see §2.9.

### 7.2 `ref` and `in` parameters

A parameter is a copy unless it says otherwise. `ref` and `in` say otherwise:
both pass the caller's storage rather than a copy of it, and the difference
between them is whether the callee may write to it.

```csharp
void Bump(ref int n) { n = n + 1; }
double LengthSquared(in Point p) { return p.X * p.X + p.Y * p.Y; }

int count = 1;
Bump(ref count);              // count is 2
LengthSquared(origin);        // no copy, and origin cannot change
```

**`ref` is written at the call as well as the declaration** (SL0445). A reader
of the line should be able to see that the value may come back changed, and
there is nothing else on it that would say so. `in` is not written at the call:
it promises the opposite, and a promise not to change anything needs no warning.

**A `ref` argument must name storage** — a local, a parameter, a field, an array
element or a dereference. A call result or a literal has no storage to pass
(SL0443), and a `const` local or a `static readonly` has storage that may not be
written (SL0444). An `in` argument needs no such thing: a value with nowhere to
live is given a temporary, which lasts as long as the frame.

**A `ref` argument is not converted.** `Bump(ref d)` where `d` is a `double` is
an error (SL0447) rather than a widening, because the callee writes back through
the pointer and a converted copy would have nowhere to put the result. An `in`
argument converts like a value one, because what it receives may be that
temporary.

**Writing to an `in` is refused** (SL0448), including through one of its fields.
Passing one on as a `ref` is refused for the same reason (SL0444).

**The mode is part of a signature.** Two overloads may not differ only in it
(SL0211), a class does not implement `void Adjust(ref int)` with `void
Adjust(int)` (SL0307), and a delegate's signature carries it. A spawned call may
not take one at all (SL0449): it would hand a job the address of the caller's
variable, and two jobs given the same one would race.

**At the ABI a `ref T` is exactly a `T*`**, which is what lets one cross a
language boundary with nothing in between:

```csharp
extern "C" double modf(double value, ref double integral);

double whole = 0.0;
double fraction = modf(3.75, ref whole);      // whole is 3, fraction is 0.75
```

A generated C header writes `ref T` as `T*` and `in T` as `const T*`. C++ names
mangle the same way, so `export "C++" void geometry::scale(ref double f, int n)`
is the symbol a C++ `void geometry::scale(double*, int)` calls.

**What is not here.** No `out`: it would need definite-assignment analysis to be
worth having over `ref`. No `ref` locals and no `ref` returns, which would need
a lifetime story the language does not have.

### 7.3 Properties

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

## 8. Interoperability and libraries

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

**A declaration joins the module it was written in**, as an ordinary member,
and so is private to that module unless it says `public`. That is what a binding
library is made of: a module of `public extern "C"` declarations is one another
module can call by the real names, with no forwarding layer in between.

```csharp
public extern "C" {
    int   GetSystemMetrics(int index);
    void* CreateWindowExW(uint extendedStyle, ushort* className, /* ... */);
}
```

A modifier written before the block belongs to every declaration in it, which is
the point of writing one there; `public` may also be written on a single member
inside. Two modules may declare the same C function, because a declaration names
a symbol rather than defining one — but only one of them should make it
`public`, or a file importing both has an ambiguous name.

**A `...` may be called and not written.** `printf` is bound with one and works;
a function this program *defines* may not have one, whatever its linkage. Nothing
in the language reads the extra arguments -- there is no `va_list` -- so the
definition would ignore them while the generated header promised the variadic
convention, which on Win64 wants floating-point arguments duplicated into the
integer registers and on SysV wants `al` to carry a vector-register count. The
integer arguments would survive and the floating-point ones would not, silently.

```
error[SL0493]: 'log_line' cannot be variadic; '...' may only be written on an
'extern "C"' declaration, because there is no 'va_list' to read the extra
arguments with. Take an array, a slice, or a count and a pointer
```

**`"C"` and `"C++"` are the conventions there are.** The string is checked, and
anything else is rejected:

```
error[SL0102]: unsupported linkage convention "Rust"; "C" and "C++" are supported
```

C++ linkage is §8.1.

**What a signature may carry.** Plain C values — primitives, pointers, and
structs of plain data — cross freely. A struct that holds a reference does not,
in either direction, because C would copy its bytes and leave the count behind
(§2.2):

```
error[SL0284]: 'Holder' holds a reference, so parameter 'h' cannot cross
extern "C"; C would copy its bytes and leave the count behind. Pass a struct of
plain data, or a raw pointer
```

### 8.1 C++ linkage

A C++ function is reached by mangling its signature the way the target's
compiler does, with no shim and no `extern "C"` on either side:

```csharp
extern "C++" int cpp_add(int a, int b);
extern "C++" double geometry::area(double w, double h);

export "C++" int Doubled(int n) { return n * 2; }
export "C++" double shapes::Perimeter(double w, double h) { return 2.0 * (w + h); }
```

A namespace is written on the declaration with `::`. It decides the linker name
and nothing else: the function joins the module it was declared in, so it is
called by its plain name — `area(3.0, 4.0)`, not `geometry.area(...)`. An
`export "C++"` with no namespace written takes the module's, because a module is
what Stainless calls a namespace, so `Doubled` above is `Interop::Doubled`.

**There are two C++ ABIs and they share nothing.** C++ has none of its own: the
platform specifies how C-shaped things work and says nothing about mangling,
vtables or unwinding, so the compilers each filled it in. gcc and clang use the
Itanium scheme; MSVC, and clang when it targets MSVC, use Microsoft's. The two
disagree about the prefix, the order of the qualifiers, whether the return type
is encoded at all, and how a repeated type is abbreviated:

| Declaration | Itanium | Microsoft |
|---|---|---|
| `int add(int, int)` | `_Z3addii` | `?add@@YAHHH@Z` |
| `void nothing()` | `_Z7nothingv` | `?nothing@@YAXXZ` |
| `int deref(int*, int*)` | `_Z5derefPiS_` | `?deref@@YAHPEAH0@Z` |
| `geometry::area(double, double)` | `_ZN8geometry4areaEdd` | `?area@geometry@@YANNN@Z` |
| `geometry::mix(int*, double*, int*)` | `_ZN8geometry3mixEPiPdS0_` | `?mix@geometry@@YAHPEAHPEAN0@Z` |

The compiler emits whichever the target uses, and `STAINLESS_CPP_ABI` overrides
the choice so that the scheme a host does not use can still be checked against a
real compiler.

Both schemes are stable, which is what makes this worth writing: Itanium has
been for far longer, and Microsoft's since Visual Studio 2015, whose v140
through v143 toolsets interoperate. What is *not* stable is the standard
library, whose types and templates are where the churn actually lives — which is
why nothing here touches them.

**How the fixed-width types map.** Stainless integers have exact sizes and C++'s
do not, so `long` is spelled as whatever is 64 bits on the target:

| Stainless | C++ |
|---|---|
| `sbyte` `byte` `short` `ushort` `int` `uint` | `signed char` `unsigned char` `short` `unsigned short` `int` `unsigned int` |
| `long` `ulong` | `long long` `unsigned long long` — C++'s `long` is 32-bit on Windows |
| `nint` `nuint` | pointer-sized: `long` on Itanium, `__int64` on Microsoft |
| `char` | `char`; it is one byte, not UTF-16 |
| `bool` `float` `double` | `bool` `float` `double` |

**What is not there yet.** Free functions only. A C++ *class* cannot be named,
which is what would need object layout, vtable layout, and an answer for
constructors, destructors and exceptions crossing a boundary Stainless does not
unwind through. Templates are not addressed and will not be by mangling alone: a
template has no symbol until something instantiates it.

### 8.2 Building a shared library

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

### 8.3 What may cross a library boundary

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

### 8.4 A Stainless library consumed by Stainless

Stainless has no headers, and inside one compilation it needs none: every
declaration is visible because every file is compiled together. A library is
where that stops. The consumer is a separate compilation with no access to the
source, so something has to carry what the source would have said.

```
stainless build lib --shared -o build/shapes.dll --metadata build/shapes.slmod
stainless build app.sl --reference build/shapes.slmod build/shapes.lib -o app.exe
```

The `.slmod` is generated, never edited, and cannot drift from the library
because it is written from the same bound program. It describes the public
surface: layouts, field offsets, signatures, and the linker names to call.

```csharp
import Library.Shapes;                  // a module this compilation has no source for

int Main() {
    var counter = new Counter("clicks", tally);
    counter.Step = 3;                   // properties, fields and methods all work
    counter.Bump();
    Console.WriteLine(counter.Describe());
    return 0;
}
```

**Reference counting reaches across.** A class is allocated through the
library's own TypeInfo, so the object gets the destructor the library compiled
for it, and the consumer's `release` runs it at the right moment.

**`public` still does not export.** It answers which modules may see a
declaration, and a C library's surface is stated once with `export "C"`. Asking
for `--metadata` says something different — that another Stainless compilation
will bind against this — and that surface is exactly the public declarations the
metadata describes.

**What does not cross, and why.** Both are consequences of the language
compiling a whole program at once, and the compiler says so where the library is
built rather than leaving the consumer to find a public type mysteriously
missing:

| | |
|---|---|
| a generic (SL0419) | a template emits nothing until it is instantiated, so a consumer with only the binary has nothing to instantiate. A generic crosses as source |
| a class implementing an interface (SL0420) | a dispatch table is indexed by an interface id assigned across a whole program, and a library and its consumer are two different programs |
| a variant (SL0441) | its cases are what a consumer would switch on, and the metadata carries layouts rather than cases |
| a slice, `T[:]` | it is a type the compiler builds on demand rather than one the source declared, so there is no name for a consumer to resolve |

**And anything reaching one of those through a field or a signature** is reported
the same way (SL0477). A public struct with a variant field would otherwise be
described happily, and the consumer would be the one to find that the field's
type is a name nothing can resolve — which is precisely the failure these
warnings exist to move to this side of the boundary.

**One thing to know about output.** Each binary links its own copy of the
runtime, so each has its own C stdio buffer. Text written from inside a library
and text written by its consumer do not interleave in the order they were
written unless something flushes. Shipping the runtime as its own shared library
would fix that, and would also put both sides on one allocator; that is still
not done.

### 8.5 Linking a platform library

Object files, static archives and import libraries can be listed among the
source paths, and are handed to the linker as they are. A library the linker can
find for itself is named with `-l` instead:

```
stainless build gui.sl bindings/win32/api/User32.sl bindings/win32/Ui.sl -l user32
```

`-l user32` reaches the Windows SDK's `user32.lib` through the linker's own
search path, rather than through whichever SDK version happens to be installed.
The spelling is the one every C toolchain takes, `-l name` or `-lname`.

**A file can name its own library**, which is usually better: the module that
calls into user32 is the one that knows it needs user32, and saying so there
stops every program that compiles it from repeating the name.

```csharp
#pragma comment(lib, "user32")
```

This is MSVC's spelling, and it is the only pragma Stainless has. Both
`"user32"` and `"user32.lib"` are accepted — the linker wants the first and a C
programmer will type the second. A pragma inside a branch `#if` did not take
means nothing, as a declaration there would. The names are gathered from every
file and merged with any `-l`, so linking a library twice is not an error.

**A library is needed by the code that is compiled, not by the code that runs.**
An undefined symbol is an error before the dead-strip that would have removed
the function referring to it, so compiling a module full of `extern "C"`
declarations does not cost anything, but compiling a *wrapper* that calls one
makes its library necessary whether or not the program ever reaches it. That is
why [bindings/win32](../bindings/win32) is source a program chooses to compile
rather than part of the standard library, which is compiled into everything --
and why it keeps its declarations in `Win32.<Dll>` modules apart from the
conveniences, so that importing the whole Windows API can stay free.

A linker failure says which of the two it is:

```
error: the linker could not find everything the program refers to:
lld-link: error: undefined symbol: GetSystemMetrics
A name declared 'extern "C"' has to come from somewhere. Link what defines it:
'-l <name>' for a library the linker can find on its own, or its path as an
ordinary input.
```

## 9. Statements and expressions

```csharp
int x = 10;             // explicitly typed local
var y = x + 1;          // inferred
const int Limit = 64;   // compile-time constant

if (y > 10) { ... } else { ... }
while (y > 0) { y = y - 1; }
for (int i = 0; i < 10; i = i + 1) { ... }
foreach (int n in numbers) { ... }
switch (y) { case 0: return 0; default: break; }
return y;
```

Three operators answer what C's answer, which is how a binding checks itself
against a header:

```csharp
sizeof(Msg)                 // 48, as C computes it
alignof(Msg)                // 8
offsetof(Msg, LParam)       // 24
```

`sizeof` and `alignof` take a type; `offsetof` takes a type and one of its
fields. A bit-field has no byte offset of its own, so `offsetof` refuses one
(SL0482), as C does. On a **class** the offset counts from the start of the
allocation rather than from the first field, because a class reference points
at the object header (§2 of [abi.md](abi.md)) — so the number is what to add to
the reference you are holding.

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

**The arithmetic C leaves undefined.** C compiles these to whatever falls out,
and an optimiser is entitled to assume they never happen — which is worse than
a wrong answer, because it can delete the code around them. Stainless defines
all three:

| Expression | C | Stainless |
|---|---|---|
| `1 << 40` on an `int` | undefined | `1 << (40 & 31)` = 256, as in C# |
| `x / 0` | undefined | aborts, the way an out-of-range index does |
| `int.Smallest / -1` | undefined | aborts; the result is not representable |

A shift count is reduced modulo the operand's width, which costs one `and` and
matches what a C# reader expects. Division is checked where the divisor is not
already known: a constant divisor is checked at compile time instead, and
`10 / 0` is an error rather than a program that runs.

```
error[SL0415]: division by zero
```

Overflow of `+`, `-` and `*` is **not** in that table: it wraps, as C# does
unchecked, and is defined rather than undefined.

### 9.1 `switch`

```csharp
switch (level) {
    case Level.Low:     return "low";
    case Level.Warning: return "warning";
    case Level.Severe:  return "severe";
    default:            return "fatal";
}
```

The value may be an integer, a `char`, a `bool`, an enum, a `String` or a
variant. For everything but a variant, each label is a constant of that type and
no two may name the same value. An enum, integer, char or bool switch becomes
one LLVM `switch` instruction, which decides for itself whether a jump table
beats a chain of comparisons. A `String` switch compares in order against the
runtime's string equality.

**A switch over a variant names cases rather than values** (§2.6). It is the one
kind that may be exhaustive, and then needs no `default`; it is also the one
where a label may bind what the case carries.

```csharp
switch (shape) {
    case Circle c: return c.Radius;     // binds the payload
    case Rect:     return shape.Width;  // narrows the switched value
    case Empty:    return 0.0;
}                                       // no default: every case is covered
```

The tag is a byte, so this is an LLVM `switch` like an enum's.

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

A `default` is optional except over a variant, where leaving a case out without
one is SL0436. Elsewhere a value that matches nothing falls past the whole
statement: there is no exhaustiveness requirement on an enum, whose value need
not be one of its members. There is no `goto case`. Each section has its own
scope, so two sections may declare the same local name — which C# does not
allow, having put the whole switch in one scope.

There is no `switch` *expression*, and the only pattern is a variant's case:
no type patterns, no constants inside one, no guards. This is the C# statement
plus the one thing a variant needs to be readable at all.

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

*What* may cross into a job is checked separately, by type, and is the rule in
§9.5: plain data, a `String`, a `[Shared]` class, or an array of plain data.
What is still unchecked is how long a borrowed thing lives — see
[concurrency.md](concurrency.md) for the model being aimed at and which parts
of it the compiler enforces today.

### 9.3 `const` and `static readonly`

A `const` is a compile-time value inlined at every use, so it holds what fits in
one: a number, a `bool`, a `char` or an enum member. Its initializer is a
literal, or a negated one — `const int GwlpUserData = -21;` — since a C header
is full of those.

A `String` is not one of them. It is a counted object, and inlining a pointer to
its bytes would produce something that looks like a `String`, passes every check
and is not one, so it is refused with the alternative:

```
error[SL0478]: a 'const' holds a number, a bool, a char or an enum, and 'String'
is none of those. Write 'static readonly String Greeting = ...' instead, which
has storage rather than being inlined
```

The literal has to suit the declared type, because the alternative is not an
error but a zero — one that compiles, runs, and is wrong everywhere the constant
was used:

```
error[SL0479]: 'Mask' is declared 'int', and a floating-point literal is not one
```

A character literal suits an integer, as it does in C#, so
`const int Newline = '
';` is fine.

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
| plain data — primitives, enums, pointers, delegates, and a `struct` of the same | there is no reference count to race over |
| `String` | immutable, and its bytes live inside the object |
| a class marked `[Shared]` | the author asserts it synchronizes itself |
| `T[]` where `T` is plain data | a job borrows it without retaining it |

Everything else is rejected, and this is a rule rather than a warning. Counting
is not what it protects: reference counts are atomic, so sharing an object no
longer corrupts its count. What nothing synchronizes is the object's *contents*,
and two threads writing one field is a race no counting scheme could have saved.

A `struct` is as safe as what is inside it, so one holding only primitives and
`String`s crosses freely and one holding a `List<T>` does not.

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
A third — `Mutex<T>` racing on the reference count of what it guarded — is
closed, because counts are atomic now (§5.2 and §5 of the ABI notes). See
[concurrency.md](concurrency.md) for the two that are left.

## 10. Conditional compilation

Some code is only for one platform, and some is only for a build that asked for
it. Stainless chooses between them the way C# does: with directives, evaluated
while the file is being read.

```csharp
#if WINDOWS
extern "C" void* VirtualAlloc(void* at, nuint size, uint type, uint protect);
#elif UNIX
extern "C" void* mmap(void* at, nuint size, int prot, int flags, int fd, long offset);
#else
#error this platform has no page allocator here
#endif
```

**A branch that is not taken is never lexed.** So it need not parse, need not
resolve, and cannot be broken by a change made somewhere else — which is the
whole reason for choosing this early rather than in the binder. A branch for a
platform you have never built on is text until the day it is compiled.

**There is no macro, no textual substitution and no `#include`.** A name always
means itself, and a declaration is still found without a header. That is the
part of "no preprocessor" that mattered; `#if` was never what made C headers
what they are.

**The directives** are `#if`, `#elif`, `#else`, `#endif`, `#define`, `#undef`,
`#error`, `#warning`, `#region` and `#endregion`. Anything else is an error
rather than something to be ignored. A directive must begin its line, and may be
indented; groups nest.

**A condition** is a name, `true`, `false`, `!`, `&&`, `||` and parentheses — the
same grammar C# has, minus `==` and `!=`, which nothing needs. **A name nobody
defined is false**, so a condition may test for something this build has never
heard of.

**`#define` and `#undef` take one name** and must come before the first
declaration in the file, as in C#: a symbol whose meaning changed halfway down
would make the lines above and below it disagree. They affect their own file
only.

**The symbols that describe the target are always defined:**

| Symbol | When |
|---|---|
| `WINDOWS`, `LINUX`, `MACOS`, `FREEBSD` | the operating system |
| `UNIX` | any of the above but Windows |
| `X64`, `ARM64`, `X86`, `ARM` | the architecture |
| `STAINLESS` | always |

Everything else comes from `-D` on the command line:

```
stainless build src -D FASTMATH -D TELEMETRY
```

There is deliberately no `DEBUG` among the built-ins. What it ought to mean is
the programmer's business, and inferring it from an optimisation level would be
a rule nobody asked for.

`#pragma` is the one directive that is not about choosing a branch; it is
covered in §8.5.

A whole file may be guarded, which is how a platform binding is written:
[bindings/win32](../bindings/win32) declares its `module` and then wraps
everything else in `#if WINDOWS`, so on any other platform those modules exist
and are empty rather than failing to build. A program that imports one and
guards its own uses compiles everywhere.
