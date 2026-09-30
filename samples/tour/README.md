# The tour

```
stainless run samples/tour
```

One program that uses every feature of the language, in the order
[the specification](../../docs/spec/index.md) introduces them. It prints what
it did at each step, so running it checks that the tour is still *true* rather
than only that it still builds.

Five files, about 2,300 lines with the commentary:

| | |
|---|---|
| `Platform.sl` | `module Tour.Platform` — the module that exists to be imported: aliases, handles, the `extern`/`export` declarations, the pragma |
| `Types.sl` | `module Tour.Types` — the catalogue: structs, classes, enums, variants, unions, interfaces |
| `Types.Members.sl` | the same module, second file — members, generics, functions as values, attributes |
| `Tour.sl` | `module Tour` — `Main`, and sections 1, 2, 3 and 9 |
| `Library.sl` | the same module, second file — sections 4 to 8 |
| `native.c`, `native.cpp` | the other side of the interop sections |

Two of those pairs exist to *be* a feature rather than to describe one: a module
spanning files (§1.2) is shown by `Tour.Types` and `Tour` each being written
twice.

## What is covered

Every section of the specification, with the exclusions listed below.

| Spec | Where |
|---|---|
| section 1 modules, imports, visibility, aliases, qualified names | `ShowModules()`; `Platform.sl` |
| §1.2 a module spanning files | the file layout itself |
| section 2.1 every primitive, the three code-unit types, escapes, conversions | `ShowPrimitives()` |
| section 2.2 structs, value semantics, a struct that owns a reference | `ShowValues()` |
| section 2.2.2 incomplete types | `Platform.sl`, `Handle__` |
| section 2.3 `[Packed]`, `[Align]`, bit-fields | `ShowValues()` |
| section 2.4 classes, ARC, `abstract`/`virtual`/`override`/`sealed`, `base(...)`, `this(...)`, `protected`, destructors, `weak` | `ShowReferences()`, `ShowContracts()` |
| section 2.5 pointers, `->`, `void*`, `T?`, narrowing | `ShowPointers()` |
| section 2.6 variants, exhaustive `switch`, `is` with a binding, generic variants, `Optional<T>` | `ShowVariants()` |
| section 2.7 unions, anonymous `struct`/`union` members | `ShowValues()` |
| section 2.8 `Result<T, TError>`, `Ok`/`Fail`, `try` | `ShowResults()` |
| section 2.10 interfaces, interface inheritance, dynamic dispatch | `ShowContracts()` |
| section 2.11-2.12 arrays, array literals, fixed arrays, slices, all four slice forms | `ShowArrays()` |
| section 2.13 enums, a named base, `[Flags]`, `HasFlag` | `ShowEnumerations()` |
| section 2.14-2.15 delegates, closures, bound methods, lambdas, capture by value | `ShowFunctions()` |
| section 2.2.4-2.2.5 tuples, deconstruction | `ShowTuples()` |
| section 3 text, escapes, `StringBuilder`, interpolation, UTF-16, encodings, `ToPointer` | `ShowText()` |
| section 4 generic functions, types, methods, constraints, generic operators, generic closures | `ShowGenerics()` |
| section 5 containers, sequences, `Math`, `Random`, `Time`, `Env`, files, JSON, XML, `Convert` | `ShowLibrary()` |
| section 6 attributes, `[Reflect]`, `typeof`, fields, properties, writing both, `FindType` | `ShowReflection()` |
| section 7.1-7.2 overloads, `ref`, `in`, `out`, named arguments | `ShowCalls()` |
| section 7.3-7.6 properties, indexers, operators, statics, static classes, nested types | `ShowMembers()` |
| section 8 `extern "C"`, variadics, `export "C"`, structs by value, delegates to C | `ShowInterop()` |
| section 8.1 `extern "C++"`, `export "C++"`, namespaces | `ShowInterop()`; `native.cpp` |
| §8.6 `#pragma comment(lib, ...)` | `Platform.sl` |
| section 9 `if`, `for`, `while`, `do`, `switch` over three things, `break`, `continue`, `goto`, labels, the ternary, every compound assignment, `++`/`--`, `?.`, `??`, `??=`, `default(T)`, `nameof`, `checked`, `unchecked`, `const`, `static` | `ShowStatements()` |
| section 9.2 `parallel`, `spawn`, `for parallel`, `threadsafe`, mutexes, atomics, `Thread`, `Future<T>` | `ShowConcurrency()` |
| section 9.4 `foreach` over an array, a slice and a type with its own `GetEnumerator` | `ShowArrays()` |
| section 10 `#if`, `#elif`, `#else`, `#define`, `#region` | `Platform.sl`, `ShowModules()` |

## What is deliberately not here

- **COM (§8.5)** and the platform bindings. Both need one operating system and,
  for COM, a registered object; `tests/cases/win32-com` and
  `tests/cases/linux-terminal` are where those live.
- **Building a shared library (§8.2–8.4).** That is a different *command*, not a
  different program: `tests/cases/shared-library` and
  `tests/cases/stainless-library` cover it.
- **`[Embed]` (section 8.7) and inline assembly (section 8.8).** An `asm` block's text is
  one architecture's; `tests/cases/embed`, `tests/cases/asm-*` and their `x86-`
  and `arm64` neighbours are where both live.
- **`#error` and `#warning`.** A tour that fired one would not build, or would
  build with a diagnostic — and a diagnostic in a sample is what the sample
  suite exists to catch.
- **Every rule that is a refusal.** A program that does not compile prints
  nothing, so the error cases stay in `tests/cases/err-*`, which is where they
  can be checked.

## The IR

The point of a program this wide is that it produces a lot of IR to be wrong
about. What was checked, on both platforms:

- **It verifies.** `clang -c` on the emitted `.ll` runs LLVM's verifier, and
  passes at `-O0` and at `-O2`, under both `--abi microsoft` and
  `--abi itanium`. So does a `-g` build, which additionally puts the debug
  metadata through it.
- **The output does not depend on the optimizer.** `-O0`, `-O1`, `-O2` and `-O3`
  print byte-identical text, which is what says the IR carries no undefined
  behaviour for the optimizer to take a different view of.
- **The output does not depend on the platform.** Windows and Linux differ in
  exactly the three lines that report which platform they are.
- **The C ABI agrees with clang's.** `native.c` compiled by clang lowers
  `c_apply_twice` to `(ptr, i32)` and `c_sum_pair` to `(i64)`; Stainless emits
  the same two signatures, on both Win64 and System V.
- **The C++ mangling agrees with clang's.** `nm` on the two object files shows
  each side defining exactly the symbol the other one wants —
  `?Doubled@tour@@YAHH@Z` under MSVC's scheme and `_ZN4tour7DoubledEi` under
  Itanium's.
- **The layouts agree with C's.** Every `sizeof`, `alignof` and `offsetof` the
  tour prints was compared against the same declarations compiled by clang.
- `checked` lowers to `llvm.sadd.with.overflow` and friends rather than to a
  wider type and a comparison; an interpolation lowers to one `sl_string_join`
  rather than a chain of concatenations; an index carries a bounds check; a
  division by a value carries a zero check.

