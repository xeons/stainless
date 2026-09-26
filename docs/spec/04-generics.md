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
another type parameter, `class`, `struct`, `new()` and `threadsafe` may too, and
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

Several are separated by commas in one clause, and several clauses by repeating
`where`. `class` or `struct` comes first and `new()` last (SL0580) — the order
carries no meaning, but a fixed one means every clause reads the same way.
A parameter is a reference type or a value type, not both, and `struct`
contradicts `new()` (SL0581).

**`new()` means a class, unlike C#.** There, `new T()` on a value type is
default-initialization, so a struct satisfies the constraint. Here `new`
allocates and a struct is declared where it is used (SL0244), so a struct would
satisfy a constraint whose only purpose it then failed.

**`threadsafe` is the one constraint that is stricter than the rule it names.**
Handing an unsynchronized object to a thread is a warning (SL0377), because the
word is an assertion no compiler can check. Written in a `where` clause it is an
error — there a library author has asked for it in their own signature, which is
a different thing from a compiler guessing.

## 4.4 What is and is not supported

Supported: generic classes, generic interfaces (including implementing them,
as in `class Money : IComparable<Money>`), generic functions with inference,
generic delegates and closures ([§2.14.1](02-types.md#2141-closure--a-method-and-the-object-it-belongs-to)), constraints of every kind in [§4.3](#43-what-a-constraint-does-and-does-not-do),
generic types nested in one another (`List<Box<int>>`), and self-referential
templates such as `class Node<T> { Node<T>? next; }`.

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
method**: `Pick<int>(a, b)`, `list.ConvertAll<String>(f)`,
`Helper.Take<T>(x)`, `Box<int>.Echo<long>(9)`. Written, the arguments are the
type arguments and nothing is inferred, which is what makes a function whose
only mention of `T` is its return type callable at all:

```csharp
T Zero<T>() => default;

var none = Zero<int>();         // nothing passed could have said what T is
```

**Only a generic candidate is considered**, as in C#. `Plain<int>(1)` on a
function that is not generic is SL0759, and a count that no template of that
name takes is SL0760. A function written with type arguments and not called —
`var f = Pick<int>;` — is SL0761: an instantiation is not a value of its own,
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
public List<R> Select<T, R>(T[:] items, Func<T, R> transform) { ... }

var spelled = Select(numbers, n => Text.FromInteger((long)n));   // R is String
```

The order is what makes it possible. `T` comes from `numbers`; that gives the
lambda its parameter type; that lets the body be bound; and the body says
what `R` is. Each step needs the one before it, so this happens after
ordinary inference rather than as part of it, and only for what is left over.
It repeats while it is still learning, so one lambda's result may settle
another's parameter.

The signature it reads may be a generic closure's — `closure R Func<T, R>(T)`
— or a generic interface's single method, which is where this started. They
differ only in where the signature is written down.

A **function passed by name** is read the same way, off its declaration
instead of a body: in `Select(names, Upper)`, `T` is `String` from `names`, so
the `Upper` meant is the one taking a `String`, and what it returns is `R`.
Where the parameter types are not known yet, a name with exactly one function
of the right arity settles them too. An overloaded name that the known types
do not narrow to one says nothing, and the call is SL0327.

A **block-bodied** lambda is read off its `return`s: `n => { return n * 2; }`
gives an `int`, and returns that differ widen to the one they all reach, as a
ternary's arms do ([§2.15](02-types.md#215-lambdas-and-closures)). A result
written in front of the parameters, `int (n) => ...`, is read without binding
anything.

Two limits, both reported as SL0327 rather than guessed at: returns that agree
on no one type, and a signature that does not mention its type parameters
plainly — `R Func<T, R>(T)` is read, `List<R> Func<T, R>(T)` is left alone.
Writing the type arguments at the call settles either.

### 4.4.3 Not yet

**An interface method cannot be generic.** Dispatch gives a method one vtable
slot, and a generic method has a body per instantiation.

## 4.5 A worked example

```csharp
public class List<T>
{
    T[] items;
    nuint count;

    public List()
    {
        items = new T[2];
        count = 0;
    }

    public nuint Count => count;

    public void Add(T item)
    {
        if (count == items.Length)
        {
            var bigger = new T[count * 2];
            for (nuint i = 0; i < count; i++)
                bigger[i] = items[i];
            items = bigger;
        }
        items[count] = item;
        count++;
    }

    public T At(nuint index) => items[index];
}
```

---

<sub>[&larr; Text](03-text.md) &nbsp;&middot;&nbsp; [The standard library &rarr;](05-standard-library.md)</sub>
