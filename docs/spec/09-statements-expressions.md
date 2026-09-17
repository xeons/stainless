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
```

Every one of those means what it means in C#, and the sections below are where
that is not the whole story. Four rules about the shape of the list itself are
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

Operators, by descending precedence: primary `a.b` `f(x)` `a[i]` `a[1:4]`
`x++ x--` · prefix `++x --x - ! ~ * &` and `(T)x` and `try` · `* / %` ·
`+ -` · `<< >>` · `< <= > >=` and `is` · `== !=` · `&` · `^` · `|` ·
`&&` · `||` · `?:` · assignment `= += -= *= /= %= &= |= ^= <<= >>=`.

That row is member access, a call, an index, a slice and the postfix steps, and
it binds tightest: `a.b.c` is `(a.b).c`, and `f(x)[i]` indexes what `f`
answered. It is also where the terms sit that look like operators and are not:
`new`, `typeof`, `sizeof`, `alignof`, `offsetof`, `nameof`, `iidof`,
`default(T)` and `checked(x)` each take a type or a parenthesised expression
rather than binding over a neighbour, so nothing can group around them wrongly.
A cast takes a unary operand, which is why `(T)a * b` is `((T)a) * b`.

`?.`, `??` and `??=` are left out of that list deliberately and are in
§9.7 below, where what they bind against is the whole of the question.

## 9.1 `switch`

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

**A switch over a variant names cases rather than values** ([§2.6](02-types.md#26-variant--a-value-that-is-one-of-several-things)). It is the one
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
for (nuint i = 0; i < values.Length; i++) {
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

### 9.1.1 Patterns

A `case` label is a pattern. Most of them are a constant, which is what makes a
switch a jump table; the rest ask something a constant cannot.

| | |
|---|---|
| a constant | `case 3:`, `case "text":`, `case Level.Low:` |
| a variant's case | `case Circle:`, `case Circle c:` |
| a type | `case Square:`, `case Square s:` |
| a range | `case > 100:`, `case <= 0:` |
| either | `case 1 or 2:`, `case > 0 and < 10:` |
| neither | `case not 0:` |
| anything | `case _:` |
| and a condition on any of them | `case Circle c when c.Radius > 10.0:` |

```csharp
switch (node) {
    case Leaf leaf when leaf.Value > 3: return "big leaf";
    case Leaf leaf:                     return "leaf";
    case Twig:                          return "twig";
    default:                            return "node";
}
```

**A pattern is a question, and every one of them becomes the `bool` that asks
it** — a comparison, a tag test, or the `is` the language already had. There is
no matching machinery underneath.

**A switch whose labels are all constants is unchanged**: one LLVM `switch`
instruction, and a jump table if LLVM decides on one. A single pattern anywhere
in it turns the whole switch into a chain of tests asked in order, because a
type, a range and a `when` are not values the governor could equal. Everything
else about the statement stays as it was — sections that may not fall through,
`break` that belongs to the switch, `continue` that passes through it.

**A name belongs to one label** (SL0619). A section reached by two of them has
proved nothing about which, so there would be nothing for the name to be; the
same rule refuses a name under `or`, `and` or `not`.

**A `when` runs after the pattern matched**, which is what makes it safe for the
guard to read what the pattern named: the two are joined by `&&`, which
short-circuits. A guarded label proves nothing about coverage, so a variant
switch that covers a case only under a `when` still needs the case or a
`default`.

### 9.1.2 `switch` as an expression

```csharp
String Describe(int n) {
    return n switch {
        < 0     => "negative",
        0       => "zero",
        1 or 2  => "small",
        _       => "large",
    };
}

double Area(Shape shape) {
    return shape switch {
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
they cover every case of a variant.

**The arms agree on a type**, the way a ternary's arms do: the first one decides
it and the rest convert to it.

**An arm nothing can reach is a warning** (SL0621), which is what an arm after
`_` is.

It lowers to the value held in a name and a conditional per arm — `t is P1 ? e1
: t is P2 ? e2 : e3` — so nothing written this way can do anything a chain of
ternaries could not, and the arm a test fails falls into the next conditional
rather than into a copy of the rest.

## 9.2 `parallel`, `spawn` and `for parallel`

```csharp
int left  = 0;
int right = 0;

parallel {
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
parallel {
    for (int i = 0; i < 8; i++) {
        squares[i] = spawn Square(i);
    }
}
```

`for parallel` splits a counted loop across the pool instead. The word sits on
the `for` rather than in front of it so that `parallel` means one thing wherever
it is written — open a fork-join scope — and the loop stays a loop with a
modifier on it:

```csharp
for parallel (nuint i = 0u; i < pixels.Length; i++) {
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
public sealed class Aes {
    public const nuint BlockSize = 16u;

    void AddRoundKey(byte[] block, nuint round) {
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
like any other slot, and what it holds at exit is simply never released. Either
way there is no teardown, which sidesteps C++'s static *destruction* order
problem as well.

A `--shared` library has no entry point to initialize statics from, so a static
in one is an error (SL0380) rather than a silently zeroed global — unless the
global can be born holding its value: `null`, `default(T)`, or a literal of a
type that is not counted, so `static int Counter = 0;` is allowed and a
`String` literal is not.

## 9.4 `foreach`

```csharp
foreach (int n in numbers) { total = total + n; }
foreach (var item in list) { Console.WriteLine(item.Name); }
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
threadsafe class Accumulator {
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

## 9.7 `?.` and `??`

```csharp
node?.Name ?? "none"        // the name, or that, if there is no node
node?.Save();               // called only if there is something to call it on
handler ??= Default();      // filled in only if it was empty
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

**A receiver that cannot be nothing is refused** (SL0604), for `?.`, `??` and
`??=` alike. `here?.Name` on a plain `Node` is a question with one answer, and
writing it suggests a doubt the type does not have.

**Each `?.` asks its own question.** `a?.b?.c` is two, and `a?.b.c` is an
error: the first answered with a `D?`, and a `.` does not reach through one.
That is the same rule everywhere else — a `C?` is narrowed before it is used —
rather than a chain that silently swallows the whole expression.

`??` binds looser than `||`, so `a ?? b || c` is `a ?? (b || c)`: the fallback
is the whole of what follows, which is what it looks like.

## 9.8 `default(T)`

```csharp
T FirstOrNothing<T>(T[:] items) {
    if (items.Length == 0u) { return default(T); }
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

## 9.9 `do`

```csharp
do { line = Read(); } while (line != null);
```

The body runs before the condition is first asked, which is the whole of the
difference from `while`. `continue` goes to the condition — it means "ask
again", not "start over".

## 9.10 `goto`

```csharp
for (int a = 0; a < n; a++) {
    for (int b = 0; b < n; b++) {
        if (Found(a, b)) { answer = a; goto done; }
    }
}
done:
```

C#'s, with one restriction: **a label goes at the top level of a function**
(SL0595). That is not taste, it is what makes the reference counting
decidable. A jump has to release whatever the scopes between it and the label
were holding, and a label inside a block would have a different answer for
every jump that could reach it. At the top level there is one answer: release
down to the function's own block. Every use a `goto` is actually for fits
there — out of nested loops, forward to a cleanup, back to a retry.

A jump forwards may skip a declaration, and the local it skipped is still
released at the end of the block it was in. That is safe because an owned slot
is cleared at function entry as well as where it is declared, so the release is
handed a null.

A jump names a label in its own function and nowhere else (SL0589); two labels
of a name is an error (SL0588); a label nothing jumps to is a warning (SL0591);
and a `goto` inside a `parallel` block is refused (SL0590), because every label
is outside one.

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
cast: `(byte)x`.

An integer literal converts implicitly to any integer type that can hold its
value, as in C#: `byte level = 200;` and `nuint size = 64;` need no cast, while
anything computed still does. A minus in front of one does not take that away:
`sbyte low = -100;` fits, `-128` fits an `sbyte` where `-129` does not, and
`byte b = -1;` is refused because nothing unsigned holds it. One that fits
nothing is refused too, under a code of its own (SL0266), because no cast makes
300 a `byte` and the value is what is wrong.

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

A shift count is reduced modulo the operand's width, which costs one `and` and
matches what a C# reader expects. Division is checked where the divisor is not
already known: a constant divisor is checked at compile time instead, and
`10 / 0` is an error rather than a program that runs.

```
error[SL0415]: division by zero
```

Overflow of `+`, `-` and `*` is **not** in that table: it wraps, as C# does
unchecked, and is defined rather than undefined.

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
line builds a `Result` and throws it away. If the author meant a method of
their own named `Fail`, it was never reached — and nothing else would have
said so, because the line is perfectly well typed.

---

<sub>[&larr; Interoperability and libraries](08-interop-libraries.md) &nbsp;&middot;&nbsp; [Conditional compilation &rarr;](10-conditional-compilation.md)</sub>
