# Handoff

Where this sits after the five-phase run, what was learned that is not obvious
from the code, and what is worth doing next. Written to be read cold.

## State

```
dotnet build Stainless.slnx                     0 warnings
dotnet test tests/Stainless.UnitTests           497 pass
dotnet run --project tests/Stainless.Tests      210 cases, 1 skipped on Windows
```

Green on Windows and on Linux (`ssh brandon@geekom-a7`, which is worth using --
it has found a bug in most sessions it has been run in). `master` is ahead of
`origin/master`; nothing has been pushed.

## What was built, in order

| | |
|---|---|
| `ce42c8e` | LLVM attributes on the runtime declarations |
| `3b00f2d` | inference from a lambda's body; combinators; a stable sort |
| `748f6ea` | `Main(String[] args)`, `Standard.Env`, `Time`, `Random`, stdin |
| `4904c10` | string interpolation |
| `7c12068` | operator overloading and indexers |
| `dd45b15` | `try`, and one error convention |

## Findings worth keeping

**The ARC numbers were measuring the wrong thing.** Counting
`sl_retain`/`sl_release` in a module counts mostly calls in library functions
the program never invokes -- hello-world's 844 are all outside `Main`. And a
read through a reference already borrows, so `cells[i].Value` in a loop emits
no counting at all. The +0/+1 pass is still worth building; the number that was
being quoted for it was really an argument for the reachability pass.

**A lambda's body can be read for a type, and now is.** `Map(xs, x => x * 2)`
needs `R` from the body, which needs `T` from the array first. That ordering is
the whole trick, and it is why the pass runs after ordinary inference rather
than as part of it.

**`char` is a UTF-8 code unit, not a character.** Interpolation refuses it for
the same reason SL0527 does. Only `char32` writes a character.

**A constructor cannot report why it failed**, which is why fallible
construction is a function in every language that checks errors. Stainless has
no static methods, so those functions are module-level: `File.Open`,
`Net.Listen`, `Net.Connect`, `Net.Bind`, `Net.Datagram`. The constructors stay
public beside them -- hiding them was tried and reverted, because a factory can
only hide a constructor when the two share a module, and `FileStream` and
`File.Open` do not.

**Two emitter bugs, both the same shape.** An `alloca` holds whatever was on
the stack, and `StoreInto` releases what it is replacing -- so a slot that is
not blanked first releases rubbish. `EmitLocalDeclaration` has always known
this; `EmitTry` had to learn it, via a heap corruption that made a test loop.

## Next, in the order I would do it

1. **The +0/+1 dataflow pass.** Still the acknowledged performance item, now
   with an honest estimate of the target: what is left to remove is references
   being passed around, not used.
2. **A reachability pass from `Main`.** Every program compiles the whole
   library. Each thing added this run -- threading, env, time, random -- is now
   compiled into programs that never mention it.
3. **`Standard.Collections` does not use the operators it now could.** `Money`
   in the samples still calls `Money.Add`, and the containers could declare
   `==` and `<` rather than `IEquatable`/`IComparable` methods. A library pass.
4. **Operator constraints.** `where T : IAddable<T>` still cannot be written;
   an interface may not declare an operator, because an operator is chosen from
   the operand types rather than dispatched. This is also what blocks
   definition-site constraint checking (§4.3).
5. **Format specifiers in interpolation.** `{n:x}` and `{n,8}` are unwritten;
   `:` and `,` inside a hole are already reserved so adding them breaks nothing.
6. The samples still cover about half the language -- see the list in the
   commit message of `9be5d2c`.

## Things to know before touching the build

- **Heredocs mangle backslashes here.** A `\n` inside `bash <<'EOF'` arrives as
  a literal newline, which has broken C#, C and Python source repeatedly this
  run. Use the Write tool for anything with escapes.
- `io.open(p, 'wb').write(io.open(p, 'rb').read())` truncates the file before
  reading it -- Python evaluates the callee first. It emptied an `expected.txt`
  once.
- `-o /dev/null` does not work for a build on Windows; the linker wants a real
  path.
- A documented `SL####` needs an `errors.txt` case pinning it, or
  `DiagnosticTests.EveryDocumentedCodeIsPinnedByACase` fails.
