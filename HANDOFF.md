# Handoff

What the last two runs built, what was learned that is not obvious from the
code, and what is worth doing next. Written to be read cold.

## State

```
dotnet build Stainless.slnx                     0 warnings
dotnet test tests/Stainless.UnitTests           561 pass
dotnet run --project tests/Stainless.Tests      220 cases, 1 skipped on Windows
```

Green on Windows and on Linux (`ssh brandon@geekom-a7`), including the
reflection metadata layout change in `fe46084` against SysV. That box is worth
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

## Findings worth keeping

**A variant's tag test already narrows, and the library forgot.** `Standard.Json`
is full of

```csharp
switch (value) { case Bool held: return held.Value; default: return fallback; }
```

when the language has had the short form all along, documented in §2.6:

```csharp
if (value.Bool) { return value.Value; }
```

It works with a shared field name across cases, and negated (`if (!value.Text)`)
for a guard clause. The `*Or` helpers in `Standard.Json` should be rewritten
this way — it is four lines instead of six and reads better. **The spec is not
at fault here; the library is.**

What the short form cannot do is narrow a *field* or a *call result* (SL0285),
because either could be a different value by the time it is read. `is` with a
binding — `if (node.Payload is Number n)` — would close that, and `is` does not
reach a variant case at all today. That is the one genuine syntax gap.

**Check whether the library already has it.** `AppendChar` was added to
`StringBuilder` and then removed: `AppendCodePoint` had done exactly that,
in `Text.sl`, since long before. `AppendByte` was genuinely missing, because
appending one byte meant building a one-element array for `AppendBytes`. The
same lesson twice in one run -- see the tag-test finding above.

**Two representations behind one syntax is the thing to avoid.** `T?` on a
value type was asked for and turned down in favour of `Option<T>`, a variant.
`C?` is a null pointer and costs nothing; a tagged pair is a different thing,
and giving `?` both meanings would have touched the ABI classifier, layout,
narrowing and mangling across 37 sites. The variant got narrowing,
exhaustiveness and ARC from machinery that already existed.

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

1. **Run the suites on Linux.** `fe46084` changed `SlFieldInfo`'s layout and
   has never been checked against SysV.
2. **Rewrite `Standard.Json`'s `*Or` helpers** with the tag-test form above.
   Half an hour, no compiler change, and the library stops teaching the long
   way by example.
3. **`is` with a binding for a variant case.** The one syntax gap: it closes
   the field-and-call-result hole that no library work can.
4. **A reachability pass from `Main`.** Every program compiles the whole
   library, and the suite went from 66s to 89s this run purely because two
   modules were added that nothing imports. It is now the most expensive
   missing thing.
5. **The +0/+1 dataflow pass.** Still the acknowledged performance item.
6. **`Standard.Collections` does not use the operators it could.** `Money` in
   the samples still calls `Money.Add`; `Standard.Time` has had this pass and
   is what the rest should look like.
7. **Method metadata in reflection**, which is what would let a deserializer
   fill a `List<T>` — the one shape `Standard.Json` still cannot represent.
8. Format specifiers in interpolation; the samples still cover about half the
   language.

## Things to know before touching the build

- **Heredocs mangle backslashes here.** A `\n` inside `bash <<'EOF'` arrives as
  a literal newline, which has broken C#, C and Python source repeatedly. Use
  the Write tool for anything with escapes. A `python << 'PY'` heredoc is safe
  when the delimiter is quoted *and* the body has no backticks.
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
  scattering of unrelated failures -- nine, once -- that all pass when the
  suite is run alone. Do not background one and start another.
