<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 7. Functions and members

## 7.1 Functions

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
matter, and it works — see [§2.10](02-types.md#210-interface--a-contract-dispatched-dynamically).

### 7.1.1 `x.F(y)` is `F(x, y)`

```csharp
names.Filter((n) => n.ByteLength() > 3u)
     .Map(Upper)
     .ToArray()
```

**A call written on a value reaches a free function when the value has no such
member.** The same functions either way — `Filter(names, keep)` and
`names.Filter(keep)` bind to one symbol — so a library of free functions is a
pipeline without being written twice.

This is uniform call syntax rather than C#'s extension methods, and the reason
is that this language has what C# was working around. A module is a scope here,
so a function need not be wrapped in a static class to exist; there is nothing
for a `this` modifier to add, and every free function in scope is already a
candidate.

**A member always wins.** The free function is looked for only where member
lookup has already failed, so a method added to a type can never be shadowed by
somebody else's function, and a new free function can never quietly take over a
call that used to reach a method.

**Visibility is the ordinary rule**: the function has to be one the file could
have called by name — its own module's, or one it imported. There is no
separate import for it, and no way for a function a file cannot see to attach
itself to a type.

**`p->F(x)` is not included.** The arrow insists there was a pointer to follow,
which is a statement about a member; a free function is not one.

An ambiguity is not resolved by taking a guess: where two free functions both
fit, the call is left to report that no member of the name exists, and naming
the function outright is the answer.

### 7.1.2 A parameter with a default

```csharp
String Draw(String text, int width = 8, char fill = '.', bool loud = false) { ... }

Draw("ab");                       // "ab......"
Draw("ab", 4);                    // "ab.."
Draw("ab", loud: true);           // and a name reaches past what was left out
```

**The default is written into the call**, from the declaration the caller can
see. That is not an implementation note: it is the whole of the design, and
every rule below follows from it.

**It must be a constant** (SL0613) -- a literal, `null`, a `const`, an enum
member or `default(T)`. Anything else would be code standing in a signature and
running at the caller, once per call site:

```
error[SL0613]: the default for 'n' is not a constant, and a default is written
into every call that leaves it out -- so a call would be running this rather
than passing it
```

**The ones that may be left out are the tail of the list** (SL0614). A default
in the middle could only be reached by a name, and a reader counting arguments
would have to know which of them had been filled in.

**`ref`, `in` and `out` may not have one** (SL0613): all three pass the caller's
storage rather than a value, and a default has no storage to be.

**Only one declaration may give it.** An `override` may not restate a default,
and neither may a method beside the interface method it implements (both
SL0614). C# allows both, and both are the same trap: a call reads the
declaration the *static* type gives it, so the same line would mean different
things through a base reference and a derived one. The default belongs to the
declaration, and there is one of it.

**A name is what reaches past one.** `Draw("ab", loud: true)` leaves `width` and
`fill` to their defaults; named arguments ([§7.2.2](#722-named-arguments)) and
defaults are the same feature from two directions, and they compose.

**A default takes part in overload resolution** only by making a candidate
applicable with fewer arguments. Two candidates that both fit are ambiguous
(SL0264) as they always were -- a default does not make one of them preferred.

**It crosses a library boundary as the value it folded to.** A default naming a
`const` of the library's own is a name the consumer cannot read, so the metadata
carries the number. A generated C header writes none of it: filling one in is
the caller's half, and a C caller has no declaration of this kind to read, so it
passes every argument.

## 7.2 `ref`, `in` and `out` parameters

A parameter is a copy unless it says otherwise. `ref`, `in` and `out` say
otherwise: all three pass the caller's storage rather than a copy of it, and
what separates them is who may write to it and who must.

| | The caller has filled it in | The callee may write | The callee must write |
|---|---|---|---|
| `ref` | yes | yes | no |
| `in` | yes | no | no |
| `out` | not necessarily | yes | yes |

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

### 7.2.1 `out`

```csharp
bool TryHalve(int n, out int half) {
    if (n % 2 != 0) { half = 0; return false; }
    half = n / 2;
    return true;
}

if (TryHalve(10, out var five)) { ... }      // declared by the call
if (TryHalve(7, out int none)) { ... }       // and named outright
TryHalve(8, out already);                    // or a variable that exists
```

At the ABI it is exactly what `ref` is, a `T*`. What it adds is a promise in
each direction: the caller need not have given the variable a value, and the
callee has to.

**The callee's half is checked** (SL0600). Every path out of the function
either writes the parameter or is an error, and handing it straight on as
somebody else's `out` counts as writing it — that callee is held to the same
promise. This is the only definite-assignment analysis in the language, and it
is here because this is the one place it is load-bearing: an ordinary local
read before it is written is still nobody's business but the author's, which is
a gap, but a consistent one. A function containing a `goto` stands the check
down, because a label can be arrived at from anywhere and the question stops
being answerable.

**The caller's storage is cleared before the call.** That is the safety net
under the gap: a hole in the analysis produces a zero rather than whatever the
stack held, which is the same promise a new array and an owned local already
make.

**A call may declare the variable**, and that is most of why `out` is worth
having over `ref`: the variable exists to catch the answer, and a line above
saying so is a line about the mechanism. `out var x` takes its type from the
parameter, which means it says nothing about which overload was meant and does
not vote on the choice.

`out` is written at the call (SL0597) for the reason `ref` is, and is refused
where the parameter is not one (SL0598).

**`out` is a contextual keyword**, and the standard library is what decided it:
`Convert.sl` and `Encoding.sl` both use `out` as a local. It is the modifier
only where a type or a name follows it.

**Where a `Result` is better.** `out` is for the answer that comes with a
question — *did it work*, *was it there* — and `Result<T, E>` is for the answer
that comes with a reason. The library reaches for `Result` ([§2.8](02-types.md#28-resultt-e--how-a-function-fails)) almost
everywhere, and `out` is the shape to use when the failure has nothing to say
for itself.

**What is not here.** No `ref` locals and no `ref` returns, which would need a
lifetime story the language does not have.

### 7.2.2 Named arguments

```csharp
Draw(text, width: 3, center: true, fill: '.');
var box = new Rect(left: 1, top: 2, right: 30, bottom: 40);
```

`name: value` says which parameter a value is for. It exists for the call a
reader cannot decode — four `bool`s in a row say nothing about which flag is
which — and for the constructor with more parameters than anyone remembers the
order of.

**Named arguments come after positional ones** (SL0601). Mixing the two orders
freely would make a reader count past the names to see where a positional one
lands. Among themselves the names may be in any order, because each says where
it goes. Each has to name a parameter, none may be given twice, and none may be
left empty — all SL0601, which says which of those went wrong.

**A name takes part in choosing an overload**, since two candidates may call
their parameters different things.

`base(...)` and `this(...)` take their arguments in order (SL0602): they name a
constructor rather than a declaration, so there is nothing for a name to match.

## 7.3 Properties

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
- **Initialized at the declaration only when it owns storage.** `public int X
  { get; set; } = 5;` gives that storage its first value, at the head of every
  constructor, exactly as a field initializer does ([§2.4.1](02-types.md#241-a-field-with-a-value)). A property that
  *computes* its value has no storage to give one to, and says so (SL0617).
- **Not indexed, by itself.** `this[i]` is an indexer, which is a property that takes arguments and has a section of its own ([§7.5](#75-indexers)).

## 7.4 Operators

```csharp
public struct Money {
    public long Cents;

    public static Money Of(long cents) {
        Money made;
        made.Cents = cents;
        return made;
    }

    public static Money operator +(Money a, Money b) { return Of(a.Cents + b.Cents); }
    public static Money operator *(Money a, long by)  { return Of(a.Cents * by); }
    public static Money operator *(long by, Money a)  { return Of(a.Cents * by); }

    public static bool operator ==(Money a, Money b) { return a.Cents == b.Cents; }
    public static bool operator !=(Money a, Money b) { return a.Cents != b.Cents; }
}
```

C#'s shape: **inside the type it is for, `static`, with every operand written
out**. The last part is the one that earns itself -- `3 * money` needs an
operator whose left operand is not the declaring type, and a method with an
implicit receiver could not express it.

An operator becomes an ordinary function named `op_Add`, `op_Equal` and so on,
which is the same lowering C# uses. Nothing can call that name: the type keeps
its operators apart from its methods, and an operator is reached by writing it.

**What may be overloaded**

| | |
|---|---|
| arithmetic | `+` `-` `*` `/` `%` |
| bitwise | `&` `\|` `^` `<<` `>>` |
| comparison | `==` `!=` `<` `>` `<=` `>=` |
| unary | `-` `!` `~` |

**What may not, and why.** `&&` and `\|\|` short-circuit, and an overload would
have to evaluate both sides to be called at all -- so overloading them would
change what the operator *means* rather than what it does (SL0558). `=` is not
an operator but a store. And the compound forms are not overloaded separately:
`a += b` is defined as `a = a + b` and picks up whatever `+` does, which is one
rule where two could disagree.

**The rules**, each of them C#'s and each for a reason that holds here:

- It belongs to a type (SL0560). A module-level one would let a program give
  somebody else's type a meaning from a distance.
- **One operand must be that type** (SL0563), so that reading `a + b` says
  where to look for what it means.
- It must be `public` (SL0561). An operator only its own module can write is a
  method with an unusual spelling.
- A comparison returns `bool` (SL0564), and **the pairs come together**
  (SL0567): `==` with `!=`, `<` with `>`, `<=` with `>=`. A type that answers
  one and not the other is a trap, and the missing half fails at a call site
  far from the declaration that forgot it.
- An interface declares none. An operator is chosen from the operand types
  where it is written rather than dispatched, so there is nothing for a
  contract to promise.

**A declared `==` is asked first**, before the reference comparison a class
would otherwise get. That is the whole reason to declare one.

**A generic type may declare operators**, and each instantiation gets its own.
`Box<T>` with an `operator +` gives `Box<int>` and `Box<long>` a body each,
with `T` substituted -- the same monomorphization every other member of a
template goes through. Whether the body is *valid* is decided per
instantiation, as [§4.3](04-generics.md#43-what-a-constraint-does-and-does-not-do) says: `a.Value + b.Value` compiles at `int` and is an
error at some type with no `+`, reported against the use that asked for it.

### 7.4.1 `implicit` and `explicit operator`

```csharp
public struct Money {
    public long Cents;

    public static implicit operator Money(long cents) { return Of(cents); }
    public static explicit operator long(Money value) { return value.Cents; }
}

Money price = 250L;             // implicit: nothing was lost
long cents = (long)price;       // explicit: say that you meant it
```

A conversion is an operator whose name is a type. It is written inside one of
the two types it is between, `static` and `public`, taking the value and
returning what it becomes, and it lowers to an ordinary function -- `op_ToMoney`
-- that nothing can call by name.

**The word is the whole difference.** `implicit` says the conversion loses
nothing, so it runs wherever the target type is expected: an assignment, an
argument, a return, an operator's operand. `explicit` says something is lost or
assumed, so it runs only where a cast is written. That is the same distinction
the built-in conversions already make -- `int` to `long` is implicit and `long`
to `int` is a cast -- and declaring one puts a type into that system rather than
beside it.

**One conversion, and no chain.** The value has to be exactly what the operator
takes, with one exception: a literal adopts the source type the way it adopts
any other, so `Money m = 5;` works against an operator taking a `long`. A
`double` does not reach `Money` by way of `long`, and an `int` variable does not
either -- write the cast. C# composes a standard conversion with a user-defined
one at each end and arrives at rules nobody can hold in their head; the rule
here is meant to fit in a sentence.

**What is refused, and why** (all SL0615):

- **Neither side is the declaring type.** A conversion between two other types
  would give somebody else's types a meaning from a distance, and a reader
  would have nowhere to look for it. Same rule as an operator's operand
  ([§7.4](#74-operators)).
- **To or from an interface.** A cast to an interface asks the object what it
  is; a conversion would make a different object instead, and the same
  punctuation would mean two things.
- **A conversion the language already has.** A derived class already converts
  to its base, an array to a slice, an `int` to a `long`. A second answer to a
  question already answered is one a reader would have to know about to predict
  what a cast does.
- **A type to itself**, and the same pair declared twice (SL0211).

Two conversions from different types that both reach the same target are not a
conflict; two that could both carry *this* value to *that* type are, and the
call site says so (SL0616) rather than picking one.

**A conversion does not cross a library boundary**, on the same terms as an
operator: neither is in a module's metadata yet, so a consumer sees the type and
not what it converts to.

## 7.5 Indexers

```csharp
public class Grid {
    int[] cells;

    public int this[nuint at] {
        get { return cells[at]; }
        set { cells[at] = value; }
    }
}
```

A property that takes arguments, lowered to `get_Item(i)` and
`set_Item(i, value)` -- again C#'s spelling. `a[i] += 1` reads through the
getter and writes through the setter, on the same terms as any other property
([§7.3](#73-properties)).

**Overloaded on what it takes**, because `this[nuint]` and `this[String]` are
different questions:

```csharp
public String this[nuint at]     { get { ... } set { ... } }
public bool   this[String named] { get { ... } set { ... } }
```

**There is no automatic form.** `{ get; set; }` on a property makes the
compiler find storage; there is nothing to find here, since what an index
*means* is the whole of what an indexer is for. Both accessors are written, or
just the getter for a read-only one.

An indexer is inherited like any other member, and works on a struct -- where
the setter reaches its receiver by pointer, as every struct method does.

## 7.6 `static` members

A method written `static` belongs to the type rather than to a value of it.
The whole of the difference is the missing receiver:

```csharp
public class Small {
    int value;

    Small(int checked) { value = checked; }        // private

    public static Result<Small, ParseError> Parse(String text) {
        // ... check, then use the constructor nothing outside can reach
        return Ok(new Small(total));
    }

    public int Value() { return value; }
}

var small = try Small.Parse(text);
```

There is no `this`, so the body cannot read a field or call a method without
saying which object it means (SL0228, SL0576). A call names the type; naming a
value instead is refused, as is naming the type to reach an instance method
(SL0576). Each of those says which spelling was meant.

Everything else about it is an ordinary method. It overloads by parameters
alongside the instance methods of the same name -- though two members differing
only by `static` collide, since the receiver was never part of the signature.
It may be named without a call, `Type.Name`, and become a delegate. And it may
use a private constructor, which is what lets a fallible factory close off the
shape it replaces ([§2.9](02-types.md#29-how-the-library-reports-failure)) rather than merely discourage it.

This is also how a **struct** gets a maker at all: a struct has no
constructors, so before this there was no way to build one in a single
expression.

A static method cannot implement an interface method: dispatch arrives on an
object, and a static method has nowhere to put one.

**A field** is the same storage a module-level `static` is, named by the type
instead of the module ([§9.3](09-statements-expressions.md#93-const-and-static)). It may be mutable, and it needs an initializer:

```csharp
public class Registry {
    static int made = 0;                        // private to the type
    public static String Kind = "registry";
    public static readonly String Version = "1";
}
```

**A property** is two static methods wearing the spelling of a field, exactly as
an instance property is two ordinary ones. Both accessors are written: an
automatic one would need storage with no initializer to fill it, and a static
has no other moment at which to be given a first value (SL0584).

**A static constructor** is `static Name() { }` inside `class Name`. It runs
once, before `Main`, after every static field's initializer -- which is C#'s
order, and the only one that lets the block arrange the fields it is there for.

C# runs one *lazily*, before the type is first used, behind a guard checked on
every static access; that guard must become atomic the moment threads exist.
Stainless compiles the whole program at once, so it runs the block in the same
pass the field initializers run in. The cost is that "before first use" becomes
"before `Main`", which a program can only tell apart by timing its own startup;
what it buys is no guard, no per-access cost, and a compile error on a cycle.

**A static class** holds static members and has no instances:

```csharp
public static class Defaults {
    public static int Retries = 3;
    public static int Doubled() { return Retries * 2; }
}
```

`new Defaults()` is refused, and so is any member that would need an instance --
a field, a constructor, a destructor, an instance method or an instance property
(SL0583). A **module** is usually the better answer, and is what the standard
library uses: a module is a scope, so its members need no prefix inside it. What
a static class buys is a name that sits *inside* a module and is reached from
one.

What `static` may not be written on:

| | Refused because | |
|---|---|---|
| a module-level function | a module has no instance for a function to belong to | SL0573 |
| an interface member | an interface promises what an *object* can do | SL0574 |
| `virtual`, `override`, `abstract` | dispatch chooses a body from the object a call arrives on | SL0575 |
| `protected` | the word is about what a derived object reaches through itself | SL0575 |
| a struct, interface, enum, variant, union or delegate | only a class has instances for the word to deny | SL0578 |

---

<sub>[&larr; Attributes and reflection](06-attributes-reflection.md) &nbsp;&middot;&nbsp; [Interoperability and libraries &rarr;](08-interop-libraries.md)</sub>
