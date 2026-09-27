<sub>[Stainless](../README.md) &rsaquo; Building and internals</sub>

# Building and internals

How to build the compiler, how it is tested, and what it is made of. For the
layout and calling-convention rules the emitter implements, see
[abi.md](abi.md).

---

## Building and testing

Requires the [.NET 10 SDK](https://dotnet.microsoft.com/download) and
[LLVM/clang](https://llvm.org) — `winget install LLVM.LLVM` on Windows,
`apt install clang` on Debian and Ubuntu.

```
dotnet build Stainless.slnx
dotnet run --project tests/Stainless.Tests      # 352 end-to-end tests
dotnet test tests/Stainless.UnitTests           # 1,337 compiler unit tests
```

`--shard=1/2` and `--shard=2/2` run alternate halves of the end-to-end cases,
for a caller whose command has to finish inside a fixed time.

[.github/workflows/ci.yml](../.github/workflows/ci.yml) runs both suites on
Linux and Windows for every push and pull request to `master`, the end-to-end
one in those two shards. How a build is numbered, published and released is
[Releasing](releasing.md).

The two suites ask different questions. An end-to-end case compiles, links and
runs a program, which proves the whole pipeline and takes a fifth of a second;
a unit test asks the front end alone — what did the lexer make of this, where
exactly does this error point, which registers does this struct travel in —
and takes a millisecond, so it can be asked by the hundred.

**A third question is what the compiler does with a program nobody wrote.**
Both suites hold programs that were meant to compile or meant to fail, and
neither holds the half-typed, truncated and nonsensical ones an editor hands a
compiler all day. [tests/Stainless.Fuzz](../tests/Stainless.Fuzz) makes those:

```
dotnet run --project tests/Stainless.Fuzz -- fuzz --minutes 10
dotnet run --project tests/Stainless.Fuzz -- replay     # which findings still fail
dotnet run --project tests/Stainless.Fuzz -- repro file.sl
```

It mutates every test case, sample and standard library file a token at a time
— deleting, repeating, swapping, nesting seven hundred deep — and compiles each
mutant through parse, bind and emit in process, stopping wherever the driver
would, and hands what emits to LLVM's verifier. A compiler may reject anything;
it may not throw, overflow its stack, run forever, report a span that is not in
the file, or emit a module LLVM refuses, and any of those is kept
under `%TEMP%/stainless-fuzz/crashes`, one directory per distinct failure, with
the input shrunk to what still fails the same way.

Each worker is a process rather than a thread, because a stack overflow ends a
.NET process whatever handler is installed and a loop cannot be interrupted, so
the supervisor keeps the input a worker was compiling when it died or went
quiet. It is not coverage-guided: that would mean instrumenting the compiler
assembly, and keeping any mutant that makes the compiler report something new
has been enough to get past the parser. It does not link or run anything, so
it finds crashes and invalid IR and not miscompilations. Verifying costs about
a tenth of a second per mutant that emits, and a sixth of the throughput. Its
first five minutes found two dozen crashes the suites had not, and a fixed one
is pinned by an ordinary case like any other bug — the fuzzer's findings
directory is not a test suite.

**LLVM's verifier is the check on the emitter.** clang 21 and later verify every
module they read, before any pass runs, so with one every linked build and
every end-to-end case is verified whatever `-O` says, and a module it refuses is
reported as an internal compiler error naming the function rather than as
clang's text. An older release clang does not: its driver passes
`-disable-llvm-verifier`, and clang 18 compiles a module that uses a value
before defining it without a word. So CI, whose runners carry older LLVMs,
sets `STAINLESS_VERIFY_IR=1`. Debug
information is the exception: clang drops a description that fails the verifier
with a warning and links the binary anyway, so the driver and the end-to-end
runner fail the build on that warning. What never reaches clang is verified on
purpose — every emitter unit test and every sample, through `Front.Verified`,
and every fuzz mutant — and `--verify-ir`, or `STAINLESS_VERIFY_IR=1`, runs it
over an `emit-ir`.

The verifier is `opt -passes=verify` where one is beside clang, which Debian's
LLVM ships and the Windows installer does not, and `clang -cc1` otherwise,
reading the module and emitting nothing. It is `-cc1` rather than the driver so
that the driver's `-disable-llvm-verifier` is never passed. Either takes about a
tenth of a second on a module holding the whole standard library, which is 5%
of building `hello.sl`. It is not on by default, even in a Debug build of the
compiler: every build that links is verified already, and all a default would
add is `emit-ir`, which is what the flag is for.

**The bound tree is checked before the emitter reads it.** The emitter trusts
what binding hands it, so a mistake in the binder surfaces far from its cause:
a node the emitter has no case for, a local it has no slot for, a write into a
temporary copy. [BoundTreeVerifier](../src/Stainless.Compiler/Binding/BoundTreeVerifier.cs)
walks every function and static initializer of a program that bound without
error, and throws an internal compiler error naming the node and its span when
the tree breaks a rule the emitter relies on: a draft node or type that binding
should have settled, an error node, an expression with no type, a local read
where nothing declared it, a parameter of another function, a `for parallel`
body reading what it did not capture, an assignment to something with no
address, a switch label that is not a constant of the switched type, a
conditional whose arms disagree with it, an inline array holding a counted
reference. It runs twice, over what binding made and over what lowering made
of it, and the second time it also refuses any node lowering exists to take
away. It is on in a Debug build of the compiler, which every suite and the
fuzzer run, and off in Release; `STAINLESS_VERIFY_BOUND` set to `0` or to
anything else overrides either. It costs about 10 ms of a 210 ms bind for
`hello.sl`, whose standard library it walks too, and about 30 ms of 670 ms for
the IDE, in a Debug build.

**A node nobody handles is a crash, not a guess.** Every dispatch over bound
node kinds — the emitter's expression and statement switches, the conversion
kinds, the types it spells — throws an `InternalCompilerError` on a case it
does not have, rather than emitting a zero. The driver reports one as a
compiler bug, and the fuzzer records one as a finding under its problem.

**One walker knows a node's children.** [BoundTreeWalker](../src/Stainless.Compiler/Binding/BoundTreeWalkers.cs)
visits every child of every node exactly once, in evaluation order, and throws
on a node kind it does not know. Every analysis that looks through a whole
tree — which statics an initializer reads, what a `for parallel` body
captures, which fields a getter reads, whether an `out` parameter is written,
whether a function holds a label, and the verifier — is a subclass that
handles the nodes it is about and calls the base for the rest, so none of them
can skip a node kind by omission. A unit test fills every property of every
node type with fresh nodes by reflection and requires the walk to return each
exactly once; a property holding a node that another child already holds is
marked `[SharedSubtree]` and is skipped.

**One rewriter knows how to rebuild a node.** [BoundTreeRewriter](../src/Stainless.Compiler/Binding/BoundTreeRewriter.cs)
goes through the same children in the same order and puts a node back
together around whatever came back for them, carrying every flag, symbol and
list the node held; a node none of whose children changed is handed back as
it was, so a rewrite that has nothing to say about a body copies none of it.
The same kind of reflection test fills every child of every node type with a
fresh node, has each replaced, and requires the rebuilt node to hold exactly
the replacements and everything else the old one held.

**Both Windows and Linux are tested.** 352 cases, of which 13 are
Windows-only and 2 are Linux-only, so Linux runs 339 and Windows 350, each
skipping the other's. A case whose *subject* differs by platform — `Path.Join` writes a
different separator, and `\x` is rooted on one and an ordinary name on the
other — carries an `expected.linux.txt` beside its `expected.txt` rather than
having the difference argued away.

Eleven of those cases are real 32-bit binaries, built and run on both systems, and
six are built for ARM64 and not run: there is no ARM64 machine here, so they
stop at an object file LLVM verified and lowered, with their signatures pinned
against clang's. Building 32-bit on Linux needs the development half of the
multilib packages, which is what
[tests/linux-x86.Dockerfile](../tests/linux-x86.Dockerfile) is for.

macOS is not tested. Nothing in the compiler is Windows-only and the runtime's
`#ifdef`s have a POSIX branch that Linux exercises, so it is likely close; the
constants in `bindings/linux` are Linux's and would not port, and that is
stated where they are.

`STAINLESS_CLANG` names the clang to use and always wins. Failing that the
compiler takes the first on `PATH`, then tries `C:\Program Files\LLVM\bin` and
its `(x86)` sibling on Windows, or `/usr/bin/clang` and `/usr/local/bin/clang`
elsewhere. `llvm-rc` is looked for beside whichever clang was found, because it
ships in the same directory.

---

## The pipeline

```
  .sl sources
      |
      v   Lexer -> Parser                       one file at a time, no #include
   syntax trees
      |
      v   Binder, in eleven whole-program passes:
      |     1. declare modules        7. compute C-compatible layouts
      |     2. declare types          8. check what crosses a language boundary
      |     3. resolve imports        9. check bodies
      |     4. resolve signatures    10. order and check static initializers
      |        and field types       11. check whatever those instantiated
      |     5. check that classes implement what they claim
      |     6. fold attributes to constants
      |
      |   A referenced library's declarations are loaded before pass 1, so a
      |   module from a binary is named exactly like one from source.
      |
      |   Nothing may depend on declaration order, so every name in the
      |   program is known before any body is checked. That single rule is
      |   what lets header files go away.
      v
   semantic tree  (fully typed, every name resolved: what the program means)
      |
      v   Lowerer: each construct binding checked, rewritten into the core
      |
   lowered tree  (the smaller core the emitter handles)
      |
      v   LlvmEmitter, with the classifier for the target's ABI
   textual LLVM IR
      |
      v   clang
   native .exe
```

| Component | Role |
|---|---|
| [Syntax/Lexer.cs](../src/Stainless.Compiler/Syntax/Lexer.cs) | tokens, and `#if` deciding which of them exist |
| [Syntax/Parser.cs](../src/Stainless.Compiler/Syntax/Parser.cs) | recursive descent + precedence climbing |
| [Binding/Binder.cs](../src/Stainless.Compiler/Binding/Binder.cs) | the eleven passes; one partial class over `Binder.*.cs`, a file per area — bodies, calls, closures, conversions, generics, inheritance, layout |
| [Binding/BoundTree.cs](../src/Stainless.Compiler/Binding/BoundTree.cs) | the bound tree's nodes |
| [Binding/BoundTreeWalkers.cs](../src/Stainless.Compiler/Binding/BoundTreeWalkers.cs) | the one walker over them, and the analyses built on it |
| [Binding/BoundTreeRewriter.cs](../src/Stainless.Compiler/Binding/BoundTreeRewriter.cs) | the one rewriter over them, which lowering is built on |
| [Binding/BoundTreeVerifier.cs](../src/Stainless.Compiler/Binding/BoundTreeVerifier.cs) | what lowering and the emitter rely on, checked after binding and again after lowering |
| [Lowering/Lowerer.cs](../src/Stainless.Compiler/Lowering/Lowerer.cs) | the semantic tree into the core: a new program, with the bodies binding made left as they were |
| [Binding/TypeSystem.cs](../src/Stainless.Compiler/Binding/TypeSystem.cs) | types and C-rule layout |
| [Binding/TargetPlatform.cs](../src/Stainless.Compiler/Binding/TargetPlatform.cs) | what `--target` and `--abi` parse to, and the host's defaults |
| [Binding/EmbeddedFile.cs](../src/Stainless.Compiler/Binding/EmbeddedFile.cs) | what an `[Embed]` static holds: which sections a target already owns, and the assembly the object is written as |
| [Binding/Builtins.cs](../src/Stainless.Compiler/Binding/Builtins.cs) | `String`, `Utf16String`, `[Flags]`, the bit instructions `Standard.Bits` puts names on, and the lookup that finds the rest in the standard library rather than declaring it |
| [Binding/Mangler.cs](../src/Stainless.Compiler/Binding/Mangler.cs) | symbol names |
| [Binding/CppMangler.cs](../src/Stainless.Compiler/Binding/CppMangler.cs) | C++ symbol names, in the Itanium and Microsoft schemes |
| [Binding/MetadataLoader.cs](../src/Stainless.Compiler/Binding/MetadataLoader.cs) | symbols for a referenced library, from its metadata |
| [Emit/Win64Abi.cs](../src/Stainless.Compiler/Emit/Win64Abi.cs) | struct passing on Win64: register, `byval`, or `sret` — it asks only how big a struct is |
| [Emit/SysVAbi.cs](../src/Stainless.Compiler/Emit/SysVAbi.cs) | System V AMD64, which asks what is *in* a struct and cuts it into eightbytes |
| [Emit/X86Abi.cs](../src/Stainless.Compiler/Emit/X86Abi.cs) | 32-bit x86, where every struct travels on the stack and the two systems differ on returns |
| [Emit/Aapcs64Abi.cs](../src/Stainless.Compiler/Emit/Aapcs64Abi.cs) | ARM64 — one classifier, because Microsoft's ABI and ARM's agree about every shape asked |
| [Emit/LlvmEmitter.cs](../src/Stainless.Compiler/Emit/LlvmEmitter.cs) | IR, metadata tables; partial over `LlvmEmitter.*.cs`, and where the four classifiers above are chosen between |
| [Emit/LlvmEmitter.Arc.cs](../src/Stainless.Compiler/Emit/LlvmEmitter.Arc.cs) | every retain and release: what each value owes, where it is moved, and what a scope drops |
| [Emit/DebugInfo.cs](../src/Stainless.Compiler/Emit/DebugInfo.cs) | what `-g` writes for a debugger |
| [Emit/CHeaderWriter.cs](../src/Stainless.Compiler/Emit/CHeaderWriter.cs) | the C header for a shared library |
| [Emit/MetadataWriter.cs](../src/Stainless.Compiler/Emit/MetadataWriter.cs) | the module metadata a Stainless consumer binds against |
| [Emit/DocWriter.cs](../src/Stainless.Compiler/Emit/DocWriter.cs) | the reference pages `stainless doc` writes from `///` blocks |
| [Driver/ModuleMetadata.cs](../src/Stainless.Compiler/Driver/ModuleMetadata.cs) | what that metadata contains, and how it is read back |
| [Driver/ProjectFile.cs](../src/Stainless.Compiler/Driver/ProjectFile.cs) | `stainless.json`, and refusing a field it does not know |
| [Driver/PackageResolver.cs](../src/Stainless.Compiler/Driver/PackageResolver.cs) | resolving dependencies, with [PackageLock.cs](../src/Stainless.Compiler/Driver/PackageLock.cs) and [Digest.cs](../src/Stainless.Compiler/Driver/Digest.cs) for the lock and the layout fingerprint |
| [Driver/Toolchain.cs](../src/Stainless.Compiler/Driver/Toolchain.cs) | finding clang and `llvm-rc` |
| [runtime/](../runtime/) | the whole runtime, split by feature |
| [stdlib/](../stdlib/) | the standard library, written in Stainless: a folder per module, a file per public type |

## Where binding is, and binding on trial

Everything about where the binder is — the function, the file, the type
arguments, the locals, the loops, the lambdas being bound, what is known about
each variant — is one `BinderContext`. A body bound in the middle of another,
such as a lambda, a local function, an instantiation's signature or a static's
initializer, is bound in a context of its own entered with `using`, and the
one it interrupted is back when that is disposed. Nothing saves and restores
the fields one at a time, so nothing forgets one.

Some binding is a trial: an overload is tried, a lambda's body is bound to learn
what it produces, or a name is bound to see whether it is callable. Binding
changes the program as well as describing it. It instantiates generics and
queues their bodies, makes closure classes and array types, and records members
as written and parameters as assigned. A trial either keeps all of that or
takes all of it back. Every table it adds to is written through `Remember`,
which notes how to undo the write, and every list is cut back to its length
when the trial began. A generic candidate that loses is discarded, so what its
lambdas instantiated is not emitted. A lambda's result, once found, is kept,
because it may be a type the body was the first to name.

A quiet trial mutes what it reports, because a guess that fails is not the
program's error. What an instantiation made inside one reports is not muted.
It is held until the outermost trial ends, and reported if that trial is kept,
because the cache would otherwise hand the instantiation to the real bind
with its complaint lost. A constraint broken by a call written `n.Count()`
went unreported that way.

## The error type

A type that could not be resolved becomes the error type, and that failure
is reported where it happened. Everything that later meets it says nothing.
A report names the types its message spells after the message, as
`diagnostics.Error(code, span, message, target, argument.Type)`, and one that
is or is built from the error type makes the report a consequence, which is
dropped. Types are asked, rather than the message searched for `<error>`, so
a message may say anything. A place that spells a type without naming it is a
compiler bug, and a Debug build, which every suite and the fuzzer run, stops
there with an internal compiler error. The fuzzer found 28 such places in
its first ten minutes. `HasErrors` is a count kept as reports arrive.

## Lowering

Binding says what a program means; lowering says how it runs. The tree the
binder makes keeps each construct as it was written -- a switch is its subject
and sections of patterns and guards, and a pattern is the questions it asks
and the values it reads, as expressions over a placeholder for the value asked
about. [Lowerer](../src/Stainless.Compiler/Lowering/Lowerer.cs) rewrites that
into the core the emitter handles, as a new program: the semantic one is left
whole, for whatever reads a program rather than running it.

Each lowering makes exactly the core the binder used to make in place, so the
emitter and its ownership rules see the same shapes: `foreach` becomes the
indexed `for` or the enumerator's `while`; `?.` and `??` the receiver held in a
`let` and a conditional on it; `as` the value held, tested and converted;
`x op= y`, `x ??= y` and the same on a property the place held where naming it
again could differ, then read and written back; a store whose value runs code
the object or array it lands in held while that code runs; `with` the clone
and its writes; an object initializer the object held in a `let` and its
entries in order; a collection expression the array literal it always was, or
with a spread every part held in order and then the storage made, sized when
every spread can say its count, and filled or added to; a deconstruction the
targets' receivers and indices held, then the values, then the stores;
`x[^1]` and `x[a..b]` on a type with a count, and an array sliced by a `Range`
value, what is indexed, its count and the offsets each evaluated once; and the
elements a call gives a `params` parameter the array, in the caller's frame
for a slice unless a `spawn` outlives the statement. A property written or
stepped becomes its accessors' calls, and how depends on whether the value a
write produces is read: where nothing reads it, it is the setter's call alone;
where something does, the receiver, indices and value are held and the value
handed on. The emitter has no case for a property write. Where one of these
names a value it does not yet have -- a loop's element, a receiver known to be
there, the object being initialized, a tuple taken apart -- the semantic node
holds a placeholder for it, and lowering puts in its place whatever holds the
value.

Binding still asks questions of what it binds -- whether an expression has an
effect, whether reading it again is free, whether this statement made it -- and
a semantic node MUST answer each as the core it lowers to would, or a warning,
a hold or an owned reference changes with it. `x[^1]` on a type with a count
stays the getter's call, so that a write through it still reaches the setter;
only its receiver, read again for the count, is a semantic node.

A node only the semantic tree holds derives from `BoundSemanticExpression` or
`BoundSemanticStatement`, and counts itself as it is made; a body whose
binding made none is already the core, and lowering hands it on untouched, as
it does each statement in a body that has one where that statement made none.
Lowering the IDE and the standard library takes about 37 ms of a 1.3 s
`emit-ir` in a Release build. Most of that is the pass's first run: lowering
the standard library alone takes 22 ms, and 3 ms when run again in the same
process.

**Matching is one lowering.** A switch statement, a switch expression and `is`
are each a list of arms, and [DecisionBuilder](../src/Stainless.Compiler/Lowering/Decisions.cs)
builds every one of them into the same tree. The arms are asked in order, but a
question is asked once on any path and its answer is remembered: a later arm
asking for the same case, constant or null of the same value has it answered,
and one asking for another case of a variant already known to hold this one is
dropped. A value read from the subject -- a payload's field, a property, an
element -- is read once on any path, and held in a name where reading it again
would not be free. A pattern under `or` or `not` that asks more than one thing
is asked whole. A tree can grow with the product of what its arms ask, so past
a budget each arm is asked whole instead, which is the chain the arms would be
without sharing and grows only with them.

A statement's tree is written as jumps. A run of questions of one value
against constants or a variant's cases is one `BoundSwitchDispatch`, an LLVM
`switch`; any other question is an `if`; an arm that matched gives its names
their values and jumps to its section, and `break` is a jump past the last
section. The labels lowering makes are reached only from before them, so they
do not make a function's declarations release on entry the way a label a
`goto` can reach from below does. An expression's tree is conditionals, with
`&&` and `||` where it answers a `bool`, which is every `is`.

## One object per type

Two types are the same type exactly when they are the same object, so `==` is
the whole of type identity and no type overrides `Equals` — a unit test holds
both. `T*`, `T[]`, `T?`, `weak T?` and `T[N]` are made only by the type they
are built from, through `MakePointerType()` and its siblings, which keep what
they made; their constructors are private, so there is no second `int*` to
compare field by field. Tuples, slices, closure types and instantiations are
kept by the binder, keyed by the objects they are made of — an instantiation
by its template's own object and its arguments', not by a name that two
modules can both print.

The derived types live on their element rather than in a table because the
primitives are shared by every compilation in a process, and the unit tests
run many at once: a table beside them would keep every compilation's types
alive, and two filled at once would disagree. The slot is filled by
compare-and-exchange.

Whether a struct carries a counted reference is asked everywhere a value is
copied, and is kept on the struct once its layout is settled. Binding the IDE
takes about 530 ms in a Release build and 155 ms once the JIT has warmed.
Indexing each module's functions by name, and reading each file's imports once
rather than at every lookup, took 90 ms off the first and a third off the
second.

## Why textual IR

Emitting `.ll` text rather than calling the LLVM C API means the compiler has no
native dependency, builds anywhere .NET does, and produces output you can read
and diff. `stainless emit-ir hello.sl` prints it.

## Why ownership works the way it does

Stainless uses **borrowed parameters and owned returns**, the same choice Swift
makes, because it removes most retain/release traffic: passing a reference to a
function costs nothing. Locals and fields own their references; assigning to one
retains the new value *before* releasing the old, so self-assignment is safe.
A parameter the body *writes to* is the one exception — it is retained on entry
and released on exit, because otherwise its store would release a reference the
caller still owns.

**The emitter decides every count, and each value says what it owes.** A value
the emitter produces is *owned* — a +1 that whoever receives it must store,
return, merge or register for release at the end of the statement — or
*borrowed*, or *uncounted*: null, a zero, an immortal literal. What each bound
node yields is stated once, in `HoldOf` in
[LlvmEmitter.Arc.cs](../src/Stainless.Compiler/Emit/LlvmEmitter.Arc.cs), and each
node's emitter marks what it makes. A context that keeps a value — a local's
initializer, an assignment whose value is discarded, a return, an element of a
tuple, variant, closure or array literal, a conditional's arm, a slice's
source — moves an owned one in and retains only a borrowed one; a context that
reads registers an owned one for release when the statement ends. So
`var b = Make();` is a call and a store, and counts nothing.

A Debug build of the compiler checks the model as it goes: that each node made
what `HoldOf` says it does, and that nothing owned is left unconsumed at the end
of a statement or a function. A value dropped on the floor is an internal
compiler error at the statement that dropped it, not a leak found at exit.

Nothing owned is held unregistered across what can return: an aggregate that
is being built is registered for release first and claimed back when it is
complete, so a `try` returning between two elements lets go of the first.
Retains and releases are relaxed and acquire-release atomics that LLVM cannot
pair up, so the elision has to happen here; `tools/arccount.ps1` counts both,
in the IR and at run time.

---

<sub>[&larr; README](../README.md) &nbsp;&middot;&nbsp;
[ABI notes &rarr;](abi.md)</sub>
