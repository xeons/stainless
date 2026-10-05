<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 7. Functions and members

## 7.1 Functions

```csharp
public int Add(int a, int b) { return a + b; }

void NoReturn() { }
```

Top-level functions are permitted — a module is a scope, so there is no need
to wrap free functions in a static class the way C# requires.

**`=>` is a body of one expression**, the same form a property has
([§7.3](#73-properties)) and with the same meaning:

```csharp
public int Scaled(int by) => _side * by;    // returns the expression
public void Grow() => _side++;              // evaluates it, returns nothing
int Twice(int n) => n * 2;                  // a free function, equally
```

What the arrow does depends on the return type, and it is the same split a
property's accessors make: a function returning a value returns the expression,
and a `void` one evaluates it. That second half is what lets `Grow` above be
written at all — the arrow is not "a `return` spelled shorter", it is the body.

It is a body like any other, so it works wherever a braced one does: an
override, an interface implementation, a generic function, a recursive call. An
`extern "C"` declaration still may not have one (SL0105), because it is a
declaration of something defined elsewhere.

**Every member that has a body may be written this way**, and which half of the
split it takes follows from what it gives back:

```csharp
public Cube(int side) => base(side);                       // a constructor
static Registry() => Kind = "registry";                    // a type initializer
public static Money operator +(Money a, Money b) => Of(a.Cents + b.Cents);
public static explicit operator long(Money m) => m.Cents;  // a conversion
public int Side => _side;                                  // a property (§7.3)
```

A constructor and a type initializer return nothing, so their arrows evaluate;
an operator and a conversion are the value they produce, so theirs return.

**Overloading is by parameter type**, for methods as much as for free
functions. A return type alone does not distinguish two of them, because a call
does not always say what it wants back:

```csharp
class Printer
{
    public String Show(int n)    => "int";
    public String Show(String s) => "text";
    public String Show(double d) => "double";
}
```

Which one a call means is decided from the arguments, exactly as it is for a
module-level function: a call that fits none is SL0263 and one that fits
several equally is SL0264.

**Fitting several is not the same as fitting them equally.** When more than one
candidate fits, the one whose every argument converts at least as well as it
does for each of the others, and one of them better, is chosen, which is C#'s
rule. An identity is better than any conversion; of two targets, the one that
converts to the other and not back is better, so an `int` goes to `long` rather
than `double`; and of two integers where neither holds the other, the signed
one is better, so a `uint` goes to `long` rather than `ulong`. It is what lets
`Text.FromInteger` take a `byte`, a `uint` or a literal although its `long`,
`ulong` and `nuint` overloads all accept one. `Pair(int, long)` and
`Pair(long, int)` called with `(1, 2)` are each better for one argument, and
that is SL0264.

**An interface method may be overloaded too.** Each overload is a slot of its
own in the interface's table, numbered by declaration like every other member,
so the call picks an overload by the arguments exactly as above and dispatch
then reaches that slot. A class implements each overload with the method whose
parameters match it, wherever in its chain that method is declared.

A *class* implementing two interfaces whose methods share a name is a different
matter, and it works — see [§2.10](02-types.md#210-interface--a-contract-dispatched-dynamically).

### 7.1.1 `x.F(y)` is `F(x, y)`

```csharp
names.Where((n) => n.ByteLength() > 3u)
     .Select((n) => n.ToUpperAscii())
     .ToArray()
```

**A call written on a value reaches a free function when the value has no such
member.** The same functions either way — `Where(names, keep)` and
`names.Where(keep)` bind to one symbol — so a library of free functions is a
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

**It must be a constant** (SL0613) — a literal, `null`, a `const`, an enum
member or `default(T)`. Anything else would be code standing in a signature and
running at the caller, once per call site:

```
error[SL0613]: the default for 'n' is not a constant, and a default is written
into every call that leaves it out -- so a call would be running this rather
than passing it. A literal, 'null', a 'const', an enum member or 'default(T)'
is what it may be; anything else belongs in the body
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
(SL0264) as they always were — a default does not make one of them preferred.

**It crosses a library boundary as the value it folded to.** A default naming a
`const` of the library's own is a name the consumer cannot read, so the metadata
carries the number. A generated C header writes none of it: filling one in is
the caller's half, and a C caller has no declaration of this kind to read, so it
passes every argument.

### 7.1.3 `params`

```csharp
int Sum(params int[] values) { ... }
String Join(String separator, params ReadOnlySpan<String> parts) { ... }

Sum(1, 2, 3);                     // the elements, one by one
Sum();                            // none: an empty array
Sum(numbers);                     // an int[] is the array itself
Join(", ", "a", "b", "c");        // gathered into a slice
```

**The last parameter may take its elements one by one**, and the call gathers
them. Like a default ([§7.1.2](#712-a-parameter-with-a-default)) it is the
caller's half: the declaration says the parameter is an array, and a call that
gives elements instead is rewritten, where it stands, into one that passes
one.

**What the gathering costs depends on what is asked for.** A `params T[]` is a
new array per call, exactly as `[1, 2, 3]` would be, because the callee has
been promised an array and may keep it. A `params ReadOnlySpan<T>`, as in C#
13, or a `params Span<T>` gathers into an array in the caller's frame: no
allocation, and the elements are released when the statement ends. A
`params ReadOnlySpan<T>` is the one to write for a function that only reads
what it was given.

**A slice of the frame may not be kept.** The slice counts the array it views
([§2.12](02-types.md#212-spant-and-readonlyspant--part-of-an-array)), and nothing in a signature can
promise not to keep one, so the frame checks on the way out: when the statement
ends, a reference to its array that anything still holds stops the program with
a message, rather than leave something pointing into a frame that is gone. A
callee that stores or returns what it was given wants a `T[]`. A `spawn`ed call
is the one exception made silently — the worker outlives the statement by
design, so its elements go on the heap.

**The declared form wins where both fit**, as in C#: `Sum(numbers)` with an
`int[]` passes it rather than an array holding it, and between `F(int)` and
`F(params int[])` a call `F(1)` takes the first. Otherwise the ordinary rules
choose ([§7.1](#71-functions)), each gathered argument converting to the element
type.

**Names reach past it and not into it.** A name may give the parameters before
it, in any order, and the elements follow the positional arguments;
`values: numbers` passes the array whole. Arguments are evaluated as written
([§7.2.2](#722-named-arguments)), the gathered ones in their places.

**A generic's type argument is read off the elements**: `First<T>(params T[]
items)` called as `First("x", "y")` is `First<String>`. Given no elements there
is nothing to read, and the call is SL0327 unless the argument is written.

What may not be `params` (SL0763): a parameter that is not the last, one passed
by `ref`, `in` or `out`, one with a default, anything but a `T[]`, a `Span<T>`
or a `ReadOnlySpan<T>`,
a delegate's or closure's parameter — a call through one passes exactly what the
signature says — and a C function's, since C has nothing to gather with.

```
error[SL0763]: 'values' cannot be 'params': only the last parameter may be
'params'; the elements a call gives one by one are whatever is left after the
others, so nothing may follow them
```

It crosses a library boundary: the metadata says which parameter gathers, and
the consumer's call sites do the gathering.

### 7.1.4 Local functions

```csharp
int Main()
{
    int factor = 3;
    Console.WriteLine(Scale(5));            // 15: called before its declaration

    factor = 10;
    Console.WriteLine(Scale(5));            // 50: it reads factor as it is now
    return 0;

    int Scale(int x) => x * factor;
}
```

**A function may be declared in a block**, with everything a function may
have — a block or an arrow body, type parameters, defaults, `params`, `ref`
and `out`. It is named from anywhere in its block, before its declaration as
well as after, so two may call each other and one may call itself. Names are
not overloaded, as in C#, and one may not share a name with a variable in its
scope (SL0218).

**What it reads of the function around it is passed at every call.** A local,
a parameter, and the object of the method it is in each reach it as a
parameter no source wrote, filled in at the call from the variable as it then
stands. So the function sees what C#'s would — the current value, at each call
— and costs what a call with a few more arguments costs: nothing is allocated,
and one that reads nothing is an ordinary function, which becomes a `delegate`
like any other.

**It is capture by value, and so it may not assign what it captured**
(SL0769). Capture by value is the model every closure here has
([§2.15](02-types.md#215-lambdas-and-closures)); an assignment would change the
copy and nothing else, and saying so beats a write that silently goes nowhere.
A lambda's copy lasts as long as its closure, so writing it is legal there, and
a write nothing reads again is SL0829. Return the value, or keep it in a field.
The object of the method is the one thing reached by reference, as it is from a
method: `this` is passed, and a field written through it is written.

**A call has to be able to see what the function reads** (SL0768). One made
before a variable the function reads is declared has no value to pass —
C# reports the same call as reading an unassigned variable.

```
error[SL0768]: 'Late' reads 'y' from around it, which every call passes it, and
that 'y' is not in reach here -- it is declared later, or another variable has
its name. Call it where the variable is in scope
```

**Named without a call, it is a value.** One that reads nothing is a function
like a module-level one, and fits a `delegate` or a `closure`. One that reads
something becomes a closure that calls it, and what it reads is copied when the
closure is made — the rule for a lambda, because it is one; it cannot be a
`delegate` (SL0381). A generic one is a value only through a call that settles
its type arguments (SL0761).

**`static` promises it reads nothing** from around it — no variable, no object
— and each attempt is SL0767. It is the same promise a `static` lambda makes,
written where the function is.

**How the list of what it reads is worked out.** A call may be bound before the
function it calls — it is declared later, or calls back into its caller — and
each call has to pass what the callee reads. So the list is learned by binding
the bodies, and where a call was bound against a shorter list than the callee
ended up with, the function around them is bound again with what was learned.
The lists only grow, so that settles, and a program that declares its local
functions before using them is bound once. The one place this cannot happen is
an initializer outside any function, where a use before the declaration is
refused (SL0768).

**The symbol says where it was declared**: `Scale` above is linked as
`Main.Scale`, one inside a method as `Type.Method.Name`, one inside another as
`Main.Outer.Inner`, so a debugger and the IR name it the way the source does.
Its parameter list is its own and then what it captured, in that order.

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
void Bump(ref int n) { n++; }
double LengthSquared(in Point p) => p.X * p.X + p.Y * p.Y;

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
Passing one on as a `ref`, or one of its fields, is refused for the same reason
(SL0444), and so is calling a struct method that writes the struct it is called
on, or setting one of its properties (SL0809). A struct method is given its
receiver by pointer, so the call is a write exactly when the method's body is
one, directly or through another method it calls on `this`. A method that only
reads is called on the caller's storage with no copy. C# copies the receiver
instead and lets the method change the copy, which keeps the promise by losing
the write without a word; here the call is refused and says so. The same holds
for a `static readonly`, a `const` and an element of a `ReadOnlySpan<T>`.

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
bool TryHalve(int n, out int half)
{
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
promise. A `try` whose failure returns before the write is such a path, and so
is a `break` that leaves a loop or a switch early; what runs only sometimes —
the right of `&&` or `||`, an arm of a conditional — writes nothing certain,
and a loop's first test, which always runs, does. The same analysis holds a
local whose type has no zero value
([section 2.16.1](02-types.md#2161-locals)); any other local read before it is written
reads the zero it was declared holding. A function containing a `goto` stands
the check down, because a label can be arrived at from anywhere and the
question stops being answerable.

**The caller's storage is cleared before the call.** That is the safety net
under the analysis: a hole in it produces a zero rather than whatever the
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
question — *did it work*, *was it there* — and `Result<T, TError>` is for the answer
that comes with a reason. The library reaches for `Result` ([§2.8](02-types.md#28-resultt-terror--how-a-function-fails)) almost
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

**A call through a delegate or a closure** names the parameters its signature
does: with `closure int Pair(int a, int b)`, `pair(b: 1, a: 5)` passes 5 for
`a`.

**Arguments are evaluated in the order they were written**, as C#'s are, and
then passed in the order the parameters were declared. `Pair(b: Log("b"), a:
Log("a"))` logs `b` first. A struct argument is copied as it is evaluated, so
a later argument that changes the variable does not reach it. A default the
call left out is a constant and has no order to keep.

`base(...)` and `this(...)` take their arguments in order (SL0602): they name a
constructor rather than a declaration, so there is nothing for a name to match.

## 7.3 Properties

```csharp
public class Person
{
    public String Name { get; set; } = "";   // automatic: the compiler owns the storage
    public int Visits { get; private set; }  // read anywhere, write in this module
    public int Id { get; }                   // set by a constructor, then fixed

    public Person(int id) { Id = id; }

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
public class Thermostat
{
    int celsius;

    public int Fahrenheit
    {
        get { return celsius * 9 / 5 + 32; }
        set { celsius = (value - 32) * 5 / 9; }
    }

    public int Kelvin
    {
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
| `public int X { get; internal set; }` | public | this module only |
| `int X { get; set; }` | this module only | this module only |

There is no `private get`. The getter is what the word `public` on the property
means, so letting the two disagree would only make the declaration lie.

**A get-only automatic property is still storage.** `public int Id { get; }` may
be assigned in a constructor of the class that declares it, and nowhere else —
the rule C# arrived at, for the reason C# arrived at it. A *computed* get-only
property has nothing to assign to at all, and the error says so.

### 7.3.1 `init` — a setter for an object being made

```csharp
public class Account
{
    public int Id { get; init; }
    public String Handle { get => field; init => field = "@" + value; } = "";
}

var account = new Account { Id = 7, Handle = "ada" };
account.Id = 8;                          // SL0781
```

`init` is `set` with a narrower list of callers: an object initializer, a
`with` ([section 2.4.7](02-types.md#247-with--a-record-again-with-some-of-it-changed)),
and — on `this`, and nowhere else — a constructor or another `init` accessor of
the declaring class or a class deriving from it. After that the object is made
and the property reads as get-only. It lowers to the same `set_Name` method a
setter does, so it costs nothing, and the rule is checked where the write is
written. Either form of body works, and an automatic `init;` stores as `set;`
does.

An `init` property is part of a contract like a setter is: what implements an
interface's `{ get; init; }`, or overrides a virtual one, says `init` too, and
one declared `set` is implemented with `set` (SL0782) — otherwise a caller of
one would be allowed a write the other forbids. A static property has no object
that is being made, so it cannot be `init` (SL0780).

```
error[SL0781]: 'Account.Id' is 'init', so it is written while its object is
being made and not after: in an object initializer, a 'with', or on 'this' in a
constructor or 'init' accessor of 'Account' or a class deriving from it
```

### 7.3.2 `required` — set by whoever makes one

```csharp
public class Person
{
    public required String Name { get; init; }
    public required int Age;

    public Person() { }

    [SetsRequiredMembers]
    public Person(String name, int age) { Name = name; Age = age; }
}

var ada = new Person { Name = "ada", Age = 36 };
var bob = new Person("bob", 40);
var cy  = new Person { Name = "cy" };    // SL0784: 'Age' is not set
```

A field or a property marked `required` has to be given a value in the object
initializer of every `new` that makes one, and the error names every member a
construction left out. It is checked at the `new` and costs nothing at run time.
A derived class inherits its base's required members, and an override that
leaves the word off does not make one optional.

**`[SetsRequiredMembers]` on a constructor** says that it sets them all, so a
`new` that runs it names none. Like `[Packed]`, it is a rule about the language
rather than a library type, so it needs no import. `new()` written with its type
left off is a `new` like any other, and so is the collection a collection
expression makes. A type argument for a `new()` constraint is refused if its
constructor taking nothing would leave one unset, because `new T()` has no
initializer to name them in (SL0328).

Only an instance field or a property with a setter or `init` can be required;
and on a public type it has to be public, setter included, because every `new`
anywhere must be able to set it (SL0783).

### 7.3.3 `field` — the property's own storage

```csharp
public class Person
{
    public String Name { get; set => field = value.Trim(); } = "";
    public Node Badge { get => field ??= MakeBadge(); }
}
```

Inside an accessor, `field` is the storage the compiler made for that property,
which is what lets an accessor do work without a field written beside it. A
property whose accessors say it owns storage exactly as an automatic one does —
it is laid out, released by the destructor and reflected like any field — so an
automatic `get;` may sit beside a written `set` that says `field`. On a static
property, the storage is a static.

The storage is written by a constructor, an initializer or `required` like
any field whose type has no zero value
([§2.16.2](02-types.md#2162-fields)) — with one exception. **Storage its
accessors read only to fill, with `field ??= ...`, may start empty** whatever
the type says: nothing reads it before the `??=` has asked, so the null is
never seen. That is how `Badge` above fills itself on first use. A lambda
written in an accessor reaches `field` through the object, so it reads what is
there when it runs.

**`field` is contextual.** It means the storage only inside an accessor of a
property, and is an ordinary name everywhere else. `@field` is the ordinary name
inside one too, and `this.field` a member of that name. A variable declared
`field` inside an accessor is refused (SL0936): every later `field` would be
the storage, so the variable could never be read, and an accessor that meant
only to compute a value would quietly own storage.

**On an interface**

```csharp
public interface INamed
{
    String Name { get; }
    int Rank { get; set; }
}
```

Accessors with no bodies, exactly as an interface method with none is a
signature. A class implements it with a property of its own; whether that
property is automatic or written makes no difference to the caller. An
accessor with a body is a default, as a method's is
([§2.10.1](02-types.md#2101-a-default-body-and-a-member-named-for-its-interface)),
and has no storage to reach: an interface has no state.

**What a property is not**

- **Not a field.** `get_Name` and `set_Name` exist as symbols, and naming one
  directly is an error: they are the lowering, not the language.
- **Not two evaluations.** `p.X += 1` calls the getter and then the setter,
  and the receiver is evaluated once for both: `Make().X += 1` makes one object
  ([§9.14](09-statements-expressions.md#914-assignment)).
- **Initialized at the declaration only when it owns storage.** `public int X
  { get; set; } = 5;` gives that storage its first value, at the head of every
  constructor, exactly as a field initializer does ([§2.4.1](02-types.md#241-a-field-with-a-value)). A property that
  *computes* its value has no storage to give one to, and says so (SL0617).
- **Not indexed, by itself.** `this[i]` is an indexer, which is a property that takes arguments and has a section of its own ([§7.5](#75-indexers)).

## 7.4 Operators

```csharp
public struct Money
{
    public long Cents;

    public static Money Of(long cents)
    {
        Money made;
        made.Cents = cents;
        return made;
    }

    public static Money operator +(Money a, Money b) => Of(a.Cents + b.Cents);
    public static Money operator *(Money a, long by)  => Of(a.Cents * by);
    public static Money operator *(long by, Money a)  => Of(a.Cents * by);

    public static bool operator ==(Money a, Money b) => a.Cents == b.Cents;
    public static bool operator !=(Money a, Money b) => a.Cents != b.Cents;
}
```

C#'s shape: **inside the type it is for, `static`, with every operand written
out**. The last part is the one that earns itself — `3 * money` needs an
operator whose left operand is not the declaring type, and a method with an
implicit receiver could not express it.

An operator becomes an ordinary function named `op_Add`, `op_Equal` and so on,
which is the same lowering C# uses. Nothing can call that name: the type keeps
its operators apart from its methods, and an operator is reached by writing it.

**What may be overloaded**

| | |
|---|---|
| arithmetic | `+` `-` `*` `/` `%` |
| bitwise | `&` `\|` `^` `<<` `>>` `>>>` |
| comparison | `==` `!=` `<` `>` `<=` `>=` |
| unary | `-` `!` `~` |

**What may not, and why.** `&&` and `\|\|` short-circuit, and an overload would
have to evaluate both sides to be called at all — so overloading them would
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
- An interface declares one only as `static abstract`, which every implementing
  type must supply, or `static virtual`, whose body is what one that supplies
  none falls back on (SL0560). An operator is chosen from the operand types
  where it is written rather than dispatched, so one of the interface's own
  would be reached only by an operand typed as the interface; see
  [§4.3.1](04-generics.md#431-static-abstract--a-promise-about-the-type).

**A declared `==` is asked first**, before the reference comparison a class
would otherwise get. That is the whole reason to declare one.

**A generic type may declare operators**, and each instantiation gets its own.
`Box<T>` with an `operator +` gives `Box<int>` and `Box<long>` a body each,
with `T` substituted — the same monomorphization every other member of a
template goes through. Whether the body is *valid* is decided per
instantiation, as [§4.3](04-generics.md#43-what-a-constraint-does-and-does-not-do) says: `a.Value + b.Value` compiles at `int` and is an
error at some type with no `+`, reported against the use that asked for it.

### 7.4.1 `implicit` and `explicit operator`

```csharp
public struct Money
{
    public long Cents;

    public static implicit operator Money(long cents) => Of(cents);
    public static explicit operator long(Money value) => value.Cents;
}

Money price = 250L;             // implicit: nothing was lost
long cents = (long)price;       // explicit: say that you meant it
```

A conversion is an operator whose name is a type. It is written inside one of
the two types it is between, `static` and `public`, taking the value and
returning what it becomes, and it lowers to an ordinary function — `op_ToMoney`
— that nothing can call by name.

**The word is the whole difference.** `implicit` says the conversion loses
nothing, so it runs wherever the target type is expected: an assignment, an
argument, a return, an operator's operand. `explicit` says something is lost or
assumed, so it runs only where a cast is written. That is the same distinction
the built-in conversions already make — `int` to `long` is implicit and `long`
to `int` is a cast — and declaring one puts a type into that system rather than
beside it.

**One conversion, and no chain.** The value has to be exactly what the operator
takes, with one exception: a literal adopts the source type the way it adopts
any other, so `Money m = 5;` works against an operator taking a `long`. A
`double` does not reach `Money` by way of `long`, and an `int` variable does not
either — write the cast. C# composes a standard conversion with a user-defined
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

A property that takes arguments, lowered to `get_Item(i)` and
`set_Item(i, value)` — again C#'s spelling. `a[i] += 1` reads through the
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

**A read-only indexer is written with `=>`**, exactly as a property is
([§3.3](../style.md#33-one-line-members)):

```csharp
public int this[nuint at] => _cells[at];
```

**An indexer may take more than one index**, and is the only thing that does:

```csharp
public int this[nuint row, nuint column]
{
    get => _cells[row * _width + column];
    set => _cells[row * _width + column] = value;
}

grid[1u, 2u] += 1;
```

An array, a slice and a pointer take the one number they are laid out by, so a
second index on one of those is SL0241. What a pair means is a question only
the type can answer, which is why answering it is what declaring an indexer is.

An indexer is inherited like any other member, and works on a struct — where
the setter reaches its receiver by pointer, as every struct method does.

**A type with a count needs no indexer for `^` and `..`.** An integer `Count`
or `Length` and an indexer taking an integer make `x[^1]` mean
`x[x.Count - 1]`, and a `Slice(start, length)` as well makes `x[1..^1]` mean
what that method returns, as C# has it
([§9.17](09-statements-expressions.md#917--and-)). An indexer declared to take
a `Standard.Index` or a `Standard.Range` is asked first.

## 7.6 `static` members

A method written `static` belongs to the type rather than to a value of it.
The whole of the difference is the missing receiver:

```csharp
public class Small
{
    int value;

    Small(int checked) { value = checked; }        // private

    public static Result<Small, ParseError> Parse(String text)
    {
        // ... check, then use the constructor nothing outside can reach
        return Ok(new Small(total));
    }

    public int Value => value;
}

var small = try Small.Parse(text);
```

There is no `this`, so the body cannot read a field or call a method without
saying which object it means (SL0228, SL0576). A call names the type; naming a
value instead is refused, as is naming the type to reach an instance method
(SL0576). Each of those says which spelling was meant.

Everything else about it is an ordinary method. It overloads by parameters
alongside the instance methods of the same name — though two members differing
only by `static` collide, since the receiver was never part of the signature.
It may be named without a call, `Type.Name`, and become a delegate. And it may
use a private constructor, which is what lets a fallible factory close off the
shape it replaces ([§2.9](02-types.md#29-how-the-library-reports-failure)) rather than merely discourage it.

A **struct** takes one on the same terms: it has constructors of its own
([section 2.2.1](02-types.md#221-a-structs-constructor)), and a static method is how
one is made by something that can fail.

A static method cannot implement an instance method of an interface: dispatch
arrives on an object, and a static method has nowhere to put one. What it can
fill is a `static abstract` requirement
([section 4.3.1](04-generics.md#431-static-abstract--a-promise-about-the-type)).

**A `const`** belongs to the type in the same way and is not storage at all: it
is inlined at every use ([§9.3](09-statements-expressions.md#93-const-and-static)),
so it needs no initializer to be run.
`Aes.BlockSize` is reached by the type's name from outside and by its own name
from within.

**A field** is the same storage a module-level `static` is, named by the type
instead of the module ([§9.3](09-statements-expressions.md#93-const-and-static)). It may be mutable, and it needs an initializer:

```csharp
public class Registry
{
    static int made = 0;                        // private to the type
    public static String Kind = "registry";
    public static readonly String Version = "1";
}
```

**A property** is two static methods wearing the spelling of a field, exactly as
an instance property is two ordinary ones. An automatic one owns a static the
source cannot name:

```csharp
public static class Registry
{
    public static int Count { get; set; }                 // starts at zero
    public static String Label { get; set; } = "registry";
    public static int Fixed { get; }                      // set by the static constructor
}
```

With no `= value` the storage starts as its type's zero, which a global is born
holding, so it needs no code to run. With one, it is ordered with every other static's initializer, and an initializer
that reads the property is ordered after it. A get-only one is written by its
type's static constructor and nowhere else.

**A static constructor** is `static Name() { }` inside `class Name`. It runs
once, before `Main`, after its own type's field initializers — which is C#'s
order, and the only one that lets the block arrange the fields it is there for.
**A type is set up as a unit**: anything that reads one of its statics — an
initializer in another type, a module-level static, another type's static
constructor — runs after that type's initializers *and* its static
constructor, so it sees what the block arranged. The units are ordered by the
same dependency sort the initializers are, and two blocks that each read the
other's type are a cycle (SL0378). A static's initializer inside a type names
the type's other statics, constants and static methods bare, as its methods do.

C# runs one *lazily*, before the type is first used, behind a guard checked on
every static access; that guard must become atomic the moment threads exist.
Stainless compiles the whole program at once, so it runs the block in the same
pass the field initializers run in. The cost is that "before first use" becomes
"before `Main`", which a program can only tell apart by timing its own startup;
what it buys is no guard, no per-access cost, and a compile error on a cycle.

**A static class** holds static members and has no instances:

```csharp
public static class Defaults
{
    public static int Retries = 3;
    public static int Doubled() => Retries * 2;
}
```

`new Defaults()` is refused, and so is any member that would need an instance —
a field, a constructor, a destructor, an instance method or an instance property
(SL0583). A **module** is usually the better answer, and is what the standard
library uses: a module is a scope, so its members need no prefix inside it. What
a static class buys is a name that sits *inside* a module and is reached from
one.

What `static` may not be written on:

| | Refused because | |
|---|---|---|
| a module-level function | a module has no instance for a function to belong to | SL0573 |
| an interface member with no body, unless it is `static abstract` | a requirement says so ([§4.3.1](04-generics.md#431-static-abstract--a-promise-about-the-type)) | SL0574 |
| `virtual`, `override`, `abstract`, on a class | dispatch chooses a body from the object a call arrives on | SL0575 |
| `protected` | the word is about what a derived object reaches through itself | SL0575 |
| a struct, interface, enum, variant, union or delegate | only a class has instances for the word to deny | SL0578 |

---

<sub>[&larr; Attributes and reflection](06-attributes-reflection.md) &nbsp;&middot;&nbsp; [Interoperability and libraries &rarr;](08-interop-libraries.md)</sub>
