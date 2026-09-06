# Handoff

What the last runs built, what was learned that is not obvious from the code,
and what is worth doing next. Written to be read cold.

## State

```
dotnet build Stainless.slnx                     0 warnings
dotnet test tests/Stainless.UnitTests           561 pass
dotnet run --project tests/Stainless.Tests      222 cases, 1 skipped on Windows
```

Green on Windows and on Linux (`ssh brandon@geekom-a7`). That box is worth
using every time: it caught the missing `errors.txt` for SL0271 within a minute
of coming back up.

`master` is ahead of `origin/master`; nothing has been pushed.

## What was built, in order

| | |
|---|---|
| `efad37a` | static methods; the fallible factories moved onto their types |
| `9dc83fc` | `where T :` gains five kinds; `[Shared]` becomes `threadsafe` |
| `12c0f93` | the whole of C#'s `static`: fields, properties, cctors, static class |
| `58b5a9e` | an audit of the spec and README against the compiler |
| `d738588` | reflection writing; `Standard.Json` and `Standard.Xml` |
| `fe46084` | array element metadata, `OrderedDictionary`, `Option<T>`, and two more |
| `ae43b16` | the docs and this file brought back in line |
| *(this run)* | `is` with a binding; `Option` becomes `Optional` and grows readers |

## Findings worth keeping

**A variant's tag test already narrows, and the library had forgotten.**
`Standard.Json` was full of

```csharp
switch (value) { case Bool held: return held.Value; default: return fallback; }
```

when the language has had the short form all along, stated in §2.6. Every one
of those is now

```csharp
if (value.Bool) { return value.Value; }
```

in `Json.sl`, `Xml.sl` and `OrderedDictionary`. The spec was not at fault; the
library was. What §2.6 was missing is a *worked example* rather than the rule,
and it has one now — a rule stated in a paragraph and a rule shown in four
lines are not the same document.

**`is` with a binding closed the rest of it, and reached further than
expected.** A tag test cannot narrow a *field* or a *call result* (SL0285),
because either could be a different value by the time it is read. So:

```csharp
if (node.Payload is Circle c) { return c.Radius; }
```

evaluates the value once and names what came out of it. It works for a
variant's case; for a class, where the test proves the downcast; and — because
a test through a `C?` asks about the null and the class at once — for

```csharp
if (node.Next is Node n) { return n.Value; }
```

**That last one is the field narrowing TODO.md still lists as an open analysis
problem.** It is available now for any reference whose type can be named, which
is most of them. The analysis is still worth having for `!= null`, but the
irritation that motivated it is largely gone.

Three refusals, each with its own diagnostic: the form must be the *whole*
condition of an `if` (SL0585), a case that carries nothing has nothing to name
(SL0586), and an interface is not offered a name (SL0587 — a reference does not
convert down to one).

SL0585 is the interesting one. The value tested is spilled into a local
*before* the `if`, so under an `&&` or a `!` it would be evaluated when the
test would not have been. Restricting the form is what keeps that from being a
silent change in behaviour.

**The implementation is entirely in the binder, and that was the whole trick.**
`BindIf` opens a `PatternScope`; spills become statements in a block wrapped
around the `if`, and bindings become declarations at the top of the branch the
test proved. The payload read has to be inside that branch — reading a case's
payload where the tag says otherwise would reinterpret one type's bytes as
another's, and for a payload holding a reference it would retain a value that
was never there. **No emitter change at all.**

**A library gap and a compiler gap are hard to tell apart from the library
side.** `Optional.FlatMap` would not infer: `IFunc<T, Optional<R>>` puts R
inside a constructed type, and `InferFromLambdaResults` only read a result that
*was* a bare type parameter. Its own comment said as much and called it "the
honest outcome until something needs otherwise" — and then something did. The
fix was to unify structurally with `Infer` rather than assign, and to let
`AsWritten` substitute all the way down; both were already written for the
argument pass. Twenty lines, and it generalises to any functional interface
whose result mentions a parameter inside something else.

**`Standard` is where the shapes of work belong.** `IFunc`, `IPredicate`,
`IAction`, `IFold` and `IComparer` moved out of `Standard.Collections`, because
`Optional.Map` needed them and `Standard` cannot depend on a module that
depends on it. That is the right home anyway: they are what §2.15 says a lambda
may become, not anything a collection owns, and `Standard` needs no import.

**Check whether the library already has it.** `AppendChar` was added to
`StringBuilder` and then removed: `AppendCodePoint` had done exactly that,
in `Text.sl`, since long before. `AppendByte` was genuinely missing, because
appending one byte meant building a one-element array for `AppendBytes`. The
same lesson twice in one run — see the tag-test finding above.

**Two representations behind one syntax is the thing to avoid.** `T?` on a
value type was asked for and turned down in favour of `Optional<T>`, a variant.
`C?` is a null pointer and costs nothing; a tagged pair is a different thing,
and giving `?` both meanings would have touched the ABI classifier, layout,
narrowing and mangling across 37 sites. The variant got narrowing,
exhaustiveness and ARC from machinery that already existed — and now Java's
readers (`Get`, `ValueOr`, `Or`, `Map`, `FlatMap`, `Filter`, `IfPresent`) on
top of it, every one written in terms of `if (this is Some held)`.

`Or` takes a value rather than a supplier, unlike Java's. A lambda here
allocates a closure to save an evaluation, which is the wrong way round at the
sizes an optional is used at.

**`new()` means a class here, unlike C#.** There `new T()` on a value type is
default-initialization; here `new` allocates. A struct would have satisfied a
constraint whose only purpose it then failed.

**A serializer that cannot represent a field must leave it out.** Writing
`null` for an array and `{}` for a `List<T>` was silently wrong in a way a
reader would have believed. `Field.IsWalkable()` — an aggregate *and* carrying
`[Reflect]` — is what tells a reflected type from a `List`.

**Reading fills an object rather than making one.** A constructor is what makes
a type's invariants true, so `Json.Populate` takes an instance the program
made. There is no `Deserialize<T>(text)`: a type argument cannot be written at
a call, so a function whose only mention of `T` is its return type could never
be called. I wrote one anyway and the test found it.

**Three compiler bugs, all found by library work rather than by tests.**

- An unreachable tail returned `ZeroOf` of the return type, and a struct
  coerced into registers has a *literal* LLVM type — `{ i8, i64 }` — which
  starts with a brace rather than `%`, so it took the integer path and emitted
  `ret { i8, i64 } 0`. It needed a `Result<T, E>` small enough to coerce, under
  Itanium, which nothing had instantiated until `Result<JsonValue, JsonError>`.
- `KindOf` unwrapped an optional and `NestedTypeInfo` did not, so a `C?` field
  reported kind Class and named no type — which is what stopped any walk into
  one.
- `public` on a constructor was silently ignored (now SL0572).

**The audit found six stale claims and four broken examples**, including a
`FileStream` paragraph describing the latch its own example three lines above
had replaced, and a `parallel for` example that counted an `int` against an
`nuint` length. Compile the examples; do not read them. The harness is in
`scratchpad/audit/` if it is still there — it is 60 lines and worth rebuilding.

## Next, in the order I would do it

1. **`is` with a binding, widened to `&&`.** `if (x is Number n && n.Held > 0)`
   is refused today and is the first thing anyone will try. It needs the name
   in scope for the rest of the condition, so the payload read has to happen
   mid-expression rather than at the top of the branch: either a lowering of
   `&&` that can carry a store, or the binding declared outside with
   definite-assignment behind it. `while` wants the same thing for the same
   reason, and `else` for a negated test falls out of it.
2. **An `as` operator**, now much smaller than TODO.md describes. `is C c`
   covers the branching case; what is left is wanting the answer as a value —
   passing it on, storing it, or a chain where an `if` per step reads badly.
3. **A reachability pass from `Main`.** Every program compiles the whole
   library, and the suite went from 66s to 89s two runs ago purely because two
   modules were added that nothing imports. It is the most expensive missing
   thing.
4. **The +0/+1 dataflow pass.** Still the acknowledged performance item.
5. **`Standard.Collections` does not use the operators it could.** `Money` in
   the samples still calls `Money.Add`; `Standard.Time` has had this pass and
   is what the rest should look like.
6. **Method metadata in reflection**, which is what would let a deserializer
   fill a `List<T>` — the one shape `Standard.Json` still cannot represent.
7. Format specifiers in interpolation; the samples still cover about half the
   language.

## Things to know before touching the build

- **Heredocs mangle backslashes here.** A `\n` inside `bash <<'EOF'` arrives as
  a literal newline, which has broken C#, C and Python source repeatedly. Use
  the Write tool for anything with escapes. A `python << 'PY'` heredoc is safe
  when the delimiter is quoted *and* the body has no backticks.
- **This file uses em dashes.** A `python` patch script that matches on `--`
  will fail its own assertion; check which one is in the text before writing
  the pattern.
- `io.open(p, 'wb').write(io.open(p, 'rb').read())` truncates the file before
  reading it — Python evaluates the callee first. It emptied an `expected.txt`
  once.
- `-o /dev/null` does not work for a build on Windows; the linker wants a real
  path.
- **Windows reserves `COM1`–`COM9` even with an extension**, so a scratch file
  named `com2.sl` does not exist as far as any program is concerned. This costs
  twenty minutes if you do not know it.
- A documented `SL####` needs an `errors.txt` case pinning it, or
  `DiagnosticTests.EveryDocumentedCodeIsPinnedByACase` fails.
- A test that looks up a function by name fragment will match the standard
  library once it grows something of that name — `AbiTests` matched
  `Standard.Xml.Cursor.Take` instead of its own `Take`. Qualify with the
  module: `4Test4Take`.
- Adding a `stdlib/*.sl` file needs `dotnet build` before any program can
  import it; the library is an embedded resource picked up by a wildcard.
- **Two end-to-end runs at once corrupt each other.** The harness builds every
  case under one shared `%TEMP%/stainless-tests/` directory, so a second run
  overwrites the first run's object files mid-compile. It shows up as a
  scattering of unrelated failures — nine, once — that all pass when the
  suite is run alone. Do not background one and start another.
