<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 9. Statements and expressions

```csharp
int x = 10;             // explicitly typed local
var y = x + 1;          // inferred
const int Limit = 64;   // compile-time constant

if (y > 10) { ... } else { ... }
while (y > 0) { y--; }
do { y++; } while (y < 10);
for (int i = 0; i < 10; i++) { ... }
foreach (int n in numbers) { ... }
switch (y) { case 0: return 0; default: break; }
goto done;
return y;
asm (out rax = low, out rdx = high) { rdtsc }
```

Every one of those means what it means in C#, and the sections below are where
that is not the whole story. The last is not C#'s at all: it is instructions for
the target's assembler, with registers paired to values, and it is in
[§8.8](08-interop-libraries.md#88-inline-assembly) beside the rest of what
reaches below the language rather than here. Four rules about the shape of the list itself are
worth stating, because each is a question a reader asks exactly once:

**A body is a statement, not a block.** `if`, `else`, `while`, `for` and
`foreach` are each followed by one statement, and a block is one statement
among others — so braces are how several are written, not something the
grammar asks for.

```csharp
if (n == 0) n = 1; else n = 2;
while (n < 3) n++;
for (int i = 0; i < 2; i++) n += 10;
```

**So `else if` is not a construct.** It is `else` followed by an `if`, which is
why nothing here has a rule for it and why a chain may be as long as it likes.
The same reading answers the dangling `else`: one belongs to the nearest `if`
that has not got one already.

```csharp
if (n > 100) { n = 0; } else if (n > 20) { n += 5; } else { n = -1; }
```

**Each of `for`'s three parts may be left out**, and `for (;;)` is the loop
only `break` leaves. The initializer is a statement, so it may declare a
variable, and that variable's scope is the loop; the condition and the step are
expressions.

**A block is a scope, and a name may not be reused inside one.** Shadowing is
refused rather than allowed, whether the name being hidden belongs to an
enclosing block, to the function, or to a parameter:

```csharp
int n = 1;
{
    int n = 2;      // error[SL0218]: 'n' is already declared in this scope
}
```

That is C#'s rule rather than C's, and for C#'s reason: where two readings of a
name are possible, the likelier cause is a mistake rather than an intention,
and saying so costs one rename.

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
at the object header ([§2 of abi.md](../abi.md#2-object-header-class-instances)) — so the number is what to add to
the reference you are holding.

Operators, by descending precedence: primary `a.b` `a?.b` `f(x)` `F<T>(x)`
`a[i]` `a?[i]` `a[1:4]` `x++ x--` `x!` · prefix `++x --x - ! ~ * & ^` and `(T)x` and `try` ·
range `..` · `* / %` · `+ -` · `<< >> >>>` · `< <= > >=` and `is` · `== !=` ·
`&` · `^` · `|` · `&&` · `||` · `?:` · assignment
`= += -= *= /= %= &= |= ^= <<= >>= >>>=`.

That row is member access, a call, an index, a slice and the postfix steps, and
it binds tightest: `a.b.c` is `(a.b).c`, and `f(x)[i]` indexes what `f`
answered. It is also where the terms sit that look like operators and are not:
`new`, `typeof`, `sizeof`, `alignof`, `offsetof`, `nameof`, `iidof`,
`default(T)` and `checked(x)` each take a type or a parenthesised argument list
rather than binding over a neighbour, so nothing can group around them wrongly.
A bare `default` and a `new(...)` with no type are terms too, and take their
type from where they are going ([§9.8](#98-defaultt), [§9.16](#916-new-with-the-type-left-off)).
A cast takes a unary operand, which is why `(T)a * b` is `((T)a) * b`.

Carrying a file's bytes is not among them: that is `[Embed]`, an attribute on a
static ([§8.7](08-interop-libraries.md#87-embedding-a-file)), because what it
produces is a declaration's storage rather than the value of an expression.

`?.`, `??` and `??=` are left out of that list deliberately and are in
§9.7 below, where what they bind against is the whole of the question.

**`>>>` shifts zeros in** whatever the left operand's sign, where `>>` copies
the sign bit of a signed one; on an unsigned operand the two are the same.
Otherwise it is a shift like the others: the left operand promotes, the result
has its type, the count is taken modulo the width, and a type may overload it
([§7.4](07-functions-members.md#74-operators)). Closing three type argument
lists at once — `List<List<List<int>>>` — still closes them, because the parser
splits the token as it already split `>>`.

## 9.1 `switch`

```csharp
switch (level)
{
    case Level.Low:     return "low";
    case Level.Warning: return "warning";
    case Level.Severe:  return "severe";
    default:            return "fatal";
}
```

Where every label is a constant, the value may be an integer, a `char`, a
`bool`, an enum, a `String` or a variant; with patterns
([§9.1.1](#911-patterns)) it may be anything. For everything but a variant, a
constant label is a constant of that type and no two may name the same value. An enum, integer, char or bool switch becomes
one LLVM `switch` instruction, which decides for itself whether a jump table
beats a chain of comparisons. A `String` switch compares in order against the
runtime's string equality.

**A switch over a variant names cases rather than values** ([§2.6](02-types.md#26-variant--a-value-that-is-one-of-several-things)). It is the one
kind that must be exhaustive or have a `default`, and it is where a label may
bind what the case carries.

```csharp
switch (shape)
{
    case Circle c: return c.Radius;     // binds the payload
    case Rect:     return shape.Width;  // narrows the switched value
    case Empty:    return 0.0;
}                                       // no default: every case is covered
```

The tag is a byte, so this is an LLVM `switch` like an enum's.

**Sections do not fall through.** Each one has to end by leaving — `break`,
`return`, `continue` or a `goto` — and running off the end is an error
(SL0407) rather than a silent jump into the next section. Values that share a
body stack their labels:

```csharp
case 0:
case 2:
case 4:
    return "even";
```

A section that means to carry on into another says which, with `goto case`
and a constant one of that section's labels has, or `goto default`:

```csharp
switch (step)
{
    case Step.Fetch:  Fetch();  goto case Step.Decode;
    case Step.Decode: Decode(); goto default;
    default:          Finish(); break;
}
```

The constant converts to the switch's type as a label does, and names a
section of the innermost switch statement around the jump. There has to be one
(SL0802), and it has to have a section with that label, or a `default` (SL0803).
A switch of patterns is a place to land too, wherever a section has a plain
constant label with no `when`. A switch over a variant is not: its sections
are entered knowing which case the value holds, which is what makes a case's
fields readable there, and a jump into one would know nothing of the kind. The
jump releases what its own section declared, as `break` does.

**`break` belongs to the switch, `continue` passes through it.** A `continue`
written inside a switch inside a loop continues the loop, as in C#; a `break`
leaves the switch and not the loop. With no enclosing loop, `continue` in a
switch has nothing to continue and is rejected.

```csharp
for (nuint i = 0; i < values.Length; i++)
{
    switch (values[i])
    {
        case -1: continue;      // next iteration, skipping the rest of the body
        case 0:  break;         // out of the switch, into the rest of the body
        default: total = total + values[i]; break;
    }
    total = total + 100;
}
```

A `default` is optional except over a variant, where leaving a case out without
one is SL0436. Elsewhere a value that matches nothing falls past the whole
statement: a statement over an enum need not name every member, as in C#,
because the value need not be one of them. A statement whose labels cover every
value it could hold — both bools, every case of a variant — ends a function
the way one with a `default` does. Each section has its own scope, so two sections may declare the same local name — which C# does
not allow, having put the whole switch in one scope.

### 9.1.1 Patterns

A `case` label is a pattern, and so is what follows `is` and each arm of a
`switch` expression. Most labels are a constant, which is what makes a switch a
jump table; the rest ask something a constant cannot.

| | |
|---|---|
| a constant | `3`, `"text"`, `Level.Low`, `null` |
| a variant's case | `Circle`, `Circle c` |
| a type | `Square`, `Square s`, `List<int>` |
| a range | `> 100`, `<= 0` |
| either, both, neither | `1 or 2`, `> 0 and < 10`, `not null` |
| anything | `_`, `var x` |
| members | `{ Radius: > 1.0 }`, `{ Owner.Name: "ann" }`, `{ }` |
| positions | `(0, var y)`, `Point(0, _)`, `Circle(var r)`, `var (a, b)` |
| elements | `[]`, `[var first, ..]`, `[.., var last]`, `[1, .. var rest]` |
| grouped | `(Circle or Square)` |
| and a condition on any of them | `case Circle c when c.Radius > 10.0:` |

```csharp
switch (node)
{
    case Leaf leaf when leaf.Value > 3: return "big leaf";
    case Leaf leaf:                     return "leaf";
    case Twig:                          return "twig";
    default:                            return "node";
}
```

**Everything nests.** A member, a position and an element each take a pattern
of their own, so `{ Keeper: { Name: "ann" } owner }` and `(Circle(> 1.0), true)`
are single patterns. A type written in front is asked first, and a name after
the whole names what matched: `Circle { Radius: > 1.0 } big`.

**Members** are fields and properties, read by name. `Owner.Name: "a"` is
`Owner: { Name: "a" }`, which asks that the owner is there before it asks
anything of it; `{ }` alone asks only that. A member that is a method is
refused (SL0776) — a pattern reads, and a call belongs in a `when`.

**Positions** are a tuple's elements, a variant case's payload fields in the
order they were declared — `Circle(var r)`, `Ok(var value)` — or, for anything
else, what its `Deconstruct` hands back ([§9.14](#914-assignment)). There are
as many positions as the value has (SL0609), and a name written on one is
checked against the element it stands for (SL0776).

**Elements** are matched on an array, a slice, an inline array, or a type with
a `Count` or `Length` and an integer indexer, `List<T>` among them. The length
is read once and asked first; each element is then read by its index from
whichever end it was written against, so `[.., var last]` reads one element.
There is one `..` at most (SL0775). What `.. var rest` names is a slice of the
same array ([§2.12](02-types.md#212-spant-and-readonlyspant--part-of-an-array)), which shares its storage
rather than copying it, or, for a type, what its `Slice(start, length)` answers
— `a[1..]` asks the same thing ([§9.17](#917--and-)). Naming the run of
anything with neither is refused (SL0775). A `String` is not matched element
by element (SL0774): its positions are bytes, and a pattern of characters over
it would be a pattern of bytes that looked like something else.

**A type is asked only of a reference.** An object is asked what class it is
and a variant which case it holds; any other value is exactly what it was
declared to be, so the one type it matches is its own — `(int count, _)` over
an `(int, String)` names the first element — and any other is SL0438.

**A pattern is a question, and every one of them is asked by a `bool`** — a
comparison, a tag test, `is`, a member read, a length. There is no matching
machinery underneath. A value a pattern reads more than once is held in a name
while it is asked about, so a property's getter runs once however many
questions are asked of what it returned, and a part is read only after what it
is part of is known to be there.

**The labels are asked in order, and each question once.** A later label that
asks what an earlier one already asked of the same value — the same case of a
variant, the same constant, null — has its answer, and one asking for another
case of a variant already known to hold this one is not asked at all; a value
read from the one switched on is read once on any path. A run of questions of
one value against constants, or of one variant against its cases, is one LLVM
`switch` instruction. So a switch whose labels are all constants is a jump
table if LLVM decides on one, and a switch over a variant dispatches on its
tag before it asks anything else, whatever its labels go on to ask. Everything
else about the statement is the same with patterns as without — sections that
may not fall through, `break` that belongs to the switch, `continue` that
passes through it.

**A name belongs to one label** (SL0619). A section reached by two of them has
proved nothing about which, so there would be nothing for the name to be; the
same rule refuses a name under `or`, and a name under `not` in a label, which
is assigned only where the label did not match. After `is` a name under `not`
is fine: it is in scope where the test was false
([§2.4.4](02-types.md#244-is-as-and-casting-down)).

**A `when` runs after the pattern matched**, which is what makes it safe for the
guard to read what the pattern named: the two are joined by `&&`, which
short-circuits. A guarded label proves nothing about coverage, so a variant
switch that covers a case only under a `when` still needs the case or a
`default`.

**A label nothing can reach is a warning** (SL0621): one whose every value an
earlier unguarded label already matches, as `case (true, true):` after
`case (true, _):`.

### 9.1.2 `switch` as an expression

```csharp
String Describe(int n)
{
    return n switch
    {
        < 0     => "negative",
        0       => "zero",
        1 or 2  => "small",
        _       => "large",
    };
}

double Area(Shape shape)
{
    return shape switch
    {
        Circle c => 3.14159 * c.Radius * c.Radius,
        Rect r   => r.Width * r.Height,
        Empty    => 0.0,
    };                              // no `_`: every case is covered
}
```

The value goes first, the arms are separated by commas, and each one is an
expression rather than a statement — which is the whole difference between this
and the statement it is named after.

**It has to be exhaustive** (SL0620). A statement that matches nothing falls
past itself; an expression that matched nothing would have no value to be, and
there are no exceptions here to throw at the hole. So the arms end with `_`, or
between them they cover every value: both bools, every case of a variant, every
member of an enum, and the same again inside a tuple, a payload, a member or a
list of any length.

```csharp
String Pair(bool a, bool b) => (a, b) switch
{
    (true, true)  => "both",
    (true, false) => "the first",
    (false, _)    => "not the first",
};
```

Coverage is worked out from what each arm certainly matches, which is the
question Maranget's algorithm asks: is some value matched by this and by none
of those? What it does not follow — a range, a `when` — counts for nothing, so
`< 0`, `0` and `> 0` over an `int` still need a `_`, where C# tracks the ranges
and does not. The error names what is left out where that is a case, a member
or a bool.

**An enum is covered once every member is named**, which is where this parts
from the statement. The value of an enum need not be one of its members — a
cast can make any — and C# answers one with a `SwitchExpressionException`.
There is nothing to throw here, so the program ends, with a message naming the
enum, where such a value arrives; a switch that has a `_` never does. A
`[Flags]` enum is never covered this way, because its values are combinations
of its members.

**The arms agree on a type**, the way a ternary's arms do: the first one decides
it and the rest convert to it.

**An arm nothing can reach is a warning** (SL0621): an arm after `_`, or one
whose every value the arms before it already match.

It is asked the way a statement's labels are, each question once, and written
as conditionals: the value held in a name, and a ternary per question — so
nothing written this way can do anything a chain of ternaries could not. An
arm that two paths reach is chosen by its number rather than written twice.
Where the arms cover everything, the last one's test is not asked, because
whatever reaches it matches; it is still run, for the names it assigns.

## 9.2 `parallel`, `spawn` and `for parallel`

```csharp
int left  = 0;
int right = 0;

parallel
{
    left  = spawn Sum(values, 0, half);
    right = spawn Sum(values, half, count);
}                       // every spawned job has finished here

return left + right;
```

`parallel` opens a fork-join scope and its closing brace waits for everything
`spawn` queued inside. Nothing here is a handle and there is no `await`: the brace **is**
the synchronization, so a job writes its result into a local the parent still
owns. That is sound because the parent cannot leave the block before the join,
which is also why a job may borrow the frame it was spawned from rather than
copying everything it needs.

**`spawn` sits in front of the call, not in front of the statement**, because
the call is the part that forks. The assignment around it is the part that does
not: the worker performs the store, into a slot the parent allocated and still
owns, and no assignment expression is ever evaluated. Writing the word at the
call is also what keeps the destination visible as an ordinary assignment to an
ordinary local — which it has to be, since the local must be declared before the
block to outlive it.

That is the whole of where `spawn` may be written. It is not a general operator:
a spawned call has no value until the join, so `total = spawn Work() + 1` and
`int local = spawn Work();` are both SL0390. The two shapes are `spawn f(x);`
and `place = spawn f(x);`, and `place` may be any variable, field or element
that outlives the block.

A `spawn` may appear anywhere inside the block, including in a loop, and each
one gets its own copy of the arguments:

```csharp
parallel
{
    for (int i = 0; i < 8; i++)
    {
        squares[i] = spawn Square(i);
    }
}
```

`for parallel` splits a counted loop across the pool instead. The word sits on
the `for` rather than in front of it so that `parallel` means one thing wherever
it is written — open a fork-join scope — and the loop stays a loop with a
modifier on it:

```csharp
for parallel (nuint i = 0u; i < pixels.Length; i++)
{
    pixels[i] = Shade(pixels[i]);
}
```

The loop has to be counted — `i = start`, `i < limit` or `i <= limit`, and a
step of `i++` or `++i`, or `i += stride` or `i = i + stride` with a positive
literal stride — because the iteration space is divided before the body runs and
a general C-style `for` has no trip count.

Three rules are enforced, each for the same reason:

| Rejected | Because |
|---|---|
| `return`, `break` or `continue` out of a `parallel` block | it would skip the join and leave jobs running against a dead frame |
| `spawn f(new Buffer())` | arguments are borrowed, and a temporary dies at the end of the statement, before the job runs |
| assigning an outside variable in a `for parallel` body | every chunk would race on one slot; write through a captured array, or accumulate into an `AtomicLong` |

*What* may cross into a job is checked separately, by type, and is the rule in
[§9.5](#95-what-may-cross-a-thread-boundary): plain data, a `String`, a `threadsafe` class, or an array of plain data.
What is still unchecked is how long a borrowed thing lives — see
[concurrency.md](../concurrency.md) for the model being aimed at and which parts
of it the compiler enforces today.

## 9.3 `const` and `static`

A `const` is a compile-time value inlined at every use, so it holds what fits in
one: a number, a `bool`, a `char` or an enum member. Its initializer is a
literal, or a negated one — `const int GwlpUserData = -21;` — since a C header
is full of those.

**It may be written at module scope or inside a type**, and means the same
thing in both. Inside a type it is named `Type.Name` from outside and without
the prefix from within, and a derived class sees what its base declared:

```csharp
public sealed class Aes
{
    public const nuint BlockSize = 16u;

    void AddRoundKey(byte[] block, nuint round)
    {
        nuint at = round * BlockSize;           // no prefix inside the type
    }
}

nuint blocks = length / Aes.BlockSize;          // and the type's name outside
```

A constant is shared state a `--shared` library may always carry, and for the
reason a static often may not: it is inlined rather than stored, so there is
nothing to initialize and no entry point needed to do it
([§7.6](07-functions-members.md#76-static-members) is where `static` runs into
that). The one place it does not reach is an inline array's length, `T[N]`,
which is settled during layout — before any type has its members — so a length
there must still be a literal or a module-level `const`.

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
`const int Newline = '\n';` is fine.

```csharp
public static readonly int Base = 20;
public static readonly String Greeting = "hello";
public static readonly AtomicLong Hits = new AtomicLong(0);

static int Counter = 0;                         // mutable, as C#'s is
```

Storage initialized once before `Main`, at module scope or inside a type
([§7.6](07-functions-members.md#76-static-members)). `readonly` is not required and is worth writing anyway: it refuses a
later assignment, and it lets a reference be made **immortal** as it is stored,
so retain and release skip it for the rest of the program. A mutable one cannot
be immortal, because replacing what it holds has to release the old value.

**Every static needs an initializer.** It is written by that and nothing else —
the initializers run before `Main` and there is no later moment at which a first
value could arrive — so `static int Counter;` is an error (SL0376).

What a static holds is *warned* about rather than refused ([§9.5](#95-what-may-cross-a-thread-boundary)): it outlives
every thread, so a `List<int>` in one is reachable from all of them and the
warning points at `Mutex<T>`. That is a change from an earlier design in which a
static had to be `readonly` and of a shareable type. The rule it replaced was
Swift 6's and Rust 2024's; this is C#'s, and it is chosen for the reason those
two are worth having and this one is worth having anyway: whether sharing is a
race is a fact about what the program does with the value, and a program with
one thread has no race to have.

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

A `readonly` static's reference is made immortal as it is stored, so it is
never destroyed and never has its count touched again. A mutable one is counted
like any other slot, and **what it holds is released when the program ends** —
in the opposite order to the one they were given it in, which is the order in
which nothing is yet depended on. That is what makes "still allocated at exit"
an exact count of what leaked rather than one that counts every static.

C++ calls its version of that a fiasco for the same reason it calls the
initialization one a fiasco, and reverse order answers only half of it: it
covers what an *initializer* read, and a destructor reaching sideways to
another static finds a slot that has already been emptied. So the rule is
written down rather than inferred — **a destructor that runs at exit MUST NOT
read a mutable static.** A table that lives for the program is declared
`readonly` and is then never torn down at all; a register that something
reports back into is emptied by its owner, from a hook registered after the
statics were made and so run before their teardown.

A `--shared` library has no entry point to initialize statics from, so a static
in one is an error (SL0380) rather than a silently zeroed global — unless the
global can be born holding its value: `null`, `default(T)`, or a literal of a
type that is not counted, so `static int Counter = 0;` is allowed and a
`String` literal is not.

## 9.4 `foreach`

```csharp
foreach (int n in numbers)
    total = total + n;
foreach (var item in list)
    Console.WriteLine(item.Name);
```

An **array** iterates by index, with no allocation and no dispatch. Anything
else is asked for a `GetEnumerator()`, found **by name rather than by
interface**, so a type can be iterated without `Standard.Collections` appearing
anywhere in the program:

```csharp
class Countdown
{
    public CountdownCursor GetEnumerator() => new CountdownCursor(3);
}

class CountdownCursor
{
    public bool MoveNext() { ... }
    public int Current => ...;
}
```

`Current` is looked for as a property first and then as a method of that name,
which is what an enumerator written before properties existed looks like; both
lower to one call. `Standard.Collections` names the shape as `IEnumerable<T>` and
`IEnumerator<T>` so that a sequence can be passed around, and `List<T>`
implements both — but `foreach` does not require them.

The collection is evaluated once, and the loop variable is declared inside the
loop, so a managed element is released at the end of each iteration rather than
piling up until the loop ends. `break` and `continue` behave as in any other
loop; `continue` advances the enumerator.

`foreach (var (key, value) in pairs)` takes each element apart into the names
it declares, by the rules of
[§2.2.5](02-types.md#225-taking-a-tuple-apart): a tuple by its elements,
anything else by its `Deconstruct`.

## 9.5 What may cross a thread boundary

Checked wherever a value can reach a second thread: a `spawn` argument or
receiver, a `for parallel` capture, and a static.

| Allowed | Why it is safe |
|---|---|
| plain data — primitives, enums, pointers, delegates, and a `struct` of the same | there is no reference count to race over |
| `String` | immutable, and its bytes live inside the object |
| a type declared `threadsafe` | the author asserts it synchronizes itself |
| `T[]` where `T` is plain data | a job borrows it without retaining it |

Everything else **warns** (SL0377). Counting is not what the rule protects:
reference counts are atomic, so sharing an object no longer corrupts its count.
What nothing synchronizes is the object's *contents*, and two threads writing
one field is a race no counting scheme could have saved.

A `struct` is as safe as what is inside it, so one holding only primitives and
`String`s crosses quietly and one holding a `List<T>` is warned about.

`threadsafe` is a word on the declaration, and an **assertion, not a proof**:

```csharp
threadsafe class Accumulator
{
    AtomicLong total;
    public void Contribute(int amount) { total.Add(amount); }
}
```

Write it on a type whose state lives behind a lock or an atomic, and nowhere
else. `Mutex<T>`, `AtomicLong` and `AtomicBool` carry it; `Guard<T>` and
`TaskScope` do not, because both belong to one thread. It is the same bargain
Rust's `unsafe impl Sync` makes, and the only place in this design where a human
promise stands in for a check.

**Which is why its absence is a warning.** Whether a type is safe to share is a
fact about its body, and no compiler reads that off a declaration; a missing
word is only ever a missing assertion. Refusing on that leaves a programmer who
knows better with one move available — write the word untruthfully — and a lie
is worse than a warning in every direction: it is permanent, it is invisible at
the call site, and it covers the next mistake too.

The one place the same fact is an error is `where T : threadsafe` ([§4.3](04-generics.md#43-what-a-constraint-does-and-does-not-do)), and
the difference is who asked: a library author stating a requirement in their own
signature, rather than a compiler guessing at one.

The word goes on a class, a struct or an interface. A variant, a union, an enum
and a delegate are refused (SL0582): each is a value with no operations of its
own, so the word on one would promise nothing.

Two gaps remain, and both are about lifetimes rather than types: a `Guard` can
outlive the lock it proves, and a job could store an array it was only lent.
A third — `Mutex<T>` racing on the reference count of what it guarded — is
closed, because counts are atomic now ([§5.2](05-standard-library.md#52-standardthreading) and [§5 of the ABI notes](../abi.md#5-ownership-convention)). See
[concurrency.md](../concurrency.md) for the two that are left.

## 9.6 Stepping by one

```csharp
i++;                    // the value it had, then one more
++i;                    // one more, and that is the value
for (int i = 0; i < n; i++) { ... }
```

`++` and `--` are C#'s, in both positions, over anything that can be written
to: a local, a parameter, a field, a bit-field, an array element, a property
and a pointer. A pointer steps by an element as C's does; a float adds one.

**It is not `x = x + 1`**, and two things separate them. The postfix form's
value is the one from *before* the write, so `i++` and `++i` are different
expressions rather than two spellings of one. And the place is worked out
exactly once, so `cells[Next()]++` calls `Next` a single time.

An enum is refused (SL0594): it is a choice rather than a count, and stepping
one means stepping the integer behind it.

## 9.7 `?.`, `?[`, `??` and `!`

```csharp
node?.Name ?? "none"        // the name, or that, if there is no node
node?.Save();               // called only if there is something to call it on
list?[0]?.Name              // the first element's name, if there is a list
handler ??= Default();      // filled in only if it was empty
node!.Name                  // a Node? used as the Node it holds
```

**The receiver is read once.** `a?.b` asks whether `a` is there and then
reaches through it, which is two mentions of one value — so it is held in a
hidden local first. Without that, `Next()?.Name` would call `Next` twice and
ask about one object while reading another.

**Nothing has to be expressible.** A class has null and a value type does not
([§2.5](02-types.md#25-pointers-and-nullability)), so:

| | |
|---|---|
| `node?.Name` | a `String?`, null when there was no node |
| `node?.Next` | a `Node?`, the same |
| `node?.Weight` | an `int`, which has no null — SL0605 |
| `node?.Save()` | nothing either way, and a statement |

The third is why `??` and `?.` are bound together rather than separately: where
they meet they fold into one question with two answers, and `node?.Weight ?? 0`
is how a value-typed member is reached. Without the fallback there is nowhere
for "there was no node" to go, and the language says so rather than inventing a
zero that a caller cannot tell from a real one.

**A receiver that cannot be nothing is refused** (SL0604), for `?.`, `?[`,
`??` and `??=` alike. `here?.Name` on a plain `Node` is a question with one
answer, and writing it suggests a doubt the type does not have.

**`a?[i]` asks the same question before an element.** The receiver is a `C?`
whose class declares an indexer ([§7.5](07-functions-members.md#75-indexers)) — an array is never null, so there is
nothing to ask of one — and the element follows the table above: a reference
answers null, and a value needs `??`. `a?[i:j]` slices the same way.

**`?[` is read as C# reads it.** `c ? [1] : [2]` is a conditional with an array
literal in its arm, and `a?[i]` is an element: after `?[` the parser looks for
a `:` following the expression, and takes the conditional only if it finds one.
The true arm of an enclosing conditional that lost its `:` to that guess is
read again with every `?[` as an element, so `c ? a?[i] : b` means what it
says.

**Neither is written through** (SL0762), as in C#. `node?.Weight = 4` would be
a write that happens only sometimes, which is an `if`, and reads better as one.

**Each `?.` asks its own question.** `a?.b?.c` is two, and `a?.b.c` is an
error: the first answered with a `D?`, and a `.` does not reach through one.
That is the same rule everywhere else — a `C?` is narrowed before it is used —
rather than a chain that silently swallows the whole expression.

`??` binds looser than `||`, so `a ?? b || c` is `a ?? (b || c)`: the fallback
is the whole of what follows, which is what it looks like.

**`x!` takes a `C?` as the `C` it holds, and checks nothing.** It is the cast
`(C)x` ([§2.5](02-types.md#25-pointers-and-nullability)) with C#'s spelling, and like the cast it emits nothing: the
same pointer is used as a different type. It is for the place where the
program knows something a check cannot prove, such as a field another method
has just filled. A null that gets through is not trapped: reaching through it
is a read at address zero, which the platform ends the program for, and a `C`
that is null is a broken promise every later reader trusts. Where the program
does not know, `if (x != null)`, `is C c` or `??` is the question to ask
instead. On a `weak C?` it reads strongly first, and on anything that cannot be
null it changes nothing, so a generic body may write it for a `T` that is only
sometimes a `C?`.

It binds as a postfix operator, so `a!.b`, `a![i]` and `F()!` read as they
look, and it cannot be confused with prefix `!` or with `!=`: nothing that
follows a whole operand can begin a negation.

## 9.8 `default(T)`

```csharp
T FirstOrNothing<T>(ReadOnlySpan<T> items)
{
    if (items.Length == 0u)
        return default(T);
    return items[0u];
}
```

The value a type's storage holds before anything is put in it: zero for a
number, `false`, null for a reference or a pointer, and every field of a struct
the same way down. It exists for generic code, which cannot write a literal for
a type it does not know.

**It is not a new hole in the null discipline**, even for a class. A fresh
array is zeroed ([§2.11.1](02-types.md#2111-t--a-counted-array)), so `new C[1][0]` already handed back a null typed as
a `C`, and `Standard.Collections` kept exactly such an array around to blank a
vacated slot with. This is that, spelled.

`default(void)` is the one refusal (SL0603): `void` is the absence of a value,
so there is none of it to zero.

**A bare `default` takes its type from where it is going**, as in C#:

```csharp
int count = default;                        // a declared local
return default;                             // the function's return type
Save(default);                              // the parameter
void Draw(int width = default) { ... }      // a parameter's default
if (count == default) { ... }               // the other side of a comparison
var picked = ready ? default : 5;           // the other arm, so an int
long wide = (long)default;                  // a cast
```

It is `default(T)` for the `T` that place names, and costs exactly that. With
nothing to name one — `var x = default;`, `default.ToString()`,
`default == default` — it is SL0757. As an argument it fits any parameter, so
two overloads that differ only there are ambiguous, as in C#.

**`case default:` is refused** (SL0758). It is nearly always a `default:` label
written wrong, and as a constant it would match whatever the zero is.

## 9.9 `do`

```csharp
do { line = Read(); } while (line != null);
```

The body runs before the condition is first asked, which is the whole of the
difference from `while`. `continue` goes to the condition — it means "ask
again", not "start over".

## 9.10 `goto`

```csharp
for (int a = 0; a < n; a++)
{
    for (int b = 0; b < n; b++)
    {
        if (Found(a, b)) { answer = a; goto done; }
    }
}
done:
```

C#'s. **A jump may leave any number of blocks and may not enter one**
(SL0595): the label it names is in the block the jump is in, or in a block
around that one. A jump into a block would arrive past whatever the block
declared ahead of the label. The rule is also what keeps the reference
counting decidable: what a jump releases is every scope it is in that the
label is not, which is known for each jump where it is written, and is the
same release a `break` out of those scopes would make.

A jump forwards may skip a declaration, and a jump backwards may run one
again. So a function with a label keeps every owned local null or owning at
every point: the slot is cleared on entry to the function, cleared again as
it is released, and a declaration that runs a second time releases what the
first run left before it stores. The skipped local is released at the end of
its block as usual, and is handed a null. The cost is a store per release and
a release per declaration, and only in a function with a label.

A jump names a label in its own function and nowhere else (SL0589) — a lambda
and a local function have labels of their own; two labels of a name is an
error (SL0588), even in blocks that do not nest, where C# allows it, because
a name that means one place in the function reads more plainly; a label nothing jumps to is a
warning (SL0591); and a jump out of a `parallel` block or a `for parallel`
body is refused (SL0590), because the work queued there has to finish there.
A jump from one place to another inside the block is ordinary. `goto case`
and `goto default` are the switch's own jumps, in [§9.1](#91-switch).

**Reachability is C#'s**, without its constant folding beyond a literal
`true`. A function has to return on every path that reaches its end
(SL0217), and a jump, a `while (true)` or `for (;;)` with no `break`, and a
`do` whose body always leaves all count as not reaching it. A label is
reached when a jump that is itself reached names it.

## 9.11 `nameof`

```csharp
FindType(nameof(Button));
Console.WriteLine($"{nameof(Width)} = {Width}");
```

The last name written, as a `String`. What it buys over the literal is that the
name is bound, so renaming the member breaks the build rather than the run:
reflection here is reached by name, and `FindType("App.Buton")` has nothing to
say for itself. It takes a variable, parameter, field, property, method or type
(SL0592, SL0596), and answers with the last name in it — `nameof(button.Width)`
is `"Width"`.

## 9.12 `checked`

```csharp
int room = checked(a + b);       // aborts rather than wrapping
checked { ... }                  // everything inside, as a block
unchecked { ... }                // and back again
```

`+`, `-` and `*` on integers wrap, and that is defined rather than undefined
(see the table below). `checked` asks them to notice instead, and to abort the
way an out-of-range index does. It costs a test and a branch that is never
taken; LLVM has an intrinsic per operation that answers with the result and a
bit, so there is no wider type and no comparison.

Signedness is part of the question: 60000 + 5000 fits a `ushort` and does not
fit a `short`. A float has nothing to check — it goes to infinity rather than
wrapping.

`checked` covers what C#'s does:

- `+`, `-`, `*`, `++` and `--` on integers;
- unary `-` on a signed integer, whose one overflow is negating the minimum;
- an explicit numeric conversion, and the cast a compound assignment implies.
  An integer must keep its value — `(byte)300` aborts, and so does `(uint)-1`
  — and a float must truncate to a value the integer holds, so a NaN or
  1e19 to an `int` aborts.

A user-defined conversion or operator is a call, and `checked` does not reach
into it.

Both are **contextual keywords**, as `closure` is: a test in this repository
had a parameter named `checked` before this existed. So is `out`, which the
standard library uses as a local.

The conditional `a ? b : c` evaluates only the arm it selects, and groups to
the right, so `a ? b : c ? d : e` reads as `a ? b : (c ? d : e)`. Its arms must
meet at one type: the same type, a common numeric type, or one that the other
converts to implicitly.

Conditions must be `bool`; there is no implicit int-to-bool conversion.
There are no implicit narrowing conversions. Widening integer conversions and
`int` -> `float`/`double` are implicit, as in C#; everything else needs a
cast: `(byte)x`. The one place a cast is implied is a compound assignment,
where `b += 10` on a `byte` is `b = (byte)(b + 10)` ([§9.14](#914-assignment)).

An integer literal converts implicitly to any integer type that can hold its
value, as in C#: `byte level = 200;` and `nuint size = 64;` need no cast, while
anything computed still does. **A `const` answers here as well as a literal**,
because a constant is a value inlined at every use — `const int Limit = 64;`
makes `nuint size = Limit;` as plain as `nuint size = 64;`, which is C#'s rule
too. An enum member does not, since its type is the enum rather than a number. A minus in front of one does not take that away:
`sbyte low = -100;` fits, `-128` fits an `sbyte` where `-129` does not, and
`byte b = -1;` is refused because nothing unsigned holds it. One that fits
nothing is refused too, under a code of its own (SL0266), because no cast makes
300 a `byte` and the value is what is wrong.

**A conditional and a `switch` expression are the values they choose between**,
so a literal arm takes its width from where the whole expression is going:

```csharp
nuint chosen = flag ? 1 : 2;                 // both arms are nuint
byte narrow = flag ? 200 : 100;
nuint switched = which switch { 0 => 1, _ => 2 };
```

The choice has no value of its own for a conversion to act on — what reaches
the target is whichever arm ran — so the conversion is of the arms. It applies
only where every arm is written out as a number: an arm that is computed needs
the cast any other computed value needs, and an arm that fits nothing says so
where it is written, `flag ? 1 : -1` against a `nuint` reporting the `-1`.

**This is where the rule departs from C#.** There a conditional whose arms are
both `int` has a natural type of `int`, and the conversion is then attempted
from that `int` rather than from the constants — so `byte b = flag ? 200 : 100;`
is CS0266 in C# and is accepted here. The departure is deliberate: every value
the expression can produce is written in the source, so the compiler can see
that each one fits, and the alternative is a suffix or a cast that says nothing
a reader did not already know.

Left to itself a literal is the narrowest of `int`, `uint`, `long` and `ulong`
that holds it, again as in C#. That matters where it meets another operand
rather than a declaration: `0xFFFF0000` is a `uint`, so `flags & 0xFFFF0000` on
an `int` widens the whole operation to `long` and the mask means what a C
header means by it. A literal that fits an `int` is an `int`, so nothing about
the ordinary case moves.

An integer literal is also exact against a `float` or a `double`:
`double d = 5000000000;` is five thousand million, not the low thirty-two bits
of it.

A floating-point literal is a `double` unless it carries the `f` suffix, which
makes it a `float` — `float half = 0.5f;` — parsed as one rather than as a
rounded double. `float half = 0.5;` is refused, as in C#, with a hint to write
the suffix; silently rounding a double is what the rule exists to stop. A
`const float` may be initialized with either spelling, since the constant's
declared type says what it holds.

A string literal has type `String`; see section 3.

**The arithmetic C leaves undefined.** C compiles these to whatever falls out,
and an optimiser is entitled to assume they never happen — which is worse than
a wrong answer, because it can delete the code around them. Stainless defines
all three:

| Expression | C | Stainless |
|---|---|---|
| `1 << 40` on an `int` | undefined | `1 << (40 & 31)` = 256, as in C# |
| `x / 0` | undefined | aborts, the way an out-of-range index does |
| the most negative `int` `/ -1` | undefined | aborts; the result is not representable |
| `(int)1e19`, `(int)NaN` | undefined | saturates to the nearest end; NaN is 0 |

A shift count is reduced modulo the operand's width, which costs one `and` and
matches what a C# reader expects. Division is checked where the divisor is not
already known: a constant divisor is checked at compile time instead, and
`10 / 0` is an error rather than a program that runs.

```
error[SL0415]: division by zero
```

Overflow of `+`, `-` and `*` is **not** in that table: it wraps, as C# does
unchecked, and is defined rather than undefined.

A float to an integer saturates because that is what .NET does on x64, and a
C# program that relied on it should keep its answer; LLVM's own `fptosi` is
poison there, which is a number the optimiser chooses. On ARM64 the
conversion instruction saturates already; on x86-64 it costs two compares.

**Nesting stops at 500 levels** (SL0108) — expressions inside expressions,
blocks inside blocks, types inside types, and interpolated strings inside the
holes of interpolated strings, which count together with whatever encloses
them. The limit exists because parsing and
binding each recurse once per level, and a file deep enough would otherwise end
the compiler rather than be refused by it: a stack overflow cannot be caught,
so there is no diagnostic and nothing to say which file did it. It is a bound
on absurdity rather than a budget: the deepest nesting in this repository, the
standard library and its tests included, is under twenty, and the usual way to
meet the limit is generated source. Only the one message is reported, because
everything the unwind would say after it is a consequence of it.

## 9.13 An expression on its own

A statement may be an expression and nothing else — an *expression statement*
— and most expressions are a mistake in that position. `total + 1;` computes a number and drops it: it is
valid C, it compiles, and it does nothing at all. So an expression standing
alone has to be one that could have had an effect, and the rest are warned
about:

```
warning[SL0222]: this expression has no effect; its result is discarded
```

**What counts as an effect is a list, not a judgement**: an assignment — plain
or compound, to a variable or to a property — a call, a `++` or `--`, and
`new`. Two more are decided by what is inside them: a conditional is effective
when either arm is, and `a?.M()` for the same reason the call inside it is.

```csharp
Advance();                  // a call, and the result may be dropped
count++;
count = Next();
thing?.Method();            // effective: the call is
ready ? Start() : Stop();   // effective: both arms are calls

count + 1;                  // SL0222 -- computed and thrown away
count;                      // SL0222
```

**A call is effective whatever it answers.** The warning is not about ignoring
a return value — a function whose result is a status is meant to be usable for
its work alone — it is about an expression that had no other reason to be
written.

**The bug it actually catches** is a name that was meant to be a call on
something else, and a variant's case constructors are where that happens:

```csharp
Fail("could not read the file");    // SL0222
```

`Fail` is `Result`'s case constructor ([§2.8](02-types.md#28-resultt-terror--how-a-function-fails)), so that
line asks for a `Result` and throws it away. If the author meant a method of
their own named `Fail`, it was never reached — and nothing else would have
said so, because the line is perfectly well typed.

**A value that waits for a type is never made.** A case constructor, an array
literal, a lambda, a function's name and `null` each take their type from where
they are going, and a statement is going nowhere. So what they were built from
is evaluated, in order, for what it does, and nothing else is: `[Next(),
Next()];` calls `Next` twice and allocates no array, and `Fail(Next());` calls
it once and builds no `Result`.

## 9.14 Assignment

```csharp
a[i++] = i;             // the element i named before it stepped
a[i++] += 10;           // i steps once, and the element read is the one written
Next().Count += 1;      // Next is called once; getter and setter share its answer
b += 10;                // on a byte: b = (byte)(b + 10)
```

**The place comes first, then the value, then the store.** That is C#'s
order. The place's receiver and indices are evaluated left to right, then the
right-hand side, and only then is anything written — so `b[j] = j = 1` writes
the element `j` named before the value changed it, and `Get().F = Log()` calls
`Get` first. The same holds for a property and an indexer, whose setter is
called with a receiver and indices that were evaluated before the value was.

**A compound assignment names its place twice and evaluates it once.**
`x op= y` reads `x`, evaluates `y`, applies `op` and writes `x` back, and
whatever the place depends on — a receiver, an index, the object a property
belongs to — is held between the read and the write. So `a[Next()] += 1` calls
`Next` once and adds to the element it read, `Make().F += 1` makes one object,
and `p.X += 1` calls the getter and the setter on the same receiver. Where the
place is a variable, or its parts are plain loads and the value has no effect,
naming it twice is the same as naming it once and nothing is held; the
ordinary `total += n` costs what it always did.

**The object a store lands in is kept alive until the statement ends.** A value
that runs code may drop the last other reference to the object or array being
written: `_items[n] = Grow()`, where `Grow` replaces `_items`. C# writes the
object it had already reached and its collector keeps that object alive; here
the reference is retained for the length of the statement, so the write lands
in the replaced object exactly as it does in C#, and nothing is written into
freed memory. It costs a retain and a release, and is paid only where the value
runs code and the container is reached through something other than a local
or a parameter, which only the statement itself could change.

**On a narrow integer, `x op= y` casts back.** The operator works at `int`, so
`b + 10` on a `byte` is an `int`, and `b = b + 10` needs a cast. `b += 10`
does not: it means `b = (byte)(b + 10)`, which is C#'s rule, and applies when
`y` itself fits `x` or the operator is a shift. `b += 300` is still refused
(SL0265), because 300 is not a byte's worth whatever the cast does. The cast
wraps as every integer cast does, and inside `checked` it aborts instead, as
every numeric cast there does ([§9.12](#912-checked)).

**A field of a temporary struct cannot be written** (SL0399). A struct a call,
a property or an indexer answered is a copy that nothing will read again, so
`list[0].X = 5`, `shape.Origin.X = 7` and `Make().X = 3` would each change the
copy and throw it away. C# refuses the same three (CS1612 and CS0131). A
struct's property on such a copy is refused for the same reason, since its
setter writes through the receiver. An element of an array or a slice is
storage, and `points[1].X = 5` writes into the array.

`a ??= b` evaluates its place once as well: it asks whether the place is empty,
and only then evaluates `b` and stores it. On a property the getter is called
once and the setter only when the getter answered nothing.

**`(a, b) = (b, a)` stores after it has read everything.** Its targets are
evaluated left to right, then every value on the right, then the stores —
[§2.2.5](02-types.md#225-taking-a-tuple-apart) has the whole of it.

## 9.15 `@name`

```csharp
int @class = 3;
extern "C" int @default(int @int);      // C's `default`, taking `int`
```

An `@` in front of a word makes it a name, whatever the word is: a keyword, a
type's keyword, or a contextual word such as `get`, `when` or `checked`, which
written this way is never the word. It is C#'s rule and exists for the same
reason — a C library, a file format or a generated binding names something with
a word this language reserved — and `@name` and `name` are one name, so
`@count` and `count` are the same variable.

**The `@` is not part of the name.** A symbol, its mangled name, what `export`
writes and what `extern` looks for are all the bare word, so `@default` above
links against a C function called `default`. An `@` followed by anything but a
letter or `_` is not a name (SL0001).

---

## 9.16 `new(...)` with the type left off

```csharp
Point origin = new();                       // a declared local
private List<int> _seen = new() { 1, 2 };   // a field, with an initializer
Point Corner() => new(1, 1);                // a return
Plot(new(3, 4));                            // an argument
Point[] row = [new(1, 1), new(2, 2)];       // an element
Point either = ready ? new(5, 5) : origin;  // the other arm
```

**The type is the one the value is going to**, and everything after it is the
`new` that type would have had: its constructors, its initializer, a class
allocated and counted, a struct made where it stands. A `C?` makes a `C`. The
arguments are bound where they were written, before the type is known, so
nothing about them depends on where the value ends up.

**With nothing to take the type from it is SL0756**: `var p = new();`,
`new().X`, a statement of its own. A type `new` cannot make — an interface, an
abstract class, a variant — is refused as it would be written out (SL0244,
SL0514).

**In overload resolution it fits any parameter `new` could make**, which is a
little narrower than C#'s "any type": `Pick(new())` against `Pick(Point)` and
`Pick(int)` chooses `Point`, where C# calls the pair ambiguous. Two class
parameters are ambiguous in both. A generic parameter learns nothing from it,
so `Id(new())` is SL0327 until the type argument is written: `Id<Point>(new())`.

---

## 9.17 `^` and `..`

```csharp
int last = numbers[^1];                 // the last element
Span<int> inner = numbers[1..^1];          // all but the first and the last
Span<int> tail = numbers[^3..];            // the last three
Span<int> all = numbers[..];

Index at = ^2;                          // kept, as C#'s System.Index
Range middle = 1..^1;                   // and System.Range
Console.WriteLine(numbers[at] + numbers[middle].Length);
```

**`^n` counts back from the end**, so `^1` is the last element and `^0` is one
past it. **`a..b` is the half-open run between two positions**, either of
which may be left out or counted from the end. Both are C#'s, operators and
precedence alike: `^` is a prefix, and `..` binds tighter than any binary
operator, so `0..n - 1` is `(0..n) - 1` and a range to `n - 1` is written
`0..(n - 1)`.

**Used at once, they cost nothing a written index would not.** On an array, a
slice or an inline array, `a[^n]` subtracts from the length the bounds check
already loads, and the check that follows refuses `^0` and anything past the
start by the same unsigned compare as any other index — reporting the `^n`
that was written. `a[i..j]` is exactly the slice `a[i:j]` is
([§2.12](02-types.md#212-spant-and-readonlyspant--part-of-an-array)): a view that shares the array,
bounds-checked the same way. Stainless's own `a[i:j]` stays, and takes `^` in
either place too: `a[1:^1]`. On an inline array a constant `^n` is folded, so
one outside it is SL0490 at compile time.

**Kept, each is a value**: `^n` is a `Standard.Index` and `a..b` a
`Standard.Range`, small structs in the module every program already has. An
`Index` used later is taken apart where it is used, so `a[at]` is one load and
a select more than `a[^2]`. An integer converts to an `Index` implicitly, as in
C#. **The count is a `nuint`** where C# has `int`, because every length here
is one; `^n` takes any integer and converts it as an index would, so a negative
one names no position and fails the bounds check.

**Any other type takes them as C# has it take them.** A type with an integer
`Count` or `Length` and an indexer taking an integer answers `x[^1]` as
`x[x.Count - 1]`, and one with a `Slice(start, length)` as well answers
`x[1..^1]` with what that method returns — for `List<T>`, a new list. The
receiver is evaluated once, and a write through `x[^1]` still reaches the
setter. An indexer declared to take an `Index` or a `Range` is asked first.

**What is refused.** Counting from the end of something with no length — a
pointer, a class with no `Count` — is SL0777; an `Index` on a type with a count
and no integer indexer is SL0241; a range over an inline array, or over a type
with no `Slice`, is SL0452, because a slice holds a counted array and an inline
array is not one; and `^` or `..` over anything but an integer is SL0242.

**A `String` is not indexed**, by `^` or otherwise, because its positions are
bytes ([§3](03-text.md)). `Substring` is how part of one is taken.

---

<sub>[&larr; Interoperability and libraries](08-interop-libraries.md) &nbsp;&middot;&nbsp; [Conditional compilation &rarr;](10-conditional-compilation.md)</sub>
