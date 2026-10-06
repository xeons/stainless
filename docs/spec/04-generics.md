<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 4. Generics

```csharp
public class Box<T>
{
    T value;

    public Box(T initial) { value = initial; }

    public T Get() => value;
    public void Set(T next) { value = next; }
}

var number = new Box<int>(41);      // T is int
var text   = new Box<String>("hi"); // T is String
```

Functions may be generic too, and their type arguments are **inferred from the
arguments passed**, or written out at the call as in C#:

```csharp
T Pick<T>(T a, T b, bool first)
{
    if (first)
        return a;
    return b;
}

Pick(10, 20, false);            // T is int
Pick("left", "right", true);    // T is String
Pick<long>(10, 20, false);      // T is long, and both arguments widen to it
```

## 4.1 Monomorphization

Stainless **monomorphizes**: `Box<int>` and `Box<String>` are two real types,
compiled separately, with no boxing and no indirection. `Box<int>` stores a
bare `int`, and a `T` parameter of a value type is passed exactly as that value
type would be. This is the C++ and Rust model rather than Java's, and it is
what lets generics keep the performance promise the rest of the language makes.

The price is the usual one. A template is not checked until something
instantiates it, so a mistake inside a generic that nobody uses goes unreported,
and errors are reported against the instantiation. Each distinct instantiation
is separate code.

**Every member goes through this, not only the methods**: an operator, an
indexer, a property, a constructor, a destructor, a static and the
`static Name() { }` block are each built once per instantiation, with the type
arguments substituted in. So a `static int Made` on `Counted<T>` is *two*
counters once `Counted<int>` and `Counted<long>` both exist, and each
instantiation's setup block runs against its own — which is C#'s rule and falls
out of monomorphization rather than being decided separately.

**An instantiation is named in an expression too.** `Box<int>.Of(41)` calls a
static method of `Box<int>`, `Box<int>.Count` reads that instantiation's static,
and `Standard.Collections.List<int>` may be qualified by its module as a type
anywhere may. Each is the same `Box<int>` a declaration names; the statics of
`Box<int>` and `Box<long>` are two sets, as above.

## 4.2 Constraints

A `where` clause says what a type argument must be — most often, which
interfaces it must implement. It goes after the parameter list and after any
base list, as in C#:

```csharp
public interface IComparable<T>
{
    int CompareTo(T other);
}

T Largest<T>(T[] values) where T : IComparable<T>
{
    var best = values[0];
    for (nuint i = 1; i < values.Length; i++)
    {
        if (values[i].CompareTo(best) > 0)
            best = values[i];
    }
    return best;
}
```

`where T : IComparable<T>` is F-bounded — T must be comparable *to itself* —
which is how comparison avoids needing a downcast. A parameter may carry several
constraints, and a declaration several clauses:

```csharp
public class Ranked<T> where T : IComparable<T>, IDescribable { ... }

public class Table<TKey, TValue> where TKey : IComparable<TKey> where TValue : IDescribable { ... }
```

An interface is not the only thing that may follow the colon: a base class,
another type parameter, `class`, `struct`, `unmanaged`, `notnull`, `zeroable`,
`new()` and `threadsafe` may too, and
[§4.3](#43-what-a-constraint-does-and-does-not-do) lists what each demands.

`where` is a **contextual** keyword, as it is in C#: it is read as one only in
the two places a constraint clause may begin — after a type's base list, and
after a generic method's parameter list — and is an ordinary identifier
everywhere else. So `where` remains available as a parameter, a local, a field
or a property name, which matters because it is an ordinary English noun that
turns up in exactly those positions:

```csharp
String Describe<T>(T thing, String where) where T : IDescribable
{
    return thing.Describe() + "@" + where;
}
```

## 4.3 What a constraint does, and does not, do

A constraint is **verified against its argument where the generic is
instantiated**, and the error names the type, the parameter and the missing
interface:

```
error[SL0328]: 'Half' cannot be used as 'T' in 'Ranked' because it does not
implement 'IDescribable'; it implements 'IComparable<Half>'
```

It does **not** cause the template body to be checked once against the
constraint, the way Rust and Swift do. Because Stainless monomorphizes, bodies
are still checked per instantiation, so a template nobody uses is never checked
at all, and a mistake inside one is reported against the instantiation rather
than the declaration. An instantiation whose arguments fail a constraint is
reported at the use and its body is not checked for them, since it was not
written for them: `Array.Clear` on a `String[]` is one SL0328, not that and
every error its body would then have.

The reason is that definition-site checking is all or nothing. It would require
that an unconstrained `T` support *nothing* — no `+`, no `<`, no indexing — and
so it would need constraints on operators as well as on methods, which is a
larger design step than adding `where`. What `where` buys today is a precise
error at the use site and a signature that states its requirements.

**What may be written after the colon:**

| | Demands | |
|---|---|---|
| `ISomething` | implements that interface | |
| `SomeClass` | is that class, or derives from it | |
| `U` | another type parameter of the same template | |
| `class` | a reference type: counted, and may be null | |
| `struct` | a value type: copied where it is assigned, never null | |
| `new()` | a **class**, not abstract, with a public constructor taking no arguments — or with no constructor declared, which is given one ([§2.4.1](02-types.md#241-a-field-with-a-value)) | |
| `threadsafe` | a type that says more than one thread may hold it ([§9.5](09-statements-expressions.md#95-what-may-cross-a-thread-boundary)) | |
| `unmanaged` | a value type with no counted reference anywhere in it: a primitive, an enum, a pointer, a delegate, or a struct or tuple of those | |
| `notnull` | a type none of whose values is null: not a `C?`, a `T[]?`, a `Notify?`, a `weak C?`, a pointer or a delegate | |
| `zeroable` | a type that has a zero value, so a body may write `default(T)` and `new T[n]` ([§2.16](02-types.md#216-zero-values)) | |
| `default` | nothing; written on an `override`, see below | |

Several are separated by commas in one clause, and several clauses by repeating
`where`. The word saying what kind of type it is — `class`, `struct`,
`unmanaged`, `notnull` or `default` — comes first and `new()` last (SL0580):
the order carries no meaning, but a fixed one means every clause reads the same
way. A parameter is one kind, so two of those words contradict each other, and
`struct` and `unmanaged` each contradict `new()` and a base class (SL0581).
`unmanaged`, `notnull` and `zeroable` are contextual, as in C#: they are read
as constraints only where a constraint is, and a type of any of those names is
still named with arguments or a qualifier.

**`zeroable` is what `default(T)` needs.** A type with no zero value — a
`String`, a class, a struct holding either — fails it (SL0328), the code every
unmet constraint reports. `unmanaged` implies it, and `class` contradicts it
(SL0581): every reference that is not optional is never null. `default` would
read better and is taken; it is the override constraint below.

```
error[SL0328]: 'String' cannot be used as 'T' in 'ZeroOf' because 'T' is
constrained to 'zeroable', and 'String' has no zero value: a 'String' is never
null
```

**`unmanaged` is what makes bytes safe to move.** A value that passes it is
all of what it holds, so a template may copy it through a `byte*`, take
`sizeof(T)` of it, or hand it to C, and no count goes out of step:

```csharp
void CopyBytes<T>(T* to, T* from, nuint count) where T : unmanaged
{
    var target = (byte*)to;
    var source = (byte*)from;
    for (nuint i = 0; i < count * sizeof(T); i++)
        target[i] = source[i];
}
```

**A generic that takes any `T` may ask instead.**
`RuntimeHelpers.IsReferenceOrContainsReferences<T>()` is C#'s, and answers
false exactly where `unmanaged` would pass. Each instantiation is compiled
on its own, so the compiler answers the call as a constant where it is bound,
and an `if` whose condition is a constant emits only the arm it takes.
`Span<T>.CopyTo` is one body and two programs:

```csharp
if (!RuntimeHelpers.IsReferenceOrContainsReferences<T>())
{
    memmove(to, from, count * sizeof(T));   // Span<byte>: this and nothing else
}
else
{
    for (nuint i = 0; i < count; i++)       // Span<String>: this, counting each
        target[i] = source[i];
}
```

`Standard.DependencyInjection.ActivatorUtilities` is answered the same way,
with code rather than a constant: `CreateInstance<T>(provider)` becomes
`new T(...)` with an argument asked of the provider for each parameter of
`T`'s widest public constructor, which is how a container makes a class
without reflecting over its constructors
([section 5.19](05-standard-library.md#519-standarddependencyinjection)). A
diagnostic about the `T` is reported at the program's own call that
instantiated the library's generic, followed out of the library through each
instantiation's first caller.

`RuntimeHelpers.GetTypeName<T>()` is answered the same way, with `T`'s name
qualified by its module as a string constant -- `App.Worker`, or
`Standard.Collections.List<App.Point>` for an instantiation. It needs no
`[Reflect]`, so it names an interface, a struct or a primitive as readily as a
class; `typeof(T).Name` reads the same name at run time from the metadata
only a `[Reflect]` type has.

Both arms are still bound for every `T`, so each MUST be valid for any type.
A function that holds a label keeps both arms, since the one not taken could
still be jumped into.

**`notnull` is narrower than C#'s**, because nullability here is in the type
rather than an annotation beside it: a `String` is never null and a `String?`
may be, so the second is refused where C# would warn.

**`default` belongs on an override**, which takes its constraints from what it
overrides and so has no other way to say a parameter is unconstrained; anywhere
else it says what leaving the clause out already says (SL0792). C#'s `allows
ref struct` has no counterpart: there is no `ref struct` to allow.

**The clauses are checked where they are written**, whether or not anything
instantiates the template. A parameter has one clause (SL0788), names each
constraint once (SL0789) and at most one base class (SL0790); parameters may
not constrain each other in a circle (SL0791); and a constraint naming a struct,
an enum, a sealed class or anything else nothing could derive from is refused
there rather than at the first use (SL0329). What needs an argument to answer
still waits for one.

**`new()` means a class, unlike C#.** There, `new T()` on a value type is
default-initialization, so a struct satisfies the constraint. Here `new T()`
allocates, and a struct is made where it stands rather than on the heap, so a
struct would satisfy a constraint whose only purpose it then failed; one given
for such a parameter is SL0328.

**`threadsafe` is the one constraint that is stricter than the rule it names.**
Handing an unsynchronized object to a thread is a warning (SL0377), because the
word is an assertion no compiler can check. Written in a `where` clause it is an
error — there a library author has asked for it in their own signature, which is
a different thing from a compiler guessing.

### 4.3.1 `static abstract` — a promise about the type

An interface may say what a **type** has, not only what an object can do. A
`static abstract` member is one every implementing type must supply, as a
public static member of the same signature; a `static virtual` one may be
supplied, and a type that supplies none gets its body. C# 11 calls this
generic math, and the shape is the same:

```csharp
public interface IAdditive<TSelf> where TSelf : IAdditive<TSelf>
{
    static abstract TSelf Zero { get; }
    static abstract TSelf operator +(TSelf a, TSelf b);
    static virtual TSelf Twice(TSelf x) => x + x;
}

public struct Money : IAdditive<Money>
{
    public long Cents;
    public Money(long cents) => Cents = cents;
    public static Money Zero => new Money(0);
    public static Money operator +(Money a, Money b) => new Money(a.Cents + b.Cents);
}

T Sum<T>(T[] items) where T : IAdditive<T>
{
    T total = T.Zero;
    foreach (var item in items)
        total = total + item;
    return total;
}
```

**Monomorphization makes this free.** C# needs the runtime to find `T.Zero`
for whatever `T` a shared body is running for. Here there is no shared body:
`Sum<Money>` is bound with `T` replaced by `Money`, so `T.Zero` is
`Money.Zero`, a direct call, and `total + item` is `Money`'s operator,
resolved exactly as it would be written out. What the interface adds is the
promise, checked where `Money` says it implements `IAdditive<Money>` (SL0305),
and the default a `static virtual` member falls back on — found by `T.Twice`
when `Money` declares no `Twice` of its own.

**A struct may implement such an interface**, as it may any other
([§2.10](02-types.md#210-interface--a-contract-dispatched-dynamically)): a
static requirement is a promise about the type, and an instance one is met by
the struct's own member where a generic reaches it.

**Reached through a type parameter, not through the interface** (SL0797),
which is C#'s rule: `IAdditive<Money>.Zero` names a requirement, and the
interface is not one of the types that meets it. A plain `static` member with a
body is the interface's own function and is named through it,
`IAdditive<Money>.Describe()`. A static member with no body has to say it is a
requirement by being `abstract` (SL0574). An operator on an interface is
`static abstract` or `static virtual` (SL0645); one operand is the interface's
own type argument, since that is the implementing type.

**One place this is wider than C#.** A `static virtual` operator's body is
found for any operand whose type implements the interface and declares no
operator of that name — not only for an operand typed by a type parameter.
Binding sees a monomorphized body, where `T` is already `Money`, and so cannot
tell the two apart.

### 4.3.2 `in` and `out` — when one instantiation stands for another

A type parameter of an interface or a delegate may be written `out`, when a
value of it only ever comes out, or `in`, when one only ever goes in. That
lets two instantiations convert where their arguments do, as in C#:

```csharp
public interface ISource<out T> { T Next(); }
public interface ISink<in T> { void Put(T item); }

ISource<Dog> dogs = kennel;
ISource<Animal> animals = dogs;             // a source of dogs gives animals
ISink<Animal> anything = pound;
ISink<Dog> dogSink = anything;              // a sink for animals takes dogs
```

It composes through another variant type, the way C#'s does —
`ISource<ISource<Dog>>` is an `ISource<ISource<Animal>>` — and the standard
library uses it: `IEnumerable<out T>`, `IEnumerator<out T>`,
`IReadOnlyList<out T>`, `IComparable<in T>`, `IEquatable<in T>`, `Func<in T,
out TResult>`, `Action<in T>`, `Predicate<in T>` and `Comparison<in T>`. So a
`List<Dog>` is an `IEnumerable<Animal>`, and `Sort` takes a list of a class
that compares itself with any `Animal`.

**Only references vary**, as in C#. An argument that differs has to convert to
the other with no instruction at all — a class to its base or an interface it
implements, an interface to one it extends, a reference to its optional, or
one variant instantiation to another — because that is what lets one pointer
be both. `ISource<int>` is not an `ISource<long>`.

**Monomorphized, the two are different interfaces**, with different ids, and
an object implementing one has no table for the other. What makes the
conversion sound is that the program is whole: each class that implements
`ISource<Dog>` and could therefore be behind an `ISource<Animal>` is given a
table for `ISource<Animal>` as well, holding the same functions slot for slot —
which is correct, because the two slots differ only in which reference type
they name, and a reference is one pointer whatever it names. A generic method
of the interface gets the same instantiation on both. So a call through the
converted reference costs what any interface call costs, the conversion
itself costs nothing, and `x is ISource<Animal>` answers as C#'s does. A
delegate or a closure needs no table: the same function pointer, and receiver,
answer either type.

**A variant parameter appears only where its word lets it** (SL0801), C#'s
CS1961: an `out` one in a return, a getter, an extended interface, or an `out`
argument of another variant type; an `in` one in a parameter, a setter, or an
`in` argument, where the direction turns round. A `ref` or `out` parameter,
a property with both accessors, an array, a slice, a pointer and a tuple are
read and written both, so neither word may reach them. A static member is not
reached through a reference and is not checked. `in` and `out` may be written
only on an interface's or a delegate's parameters (SL0800); a class or struct
holds what it holds, and a function has nothing to convert.

### 4.3.3 A member's own `where`

A member of a generic type may constrain the **type's** parameters with a
clause of its own. It then exists only in the instantiations whose arguments
meet it:

```csharp
public struct Span<T>
{
    public void Clear() where T : zeroable { ... }
}

Span<int> numbers = ...;
numbers.Clear();                            // fine
Span<String> names = ...;
names.Clear();                              // error[SL0816]
```

```
error[SL0816]: 'Span<String>' has no 'Clear': 'String' cannot be used as 'T' in
'Clear' because 'T' is constrained to 'zeroable', and 'String' has no zero
value: a 'String' is never null
```

The member of an instantiation that fails is not bound, so its body is never
checked against arguments it was not written for, and naming it is the error —
at the call, where C# and Rust report it. Rust's `impl<T: Default>` and Swift's
conditional extension are the same idea; without it, `Span<String>` itself
would be refused for a method it never calls.

A dispatched member — virtual, abstract, an override, an interface's — is in
every instantiation's table, so it may not have one (SL0334), and neither may a
member of a type that is not generic (SL0331).

## 4.4 What is and is not supported

Supported: generic classes, generic interfaces (including implementing them,
as in `class Money : IComparable<Money>`), generic functions with inference,
generic delegates and closures ([§2.14.1](02-types.md#2141-closure--a-method-and-the-object-it-belongs-to)), constraints of every kind in [§4.3](#43-what-a-constraint-does-and-does-not-do),
generic types nested in one another (`List<Box<int>>`), and self-referential
templates such as `class Node<T> { Node<T>? next; }`.

**A generic name is declared once per number of type parameters**, as C#'s
are: `Func<TResult>`, `Func<T, TResult>` and `Func<T1, T2, TResult>` are three
declarations, and a non-generic `Action` sits beside `Action<T>`. The number
written at the use is which one is meant; two of one name and one arity are a
duplicate (SL0201), and a count that matches none is SL0323.

**Generic functions overload on the shape of their parameters.** Two templates
may share a name, and a call tries each one of the right arity, keeping those
that both infer and would accept the arguments. Two or more survivors are
ranked as any overloads are ([§7.1](07-functions-members.md#71-functions)): the one every
argument converts to at least as well, and one argument better, is the call,
and without one it is an ambiguity (SL0453). None is the inference error.
`Standard.Collections` has both `Sort<T>(Span<T>)` and `Sort<T>(IList<T>)`, and
`Sort(numbers)` and `Sort(list)` each reach the right one; it has `Trim` over a
`Span<T>` and over a `ReadOnlySpan<T>`, and a `Span<T>` reaches the first,
which keeps it writable.

**A lambda is ranked by what it returns**, as in C#. Its body is read with the
parameters each candidate would give it: a body whose result does not convert
to a delegate's is not that delegate, and between two that take the same
parameters, the one whose result is exactly the body's, or converts better
from it, wins. So `Sum(items, i => i.Count)` and `Sum(items, i => i.Price)`
reach the `int` and the `double` overload of `Sum`.

**An array literal's elements are a type to infer from.** `ToList([1, 2, 3])`
reads `T` as `int`, because the elements agree on one, as they would for
`var numbers = [1, 2, 3]`.

**Generic methods** are supported too, including inside a generic type, where
the enclosing type's arguments are already fixed and only the method's own are
inferred:

```csharp
public class Pair<A>
{
    A left;
    public Pair(A initial) { left = initial; }
    public A KeepLeft<B>(B other) => left;
}

var pair = new Pair<String>("outer");
pair.KeepLeft(7);           // A is String already; B is inferred as int
pair.KeepLeft<long>(7);     // or written, and 7 widens to it
```

### 4.4.1 Writing type arguments at a call

**A type argument list may be written on any call to a generic function or
method**: `Pick<int>(a, b)`, `Enumerable.Repeat<long>(0, 4u)`,
`Helper.Take<T>(x)`, `Box<int>.Echo<long>(9)`. Written, the arguments are the
type arguments and nothing is inferred, which is what makes a function whose
only mention of `T` is its return type callable at all:

```csharp
T Zero<T>() => default;

var none = Zero<int>();         // nothing passed could have said what T is
```

**Only a generic candidate is considered**, as in C#. `Plain<int>(1)` on a
function that is not generic, and a count that no template of that name takes,
are each SL0323. A function written with type arguments and not called —
`var f = Pick<int>;` — is SL0834: an instantiation is not a value of its own,
and a delegate names the overload it wants by its own signature.

**`<` after a name is read the way C# reads it.** In an expression `<` is also
less-than, so a type argument list is tried only after a name, and kept only
when everything up to the matching `>` parses as types *and* the token after
the `>` is one of `( ) ] } : ; , . ? == != | ^ && || & [`, or the end. That is
C#'s list for the same ambiguity, and it decides the classic cases the same
way:

| Written | Read as |
|---|---|
| `F<A, B>(7)` | a call to `F` with two type arguments |
| `F(G<A, B>(7))` | one argument: a generic call |
| `F(a < b, c > d)` | two arguments, each a comparison, since `d` follows the `>` |
| `a < b > c` | `(a < b) > c` |
| `F<List<int>>()` | nested type arguments; the `>>` is split in two |

The guess parses the types alone and is thrown away when it does not hold, so
it never re-reads anything past the `>`.

### 4.4.2 Inferring from a lambda

A parameter that appears only in a **lambda's** result is inferred, because a
lambda's body is something to read a type off:

```csharp
public List<R> Select<T, R>(ReadOnlySpan<T> items, Func<T, R> transform) { ... }

var spelled = Select(numbers, n => Text.FromInteger((long)n));   // R is String
```

The order is what makes it possible. `T` comes from `numbers`; that gives the
lambda its parameter type; that lets the body be bound; and the body says
what `R` is. Each step needs the one before it, so this happens after
ordinary inference rather than as part of it, and only for what is left over.
It repeats while it is still learning, so one lambda's result may settle
another's parameter.

The signature it reads may be a generic closure's — `closure R Func<T, R>(T)`
-- or a generic interface's single method. They differ only in where the
signature is written down.

A **function passed by name** is read the same way, off its declaration
instead of a body: in `Select(names, Upper)`, `T` is `String` from `names`, so
the `Upper` meant is the one taking a `String`, and what it returns is `R`.
Where the parameter types are not known yet, a name with exactly one function
of the right arity settles them too. An overloaded name that the known types
do not narrow to one says nothing, and the call is SL0327.

A **closure already held** — a `Func<int, String>` in a variable — is read off
its type, argument by argument, as an instantiated interface is.

A **block-bodied** lambda is read off its `return`s: `n => { return n * 2; }`
gives an `int`, and returns that differ widen to the one they all reach, as a
ternary's arms do ([§2.15](02-types.md#215-lambdas-and-closures)). A result
written in front of the parameters, `int (n) => ...`, is read without binding
anything.

A result that carries its parameter inside another type -- `Optional<R>
Func<T, R>(T)`, or `List<R>` -- is matched part by part, so a lambda producing
an `Optional<nuint>` says `R` is `nuint`. Returns that agree on no one type are
SL0327 rather than guessed at; writing the type arguments at the call settles
it.

### 4.4.3 A generic method that is dispatched

**An interface method may be generic, and so may a `virtual`, `abstract` or
`override` method of a class**:

```csharp
public interface IStore
{
    T Keep<T>(T value);
    String Describe<T>(T value) => "stored";    // a default, as any member may have
}

public abstract class Node
{
    public abstract R Accept<R>(IVisitor<R> visitor);
}
```

C# compiles one body for these and has the runtime make an instantiation when
a call first needs one. Here each instantiation is a function of its own, and a
table slot holds one function, so **each instantiation the program calls is a
slot of its own**: `store.Keep(1)` and `store.Keep("x")` are two slots of
`IStore`, and every class implementing `IStore` has its own `Keep` template
instantiated at `int` and at `String` to fill them. A virtual one is the same
over a class and everything derived from it, its slots numbered after every
slot the family's tables already had, so nothing written by hand moves.

That is sound because the program is whole. Every call is bound before
anything is emitted, so which instantiations are called through `IStore` is
known, and so is every class that could be behind the reference — including an
instantiation of a generic class that implements it, which is a class like any
other once something makes one. It is found by repeating until nothing new
turns up, since instantiating one class's template binds a body that may call
another instantiation. The cost is the usual cost of monomorphizing, paid per
implementing class: `Keep<int>` is compiled for every class implementing
`IStore`, whether or not one of them is ever behind a call to it.

A class implements a generic interface method with a public generic method of
the same name and the same numbers of type parameters and parameters
(SL0305); whether the types then agree is known per instantiation and
reported there, once (SL0307). An `override` names one of the same shape it
inherits (SL0499, SL0503), a concrete class answers every abstract one
(SL0504), and one that returns something else once instantiated is SL0502, as
a plain override is. `base.Accept<R>(v)` calls the replaced body, as `base.M()`
does.

**Two things this cannot do, and both are refused rather than approximated.**

- **An instantiation that makes a larger one of itself** — `Keep<T>` calling
  `Keep<List<T>>` through the interface — is a new function at every step.
  C# makes the next one when the call happens, if it ever does; a compiler that
  makes them all in advance has no last one, and a type argument nested more
  than 48 deep is SL0798. The same limit stops a plain generic function
  recursing the same way.
- **Another binary.** A library's slots are numbered without its consumer's
  instantiations, so a class with a generic virtual method is left out of a
  library's metadata (SL0419), as a class implementing an interface already is.

A `static abstract` or `static virtual` member may not be generic (SL0322): it
is met by a member of each implementing type, which is not a slot an
instantiation can fill.

## 4.5 A worked example

```csharp
public class List<T>
{
    Slot<T>[] items;                    // past `count`, empty
    nuint count;

    public List()
    {
        items = new Slot<T>[2u];
        count = 0;
    }

    public nuint Count => count;

    public void Add(T item)
    {
        if (count == items.Length)
        {
            var bigger = new Slot<T>[count * 2];
            for (nuint i = 0; i < count; i++)
                bigger[i] = items[i];
            items = bigger;
        }
        items[count] = item;
        count++;
    }

    public T At(nuint index) => items[index].Value;
}
```

`new T[2]` would be refused for a `List<String>`, whose elements have no zero
to start as ([§2.16](02-types.md#216-zero-values)). The storage past `count`
holds no items, so it is an array of `Slot<T>`, whose zero is empty
([section 2.16.3](02-types.md#2163-arrays)). For a `List<int>` a slot is an
`int` and costs nothing; for a `List<String>` it is a pointer, and reading one
nothing wrote stops the program rather than hand out a null.

---

<sub>[&larr; Text](03-text.md) &nbsp;&middot;&nbsp; [The standard library &rarr;](05-standard-library.md)</sub>
