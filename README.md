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

For the other end of the scale, [samples/tour](samples/tour) is one program that
uses every feature in this document, printing what it did at each step -- so
running it says whether the tour is still true, and not only whether it still
builds.

```
$ stainless run samples/tour
```

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

A field or a call result carries no proof — either could be a different value
by the time the payload is read — so `is` puts what a test found under a name,
evaluating the thing tested once:

```csharp
if (node.Payload is Circle c) { return c.Radius; }
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

### Failure

```csharp
public Result<List<String>, IOError> ReadAllLines(String path) {
    return Ok(IO.SplitLines(try ReadAllText(path)));
}
```

`try e` is the value on success, and returns `Fail(e.Error)` from the enclosing
function on failure -- the named temporary and the early return it replaces,
moved to where the value is used. It is `try` rather than `?` because a postfix
`?` would sit exactly where the ternary's does; Zig means the same by the word,
and there are no exceptions here to confuse it with.

The library reports failure two ways, and the difference is whether there is a
value: `Result<T, E>` when there is one, the error enum when there is not.
Construction is the awkward case, since a constructor must return its type and
cannot say why it failed. So `FileStream.Open`, `TcpListener.Listen` and
`TcpClient.Connect` are static methods of the types they make, each returning a
`Result`, and the constructors they replace are private -- a static method is
inside the type, so it can reach one nothing outside can.

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

### Text

```csharp
Console.WriteLine($"clicks: {clicks}  at {x}, {y}");
```

`$"..."` is sugar over the conversions that were already there, and one thing
that is not sugar: the whole string is joined in **one allocation**, where the
`+` chain it replaces allocates once per operator and discards all but the
last. That line emits five `sl_string_concat` calls written the old way and one
`sl_string_join` written this way.

A hole takes a `String`, a number, a `bool` or a `char32`. Anything else is
refused rather than given a default -- there is no `ToString` every type owes.
A `char` is one UTF-8 *code unit* and not a character, so it has to say which it
means: `(char32)c` for the character, `(long)c` for the number.

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

T Fresh<T>(T old) where T : new() { return new T(); }
T Copied<T>(T value) where T : struct { return value; }
String Says<T>(T animal) where T : Animal { return animal.Says(); }
String Both<T, U>(T a, U b) where T : U where U : INamed { return b.Name(); }
```

`new()` means a **class** here, unlike C#: `new` allocates, and a struct is
declared where it is used -- so a struct would satisfy a constraint whose only
purpose it then failed.

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
ages["ada"] = 36;
ages["grace"] = None;                   // None removes

if (ages["ada"] is Some found) { Use(found.Value); }
int guess = ages["nobody"].ValueOr(0);

var numbers = new List<int>();
numbers.Add(1);
numbers[0] += 1;
Sort(numbers);
```

A dictionary's subscript answers `Optional<V>`, as Swift's does: a key is data
that arrived from somewhere, so a lookup that misses is an answer rather than
a reason to stop the program. A list's is a plain `V`, because an index is a
position the caller worked out and an out-of-range one is the mistake
`array[i]` is.

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

### Statics

```csharp
public class Small {
    int value;
    static int made = 0;                           // mutable storage

    Small(int checked) { value = checked; made = made + 1; }   // private

    public static Result<Small, ParseError> Parse(String text) { ... }
    public static int Made { get { return made; } }
}

public static class Defaults {
    public static int Retries = 3;
}

var small = try Small.Parse(text);
```

C#'s model: fields, methods, properties, static constructors and `static
class`, at module scope or on a type, mutable or `readonly`. Storage is
initialized before `Main` in an order the compiler works out from the
dependency graph -- no lazy guard on every access, and a compile error on a
cycle rather than a zero at run time. A static constructor runs there too,
which is the one departure from C#: "before first use" becomes "before
`Main`".

A static member is one of the type rather than of a value of it. The whole of the difference
is the missing receiver: no `this`, so no field is reachable without saying
which object is meant, and a call names the type.

It exists for the case above. A constructor has to return its own type, so it
cannot say why it failed, and the best it could do was hand back an object
holding nothing -- which is a value a caller can go on using while nothing
forces the check. A static method is *inside* the type, so it can use a private
constructor, and that is what turns the discouraged shape into an absent one.

It is also how a struct gets a maker at all, since a struct has no
constructors.

### Operators and indexers

```csharp
public struct Money {
    public long Cents;

    public static Money Of(long cents) { Money m; m.Cents = cents; return m; }

    public static Money operator +(Money a, Money b) { return Of(a.Cents + b.Cents); }
    public static Money operator *(long by, Money a) { return Of(a.Cents * by); }

    public static bool operator ==(Money a, Money b) { return a.Cents == b.Cents; }
    public static bool operator !=(Money a, Money b) { return a.Cents != b.Cents; }
}

public class Grid {
    int[] cells;

    public int this[nuint at] {
        get { return cells[at]; }
        set { cells[at] = value; }
    }
}
```

An indexer's getter and setter share one type, which is a constraint worth
knowing before designing one: a lookup that may miss answers `Optional<V>`, so
its setter takes an `Optional<V>` too. That is how `Dictionary` spells removal
as `map[key] = None`.

C#'s shape: inside the type, `static`, every operand written out. That last
part is what makes `3 * money` expressible -- an operator whose left operand is
not the declaring type has no receiver to hang off.

`&&` and `||` cannot be overloaded, because they short-circuit and an overload
would have to evaluate both sides to be called at all. The compound forms are
not overloaded separately either: `a += b` is `a = a + b` and picks up whatever
`+` does. `==` and `!=` must be declared together, as must `<`/`>` and
`<=`/`>=`; a type that answers one and not the other is a trap.

### Inheritance

```csharp
public abstract class Shape {
    protected int sides;

    Shape(int howMany) { sides = howMany; }

    public abstract double Area();
    public virtual String Name() { return "shape"; }
}

public class Polygon : Shape {
    double width;

    Polygon(int howMany, double w) {
        base(howMany);                  // the first statement, always
        width = w;
    }

    public override double Area() { return width * width; }
    public override String Name() { return "polygon"; }
}

public sealed class Square : Polygon {
    Square(double side) { base(4, side); }

    public sealed override String Name() { return "square"; }
}

Shape shape = new Square(3.0);
shape.Name();                           // "square" -- three loads and a call

if (shape is Square) {
    Square square = (Square)shape;      // checked; there is no exception to throw
}

if (shape is Square square) { ... }     // or once, named where it holds
```

C#'s model: one base class, any number of interfaces, and `virtual`,
`override`, `abstract`, `sealed`, `protected` and `base` meaning what they mean
there. **One base and not several** is what keeps it cheap: a class reference
points at the object header and the fields follow it, so a base subobject starts
at the same address as the derived object. An upcast emits nothing, reference
identity stays pointer identity, and `sl_retain` goes on taking the object's own
address. With two bases none of those would hold.

Constructors chain — explicitly with `base(...)`, implicitly to the one taking no
arguments, or sideways with `this(...)` to another constructor of the same class
— and destructors chain the other way, derived first, so a derived destructor can
still read what its base holds. `base.M()` is not dispatched, which is the only
way an override can reach what it replaced.

Properties take the same words, since their accessors are the methods: an
`abstract` property declares two abstract accessors and a setter dispatches
exactly as a getter does.

Hiding is refused: a method with the same name and parameters as one it inherits
must say `override`, and what it overrides must be `virtual` or `abstract`. C#
allows `new` to hide instead; a language with no way to reach the hidden member
has nothing to say it about.

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

### Handles that are told apart

```csharp
public struct HWND__;               // declared here, laid out somewhere else
public struct HDC__;

public using HWND = HWND__*;        // C's own idiom, and the reason for both
public using HDC  = HDC__*;
public using Count = nuint;         // a weak alias over anything at all
```

`using X = Y;` gives a type a second name — the word is free because `import`
took the job C# gives it. An alias **is** the type it names: no wrapper, no
conversion, nothing at run time.

Distinctness comes from what it names. A `struct` with no body is C's incomplete
type, so `HWND__*` and `HDC__*` are different types because they point at
different things:

```
error[SL0262]: argument 1 of 'Width' expects 'HWND__*', but 'HDC__*' was given
```

It costs nothing at all — neither type is laid out, emitted, or present at run
time — and a generated C header says exactly what the source said:

```c
struct App_HWND__;
typedef struct App_HWND__* App_HWND;
```

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
matching target. `--abi microsoft|itanium` picks one; the default is the host's,
and it reaches name mangling, bit-fields and how a struct is passed — Win64
asks only how big one is, System V asks what is in it, and
[§3.4 of the ABI notes](docs/abi.md) has the rules and the shapes they were
checked against.

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
comes from `-D`. The architecture is the one being built *for*, so
`--target x86` defines `X86` rather than the host's `X64`:

```
stainless build src -D FASTMATH
```

There is one pragma, and it is MSVC's: a file names a library it needs, rather
than every program that compiles it repeating `-l` on the command line.

```csharp
#pragma comment(lib, "user32")
```

### The Win32 API

[bindings/win32](bindings/win32) is what all of the above adds up to: the
Windows entry points, constants, structs, unions, enums, delegates, handle
types and COM interfaces that the samples and the tests here need, with a layer
of convenience functions over them. There is no marshalling layer and nothing
is generated — a `WNDCLASSEXW` is a Stainless `struct` whose `sizeof` is 80 as
it is in C, and a `WNDPROC` is a `delegate`, which is the bare function pointer
Windows calls.

It comes in two layers, and the module name says which is which. **A DLL name is
the declarations**, spelled as Windows spells them:

```csharp
import Win32.User32;

long Procedure(HWND window, uint message, ulong wParam, long lParam) {
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
[LLVM/clang](https://llvm.org) — `winget install LLVM.LLVM` on Windows,
`apt install clang` on Debian and Ubuntu.

```
dotnet build Stainless.slnx
dotnet run --project tests/Stainless.Tests      # 280 end-to-end tests
dotnet test tests/Stainless.UnitTests           # 834 compiler unit tests
```

The two suites ask different questions. An end-to-end case compiles, links and
runs a program, which proves the whole pipeline and takes a fifth of a second;
a unit test asks the front end alone -- what did the lexer make of this, where
exactly does this error point, which registers does this struct travel in --
and takes a millisecond, so it can be asked by the hundred.

**Both Windows and Linux are tested.** 280 cases, of which 12 are
Windows-only and 2 are Linux-only, so Linux runs 268 and Windows 278, each
skipping the other's. A case whose *subject* differs by platform -- `Path.Join` writes a
different separator, and `\x` is rooted on one and an ordinary name on the
other -- carries an `expected.linux.txt` beside its `expected.txt` rather than
having the difference argued away.

Four of those cases are real 32-bit binaries, built and run on both systems, and
two are built for ARM64 and not run: there is no ARM64 machine here, so they
stop at an object file LLVM verified and lowered, with their signatures pinned
against clang's. Building 32-bit on Linux needs the development half of the
multilib packages, which is what
[tests/linux-x86.Dockerfile](tests/linux-x86.Dockerfile) is for.

macOS is not tested. Nothing in the compiler is Windows-only and the runtime's
`#ifdef`s have a POSIX branch that Linux exercises, so it is likely close; the
constants in `bindings/linux` are Linux's and would not port, and that is
stated where they are.

The compiler finds clang on `PATH`, at `C:\Program Files\LLVM\bin`, or wherever
`STAINLESS_CLANG` points.

## Using it

```
stainless build [paths...]     compile to a native executable
stainless run   [paths...]     compile, then run it
stainless emit-ir [paths...]   print the generated LLVM IR
stainless init [name]          write a stainless.json here
stainless restore              resolve dependencies and lock them

  -o, --out <path>       output file
  --shared               build a shared library instead of an executable
  --header <path>        write a C header for the exported surface
  --metadata <path>      write module metadata for a Stainless consumer
  -r, --reference <path> bind against a library's module metadata
  --project <path>       the project file to build, or its directory
  --no-project           ignore any project file and use the paths alone
  --update               re-resolve dependencies, ignoring the lock
  --locked               fail rather than change the lock file
  --offline              use the package cache and never the network
  --runtime <shared|static>
                         whether the runtime is one shared library or a
                         copy in this binary. Shared where two Stainless
                         binaries meet, static everywhere else
  -O<0-3>                optimization level (default -O2)
  -g, --debug            describe the program to a debugger
  -D, --define <name>    define a symbol for '#if' to test
  -l, --library <name>   link a library the linker finds by name
                         (a source file can name one itself, with
                          '#pragma comment(lib, "user32")')
  --abi <microsoft|itanium>  which C and C++ ABI to agree with: names,
                         bit-fields and how a struct is passed
  --target <name>        the machine to build for: x64 (the default), x86 or
                         arm64, optionally with a system -- x86-windows,
                         x86-linux, arm64-windows, arm64-linux
  --keep                 keep the generated .ll
  --obj <dir>            directory for intermediates (default ./obj)
  -h, --help  -v, --version
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

### Projects

That command line says everything the build needs, and it cannot be *read*. A
tool that wants to know what a program is made of — an editor, a language
server, a package resolver — can only run a build and watch what happens, and a
Makefile is no better, because a Makefile is a program too.

So a project is a document. `stainless.json` at the root of a package, and
`stainless build` with no paths finds it here or in a parent:

```json
{
  "name": "app",
  "version": "0.1.0",
  "kind": "executable",
  "sources": ["src"],
  "dependencies": {
    "shapes": { "path": "../shapes", "version": "^1.0" }
  }
}
```

```
stainless init app      # writes exactly those four fields
stainless run           # builds the project, and whatever it depends on
```

JSON because both sides can already read it: the compiler has a parser in the
framework it is written in, and [stdlib/Json.sl](stdlib/Json.sl) is the other
one — so a program written in this language can read its own project file with
nothing new written. A nicer syntax would cost two parsers for ever.

**A field the format does not know is refused**, not ignored. A typo that
silently did nothing is the failure a readable project file exists to prevent:

```
error: 'optimise' is not a field of a project file; did you mean 'optimize'?
```

### Packages

A dependency comes from a directory or from git, and says which versions will
do. A bare version is a caret — `1.2.0` means "1.2.0 up to but not including
2.0.0" — which follows Cargo rather than npm, because the bare spelling is the
one people type and it should mean what they almost always want.

```json
"dependencies": {
  "geometry": { "path": "../geometry" },
  "json":     { "git": "https://example/json.git", "tag": "v2.1.0", "version": "^2.1" },
  "widgets":  { "path": "../widgets", "link": "shared" }
}
```

**A dependency is compiled in by default**, and that is the interesting choice.
Source is the model this language already has — one program, no headers,
whole-program binding — so generics, interfaces and variants all cross a source
dependency, when none of them can cross a binary one. `"link": "shared"` is the
opt-in for a real boundary: the package is built once as a shared library, bound
against through its metadata, and can be replaced without rebuilding what uses
it.

`stainless.lock` records what resolution decided — the exact commit, and a
digest of the files that were read — and belongs in version control. A tag can
be moved and a branch is expected to; a locked build goes to the commit rather
than to the name, and `--update` is the request to look again.

#### A version is a promise; the digest is a fact

Nothing stops 1.2.3 being rebuilt with a field added to the middle of a class,
and nothing about the number says it happened — while everything compiled
against it has that class's offsets baked in. It is not a link error. It is a
program that reads the wrong four bytes and keeps going.

So the metadata also carries a fingerprint taken over the layouts themselves,
and the build compares. Move a field without moving the version and it says so,
by name:

```
note: 'shapes' 1.0.0 describes a different surface than the last build of 1.0.0
      did: Shapes.Canvas. A version number is a promise about exactly this, and
      whatever was compiled against the old surface has those offsets and
      signatures built into it -- the linker cannot tell, because the symbols
      did not change.
```

Adding a function is not a broken promise and says nothing; moving a field is.
A path dependency is told rather than stopped, because being edited in place is
the entire reason to use one.

[samples/packages](samples/packages) is two packages and one program, and
[docs/packages.md](docs/packages.md) is the whole of it: every field, the
version ranges, what resolution does and what it deliberately does not.

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

Classes cross with their fields, properties, methods, constructors, destructors
and **events**, and so do structs, enums, free functions, `closure` types and
`delegate` types. A consumer subscribes to an event declared in a library it has
no source for, with handlers of its own, and the library raises them — and
because the method that raises an event is private, "only the declaring type may
raise it" holds across the boundary without anything checking it there.

Reference counting reaches across too: the object is allocated through the
library's own TypeInfo, so it is destroyed by the destructor the library
compiled for its layout, when the consumer drops the last reference.

**Both sides link one runtime**, which is what makes that count one count. They
share an allocator and a C stdio buffer as well, so what a library prints
interleaves with its consumer's output in the order the two of them wrote it.
The compiler builds `stainless-rt` once and copies it beside each binary, so
`build/` ends up holding it next to the library and the program.

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
- Type aliases: `using Handle = void*;`, module-level, public or not, naming
  another alias or a type from another module. An alias is the type it names, so
  it costs nothing and converts nothing; a ring of them is refused whether or
  not anything uses it
- Opaque struct types: `public struct HWND__;`, C's incomplete type, declared
  here and laid out somewhere else. A value of one cannot exist and a pointer to
  one is a distinct type, so handles are told apart at no run-time cost at all.
  The generated C header declares the tag and typedefs the alias, exactly as C
  would write it by hand
- Bit-fields: `public uint Kind : 4;` in a struct or a union, with the width a
  constant from one to the width of the declared type. Both C ABIs are
  implemented — Microsoft opens a new storage unit when the declared type's size
  changes, Itanium packs across — and `--abi` chooses, defaulting to the host's.
  A signed field sign-extends from its own width; writing one leaves its
  neighbours alone; one has no address, so no `ref` to it
- Both struct conventions, chosen by the same `--abi`: Win64 asks only how big
  a struct is, and System V AMD64 asks what is in it — cutting it into
  eightbytes and passing each in an integer or an SSE register, so
  `{ double; int; }` takes one of each and `{ float; int; }` takes one. Every
  shape was checked against clang built for the matching target
- **32-bit x86**, with `--target x86`: a four-byte pointer, and every header
  counted in words rather than in eights. Every struct travels on the stack,
  because there are no argument registers to classify into; returns are where
  the two systems part company, and Windows returns a struct of 1, 2, 4 or 8
  bytes in a register where i386 System V returns every struct in memory. Both
  systems are built *and run* by the suite, as real 32-bit binaries
- **ARM64**, with `--target arm64`, and one classifier for both systems because
  Microsoft's ARM64 ABI and ARM's agree about every shape asked. A struct whose
  members are all the same floating-point type, four or fewer of them and no
  padding, travels in one SIMD register each however big it is; everything else
  of sixteen bytes or less goes in one or two general registers, and everything
  larger is a pointer to a copy. Nothing here has *run* an ARM64 binary: there
  is no such machine and no ARM64 C library to link against, so the cases stop
  at an object file that LLVM verified and lowered, with the signatures pinned
  against clang's
- **Calling conventions** a declaration can name: `__cdecl`, `__stdcall`,
  `__fastcall` and `__vectorcall`, written after the linkage string and
  applying to one declaration or to a whole `extern "C"` block. On x64 only
  `__vectorcall` differs, and ARM64 has one convention at all; on x86 each
  decorates the linker name with what its arguments occupy — `_f@8` for
  `__stdcall` — which is what makes a caller and a callee disagreeing about the
  count a link error rather than an unbalanced stack. Decoration is Microsoft's
  and stops where PE does: an i386 ELF `__stdcall` gets the convention and the
  plain name, which is what gcc has always done
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
- Flow narrowing, for a variant's case and for `C?` alike: `if (x != null)`
  makes `x` a `C`, through an `if`, a `!`, `&&`, `||`, a ternary, an early
  return and a `switch`. Only for a local or a parameter, and never for a
  `weak C?`, which may die between the check and the use; an assignment takes
  the proof away, and so does one anywhere in a loop body
- `is` with a name — `if (node.Payload is Circle c)`, for a variant's case or a
  class — which is how a field or a call result gets at what a test found. The
  value is evaluated once and the name is in scope where the test succeeded.
  Over a `C?` it asks about the null and the class at once, so
  `if (node.Next is Node n)` is the narrowing a field could not have
- `class` with fields, constructors, destructors, methods; ARC with correct
  nested destruction
- Single inheritance, the C# model: `virtual`, `override`, `abstract`,
  `sealed`, `protected`, `base(...)` chaining and `base.M()`. A virtual call is
  three constant-offset loads and an indirect call — one fewer than an interface
  call, because there is no interface id to look up. Fields are laid out after
  the base's, destructors chain derived-first, interfaces and their tables are
  inherited, and an upcast emits no instructions at all
- `com interface` and `com class`: COM's binary contract, which is a pointer
  to a vtable pointer and needs no operating system, so both work on every
  platform. ARC drives `AddRef` and `Release`, `is` and a cast are
  `QueryInterface`, and `[Guid("...")]` folds to a constant `iidof` names. A
  com class presents vtables from an ordinary object through tear-offs, one per
  interface, each with the distance back that lets a `Release` find the header.
  Every slot is `__stdcall` on x86 — part of the contract rather than a Windows
  detail — which a `com interface` does not have to say, because the convention
  is stamped on when its table is numbered
- `x is T` and a checked `(T)x`, for classes and interfaces alike. `is` answers
  false for null, so a test through a `C?` asks about null and about the class
  at once; a cast that does not hold names what the object really is and ends
  the program, there being no exception for it to throw
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
- `static` as C# means it: fields, methods, properties, static constructors and
  `static class`, on a module or on a type, mutable or `readonly`. Storage is
  initialized before `Main` in an order the compiler computes from the
  dependency graph — no lazy guard, and a compile error on a cycle. A static
  method is what a fallible factory is written as, since it can use a private
  constructor and a constructor cannot report why it failed
- `threadsafe`, a word on a class, struct or interface saying that operations
  on it synchronize themselves. Anything crossing a thread that is not that,
  plain data, a `String` or an array of plain data draws a warning at the
  `spawn`, the `parallel for` capture, or the static that would share it --
  a warning rather than a refusal, because the word is an assertion no compiler
  can check, and refusing would leave someone who knows better with nothing to
  do but write it untruthfully. `where T : threadsafe` is the strict form, and
  there it is an error, because the library author asked
- Full operator set with C# precedence, short-circuit `&&` and `||`, and the
  conditional `a ? b : c`. The arithmetic C leaves undefined is defined here:
  a shift count is reduced modulo the operand's width as in C#, so `1 << 40` is
  256 rather than garbage, and an integer division by zero — or the one signed
  division that overflows — aborts the way an out-of-range index does, rather
  than being folded to whatever the optimiser likes. A divisor that is zero at
  compile time is an error instead. Aborting writes a line to standard error
  and ends the process, after flushing everything the program has written, so
  the output that led up to the failure is there to read
- `var`, `const`, explicit locals, compound assignment
- `String`: UTF-8, immutable, reference counted, `+` and `==`, zero-copy
  `ToPointer()`, `ToUtf16()`, and literals that never allocate. UTF-16 converts
  back with `ToText()` or, from a buffer a platform API filled, with
  `Text.FromUtf16`; anything malformed becomes U+FFFD in both directions, so a
  `String` is UTF-8 by invariant
- A string API to go with it: `StartsWith`, `Contains`, `IndexOf`,
  `LastIndexOf`, `Substring`, `Before`/`After`/`AfterLast`, `Trim`, `Replace`,
  `Repeat`, `PadLeft`/`PadRight`, `Split`, `SplitLines`, `Join`, `CompareTo`,
  the ASCII case pair, and `CodePointAt`/`NextCodePoint` for walking the text
  properly. All of it written in Stainless rather than C, because a type may be
  declared more than once inside its own module and `String`'s second
  declaration is `stdlib/Text.sl` — which is also why `Split` can return a
  `String[]` when the runtime cannot allocate one
- A type may span declarations, the way a module already spans files. The first
  says what the type is — its kind, its fields, what it derives from — and a
  later one adds behaviour and nothing else. No `partial` keyword, because
  there is nothing for it to prevent
- `StringBuilder`: appending, reading (`ByteAt`, `IndexOf`) and editing
  (`Insert`, `Remove`, `Truncate`, `ReplaceAll`). It hands out no pointer,
  unlike `String`: its bytes move as it grows, so one would dangle at the next
  append
- `char`, `char16` and `char32`: one UTF-8 code unit, one UTF-16 code unit and
  one Unicode scalar. Three encodings rather than three widths, so none becomes
  another without a cast, and a character literal is one scalar that takes the
  narrowest of the three holding it whole. `Utf16String.ToPointer()` is a
  `char16*`, which is what makes handing a wide API the wrong 16-bit pointer a
  compile error
- `T[]`: counted arrays, always bounds checked, elements released with the array
- Array literals: `[1, 2, 3]`, taking their type from where they are going — a
  `T[]`, a `T[N]` of matching length or a `T[:]` — or from their own elements
  when nothing else says, so `var xs = [1, 2, 3]` needs no type written out
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
- Generics: generic classes, interfaces, functions and methods, monomorphized,
  with inference at call sites and constraints: an interface, a base class,
  another type parameter, `class`, `struct`, `new()` and `threadsafe`
- `enum`, strongly typed: a distinct type over an integer that never converts
  implicitly in either direction, with an optional underlying type
  (`enum Level : byte`)
- `[Flags]` enums: `|`, `&`, `^` and `~` on an enum whose members are bits,
  producing that same enum rather than its number, plus `HasFlag`. The marker
  needs no import, because it is a rule about enums rather than a library
- `ref`, `in` and `out` parameters: the caller's storage rather than a copy of
  it. `ref` is writable and `in` is not; `out` is writable and *must* be
  written, which is the promise that lets the caller pass a variable holding
  nothing. `ref` and `out` are written at the call as well as the declaration,
  must name storage, and are not converted; writing to an `in`, or passing one
  on as a `ref`, is refused. A call may declare the variable an `out` fills —
  `TryHalve(10, out var five)` — taking its type from the parameter. The mode is
  part of a signature, so overloads may not differ only in it and a class does
  not implement `ref int` with `int`. All three are a `T*` at the ABI, so
  `extern "C" double modf(double, ref double)` needs no shim, and a generated
  header writes them `T*`, `const T*` and `T*`
- Named arguments: `Draw(text, width: 3, center: true)`, after the positional
  ones. Each names a parameter, none twice, none left out, and the names take
  part in choosing an overload — which is what makes a four-`bool` call and a
  wide constructor readable
- `delegate`: a named function pointer, one word, C ABI compatible in both
  directions, and storable in a `struct`
- `closure`: a method **and the object it belongs to** — two words, what Delphi
  spells `of object`, and what a callback has to be to know anything.
  `counter.Add` and a capturing lambda are the same type and interchangeable;
  the receiver is kept alive by ARC for as long as the closure is; and `==`
  compares both words, so one is removable from a list of them. It costs
  nothing to support: a method already takes its receiver as argument zero, so
  a bound method pointer is the method's own address beside the object, and
  being two fields is what gives it layout, both ABI classifiers and reference
  counting without any of them being written for it
- `event`: several subscribers behind one name, in C#'s shape —
  `source.Changed += listener.OnChanged` and `-=` to take it off again, removal
  by closure equality so the right one goes. Raising calls every subscriber in
  the order they subscribed, and **only the declaring type may raise it**: from
  outside, those two operators are all there is, which is what separates an
  event from a public field of closure type. Two of C#'s sharp edges are filed
  off: raising an event nobody has subscribed to does nothing rather than
  throwing, so no `?.Invoke` anywhere, and a handler must return `void`, since
  with several subscribers there is no honest answer to what it returned. A
  raise reads the subscriber list before it starts, so a handler may subscribe
  or unsubscribe while it runs. Events cross a library boundary: a program
  subscribes to one declared in a library it has no source for
- Lambdas: `value => value * factor` becomes a generated class capturing **by
  value**, so it may outlive the scope that built it. What it is *seen* as is
  decided by what it is assigned to — a `closure`, a single-method interface,
  or, if it captures nothing, a `delegate`. A
  lambda written in a method reaches its object too — a field, a property,
  `this`, or a method called without a receiver — and captures what it reads by
  the same rule
- `weak C?`: assignable, so a reference cycle can be broken. A weak reference
  costs the object nothing while it lives and reads back as `null` once it is
  gone, rather than as a pointer into freed memory
- `foreach` over arrays and over anything with a `GetEnumerator()`, plus
  `IEnumerable<T>` / `IEnumerator<T>` in `Standard.Collections`
- One runtime where two Stainless binaries meet: a program and the libraries it
  loads reach the same allocator, the same reference counts and the same stdio
  buffer, so an object made on one side and dropped on the other is counted once
  and output interleaves in the order it was written. It is a shared library
  built once and copied beside what uses it; a program with no such boundary
  keeps the copy compiled into it and stays a single file. `--runtime` overrides
  the choice, and a mismatch across a boundary is refused rather than left to
  misbehave
- Interfaces: several per class, dynamic dispatch, checked at compile time,
  inherited by a derived class along with everything else, and extending one
  another with free conversion to the base. A class may implement
  two instantiations of one generic interface — `IEq<int>` and `IEq<String>` —
  because each interface has its own dispatch table and the overloads land in
  different slots
- Overloading by parameter type, on methods as well as module-level functions;
  a return type alone does not distinguish two of them
- `Standard.Collections`: `List<T>`, `Dictionary<K, V>`, `HashSet<T>`,
  `Queue<T>`, `Stack<T>`, `LinkedList<T>` and `SortedList<K, V>`, plus
  `IComparable<T>`, `IEquatable<T>`, `IHashable`, `IReadOnlyList<T>`,
  `IList<T>`, `IEnumerable<T>` and `IEnumerator<T>`. Every container is
  array-backed — ARC cannot collect a cycle, so the linked list links by index
  rather than by reference — and every one of them walks itself when iterated
  rather than copying into a list first
- **`Sort` is a stable merge sort**, over a `T[:]` or an `IList<T>`, by
  `IComparable<T>` or by a `Comparer<T>` you pass. Stability is what lets a
  multi-key order be built by sorting twice. Alongside it: `Largest`,
  `Smallest`, `IndexOf`, `RemoveFirst`, `RemoveWhere`, `Reverse`,
  `BinarySearch` and `LowerBound`
- **`x.F(y)` is `F(x, y)`** when `x` has no member `F`, which is what makes the
  library chain:

  ```csharp
  words.Where(w => w.Length() > 1u).Distinct().OrderBy(ByLength).ToArray()
  ```

  Uniform call syntax rather than extension methods: a module is a scope here,
  so a function need not be wrapped in a static class to exist and there is
  nothing a `this` modifier would add. A member always wins, so nothing a type
  declares can be shadowed by somebody else's function
- **Combinators**, over an array, a slice or any `IEnumerable<T>`: `Map`,
  `Filter`, `Reduce`, `Any`, `All`, `CountWhere`, `Find`, `FirstOr`,
  `IndexWhere`, `ForEach`, `Take`, `Skip`, `Distinct`, `OrderBy`, `ToList` and
  `ToArray`, plus `Where`, `Select`, `Aggregate` under the names LINQ gave
  them. Each takes a generic
  `closure` — `Func<T, R>`, `Predicate<T>`, `Action<T>`, `Fold<A, T>`,
  `Comparer<T>` — so a lambda and a method that already exists are the same
  thing:

  ```csharp
  var adults = Filter(people, p => p.Age >= 18);
  var names  = Map(adults, p => p.Name);
  long total = Reduce(numbers, (long)0, (sum, n) => sum + (long)n);

  ForEach(lines, report.Note);        // a method bound to an object
  Sort(people, (a, b) => a.Age - b.Age);
  ```

  These were one-method interfaces until a closure could be generic, and the
  bound-method line is what that bought: an interface needs an object that
  implements it, so passing an existing method meant declaring a class whose
  only purpose was to carry it.

  Eager, not lazy: each returns a `List<T>`, because lazy chaining wants
  generators and the language has no `yield`
- **"Not there" is an `Optional`**, not a sentinel. `IndexOf`, `IndexWhere`,
  `Find` and a dictionary's `map[key]` answer with one, so a length, a magic
  number or a crash never stands in for a miss. A value converts implicitly to
  the `Optional<T>` holding it, as it does to a `T?` in Swift and C#, which is
  what lets `map[key] = value` stay ordinary while `map[key]` stays honest
- Primitives, enums and `String` satisfy `IComparable<T>`, `IEquatable<T>` and
  `IHashable` without declaring it, so `Sort(numbers)` works on a `List<int>`
  and `Dictionary<String, V>` needs nothing extra
- `StringBuilder`: mutable text with amortised O(1) appends
- `Standard.Threading`: two layers. The structured one is `Mutex<T>` and its
  `Guard<T>` (the lock owns what it guards, and a destructor releases it),
  `Monitor<T>` with `Wait`/`Pulse`, `RwLock<T>` with separate read and write
  guards, `AtomicLong`/`AtomicInt`/`AtomicBool`, and `TaskScope` for running
  `Job` delegates on the pool. The unstructured one is `Thread` itself
  (`Join`, `Detach`, and a destructor that joins), `Semaphore`,
  `ManualResetEvent`, `AutoResetEvent`, `CountdownEvent`, `Barrier`, `SpinWait`
  and `Threading.Sleep`/`Yield`/`CurrentId`. A `spawn`ed job may borrow the
  frame that spawned it; a `Thread` may not, and what it touches has to outlive
  it — see [docs/concurrency.md](docs/concurrency.md) §11
- `Standard.Math`: the C library's floating point, plus `Abs`/`Min`/`Max`/
  `Clamp`/`Sign` overloaded across `int`, `long`, `nuint` and `double`,
  `IsNaN`/`IsInfinite`/`IsFinite`, `GreatestCommonDivisor`, and the bit
  functions. A module is a scope, so `Math.Sqrt(x)` needs no static class
- `Standard.Concurrent`: `ConcurrentQueue<T>`, `ConcurrentStack<T>`,
  `ConcurrentDictionary<K, V>` and a blocking `Channel<T>`. Each owns its
  collection in a field and never hands out a reference to it, because a lock
  protects what it guards and not the reference *count* of what it guards
- `Standard.Process`: running another program, on both platforms.
  `Run(program, arguments)` waits and captures; `Start` hands back a `Process`
  to wait on, poll or stop. **There is no shell** — the arguments are a list,
  so a `>` or a space in a filename is a character the child receives rather
  than something a shell acts on. A failure to *start* is a `ProcessError`; a
  program that ran and returned 1 is a `Completed`, which is an outcome. Both
  streams are drained while it runs, because a pipe holds about 64KB and a
  parent that waits first would wait forever. `Signals.Watch()` notices Ctrl-C
  as a flag to read rather than a handler to run in
- `Standard.Env`: the command line, environment variables and the working
  directory. `Main(String[] args)` is the better way to read the arguments --
  a function that takes what it needs beats one that goes looking -- and
  `Env.Arguments()` is for the code that is nowhere near `Main`
- `Standard.Time`: `Instant` (a point on the wall clock) and `Duration` (a
  length), both structs over one `long` of nanoseconds that declare the
  arithmetic to go with it -- `hour + minute`, `later - earlier` -- and are
  made by naming the unit, `Duration.FromSeconds(30)`. Plus `DateTime` for the
  parts a person reads, ISO 8601 in both directions, and `Clock` over the
  **monotonic** counter -- which is the only correct way to measure how long
  something took, because the wall clock can jump mid-measurement. The UTC
  calendar is computed rather than delegated, so dates before 1970 work on
  Windows too
- `Standard.Random`: xoshiro256**, seeded by you for a reproducible run or by
  the operating system for an unpredictable one. A class rather than free
  functions, because the state has to live somewhere and a hidden global one
  is what makes a program impossible to replay. `Random.Bytes` goes straight to
  the platform's cryptographic source, which is what a key or a token wants
- `Standard.IO`, `Standard.File`, `Standard.Directory`, `Standard.Path`:
  `IStream` with `FileStream` and `MemoryStream`, whole-file reads and writes,
  directory listing, and textual path handling. Failure is a returned value —
  a `Result<T, IOError>`, or a bare `IOError` where nothing is produced. Paths
  are UTF-8 and are widened to UTF-16 before they reach Windows.
  `Standard.Path` answers the platform's questions rather than one platform's:
  Windows reads both `\` and `/` apart and writes `\`, and everywhere else
  only `/` is a separator — a backslash there is an ordinary character a
  filename may contain, so treating `report\2026.csv` as two parts would be
  wrong rather than lenient
- `Standard.Net`: `TcpListener`, `TcpClient`, `UdpSocket` and the `Socket`
  underneath them, the same on Windows and Linux. `TcpClient` is an `IStream`,
  so a reader written against a file works over a connection with nothing
  changed. Winsock and BSD sockets disagree about the handle, the errors, the
  close and the startup; all of that is in `runtime/socket.c` and none of it
  reaches a program
- `Standard.Encoding`: UTF-8, UTF-16 and UTF-32 in both byte orders, ASCII,
  Latin-1 and Windows-1252, behind an `IEncoding` a program can implement.
  Lossy by default, because `GetString` returns a `String` and a `String` is
  valid UTF-8 by invariant; `TryGetString` is the strict form and refuses an
  overlong sequence as well as a malformed one. `Detect` reads a byte order mark
- `Standard.Json` and `Standard.Xml`: each in two layers. A document that needs
  no type -- `Json.Parse` gives a `JsonValue`, a variant that is exactly one of
  the six things JSON has, and `Xml.Parse` gives an `XmlNode` -- and a mapping
  onto a `[Reflect]` type, where `Serialize` reads an object's fields and
  `Populate` writes them. Reading fills an object the program made rather than
  allocating one, so a constructor has established the type's invariants before
  a single field is overwritten, and a field the document does not mention keeps
  what the constructor chose. Arrays and collections are left out of the
  mapping: the field tables record that a field is an array and nothing about
  its elements, so a type holding one wants the document layer
- `Optional<T>`, a variant in `Standard`: a value or none, for the types `T?`
  cannot describe. `C?` is a nullable reference and costs nothing, but a value
  type has no spare bit to be null with — so `nuint?` is refused and this is
  what `IndexOf` answers with instead of a magic number. Not a second meaning
  for `?`: a pointer for a class and a tagged pair for a value would have been
  two representations behind one spelling. It reads like Java's — `HasValue`,
  `IsEmpty`, `Get`, `ValueOr`, `Or`, `Map`, `FlatMap`, `Filter`, `IfPresent` —
  over machinery that is all variant: `if (found is Some at)` is what every one
  of them is written in terms of
- `OrderedDictionary<K, V>`: a dictionary that keeps the order its keys were
  added in, found by scanning rather than hashing. For wherever the order is
  part of the data — a parsed document read back the way it was written — and
  not for anything large enough for O(n) lookup to hurt
- `Standard.Text.FromDouble` writes the shortest text that reads back as the
  same number, and `Standard.Convert.ToDouble` is its correctly-rounded
  inverse, so a number survives being written and read
- `Standard.Convert`: base64 and base64url, hex, and integer and floating-point
  parsing in any radix from 2 to 36. Everything that can fail returns a
  `Result`, because there is no exception to throw and no `out` to fill
- `Standard.Text` (imported everywhere), `Standard.Ascii`, `Standard.Console`,
  `Standard.Reflection`
- Raw pointers, `sizeof`, `alignof`, `offsetof`, `typeof`, casts, `new`, `this`.
  The three layout questions answer exactly what C's do, which is how a binding
  checks itself against a header; `offsetof` on a class counts from the
  allocation, so the number is what to add to the reference you hold
- Integer literals that fit convert implicitly, as in C#, and one that fits
  nothing is refused rather than truncated. A literal is the narrowest of
  `int`, `uint`, `long` and `ulong` that holds it, so a mask written the way a
  C header writes it means what it says. A floating-point literal is a `double`
  unless it carries the `f` suffix
- Shared libraries: `--shared` with a generated C header, and an export table
  containing exactly the `export "C"` functions
- Stainless libraries consumed by Stainless: `--metadata` writes a `.slmod`
  describing a library's public surface, and `--reference` binds another
  compilation against it. Classes cross with their fields, properties, methods,
  constructors, destructors and events; so do structs, enums, free functions,
  closures and delegates, and reference counting reaches across, because an
  object is allocated through the library's own TypeInfo. Generics and classes
  implementing interfaces do not cross, and the compiler says so where the
  library is built
- **Deriving from a class in another binary.** Its layout, its dispatch table
  slot by slot, its destroy hook and its protected members all cross, so a
  derived class puts its fields after fields it never saw laid out, builds its
  table on top of one compiled elsewhere, overrides into it, and hands the
  object back to the library when its own destructor is done. What it costs is
  that the base's table length is part of its contract: adding a virtual method
  to a public class is a breaking change, and the ABI digest is what enforces
  it rather than convention
- Projects and packages: a `stainless.json` that states what a program is made
  of — a document rather than a script, so a tool can read it — plus versioned
  dependencies from a path or from git, a committed `stainless.lock`, and an ABI
  digest over every layout and signature, so a library whose surface moved under
  a fixed version is a message instead of a program reading the wrong four
  bytes. A dependency is compiled in by default, which is the model the language
  already has; `"link": "shared"` is the opt-in for a binary boundary. See
  [docs/packages.md](docs/packages.md)
- Attributes and opt-in reflection: field names, offsets, kinds and attribute
  values readable at run time, from `const` tables in the binary
- `-g`: debug information, in CodeView on Windows and DWARF elsewhere. Every
  instruction carries a source location, every function is named as it was
  written and as the linker sees it, and every local and parameter is described
  with its type and its stack slot. The standard library is written to
  `obj/stdlib/` and the runtime's C compiled `-O0 -g`, so a stack trace through
  `List.Add` and into `sl_retain` names real files and real lines rather than
  addresses. See [§7 of the ABI notes](docs/abi.md)
- [bindings/win32](bindings/win32): the Windows API — entry points, constants,
  structs, unions, enums, delegates, handle types and COM interfaces — as
  declarations rather than a marshalling layer, in two layers a module name
  apart:
  `Win32.User32` is what the DLL exports, `Win32.Ui` is the conveniences on top.
  Source a program compiles rather than part of the standard library, because
  compiling a wrapper is what makes its library necessary; the raw layer needs
  no library at all
- [bindings/linux](bindings/linux): the Linux socket calls, the terminal
  (`termios` and `ioctl`, with raw mode, the window size, the cursor and
  colour) and the event loop (`epoll`, `eventfd`, `timerfd`, `inotify`) — where
  everything is a file descriptor, so one wait covers sockets, timers, file
  changes and other threads together. On the same terms as the Win32 ones.
  `#if LINUX` and not `#if UNIX`, because the functions are POSIX and the
  numbers are not — `AF_INET6` is 10 here, 23 on Windows and 30 on macOS — so
  a file claiming to be POSIX would have to be wrong on two platforms out of
  three. Both bindings are checked against the real headers by a C file
  compiled beside the test, which is how a constant in a binding stops being
  somebody's recollection
- Conditional compilation: `#if`, `#elif`, `#else`, `#endif`, `#define`,
  `#undef`, `#error`, `#warning`, `#region` and `#endregion`, with C#'s
  condition grammar, plus `#pragma comment(lib, "...")` so a file can name the
  library it needs. A branch that is not taken is never lexed, so it need not
  parse. `WINDOWS`, `LINUX`, `MACOS`, `FREEBSD`, `UNIX`, `X64`, `ARM64`, `X86`,
  `ARM` and `STAINLESS` describe the target — the architecture one follows
  `--target`, so a binding guarded by `#if X86` compiles the half it means to;
  `-D` adds the rest. No macros and no `#include`: a name always means itself
- Diagnostics with source excerpts and caret runs

## What does not exist yet

Being straight about the edges, roughly in the order they are worth adding:

- **Constraints are checked at the instantiation, not the declaration.**
  `where T : IShape` is verified where the generic is used, but the body is
  still checked per instantiation, so an unused template is never checked and
  a mistake inside one is reported against its use. Definition-site checking
  would need constraints on operators too, which is a larger step.
- **Type arguments cannot be written at a call.** `Pick<int>(...)` is rejected,
  because `<` in expression position is ambiguous with less-than, so a type
  parameter that appears only in the function's own return type cannot be
  worked out. That holds for generic methods too, and an interface method
  cannot be generic at all, since dispatch gives it one slot. A parameter that
  appears only in a *lambda's* result is a different case and is inferred, by
  binding the body once the other arguments have given it its parameter types —
  which is what makes `Map(numbers, n => n * 2)` work. The same ambiguity is
  why an instantiation cannot be *named* in expression position either:
  `new Box<int>(...)` reads, because a type is what is expected after `new`,
  but `Box<int>.Of(2)` and `Box<int>.Count` do not. A generic type's static
  members are reachable from inside it and from a value of it, and a maker for
  one is written as a module-level generic function. Inside the type its own
  statics are named directly, as they are anywhere else.
- **No `switch` expression, and the only pattern is a variant's case.** A
  switch over a variant covers cases and may bind a payload; everywhere else
  `switch` is the C# statement and only that. No type patterns, no constants
  inside a case pattern, no guards, no `goto case`, and no exhaustiveness
  requirement on an enum, whose value need not be one of its members.
- **A lambda needs something to be.** It is typed by what it is assigned to, so
  `var f = x => x;` has nothing to infer from and is refused (SL0553). Capture
  is by value only, and a capturing lambda cannot become a `delegate` — a
  function pointer has nowhere to keep what was captured. A lambda that captures `this` keeps its object
  alive, so an object holding its own closure is a cycle; `weak` is how that is
  broken.
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
- **Case mapping is ASCII only.** `ToUpperAscii` and `ToLowerAscii` map A–Z
  and leave every other byte alone, and say so in their names. Full Unicode
  case mapping is a table of several thousand entries with locale exceptions,
  and the runtime has no room for it yet. There is also no collation: strings
  order by their bytes, which happens to order by code point and does not
  resemble any language's idea of alphabetical.
- **`String` positions are byte offsets.** That is what makes length O(1), and
  every position the library produces lands on a character boundary because it
  came from matching whole text. A position a caller invents is its own
  business: `Substring(1, 1)` on a multi-byte character will slice it in half.
  `CodePointAt` and `NextCodePoint` are the way to walk the text properly.
- **Flow narrowing does not reach a field.** `if (x != null)` makes `x` usable
  as a `C` (§2.5), on the same terms a variant is narrowed — but only for a
  local or a parameter, because a field or a call result may be a different
  value by the time it is read. `if (node.Next != null) { node.Next.Value }` is
  refused, and a local is both the fix and what the code meant. `is` with a
  name is the other fix and reads better: `if (node.Payload is Circle c)` for a
  variant's case, `if (node.Next is Node n)` for a `C?` — the value is taken
  once, so there is nothing to prove about a second read.
- **There is no `as`, and no covariant return.** `is C c` now covers the case
  `as` is usually reached for; what is left is wanting the answer as a value
  rather than as a branch. An override returns exactly what it overrides
  (SL0502).
- **Hiding an inherited member is refused, not warned about.** C# has `new` for
  it; a language with no way to reach the hidden member has nothing to say it
  about, so the same name and parameters means `override` or nothing (SL0503).
- **Reflection describes fields, properties and array elements.** A property
  is its accessors rather than an offset, so setting one through reflection
  runs the setter — which is what anything whose setter does work needs, and
  what writing an automatic property's storage silently skips.
  `Field.IsPropertyStorage()` is how the two are told apart. `FindType` looks
  a `[Reflect]` type up by its qualified name, so a document can say which type
  it wants where `typeof` cannot. **Methods and interfaces carry no metadata.**
  That is what stops a serializer filling a `List<T>`: its storage is private
  and the way in is `Add`, which nothing here can call. An array is described
  and does round-trip.
- **An interface method may not be overloaded.** Dispatch gives each one a
  single slot, so two of a name in one interface would be a call the receiver
  could not resolve. Methods on classes and structs overload freely, and a
  class may implement two interfaces whose methods share a name.
- **A property is not initialized where it is declared.** `{ get; set; } = 5;`
  is rejected for the same reason a field initializer is. `p.X += 1` also needs
  a receiver that is a plain load, since the getter and the setter each
  evaluate it. An indexer has no automatic form: `{ get; set; }` would have
  nothing to find storage for.
- **The compiler prunes no dead code; the linker does.** Every stdlib module is
  compiled with your program whether or not it is imported, and only generics
  are free — an uninstantiated template emits nothing, but a non-generic
  function or class is emitted either way. What saves the binary is that
  everything goes into its own section and the linker discards what nothing
  reached: hello-world calls `puts` and returns, so it reaches *no* standard
  library function at all, and the linker throws every one of them away.

  The compile is what nothing saves. The IR is the full size however little of
  it is used, so every build pays to emit and optimise the whole library, and
  each thing added to the library is added to every program that never mentions
  it. A reachability pass from `Main` is the real answer, and the fact that the
  stripped binary comes out identical however much the library grows is the
  measure of how completely the compiler is leaving the job to the linker.
- **Unoptimized ARC.** Retain/release traffic is correct but redundant, and a
  redundant pair costs more since the counts became atomic. The +0/+1 dataflow
  pass that removes the pair around a borrow is the fix.

  Worth knowing how much is actually at stake, because the obvious measurement
  overstates it. Counting `sl_retain` and `sl_release` in a module is not
  counting what runs: nearly all of them are in library functions the program
  never calls, so that number is really about the missing reachability pass
  above. **A read through a reference already borrows** — `cells[i].Value` in a
  loop emits no reference counting at all — so what is left to remove is
  narrower than it looks. The runtime declarations now tell LLVM what is true
  of each entry point (`sl_retain` touches only the object's header;
  `sl_release` may run any destructor and so promises nothing; the failure
  paths do not return), which is worth having for its own sake and measurably
  changes nothing. Only the +0/+1 pass will.
- **Thread safety is advice, not a proof.** What crosses a thread is checked
  by type and warned about, and `threadsafe` is an assertion -- the same bargain
  as Rust's `unsafe impl Sync`. What is unchecked entirely is how long a
  borrowed thing lives: a `Guard` can outlive the lock it proves, and a job
  could store an array it was only lent. See
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
- **A `--shared` library cannot have a static**, of a module or of a type:
  there is no entry point to initialize one from (SL0380). There is no
  per-thread storage either, and no automatic static property -- its backing
  storage would have no initializer, which is the one moment a static has.
- **An enum does not cross `extern "C"`.** A `[Flags] enum : uint` will not pass
  to a `uint` parameter without a cast, which is why
  [bindings/win32](bindings/win32) spells its constants as bare `const uint`
  rather than as the typed sets they are.
- **An inline array holds plain data only** and cannot be passed by value
  (SL0486, SL0491). The first is the same question a union cannot answer; the
  second is because C decays an array parameter to a pointer and Stainless has
  no decay, so `ref T[N]` is the spelling that lines up.
- **Sockets are blocking, and there is no TLS.** `Standard.Net` has one
  socket's worth of waiting — `WaitToRead`, `WaitToWrite` and a non-blocking
  mode — and nothing that waits on many at once, so a server that holds a
  thousand connections wants a thread each. There is no `select` or `epoll`
  over a set, no async, and nothing encrypted: a program that needs TLS reaches
  for the platform's own through `extern "C"`. `Socket.Connect` on a socket
  that is already open tries one address rather than all of them, because a
  socket whose connect failed cannot be reused and that one is already made —
  `Socket.OpenConnected(host, port, ...)` is the form that tries each.
- **No portable COM activation.** `com interface` and `com class` are in the
  language (§8.5) and work on every platform, because a COM interface is a
  pointer to a vtable pointer and nothing else; `Win32.Com` and `Win32.ShellCom`
  bind the Windows half, so `CoCreateInstance`, `IShellItem` and `IFileDialog`
  all work. What is absent is activation anywhere *but* Windows — a class
  factory, a registry of them, `DllGetClassObject` — and, on Windows, the parts
  nobody has asked for: apartments beyond `CoInitializeEx`, marshalling,
  proxies and stubs, `IDispatch`.
- **A library's surface is narrower than a module's.** `--metadata` lets a
  Stainless library be consumed by Stainless, but a generic, a class that
  implements an interface, a variant and a slice all stay behind: a template
  emits nothing until it is instantiated, a dispatch table is indexed by an id
  assigned across a whole program, a variant's cases are not a layout, and a
  slice is a type the compiler builds rather than one the source declared.
  Anything reaching one of those through a field or a signature is reported too
  (SL0419, SL0420, SL0441, SL0477), all of them where the library is built
  rather than where the consumer trips over them.
- **The shared runtime is a file to carry.** Where two Stainless binaries meet
  the runtime is one shared library, which is what puts them on one allocator
  and one stdio buffer — and it then has to sit beside them. The compiler copies
  it there, but a binary moved on its own will not find it. A program with no
  library boundary keeps the copy compiled in and stays standalone, which is
  what the default is about.
- **No `ref` locals and no `ref` returns**, which would need a lifetime story
  the language does not have. `out` does exist, and brought the language's only
  definite-assignment analysis with it: every path out of the function has to
  write the parameter (SL0600), and the caller's storage is cleared before the
  call so that a hole in that produces a zero rather than whatever the stack
  held. An ordinary local read before it is written is still nobody's business
  but the author's.
- **Tuples**: `(int, String)`, structural, with `Item1` upwards for fields and
  `var (low, high) = MinMax(xs);` where the names matter. A tuple is a struct,
  so layout, both ABI classifiers and reference counting apply to it with
  nothing written for tuples
- **A type may be declared inside another**, and is lifted out and named for
  where it was written: `Rect.Point` from outside, `Point` from within `Rect`.
  Nesting is about where a name is reached from and nothing else — no hidden
  reference to an outer instance, and no bearing on layout. It composes, and a
  nested type does not see its outer type's parameters
- `?.`, `??` and `??=`, over a `C?`. The receiver is read once, so
  `Next()?.Name` calls `Next` one time. A reference member answers null; a
  value member has no null to answer with, so `node?.Weight` needs a
  `?? fallback` and says so (SL0605) rather than inventing a zero a caller
  cannot tell from a real one. A receiver that cannot be nothing is refused,
  and `a?.b.c` is an error where `a?.b?.c` is the question actually being asked
- `default(T)` is the zeroed value of a type, for generic code that cannot
  write a literal for a type it does not know. Not a new hole in the null
  discipline: a fresh array is zeroed, so `new C[1][0]` was the spelling before
  it. `String.Empty` is a static property rather than a field, because a
  `--shared` library has no entry point to initialize a static from
- Field initializers are rejected — assign in a constructor.

What is being worked on next, and the known bugs, are in **[TODO.md](TODO.md)**.

## Repository layout

```
docs/                  language specification, ABI, concurrency, packages
runtime/               the runtime, split by feature, embedded in the compiler
stdlib/                the standard library written in Stainless, also embedded
bindings/win32/        the Windows API, compiled only by a program that asks
bindings/linux/        the Linux system calls, on the same terms
bindings/gtk/          GTK 2 and 3, and a widget layer over them
forms/                 a GUI framework: the LCL's architecture, C#'s names
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
