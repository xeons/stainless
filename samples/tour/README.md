# The tour

```
stainless run samples/tour
```

One program that uses every feature of the language, in the order
[the specification](../../docs/language-spec.md) introduces them. It prints what
it did at each step, so running it checks that the tour is still *true* rather
than only that it still builds.

Five files, about 2,000 lines with the commentary:

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
| §1 modules, imports, visibility, aliases, qualified names | `Modules()`; `Platform.sl` |
| §1.2 a module spanning files | the file layout itself |
| §2.1 every primitive, the three code-unit types, escapes, conversions | `Primitives()` |
| §2.2 structs, value semantics, a struct that owns a reference | `Values()` |
| §2.2.1 incomplete types | `Platform.sl`, `Handle__` |
| §2.3 `[Packed]`, `[Align]`, bit-fields | `Values()` |
| §2.4 classes, ARC, `abstract`/`virtual`/`override`/`sealed`, `base(...)`, `this(...)`, `protected`, destructors, `weak` | `References()`, `Contracts()` |
| §2.5 pointers, `->`, `void*`, `T?`, narrowing | `Pointers()` |
| §2.6 variants, exhaustive `switch`, `is` with a binding, generic variants, `Optional<T>` | `Variants()` |
| §2.7 unions, anonymous `struct`/`union` members | `Values()` |
| §2.8 `Result<T, E>`, `Ok`/`Fail`, `try` | `Results()` |
| §2.10 interfaces, interface inheritance, dynamic dispatch | `Contracts()` |
| §2.11–2.12 arrays, array literals, fixed arrays, slices, all four slice forms | `Arrays()` |
| §2.13 enums, a named base, `[Flags]`, `HasFlag` | `Enumerations()` |
| §2.14 delegates, closures, bound methods, lambdas, capture by value | `Functions()` |
| §2.15 tuples, deconstruction | `Tuples()` |
| §3 text, escapes, `StringBuilder`, interpolation, UTF-16, encodings, `ToPointer` | `Textual()` |
| §4 generic functions, types, methods, constraints, generic operators, generic closures | `Generics()` |
| §5 containers, sequences, `Math`, `Random`, `Time`, `Env`, files, JSON, XML, `Convert` | `Library()` |
| §6 attributes, `[Reflect]`, `typeof`, fields, properties, writing both, `FindType` | `Reflected()` |
| §7.1–7.2 overloads, `ref`, `in`, `out`, named arguments | `Calls()` |
| §7.3–7.6 properties, indexers, operators, statics, static classes, nested types | `Members()` |
| §8 `extern "C"`, variadics, `export "C"`, structs by value, delegates to C | `Interop()` |
| §8.1 `extern "C++"`, `export "C++"`, namespaces | `Interop()`; `native.cpp` |
| §8.6 `#pragma comment(lib, ...)` | `Platform.sl` |
| §9 `if`, `for`, `while`, `do`, `switch` over three things, `break`, `continue`, `goto`, labels, the ternary, every compound assignment, `++`/`--`, `?.`, `??`, `??=`, `default(T)`, `nameof`, `checked`, `unchecked`, `const`, `static` | `Statements()` |
| §9.2 `parallel`, `spawn`, `parallel for`, `threadsafe`, mutexes, atomics | `Concurrency()` |
| §9.4 `foreach` over an array, a slice and a type with its own `GetEnumerator` | `Arrays()` |
| §10 `#if`, `#elif`, `#else`, `#define`, `#region` | `Platform.sl`, `Modules()` |

## What is deliberately not here

- **COM (§8.5)** and the platform bindings. Both need one operating system and,
  for COM, a registered object; `tests/cases/win32-com` and
  `tests/cases/linux-terminal` are where those live.
- **Building a shared library (§8.2–8.4).** That is a different *command*, not a
  different program: `tests/cases/shared-library` and
  `tests/cases/stainless-library` cover it.
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

## What writing it found

Six bugs, all fixed, each with a regression case named beside it:

1. **A generic variant and a generic class that name each other got a one-byte
   payload** and segfaulted at the first store. An instantiation's layout was
   computed while another instantiation was still declaring its members, and
   `LayoutComputed` meant nothing revisited it. — `tests/cases/nested-generics`
2. **A negated integer literal past the `int` range was truncated to 32 bits,**
   silently: `long x = -9000000000000000000;` gave 494665728, `int` to `long`
   being an implicit widening with nothing to complain about. —
   `tests/cases/arithmetic-edges`
3. **An unsigned value past 2^63 printed as a negative number.**
   `Text.FromInteger(nuint)` and every interpolation of one went to the signed
   formatter. — `tests/cases/arithmetic-edges`
4. **A `void*` local made a `-g` build fail to link.** DWARF spells `void*` as a
   pointer with no base type; LLVM wants the field written all the same, as
   `null`. — `tests/cases/debug-info`
5. **`[Align(N)]` reached the layout numbers and not the generated type.**
   `sizeof(Wide)` said 16 while an array of them had a stride of 4, and a struct
   holding one put it four bytes in rather than sixteen. LLVM has no way to be
   told a type's alignment, so a struct whose computed layout differs from what
   LLVM would make of its fields is now written out: packed, with the padding
   spelled `[k x i8]` between the fields and after the last. It is contagious on
   purpose — a packed struct reports an alignment of 1, so anything holding one
   is written out in turn -- which is what carries the correction outwards. Of
   the 153 structs the tour emits, three need it. The same mechanism fixes a
   struct holding a struct of bit-fields, whose storage is bytes and whose
   alignment was therefore not its own. — `tests/cases/layout-queries`
6. **`Guid`'s field indices were its field offsets**, and its offsets were never
   set at all. It is built by hand in `Builtins` rather than bound from source,
   so nothing else filled either in, and the two lists read plausibly as one:
   `Data2` reached member 4 of a struct with four members. Nothing had ever read
   past `Data1`. Found because the layout fix above compares the two.
   — `tests/cases/com`
