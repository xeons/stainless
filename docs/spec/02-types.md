<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 2. Types

## 2.1 Primitives

Names and sizes match C# exactly.

| Stainless | Size | C equivalent |
|---|---|---|
| `sbyte` `short` `int` `long` | 1/2/4/8 | `int8_t` … `int64_t` |
| `byte` `ushort` `uint` `ulong` | 1/2/4/8 | `uint8_t` … `uint64_t` |
| `nint` `nuint` | pointer | `intptr_t` / `size_t` |
| `float` `double` | 4/8 | `float` / `double` |
| `bool` | 1 | `bool` |
| `char` | 1 | `char` — one UTF-8 code unit |
| `char16` | 2 | `char16_t` — one UTF-16 code unit |
| `char32` | 4 | `char32_t` — one Unicode scalar |
| `void` | 0 | `void` |

`void` is the absence of a value rather than a value of no size, so the only
place it can be written is what a function returns (SL0309). There is no
variable, field, parameter or type argument of it, and no array or slice of one
(SL0310, SL0451). `void*` is not a value of it but a pointer, and means what
C's does.

The three code unit types are **three encodings, not three widths of one
type**, and none of them converts to another without a cast:

```csharp
char   a = 'A';                 // U+0041, one UTF-8 byte
char16 e = 'é';                 // U+00E9: two bytes, but one UTF-16 unit
char32 g = '😀';                // U+1F600: a surrogate pair, so one scalar

char16 wrong = a;               // error: an encoding is not a width
char16 right = (char16)a;       // allowed, and says so at the call site
```

```
error[SL0527]: 'char' and 'char16' are different encodings, not different
widths of one, so one does not become the other on its own; a cast '(char16)'
moves the bits across and re-encodes nothing
```

That is not pedantry. `'é'` is `C3 A9` in UTF-8, `00E9` in UTF-16 and
`000000E9` as a scalar; widening the first byte of the UTF-8 form to sixteen
bits gives `00C3`, which is a different character. A conversion that looks free
and silently re-labels text is the bug the rule exists to stop.

A **character literal is one Unicode scalar**, written directly or as an
escape, and takes the narrowest of the three that holds it in a single unit:

```csharp
char16 japan   = '\u65E5';       // four hex digits, up to U+FFFF
char32 grin    = '\U0001F600';   // eight, which is the only way past U+FFFF
const int Tab  = '\t';           // still an ordinary integer constant
```

```
error[SL0527]: U+00E9 takes 2 bytes of UTF-8, so it is not one 'char';
declare it 'char16' or 'char32'

error[SL0526]: U+D800 is not a Unicode scalar value, so \u cannot name it;
scalars stop at U+10FFFF and the surrogate range U+D800 to U+DFFF is reserved
for UTF-16 pairs
```

**One scalar means one**, so `''` is not a character (SL0010); `'\0'` is how
the zero one is written. And `\u` takes exactly four hex digits where `\U`
takes eight (SL0008) — a short one is a mistake rather than a smaller number,
since `"\u12"` reading as U+0012 is a value nobody wrote. `\x` is the
exception and is a byte in one digit or two, as in C.

Against **every other integer they behave as integers**: `char16` and `ushort`
are the same width and convert freely, arithmetic works, and a `switch` takes
them. It is only each other they refuse.

## 2.2 `struct` — value type, C layout

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

**A struct may also hold a reference**, and `Result<T, TError>` is the reason it may:

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
([§9.5](09-statements-expressions.md#95-what-may-cross-a-thread-boundary)). A struct of plain data is unaffected by both rules and pays for neither.

### 2.2.1 `struct HWND__;` — a type declared and not laid out

A `struct` written with no body at all is C's incomplete type: declared here,
laid out somewhere else, and never completed. The only thing that can be done
with one is point at it.

```csharp
public struct HWND__;
public struct HDC__;

public using HWND = HWND__*;
public using HDC  = HDC__*;
```

That is C's own idiom, and it is the reason both features want doing together.
`HWND__*` and `HDC__*` are different types because they point at different
things, so passing one where the other belongs is caught:

```
error[SL0262]: argument 1 of 'Width' expects 'HWND__*', but 'HDC__*' was given
```

It costs nothing. Neither type is ever laid out, emitted, or present at run
time; what crosses is a pointer, exactly as `void*` did. The tag is spelled
`HWND__` for the same reason C spells it that way: it is the name a diagnostic
will show.

**A value of one cannot exist**, which is checked at the single point every
written type passes through — a field, a local, a parameter, a return type, an
array element, a `sizeof` and a generic argument all arrive there:

```
error[SL0524]: 'HWND__' is declared without a body, so its size is not known
here and there is no value of it to have; write 'HWND__*', which is what an
incomplete type is for
```

Only a `struct` may be written this way (SL0523). A class is reached through a
pointer this compiler has to lay out; a union and a variant are nothing but
their contents; and a generic one has nothing for a type parameter to appear in.

**It is not a forward declaration.** Stainless has none, because declaration
order never matters: a type is either complete or opaque for the whole program,
and a second declaration of the same name is the ordinary duplicate (SL0201).

A generated C header says exactly what the source said — the tag declared and
never defined, and the alias as the typedef it is:

```c
struct App_HWND__;
typedef struct App_HWND__* App_HWND;

int32_t Width(struct App_HWND__* window);
```

Signatures spell the underlying type: the header states the ABI, and an alias is
a name rather than a type. The typedef is there so C can spell a handle the way
the Stainless source does.

### 2.2.2 A type declared inside another

```csharp
public struct Rect {
    public struct Point { public int X; public int Y; }

    public Point TopLeft;          // the short name, from inside
}

Rect.Point corner;                 // and the long one, from outside
```

**It is lifted out and named for where it was written.** `Rect.Point` is the
type's name everywhere — in a diagnostic, in the mangled symbol, and at a use
site — and it is an ordinary module-level type that happens to have a dot in
its name.

That is the whole of what nesting means here: it is about **where a name is
reached from**. An inner type has no privileged view of the outer one, no
implicit reference to an instance of it, and no bearing on layout — a `Rect` is
four ints whether `Point` is written inside it or beside it. C#'s nested types
work this way too; Java's inner classes do not, and the difference is the
hidden field Java adds.

Classes, structs, interfaces, variants, unions, enums and delegates may all be
nested, and nesting composes: `Widget.Bag.Slot` is a struct inside a class
inside a class.

**A nested type does not see its outer type's parameters.** A type inside
`Cache<T>` is hoisted to `Cache.Entry`, which is one type rather than one per
instantiation — so a field of type `T` in it is a `T` that is not in scope. Say
what it holds, or take the parameter again:

```csharp
public class Cache<T> {
    public struct Entry { public nuint Age; }        // fine: mentions no T
}
```

### 2.2.3 `(int, String)` — a tuple

```csharp
(int, int) MinMax(int[:] numbers) {
    ...
    return (low, high);
}

var (low, high) = MinMax(numbers);      // named where the names matter
var range = MinMax(numbers);            // or kept whole
Console.WriteLine(Text.FromInteger(range.Item1));
```

Several values travelling as one, for the function with two answers that
belong together and no reason to declare a struct for the sake of it.

**A tuple is a struct.** Layout, both ABI classifiers and the reference walk
that retains and releases what a value holds all apply to it without a line of
any of them being written for tuples — the same bargain `closure` made
([§2.14.1](#2141-closure--a-method-and-the-object-it-belongs-to)).

**It is structural.** `(int, String)` written in two modules is one type,
interned by its element types the way `T[:]` is by its element. Nothing is
declared and nothing has to line up but the types.

**The fields are `Item1` upwards, and have no names of their own.** Named
elements would have to either take part in the type's identity — making
`(int a, int b)` and `(int x, int y)` different types, which is a trap — or not,
which leaves two names for one field. Where a name is wanted it is wanted at
the *use* site, and that is what `var (low, high) = ...` is for.

**At least two elements** (SL0606): one value in parentheses is that value.
Every element is a value (SL0607), so a call returning nothing cannot be one.
Taking one apart names exactly as many things as it holds (SL0609), and only a
tuple can be taken apart (SL0608).

A tuple is a type like any other: nested in another tuple, held in a
`List<(int, String)>`, inferred through a generic — `T FirstOf<T, U>((T, U) p)`
reads `T` from the argument the way it would through any other shape.

## 2.3 `[Packed]` and `[Align]`

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

### Bit-fields

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
one explicitly; the default is the host's, and it reaches C++ names, bit-fields
and how a struct is passed — Win64 asks only how big one is, System V asks what
is in it. See [§3.4 of abi.md](../abi.md#34-how-a-struct-is-passed).

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

## 2.4 `class` — reference type, ARC managed

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

Members are fields, methods, properties ([§7.3](07-functions-members.md#73-properties)), one destructor and any number
of constructors.

A class value is a pointer to a heap object preceded by an object header
(see [abi.md](../abi.md)). Assignment copies the *reference* and retains it.
`new Buffer(64)` allocates, runs the constructor, and yields a reference with
a count of 1.

### 2.4.1 A field with a value

```csharp
public class Panel {
    public int Width = 80;
    public String Title = "untitled";
    public bool Visible { get; set; } = true;

    public Panel() { }
    public Panel(String title) { Title = title; }       // the body has the last word
}
```

A field initializer runs **at the head of every constructor**, in the order the
fields were declared, before the constructor's own statements. So the two
constructors above both produce a `Panel` whose `Width` is 80, and the second
one's `Title` is what it was given rather than `"untitled"`.

An automatic property's `= value` is the same thing: the storage it owns is a
field, and this is that field's initializer.

**A class that declares no constructor gets one**, taking no arguments, so that
there is a head for the initializers to be at. `new Counter()` meant that
already; what is new is that something runs.

**A constructor that chains to `this(...)` does not run them**, because the one
it delegates to already did, and running them twice would undo whatever that
constructor decided. The base class's initializers are not here either: the
base's own constructor runs them, and that call is what a derived constructor
starts with.

**An initializer cannot read the object** (SL0617) — not `this`, not another
field, not a method. It runs before the constructor's body and in declaration
order, so what it would read is whatever the allocation left, which is zero.
A constructor is where one field's value may depend on another. Everything else
is in reach: a literal, a `const`, a static, a call to a free function, a `new`.

**Only a class has them.** A `struct` is made by declaring one — `Point p;` —
and there is no moment there for an initializer to run at, so one is refused
(SL0617) rather than silently skipped.

### 2.4.2 Making one with its members written out

```csharp
var panel = new Panel { Title = "readme", Width = 12 };
var panel = new Panel("readme") { Width = 12 };         // arguments as well
var numbers = new List<int> { 1, 2, 3 };
```

An object initializer is short for the construction held in a name, a write per
entry, and then the name — and it is lowered to exactly that, so nothing it can
do is anything the written-out form could not. The writes go through a setter
where the member is a property, as they would anywhere else.

A brace list of *bare* values is a collection initializer instead: one `Add` per
value, found **by name rather than by interface**, which is the rule `foreach`
already keeps for `GetEnumerator` ([§9.4](09-statements-expressions.md#94-foreach)). A type can be built up this way
without `Standard.Collections` appearing anywhere in the program.

Which of the two a brace list is comes from its entries, and **they may not be
mixed** (SL0618): one that did both would be two different things at once, and
a reader would have to know the type to see which each entry was. The other
refusals are the ones an assignment would have given anyway — no such member,
a property with no setter, a member that is not visible — plus a type with no
`Add` to add to.

### 2.4.3 Inheritance

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

A property takes the same words, and they belong to the pair: its accessors are
the methods, so an `abstract` property declares two abstract accessors and an
`override` one replaces both. A setter dispatches for the same reason a getter
does.

```csharp
public abstract class Node {
    public abstract int    Weight { get; }
    public abstract String Tag    { get; set; }
}
```

**One base, not several.** A class reference points at the object header and the
fields follow it, so with a single base the base subobject starts at the same
address as the derived object. An upcast is therefore free — no instructions at
all — reference identity stays pointer identity, and `sl_retain` goes on taking
the object's own address. Multiple inheritance would end all three at once; see
[TODO.md](../../TODO.md) for the longer argument.

A virtual call is three loads and an indirect call; see
[§2.0.1 of abi.md](../abi.md#201-virtual-dispatch).

**`base` is where to look, not a value.** `base.M()` calls the implementation
this class replaced, and is not dispatched — through the vtable an override
would find itself. **A property reached through `base` is the same**, in both
directions: `base.P` calls the getter this class replaced and `base.P = x` its
setter, because a property is a pair of methods ([§7.3](07-functions-members.md#73-properties)) and the rule is about
methods. It is the one place the distinction is load-bearing rather than
pedantic — an override written the obvious way,

```csharp
public override int Value { get => base.Value; }
```

would otherwise call itself for ever. `base(...)` runs the base constructor, before this class's body: the base is
built first, and a body that had already run would be reading fields nothing
had set. Left out, the base's constructor taking no arguments is called for
you, and there being none is an error rather than a class that skips it.

**It is written in one of two places**, and they mean the same thing:

```csharp
public Square(double side) : base(4)     // after the parameters, as in C#
{
    _side = side;
}

public Square(double side)
{
    base(4);                             // or as the very first statement
    _side = side;
}
```

The clause is the one to reach for — a reader looking at a constructor's
signature sees what it builds without reading into the body — but the statement
form is not going anywhere, and most of this repository still writes it.

A constructor writes the call once, in one place or the other, and nothing may
follow the `:` but these two calls:

```
error[SL0516]: 'base(...)' has to be the first statement of the constructor
error[SL0517]: 'Shape' has no constructor that takes no arguments, so 'Circle'
has to say which one to run: write 'base(...)' as the first statement of its
constructor
error[SL0732]: a constructor may be followed by ': base(...)' or ': this(...)'
and nothing else; there are no initializer lists here, because a field is
initialized where it is declared or in the body
error[SL0733]: this constructor already chains after its parameters, so the
body must not chain again; the two spellings are one call and a constructor
makes it once
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

**`this(...)` delegates to another constructor of the same class**, in either
of the same two places. The one it delegates to builds the base, so no base
construction is inserted alongside it — inserting one would build the base twice
and the second pass would overwrite what the first had set. A ring of
constructors that delegate to each other never builds anything, and is refused:

```csharp
public class Pair {
    int a;
    int b;

    Pair(int x, int y) { a = x; b = y; }
    Pair(int both)     { this(both, both); }
    Pair()             { this(0); }
}
```

```
error[SL0521]: the constructors of 'Ring' delegate to each other in a ring, so
none of them ever builds anything
```

**Destructors chain, derived first**, so a derived destructor may read what its
base still holds. Interfaces are inherited too, and an override takes the slot,
so a call through an interface reaches the same body a virtual call would.

**A class from a referenced library may be derived from.** Its layout, its
dispatch table slot by slot, its destroy hook and its protected members all
cross in the metadata, so what is built here is built on top of them rather than
instead of them: the derived object's fields sit after fields this compilation
never laid out, its table starts as a copy of one compiled elsewhere, and its
destructor hands the object back to the library when it has finished its own
half.

What that costs is that **the base's table length becomes part of its
contract**. A derived class appends after the last slot, so a later version of
the base adding a virtual method would want a slot something else is already
using — which makes adding one to a public, non-sealed class a breaking change,
enforced by the ABI digest rather than by convention (see
[§5 of packages.md](../packages.md#5-the-digest)).

A `com class` from a referenced library still cannot be derived from (SL0513):
its tear-offs are laid out after its fields by the compilation that built it, so
a derived class's own fields would land on top of them. Neither can a class the
runtime provides, such as `String`.

### 2.4.4 `is`, `as`, and casting down

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

**Naming what the test found.** A test may put the object under a name, in
scope where the test succeeded:

```csharp
if (shape is Square square) {
    ...                                 // 'square' is a Square here
}
```

That is the cast written once instead of twice. The name is in scope in the
branch the test proved and nowhere else — not after the `if`, and not in the
rest of the condition — so the form is the whole condition of an `if` and not
part of a larger one (SL0585). A *class* is what may be named: `x is INamed n`
is refused (SL0587), because a reference does not convert down to an interface
and there would be nothing for `n` to be.

**An interface reference narrows to a class**, which is the same question asked
the same way:

```csharp
IShape shape = new Square(3.0);

if (shape is Square square) { ... }     // the class behind the interface
Square also = (Square)shape;            // checked, and aborts if it were not
```

An interface reference *is* the object pointer ([§2.10](#210-interface--a-contract-dispatched-dynamically)) — the dispatch table
hangs off the object rather than travelling beside the reference — so asking
whether it points at a `Square` is the question a class downcast already asks,
and the pointer that comes back is the one that went in. It costs the same
`sl_is_instance` and emits nothing else.

The one narrowing refused here is the one that could never hold: a **sealed**
class that does not implement the interface, since nothing below it can supply
what it lacks. An unsealed one is allowed even when it does not itself implement
the interface, because something deriving from it may.

**What is tested is evaluated once**, which is what makes this the way to read
a field or a call result. `is` through a `C?` asks about the null and the class
at once, so it is also the narrowing that [§2.5](#25-pointers-and-nullability) cannot give a field:

```csharp
if (node.Next is Node n) { return n.Value; }    // 'node.Next' read once
```

A test that could never be true is a mistake rather than a constant false:

```
error[SL0518]: no object is both a 'Circle' and a 'Unrelated': neither derives
from the other
```

**`as` is the same question, answered with a value.** `x as C` is a `C?`: the
reference where the test held, and null where it did not.

```csharp
Square? square = shape as Square;               // the reference, or null
String name = (shape as INamed)?.Name() ?? "anonymous";
```

That second line is what `as` is for. `is C c` already covers the branch, and
covers it better — the name is in scope exactly where it was proved. What it
cannot do is hand the answer on: pass it to something taking a `C?`, store it,
or give it a fallback with `??`. Those want a value, and a branch is not one.

What is tested is evaluated once, as with `is`, so `Parent() as Frame` calls
`Parent` a single time. The arm the test allows is that same pointer under the
type the test bought — no second check — and a conversion that cannot fail
gets no test at all: `square as Shape` is the ordinary widening and emits
nothing.

What it refuses is what could never be anything but null, since `as` is for a
question with two answers and these have one (all SL0612):

```
error[SL0612]: no object is both a 'Alpha' and a 'Beta': neither derives from
the other, so this would always be null

error[SL0612]: 'as' answers with an optional already, so the '?' says it twice;
write 'as Alpha'
```

A COM interface is the other refusal, and it is not about the answer being
known: `QueryInterface` is a call the object answers, and answers again, so a
test followed by a conversion would ask twice and could be told two different
things. `(IThing)x` asks once, and ends the program if the answer was no —
which is the same bargain a binding `is` refuses for the same reason (SL0587).

## 2.5 Pointers and nullability

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
stores its own closure is such a cycle; see [§2.15](#215-lambdas-and-closures).

**A checked optional is the thing it holds.** `C?` and `C` are the same
pointer, so once a check has established that one is not null the compiler lets
it be used as the other, and nothing is emitted for the conversion:

```csharp
Node? at = head;
while (at != null) {
    Print(at.Value);            // `at` is a Node here
    at = at.Next;               // and a Node? here, because a check said what
}                               // it held, not what it may be given next
```

The proof comes from the same shapes that narrow a variant ([§2.6](#26-variant--a-value-that-is-one-of-several-things)), which is
the same machinery and the same table:

| Shape | What it proves |
|---|---|
| `if (x != null) { … } else { … }` | `x` in the first arm |
| `if (x == null) { return …; }` | `x` for the whole rest of the block |
| `x != null ? x.V : d` | in the arm the check chose |
| `if (x != null && x.Ok())` | on the right of `&&`, and inside the branch |
| `while (x != null) { … }` | in the body |

**Nothing that could have changed it survives.** An assignment takes the proof
away, and, inside a loop, an assignment anywhere in the body does:

```csharp
if (x != null) {
    x = Next();
    x.Value                     // error[SL0248]: the proof was about the old value
}
```

**Only a name can be narrowed** — a local or a parameter. A field or a call
result may be a different value by the time it is read, so neither carries a
proof, and putting it in a local first is both the fix and what the code meant:

```
error[SL0248]: 'Node?' may be null, and this is not something a check can be
about: a field or a call result may be a different value by the time it is
read. Put it in a local, check that against null, and reach 'Value' through it
```

The other fix is `is` with a name ([§2.4.4](#244-is-as-and-casting-down)), which reads the field once and
names what came out of it:

```csharp
if (node.Next is Node n) { return n.Value; }
```

**A `weak C?` is never narrowed.** It may die between the check and the use,
which is the whole of what weak means, so no check could establish anything
about it. Reading it into a strong `C?` is what makes it safe to look at, and
that read is where the runtime check happens.

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

## 2.6 `variant` — a value that is one of several things

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
widest case ([§2 of the ABI notes](../abi.md#2-object-header-class-instances)). Nothing allocates, and the payloads overlap,
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
be built this way, because type arguments cannot be written at a call ([§4.4](04-generics.md#44-what-is-and-is-not-supported)).

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
for the reason given in [§2.8](#28-resultt-terror--how-a-function-fails).

**This is the short form, and it is usually the one to write.** A reader that
answers with a fallback needs no `switch`:

```csharp
double RadiusOr(Shape shape, double fallback) {
    if (shape.Circle) { return shape.Radius; }
    return fallback;
}
```

It works with a field name shared across cases — narrowing has settled which
case is there, so `shape.Radius` is that case's — and negated, which is what a
guard clause wants: `if (!shape.Circle) { return fallback; }`.

**`is` names what a test found**, for the two things a bare tag test cannot be
about:

```csharp
if (node.Payload is Circle c) { return c.Radius; }
```

A field or a call result carries no narrowing (SL0285), because either could be
a different value by the time the payload is read. `is` says so explicitly: the
value is evaluated once and what came out of it has a name. That name is a copy
of the case's payload — the same struct `case Circle c:` binds — and it is in
scope in the branch the test proved and nowhere else, so the form is the whole
condition of an `if` rather than part of one (SL0585). A case that carries
nothing has nothing to name (SL0586); `if (value is Null)` is the whole
question there.

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

## 2.7 `union` — every member at offset zero

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

**A union is the untagged half of what a `variant` is** ([§2.6](#26-variant--a-value-that-is-one-of-several-things)). A variant knows
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

## 2.8 `Result<T, TError>` — how a function fails

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

**`Result<T, TError>` is an ordinary variant** ([§2.6](#26-variant--a-value-that-is-one-of-several-things)), declared in `Standard`, which
is imported everywhere:

```csharp
public variant Result<T, TError> {
    Ok(T Value);
    Fail(TError Error);
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
([§4.4](04-generics.md#44-what-is-and-is-not-supported)) — and one value could not say what both of them are: `Ok(4)` fixes `T`
and says nothing about `TError`. So the compiler reads the type being returned,
assigned into, or passed as an argument, exactly as it does for a lambda:

```csharp
Result<int, Why> Doubled(int n) {
    if (n < 0) { return Fail(Why.TooSmall); }   // TError from the return type
    return Ok(n * 2);                           // T from the return type
}

Result<int, Why> held = Ok(4);                  // and from a declared local
var loose = Ok(4);                              // error[SL0287]: nothing to infer from
```

For the same reason a module-level function may not be named `Ok` or `Fail`
(SL0414) — the general rule for any variant's case, [§2.6](#26-variant--a-value-that-is-one-of-several-things). A *method* still may.

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
var raw = File.ReadAllText(path);
if (!raw.Ok) { return Fail(raw.Error); }
Console.Write(raw.Value);                    // proved by the line above
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

**Aborting means aborting.** It writes a line to standard error and ends the
process — there is no unwinding, no handler and no exit code to inspect from
inside. What it does first is flush everything the program has written, so the
output that led up to the failure is there to read: the moment a program's
account of itself is worth most is the moment it stops.

Every abort in the library is one a caller could have avoided by asking, and
each says so where it is declared. `Dictionary.Get` and `SortedList.Get` have
`ContainsKey` and `GetOr`; `Queue`, `Stack` and `LinkedList` have `Count` and
`IsEmpty`; `Optional.Get` has `ValueOr` and `is Some x`; `Env.ArgumentAt` has
`ArgumentCount`. The rest of what aborts is the runtime running out — memory,
a thread, a mutex — where the function that failed has no way to return
anything at all.

**`try` passes a failure to the caller.**

```csharp
public Result<List<String>, IOError> ReadAllLines(String path) {
    return Ok(IO.SplitLines(try ReadAllText(path)));
}
```

`try e` evaluates `e`; on success the expression *is* the value, and on failure
the enclosing function returns `Fail(e.Error)` at once. It is exactly the two
lines it replaces — the named temporary and the early return — moved to where
the value is used.

It is spelled `try` and not `?` for a reason worth recording: a postfix `?`
would sit exactly where the ternary's does, so `f() ? a : b` and `f()?` could
not be told apart without fragile lookahead. `try` is unambiguous as a prefix,
and Zig means the same thing by it. There are no exceptions here for it to be
confused with.

Three rules:

- Only inside a function returning a `Result` (SL0570). There is nowhere else
  for the failure to go, and aborting instead would be a decision the caller
  never made. A caller with a sensible default wants `ValueOr`.
- The operand must be a `Result` (SL0569).
- **The error types must match** (SL0571). `try` passes a failure on unchanged;
  converting one error type to another is a decision about what the failure
  means, and this refuses to make it silently.

It binds like any other prefix, so `try a + b` is `(try a) + b` and
`try f().x` covers the whole chain. It is an expression, so several may appear
in one — `Ok(try P(a) + try P(b))` — and each returns on its own failure.

### 2.8.1 `Optional<T>` — a value, or none

`C?` is a nullable reference: the null is the pointer, so it costs nothing and
the compiler narrows it ([§2.5](#25-pointers-and-nullability)). A **value type has no spare bit to be null
with**, so `nuint?` is refused (SL0271), and what used to stand in was a magic
number — a lookup answering with the largest `nuint` there is, and every caller
agreeing to read that as "not there".

`Optional<T>` is that said properly, and it is an ordinary variant:

```csharp
public variant Optional<T> {
    None;
    Some(T Value);
}
```

So it costs a tag beside the value and nothing else, the payload is readable
only where the case has been established, and every rule it appears to have is
a rule variants have:

```csharp
if (found.Some) { return values[found.Value]; }
return fallback;
```

A call result carries no narrowing, so a lookup is read with a name:

```csharp
if (map.IndexOf(key) is Some found) { return values[found.Value]; }
return fallback;
```

**A value becomes the `Optional<T>` holding it**, as it becomes a `T?` in Swift
and C#. `Some(x)` is still how a case is named where naming it reads better;
the conversion is what lets a signature ask for an optional without every
caller having to say so.

```csharp
Optional<int> port = 8080;              // the same as Some(8080)
Optional<int> none = None;
```

The rule is what makes an indexer able to be honest. A getter and a setter
share one type ([§7.5](07-functions-members.md#75-indexers)), so a subscript answering `Optional<TValue>` takes one as
well, and without this every write through it would read `map[key] =
Some(value)`. With it, `map[key] = value` sets and `map[key] = None` removes
([§5.4](05-standard-library.md#54-standardcollections)).

It never applies to something already of that type, so an `Optional<T>`
assigned to one is not wrapped twice, and an exact match always beats it in
overload resolution. An `Optional<T>` assigned to an `Optional<Optional<T>>`
*is* wrapped, which is what that says.

**The readers**, for a caller that would rather not branch:

| | |
|---|---|
| `HasValue`, `IsEmpty` | whether there is one |
| `Get()` | the value, **aborting** when there is none — the bargain `Dictionary.Get` makes |
| `ValueOr(fallback)` | the value, or something the caller supplies |
| `Or(other)` | this one if it holds anything, else `other` |
| `Map(f)` | the value put through `f`, or none — `Optional<R>` |
| `FlatMap(f)` | the same, for an `f` that answers with an optional of its own |
| `Filter(p)` | this one if `p` accepts what it holds, else none |
| `IfPresent(a)` | runs `a` on the value, if there is one |

`Map`, `FlatMap`, `Filter` and `IfPresent` take `Func`, `Predicate` and
`Action` ([§5.5](05-standard-library.md#55-doing-something-to-every-element)) — generic closures, so a lambda or a bound method is what gets
written at them:

```csharp
Optional<String> name = index.IndexOf(id).Map(i => people[i].Name);
```

`Or` takes a value rather than something that produces one on demand, unlike
Java's: a lambda here allocates a closure to save an evaluation, which is the
wrong way round at the sizes this is used at.

**It is not a replacement for `C?`.** A nullable reference stays what it is —
the representation is already free there, and `if (c != null)` narrows without
a case to name. Two representations behind one `?` was the alternative, and it
would have meant `T?` being a pointer for a class and a tagged pair for a
value, across layout, mangling and the ABI classifier. The names differ for the
same reason they are different things: `Optional<T>` is this type, and "an
optional" is what this document calls `C?`.

## 2.9 How the library reports failure

Two conventions, and the difference between them is whether there is a value.

| The function | reports failure as |
|---|---|
| produces a value | `Result<T, TError>` |
| produces nothing | the error enum, with `None` for success |

`File.ReadAllBytes` returns a `Result<byte[], IOError>`; `File.Delete` returns
an `IOError`. The second is not a lesser form of the first — `Result<void, TError>`
is not expressible, and would say nothing the enum does not.

**Construction is the awkward case**, because a constructor has to return its
type and so cannot report why it failed. Every language with checked errors
answers this with a function — Rust's `TcpStream::connect`, Go's `net.Dial` —
and so does this one, as a **static method of the type being made** ([§7.6](07-functions-members.md#76-static-members)):

```csharp
var listener = try TcpListener.Listen("0.0.0.0", 80u);
```

The constructor is private, and that is what makes this the way in rather than
merely the recommended way. A static method is inside the type, so it may use a
constructor nothing outside it can — which is why the failing shape is gone
rather than discouraged. There is no way left to obtain a listener that exists
and is not listening.

`FileStream.Open`, `Socket.Open`, `TcpListener.Listen`, `TcpClient.Connect`,
`UdpSocket.Bind` and `UdpSocket.Datagram` are the ones that can fail. Each
returns a `Result`, whose failure cannot be walked past because it has no value
to read until its case has been named.

`IsOpen` and `Error` remain on a stream or a socket, for what happens
*after* it is open: a read on a closed stream is an outcome of the read, and
there is nowhere else to put it.

## 2.10 `interface` — a contract, dispatched dynamically

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
([§7.3](07-functions-members.md#73-properties)), so an interface property is one vtable slot per accessor and a class
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
[abi.md](../abi.md) for the tables. An interface reference can be asked what it
really is, and cast to it, exactly as a class reference can [§2.4.4](#244-is-as-and-casting-down).

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

The two methods share a name and are told apart by their parameters ([§7.1](07-functions-members.md#71-functions)).
`IEq<int>`'s table takes the first and `IEq<String>`'s the second, so a call
through either reference reaches the right one, and a call on `Both` itself
picks by argument type. What may *not* be overloaded is a method of one
interface, since that is one slot.

## 2.11 Arrays

### 2.11.1 `T[]` — a counted array

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

**An array can be written out**, with the same allocation and a store per
element — at a constant index, so nothing is bounds checked that need not be:

```csharp
var numbers = [1, 2, 3, 4];             // int[]
String[] names = ["alpha", "beta"];     // from the declared type
Show(["one", "two",]);                  // and from a parameter; the comma is fine
```

**A literal has no type of its own.** What it becomes is decided by where it is
going, exactly as for a lambda ([§2.15](#215-lambdas-and-closures)) and a bare variant case name ([§2.6](#26-variant--a-value-that-is-one-of-several-things)) — a
`T[]`, a `T[N]` of matching length, or a `T[:]`:

```csharp
int[3] fixed = [7, 8, 9];               // an inline array; the length is the type
int total = Sum([10, 20, 30]);          // a T[:] parameter, through the array
```

Unlike those two it can also decide for itself, because its elements are values
and a lambda's body is not. With nothing else to go on the elements settle it,
widening between themselves the way a ternary's arms do:

```csharp
var mixed = [1, 2L, 3];                 // long[], as `flag ? 1 : 2L` is a long
```

An empty one has nothing to settle from and needs to be told:

```
error[SL0548]: an empty array literal has no element type and nothing here says
what it should be; write 'new T[0]', or give the variable a type

error[SL0549]: this element is 'String' and the ones before it are 'int'; an
array holds one type, so either make them agree or give the array a type of its
own

error[SL0547]: 'int[3]' holds exactly 3 elements, and this literal has 2; an
inline array is its elements, so there is nowhere to keep a different number of
them
```

Elements are stored the way an assignment into an element is, so a literal of
references retains every one — `[a, b]` outlives the locals `a` and `b`.

### 2.11.2 `T[N]` — an inline array

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

## 2.12 `T[:]` — part of an array

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

## 2.13 `enum` — a distinct type over an integer

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
into, unlike `[Reflect]`, which comes with the subsystem it belongs to.

## 2.14 `delegate` — a named function pointer

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
[§2.15](#215-lambdas-and-closures) — and only a non-capturing one can be a delegate, because there is nowhere
in a single pointer to keep what was captured. `closure` below is the type that
does have somewhere.

**A delegate may name a calling convention**, where a function already can:

```csharp
public delegate __stdcall int GdipDrawLineI(
    void* graphics, void* pen, int x1, int y1, int x2, int y2);
```

It goes in front of the return type, which is where `extern "C" __stdcall int
f()` already puts it, and the names are the same four a function may use:
`__cdecl`, `__stdcall`, `__fastcall` and `__vectorcall`.

A delegate is the only *type* that needs one. Everywhere else the convention
belongs to a symbol: a function declares it, the linker name carries it, and a
call site reads it off the function it names. A delegate names no symbol — it
is a pointer, and what it points at was compiled by somebody else — so if the
type does not say, the call site has nothing to ask.

It matters on x86 and nowhere else: x64 and ARM64 each have one convention, so
the word is accepted and ignored there. That is precisely why leaving it off is
dangerous rather than merely wrong. A `__stdcall` callee removes the arguments
itself, so a 32-bit call through a delegate that did not say so returns to a
stack pointer several words adrift — and the program does not fail at that
call, it fails later, somewhere else.

A `closure` may not name one (SL0621). It is a pointer *and* a receiver, passed
by machinery this language emits at both ends, so there is no foreign function
for a convention to describe.

**A pointer converts to a delegate with an explicit cast**, and back:

```csharp
void* symbol = GetProcAddress(library, "GdipDrawLineI".ToPointer());
var draw = (GdipDrawLineI)symbol;
```

This is what dynamic loading is made of — `GetProcAddress` and `dlsym` answer a
`void*`, and the only useful thing to do with one is call it. Explicit only:
nothing about a `void*` says it points at code, let alone at code of this
signature, so the cast is an assertion by the programmer in the same way
`(Shape)pointer` is.

### 2.14.1 `closure` — a method and the object it belongs to

```csharp
public closure void Notify(int value);

Notify first  = counter.Add;              // a bound method
Notify second = other.Add;                // same type, different object
Notify third  = (v) => { label.Show(v); };  // a capturing lambda
first(5);
```

A closure is **two pointers**: a function, and the receiver to call it on.
Delphi spells the same distinction `of object`, and it is the difference
between a callback that can know something and one that cannot — a delegate
holds a function, and a function alone cannot say *which* counter to add to.

**The representation costs nothing.** A method already takes its receiver as
argument zero, so a bound method pointer is literally the method's own address
beside the object, and calling one is a single indirect call with no thunk and
no shuffling. Being two fields is also what gives it layout, both ABI
classifiers, and the reference counting that keeps its object alive — none of
which was written for closures.

**The receiver is kept alive** for as long as the closure is:

```csharp
Notify Escaping() {
    var counter = new Counter();
    return counter.Add;            // the closure holds the counter
}
```

**A lambda becomes one too**, capturing by value as it always does ([§2.15](#215-lambdas-and-closures)): a
captured `int` is a copy, and a captured reference is shared. The object behind
the closure is then the class the compiler generated to hold what was captured,
which is why a lambda and a bound method are the same two words and
interchangeable everywhere.

**Comparison is both words** — the same method *and* the same object:

```csharp
first == counter.Add        // true
first == other.Add          // false: different object
first == counter.Subtract   // false: different method
```

That is what makes a closure removable from a list of them, and it is the
reason a method pointer is a value rather than an object: two mentions of
`counter.Add` are equal, where two generated wrappers would not have been.

**A plain function becomes one too**, with no lambda around it:

```csharp
public closure String Shout(String text);
String Upper(String s) => s.ToUpperAscii();

Shout loud = Upper;
var shouted = names.Map(Upper);           // R is String, read off Upper
```

It has no object, so the receiver word is null and the function word is a thunk
the compiler writes once per function: it takes the receiver, ignores it, and
passes the arguments on. Once rather than once per mention is what keeps
comparison honest — two mentions of `Upper` are equal, so a function added to
an event with `+=` comes off again with `-=` — and a null receiver means making
one allocates nothing. A generic result is read off the function's declared
return type, as it is off a lambda's body
([§4.4](04-generics.md#44-what-is-and-is-not-supported)).

**What it is not**

- **Not a C function pointer** (SL0360). Sixteen bytes cannot go where eight
  are expected, so a closure never satisfies a `delegate` and never crosses
  `extern "C"`. Declare a `delegate` for that, and take the context as an
  argument the way C does.
- **Not inferrable by `var`** (SL0553), for the reason a bare function name is
  not: `counter.Add` names a method, and which closure type it becomes is what
  the declaration says.

**A closure may be generic**, and a delegate may too:

```csharp
public closure bool Predicate<T>(T value);
public closure R    Func<T, R>(T value);

public List<T> Filter<T>(T[:] items, Predicate<T> keep) { ... }
```

Each set of type arguments makes a real type, the way `Box<int>` does — there
is simply much less of it to make. A delegate is a signature and nothing else,
so an instantiation resolves that signature under the substitution and stops;
there are no members to declare, no interfaces to satisfy, and no layout to
compute, a delegate being one pointer and a closure always the same two.

This is what `Standard.Collections` is built on. Before it, the only generic
thing a lambda could become was an interface with one method, and an interface
needs an *object* that implements it — so `ForEach(lines, report.Note)` was
unwritable, and the library declared `IFunc`, `IPredicate`, `IAction`, `IFold`
and `IComparer` to stand in for the five shapes it wanted.

`closure` is a **contextual** keyword, as `event` is ([§2.14.2](#2142-event--several-subscribers-behind-one-name)): it means
something at the head of a declaration and is an ordinary name everywhere else.

### 2.14.2 `event` — several subscribers behind one name

```csharp
public closure void ChangeHandler(Source sender, Change what);

public class Source {
    public event ChangeHandler Changed;

    public void Announce(int code) { Changed(this, new Change(code)); }
}

source.Changed += listener.OnChanged;       // subscribe
source.Changed -= listener.OnChanged;       // unsubscribe
```

An event is a list of closures that reads like one. Raising it calls every
subscriber **in the order they subscribed**, each with the arguments the raise
was written with.

**Only `+=` and `-=` cross the boundary.** From outside the declaring type,
those two operators are all there is: an event cannot be read (SL0555), assigned
(SL0556) or raised (SL0554). That is the difference between an event and a
public field of closure type, and the whole reason the word exists — one
subscriber must not be able to see the others, replace them all, or fire the
event on the publisher's behalf.

Inside the declaring type it is raised by writing its name. Only *that* type: a
derived class raises its base's event through a protected method the base
provides for it, as in C#.

**An empty event does nothing.** Raising one nobody has subscribed to is a
no-op, not an error, so a publisher never checks:

```csharp
public void Announce(int code) { Changed(this, new Change(code)); }   // safe when empty
```

That is deliberately not C#, where an unsubscribed event is null and raising it
throws — which is why almost every C# codebase writes `Changed?.Invoke(...)` at
every raise site.

**A handler must return `void`** (SL0549). Raising calls every subscriber, so
there is no single value to return; C# keeps the last one's and discards the
rest. A handler that needs to report something takes an argument to report
through.

**The type must be a `closure`** (SL0548), not a `delegate`: a subscriber is
almost always a method on an object, and a delegate is one pointer with nowhere
to keep the object. A plain function subscribes by way of a lambda, which is
what gives it one.

**Removal is by value**, on the same terms as closure equality ([§2.14.1](#2141-closure--a-method-and-the-object-it-belongs-to)) — the
same method *and* the same object. The same handler subscribed twice is two
subscriptions, and one `-=` undoes one of them. Unsubscribing something that was
never subscribed does nothing, so a tidy-up may run twice.

**A raise takes the subscriber list before it starts.** Subscribing or
unsubscribing during a raise does not disturb the raise in progress: exactly the
subscribers that were there when it began run, none of them twice, and the next
raise sees the change.

```csharp
public void Once(Source sender, Change what) {
    source.Changed -= this.Once;       // safe: this raise still finishes
}
```

**Events are not static** (SL0550): the subscribers would outlive every object
that added one, and nothing would ever take them off.

An event lowers to a hidden array of subscribers and three methods —
`add_Name`, `remove_Name` and `raise_Name` — the way a property lowers to
`get_Name` and `set_Name`. The array is replaced rather than changed by each
subscription, which is what the paragraph above rests on.

**An event crosses a library boundary.** A consumer subscribes to and
unsubscribes from an event declared in a library it has no source for, with
handlers of its own, and the library raises them. What crosses is the closure
type, the two methods, and the storage; `raise_Name` is private and does not —
so "only the declaring type may raise it" holds across the boundary by
construction rather than by a check on the far side.

## 2.15 Lambdas and closures

A lambda is typed by what it is assigned to, and there are **three** things it
may become: a `closure` ([§2.14.1](#2141-closure--a-method-and-the-object-it-belongs-to)), an **interface with exactly one
method**, or a **delegate**.

```csharp
public closure int Transformer(int value);
public interface ITransform { int Apply(int value); }

int factor = 3;

Transformer scale = (int value) => value * factor;  // a closure: the usual one
ITransform  shift = value => value + factor;        // an interface, also fine
Transform   plain = (int value) => value * 2;       // captures nothing: a delegate
```

**Reach for the closure.** It is the one that needs no type declared for the
sake of it, the one a bound method also fits, and the one two of which can be
compared. An interface target is what to use when the thing being passed is
genuinely an object with a role — a comparer, a visitor — rather than a
callback.

All three generate the same class: one field per captured value, the shape C#
uses for delegates and Rust for `Fn`. It is an ordinary class, so it is
reference counted, it lives in a `List<T>` like anything else, and its
destructor releases what it captured. A closure is that object beside the
address of its method; an interface reference is that object alone.

**A lambda that writes its parameter types has a type of its own**, so `var`
can hold one:

```csharp
var doubled = (int x) => x * 2;         // a closure int(int)
Console.WriteLine(Text.FromInteger(doubled(21)));
```

It is a `closure`, because a lambda may capture and a delegate has nowhere to
keep what it captured. The type is the signature and nothing else, so two
lambdas of the same shape are the same type and either may be assigned to the
other — and a `closure` somebody declared with that shape is interchangeable
with both, since all three are the same two words.

What this does not reach is a lambda that has not said enough (both SL0553):

- **A parameter with no type.** `var f = x => x;` has nothing to infer from —
  that is the whole of what a target type was supplying.
- **A block body.** Its result is whatever its `return`s agree on, and that is
  decided by the type it is becoming rather than the other way round. One
  expression, or write the type out.

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
`this` itself, and a method called without a receiver all resolve — and *what*
is captured differs between them, which is the one part of this section to read
twice:

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
closure the compiler generated for it — and **`this` is what gets captured**,
by the same by-value rule as a local, which for a class reference means the
closure holds the object.

So the three differ:

| written | captured | reads |
|---|---|---|
| `Factor` | the *value* `Factor` had | what it said when the closure was made |
| `this.Factor` | `this` | what it says when the closure runs |
| `Triple(value)` | `this`, because the call needs one | the method, now |

**A bare member read is the only one that copies**, and it copies because the
name resolved to a read in the enclosing scope rather than to a member of
something the closure holds. Naming the receiver is what makes it live.

**On a struct it is live for neither**, and the reason is the same rule rather
than an exception to it: `this` in a struct method is the struct, so capturing
it by value copies the value. On a class `this` is a counted reference, and a
copy of a reference still names the one object — which is also why the closure
keeps it alive. There is no spelling that reads a struct's original storage
from a lambda; pass what the lambda needs as a parameter instead.

**A captured member that something else writes is a warning** (SL0610), because
the rule above reads like the opposite of itself at the one place it matters:

```csharp
class Peer {
    bool busy;

    public Peer() {
        OnChanged(() => {
            if (busy) { return; }       // SL0610: `busy` is a copy
            Report();
        });
    }

    public void Set(int value) {
        busy = true;                    // this is what makes it a warning
        Write(value);
        busy = false;
    }
}
```

`if (busy)` is a line nobody reads twice and it means "if `busy` was set when
this lambda was made" — which is `false`, for ever. The warning names the two
halves and fires only when both are there: a member a constructor sets and
nothing else changes cannot surprise a closure, so capturing one of those is
silent. Inside a struct it says something different, because there the fix
below does not exist.

The fix is to name the receiver, which captures the object rather than the
answer — `if (this.busy)`. A method that reads the field does the same thing
for the same reason, and reads better where the test is worth a name:

```csharp
bool Busy() { return busy; }
```

**Capturing `this` keeps the object alive**, which makes an object that stores
its own closure a reference cycle. ARC cannot collect one, so break it with a
`weak` reference ([§2.5](#25-pointers-and-nullability)) exactly as you would any other.

Parameter types may be written or left out; left out, they come from the target,
which is the only thing that knows them. A lambda with no target is an error —
`var f = x => x;` has nothing to infer from, and SL0553 says so.

A closure is a class, so crossing a thread boundary with one warns unless it is
declared `threadsafe` ([§9.5](09-statements-expressions.md#95-what-may-cross-a-thread-boundary)) — which it cannot be, having no declaration to
write the word on. That is the right answer rather than an oversight: a closure
holds captured state, and nothing synchronizes it.

---

<sub>[&larr; Modules](01-modules.md) &nbsp;&middot;&nbsp; [Text &rarr;](03-text.md)</sub>
