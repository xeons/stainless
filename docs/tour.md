<sub>[Stainless](../README.md) &rsaquo; A tour of the language</sub>

# A tour of the language

If you write C#, you can read Stainless on sight. The differences are all
underneath: values instead of objects, refcounts instead of a collector, a
linker instead of an assembly loader.

This is the guided version, written to be read start to finish. The
[language specification](spec/index.md) is the exhaustive one, and
[samples/tour](../samples/tour) is this same ground as one program that prints
what it did at each step — so running it says whether the tour is still true,
and not only whether it still builds.

---

```csharp
module App.Shapes;

import App.Math;

extern "C" int printf(byte* format, ...);

// A value type. Copied by assignment, laid out exactly like the C struct.
public struct Point
{
    public double X;
    public double Y;

    public double Length2() => X * X + Y * Y;
}

// A reference type. Heap allocated, reference counted, destroyed at zero.
public class Buffer
{
    byte* data;
    nuint length;

    public Buffer(nuint n)
    {
        data = Allocate(n);
        length = n;
    }

    ~Buffer() { Free(data); }

    public nuint Length => length;
}

// Callable from C as plain `sl_scale`.
export "C" Point sl_scale(Point p, double factor)
{
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
public variant Shape
{
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

double Area(Shape shape)
{
    switch (shape)
    {
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
if (node.Payload is Circle c)
    return c.Radius;
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
Result<Config, IOError> Load(String path)
{
    var text = File.ReadAllText(path);
    if (!text.Ok) { return Fail(text.Error); }     // now the rest holds a value
    return Ok(Parse(text.Value));
}
```

`Result<T, TError>` is an ordinary variant — `Ok(T Value)` and `Fail(TError Error)` — and
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

```csharp
public Result<List<String>, IOError> ReadAllLines(String path)
{
    return Ok(IO.SplitLines(try ReadAllText(path)));
}
```

`try e` is the value on success, and returns `Fail(e.Error)` from the enclosing
function on failure — the named temporary and the early return it replaces,
moved to where the value is used. It is `try` rather than `?` because a postfix
`?` would sit exactly where the ternary's does; Zig means the same by the word,
and there are no exceptions here to confuse it with.

The library reports failure two ways, and the difference is whether there is a
value: `Result<T, TError>` when there is one, the error enum when there is not.
Construction is the awkward case, since a constructor must return its type and
cannot say why it failed. So `FileStream.Open`, `TcpListener.Listen` and
`TcpClient.Connect` are static methods of the types they make, each returning a
`Result`, and the constructors they replace are private — a static method is
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

### Interpolation

```csharp
Console.WriteLine($"clicks: {clicks}  at {x}, {y}");
```

`$"..."` is sugar over the conversions that were already there, and one thing
that is not sugar: the whole string is joined in **one allocation**, where the
`+` chain it replaces allocates once per operator and discards all but the
last. That line emits five `sl_string_concat` calls written the old way and one
`sl_string_join` written this way.

A hole takes a `String`, a number, a `bool` or a `char32`. Anything else is
refused rather than given a default — there is no `ToString` every type owes.
A `char` is one UTF-8 *code unit* and not a character, so it has to say which it
means: `(char32)c` for the character, `(long)c` for the number.

### Arrays and generics

```csharp
var numbers = new int[5];
numbers[2] = 9;                     // bounds checked, unsigned compare

public class Box<T>
{
    T value;
    public Box(T initial) { value = initial; }
    public T Value => value;
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

T Fresh<T>(T old) where T : new() => new T();
T Copied<T>(T value) where T : struct => value;
String Says<T>(T animal) where T : Animal => animal.Says();
String Both<T, U>(T a, U b) where T : U where U : INamed => b.Name;
```

`new()` means a **class** here, unlike C#: `new` allocates, and a struct is
declared where it is used — so a struct would satisfy a constraint whose only
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
Trace[:] Middle()
{
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
emitted either way — see [dead code](status.md#what-does-not-exist-yet) in
what is implemented.

```csharp
import Standard.Collections;

public class Money : IComparable<Money>, IEquatable<Money>
{
    public int  CompareTo(Money other) { ... }
    public bool EqualTo(Money other)   { ... }
}

var prices = new List<Money>();
prices.Add(new Money(250));

Sort(prices);              // where T : IComparable<T>
Largest(prices);           // takes an IReadOnlyList<T>, so it cannot mutate
```

`List<T>`, `Dictionary<TKey, TValue>`, `HashSet<T>`, `Queue<T>`, `Stack<T>`,
`LinkedList<T>` and `SortedList<TKey, TValue>`. A primitive, an enum and a `String`
satisfy `IComparable<T>`, `IEquatable<T>` and `IHashable` without declaring it,
which is what lets them be keys and be sorted:

```csharp
var ages = new Dictionary<String, int>();
ages["ada"] = 36;
ages["grace"] = None;                   // None removes

if (ages["ada"] is Some found)
    Use(found.Value);
int guess = ages["nobody"].ValueOr(0);

var numbers = new List<int>();
numbers.Add(1);
numbers[0]++;
Sort(numbers);
```

A dictionary's subscript answers `Optional<TValue>`, as Swift's does: a key is data
that arrived from somewhere, so a lookup that misses is an answer rather than
a reason to stop the program. A list's is a plain `T`, because an index is a
position the caller worked out and an out-of-range one is the mistake
`array[i]` is.

`IList<T>` extends `IReadOnlyList<T>`, and interfaces are named with a leading
`I` as in C#.

### Passing by reference

A parameter is a copy unless it says otherwise. `ref` passes the caller's
storage and may write it; `in` passes the same storage and promises not to.

```csharp
void Bump(ref int n) { n++; }
double LengthSquared(in Point p) => p.X * p.X + p.Y * p.Y;

int count = 1;
Bump(ref count);              // count is 2
LengthSquared(origin);        // no copy, and origin cannot change
```

`ref` is written at the call too, because a reader should be able to see that
the value may come back changed. A `ref` argument has to name storage and is not
converted on the way in — the callee writes back through it, and a converted
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
public class Person
{
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
public String ToJson<T>(T value)
{
    var type = typeof(T);
    for (nuint i = 0; i < type.FieldCount; i++)
    {
        var field = type.FieldAt(i);
        if (field.Has("JsonIgnore"))
            continue;
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
public class Person
{
    public String Name { get; set; }         // automatic: the compiler owns the storage
    public int Visits { get; private set; }  // read anywhere, write in this module
    public int Id { get; }                   // set by a constructor, then fixed

    public String Label => Name + "#" + Text.FromInteger(Id);   // computed

    public Person(String name, int id) { Name = name; Id = id; Visits = 0; }
    public void Visit() { Visits++; }
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
public int Fahrenheit
{
    get { return celsius * 9 / 5 + 32; }
    set { celsius = (value - 32) * 5 / 9; }
}
```

### Statics

```csharp
public class Small
{
    int value;
    static int made = 0;                           // mutable storage

    Small(int checked) { value = checked; made++; }   // private

    public static Result<Small, ParseError> Parse(String text) { ... }
    public static int Made { get { return made; } }
}

public static class Defaults
{
    public static int Retries = 3;
}

var small = try Small.Parse(text);
```

C#'s model: fields, methods, properties, static constructors and `static
class`, at module scope or on a type, mutable or `readonly`. Storage is
initialized before `Main` in an order the compiler works out from the
dependency graph — no lazy guard on every access, and a compile error on a
cycle rather than a zero at run time. A static constructor runs there too,
which is the one departure from C#: "before first use" becomes "before
`Main`".

A static member is one of the type rather than of a value of it. The whole of the difference
is the missing receiver: no `this`, so no field is reachable without saying
which object is meant, and a call names the type.

It exists for the case above. A constructor has to return its own type, so it
cannot say why it failed, and the best it could do was hand back an object
holding nothing — which is a value a caller can go on using while nothing
forces the check. A static method is *inside* the type, so it can use a private
constructor, and that is what turns the discouraged shape into an absent one.

It is also how a struct gets a maker at all, since a struct has no
constructors.

### Operators and indexers

```csharp
public struct Money
{
    public long Cents;

    public static Money Of(long cents) { Money m; m.Cents = cents; return m; }

    public static Money operator +(Money a, Money b) => Of(a.Cents + b.Cents);
    public static Money operator *(long by, Money a) => Of(a.Cents * by);

    public static bool operator ==(Money a, Money b) => a.Cents == b.Cents;
    public static bool operator !=(Money a, Money b) => a.Cents != b.Cents;
}

public class Grid
{
    int[] cells;

    public int this[nuint at]
    {
        get { return cells[at]; }
        set { cells[at] = value; }
    }
}
```

An indexer's getter and setter share one type, which is a constraint worth
knowing before designing one: a lookup that may miss answers `Optional<TValue>`, so
its setter takes an `Optional<TValue>` too. That is how `Dictionary` spells removal
as `map[key] = None`.

C#'s shape: inside the type, `static`, every operand written out. That last
part is what makes `3 * money` expressible — an operator whose left operand is
not the declaring type has no receiver to hang off.

`&&` and `||` cannot be overloaded, because they short-circuit and an overload
would have to evaluate both sides to be called at all. The compound forms are
not overloaded separately either: `a += b` is `a = a + b` and picks up whatever
`+` does. `==` and `!=` must be declared together, as must `<`/`>` and
`<=`/`>=`; a type that answers one and not the other is a trap.

### Inheritance

```csharp
public abstract class Shape
{
    protected int sides;

    Shape(int howMany) { sides = howMany; }

    public abstract double Area();
    public virtual String Name => "shape";
}

public class Polygon : Shape
{
    double width;

    Polygon(int howMany, double w)
    {
        base(howMany);                  // the first statement, always
        width = w;
    }

    public override double Area() => width * width;
    public override String Name => "polygon";
}

public sealed class Square : Polygon
{
    Square(double side) { base(4, side); }

    public sealed override String Name => "square";
}

Shape shape = new Square(3.0);
String name = shape.Name;               // "square" — three loads and a call

if (shape is Square)
{
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
public interface IShape
{
    double Area();
    String Describe();
    String Name { get; }        // one vtable slot per accessor
}

public class Circle : IShape
{
    double radius;
    public Circle(double r) { radius = r; }
    public double Area() => 3.14159 * radius * radius;
    public String Describe() => "circle";
    public String Name { get; set; }
}

double TotalArea(IShape a, IShape b) => a.Area() + b.Area();
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
public struct Header
{
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
[§3.4 of the ABI notes](abi.md#34-how-a-struct-is-passed) has the rules and the shapes they were
checked against.

A signed bit-field sign-extends from its own width, so a three-bit `int` holding
7 reads back as -1. A bit-field has no address, so it cannot be passed by `ref`.

### Unions

C's, and here for the reason `extern "C"` is here: a great many headers describe
a value that is one of several things and record the choice somewhere else.

```csharp
public union Word
{
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
public struct SystemInfo
{
    public union
    {
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
`FREEBSD`, `UNIX`, `X64`, `X86`, `ARM64` and `STAINLESS` are defined for you; everything else
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

[bindings/win32](../bindings/win32) is what all of the above adds up to: the
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

nint HandleWindowMessage(HWND window, uint message, nuint wParam, nint lParam)
{
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
The raw layer has no such cost, and links with nothing named at all; each
convenience module names its own library with `#pragma comment(lib, ...)`, so
neither needs a `-l`, but the whole directory links every one of them:

```
stainless build app.sl bindings/win32/api                        # free
stainless build gui.sl bindings/win32                            # with the conveniences
```

Every file is `#if WINDOWS`, so elsewhere the modules exist and are empty rather
than failing to build. [samples/win32/window.sl](../samples/win32/window.sl) is a
working window — class, message loop, double-buffered GDI painting, keyboard —
[samples/win32/resources.sl](../samples/win32/resources.sl) reads what its own
binary carries, and [bindings/win32/README.md](../bindings/win32/README.md) is the
guide.

Full details are in the **[language specification](spec/index.md)**, with
**[abi.md](abi.md)** for layout and calling convention and
**[concurrency.md](concurrency.md)** for where threading is going.

---

<sub>[&larr; README](../README.md) &nbsp;&middot;&nbsp;
[Language specification &rarr;](spec/index.md)</sub>
