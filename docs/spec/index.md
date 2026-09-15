<sub>[Stainless](../../README.md) &rsaquo; Language specification</sub>

# Stainless Language Specification

<sub>Draft 145</sub>

> **An extreme rough draft.** This describes an experiment rather than a settled
> design; anything here may change, and several sections describe behaviour that
> was arrived at by trying it rather than by deciding it in advance.

Stainless is a general-purpose language reaching for the performance of C and
C++ with the flexibility of a higher-level one, by combining ideas that do not
usually appear together: C#'s syntax and namespaces, C's layout and ABI,
Swift's reference counting, monomorphized generics as in C++ and Rust, and
reflection as static tables in the binary as in Swift and Go.

**The four ideas it is built around**

1. **No header files.** Declarations are order-independent within and across
   modules; the compiler resolves the whole program graph before checking any
   body. There is no `#include`, no macro, no include guards, no forward
   declarations, no ODR. `#if` and its relatives do exist, as in C#
   ([&sect;10](10-conditional-compilation.md)): choosing between two platforms
   is a different question from finding a declaration.
2. **Native code via LLVM.** No VM, no JIT, no runtime startup cost beyond a
   small ARC runtime.
3. **ARC, not GC.** Reference types are reference-counted and destroyed
   deterministically. No collector, no pauses, no tracing thread.
4. **C and C++ ABI compatible.** `struct` types use the platform C layout,
   `extern "C"` functions use the platform calling convention, and Stainless
   functions are callable from C. Interop needs no marshalling layer.
   `extern "C++"` and `export "C++"` do the same for C++ free functions, by
   mangling a signature the way the target's compiler does. A C++ *class*
   cannot be named yet.

If you write C#, you can read Stainless on sight. The differences are all
about what happens underneath: values instead of objects, refcounts instead
of a collector, a linker instead of an assembly loader.

The specification says what the language *is*. Two companions say how it is
built and what it runs on: [abi.md](../abi.md) for layout, mangling and calling
convention, and [concurrency.md](../concurrency.md) for where threading is
going. [What is implemented today](../status.md) is tracked separately, because
it changes faster than this does.

---

## Contents

### [1. Modules](01-modules.md)

What a module is, how one spans files, and why nothing depends on declaration order.

- [1.1 Every file names its module](01-modules.md#11-every-file-names-its-module)
- [1.2 A module may span files](01-modules.md#12-a-module-may-span-files)
  - [1.2.1 And so may a type](01-modules.md#121-and-so-may-a-type)
- [1.3 The module is the unit of visibility](01-modules.md#13-the-module-is-the-unit-of-visibility)
- [1.4 `import` adds names; it never grants access](01-modules.md#14-import-adds-names-it-never-grants-access)
- [1.5 Aliases](01-modules.md#15-aliases)
- [1.6 Ambiguity](01-modules.md#16-ambiguity)
- [1.7 What is automatic](01-modules.md#17-what-is-automatic)
- [1.8 Order never matters](01-modules.md#18-order-never-matters)

### [2. Types](02-types.md)

Primitives, `struct`, `class`, pointers, `variant`, `union`, `Result`, `interface`, arrays, slices, `enum`, delegates, closures, events and lambdas.

- [2.1 Primitives](02-types.md#21-primitives)
- [2.2 `struct` — value type, C layout](02-types.md#22-struct--value-type-c-layout)
  - [2.2.1 `struct HWND__;` — a type declared and not laid out](02-types.md#221-struct-hwnd--a-type-declared-and-not-laid-out)
  - [2.2.2 A type declared inside another](02-types.md#222-a-type-declared-inside-another)
  - [2.2.3 `(int, String)` — a tuple](02-types.md#223-int-string--a-tuple)
- [2.3 `[Packed]` and `[Align]`](02-types.md#23-packed-and-align)
- [2.4 `class` — reference type, ARC managed](02-types.md#24-class--reference-type-arc-managed)
  - [2.4.1 A field with a value](02-types.md#241-a-field-with-a-value)
  - [2.4.2 Making one with its members written out](02-types.md#242-making-one-with-its-members-written-out)
  - [2.4.3 Inheritance](02-types.md#243-inheritance)
  - [2.4.4 `is`, `as`, and casting down](02-types.md#244-is-as-and-casting-down)
- [2.5 Pointers and nullability](02-types.md#25-pointers-and-nullability)
- [2.6 `variant` — a value that is one of several things](02-types.md#26-variant--a-value-that-is-one-of-several-things)
- [2.7 `union` — every member at offset zero](02-types.md#27-union--every-member-at-offset-zero)
  - [2.7.1 Nameless members](02-types.md#271-nameless-members)
- [2.8 `Result<T, E>` — how a function fails](02-types.md#28-resultt-e--how-a-function-fails)
  - [2.8.1 `Optional<T>` — a value, or none](02-types.md#281-optionalt--a-value-or-none)
- [2.9 How the library reports failure](02-types.md#29-how-the-library-reports-failure)
- [2.10 `interface` — a contract, dispatched dynamically](02-types.md#210-interface--a-contract-dispatched-dynamically)
- [2.11 Arrays](02-types.md#211-arrays)
  - [2.11.1 `T[]` — a counted array](02-types.md#2111-t--a-counted-array)
  - [2.11.2 `T[N]` — an inline array](02-types.md#2112-tn--an-inline-array)
- [2.12 `T[:]` — part of an array](02-types.md#212-t--part-of-an-array)
- [2.13 `enum` — a distinct type over an integer](02-types.md#213-enum--a-distinct-type-over-an-integer)
- [2.14 `delegate` — a named function pointer](02-types.md#214-delegate--a-named-function-pointer)
  - [2.14.1 `closure` — a method and the object it belongs to](02-types.md#2141-closure--a-method-and-the-object-it-belongs-to)
  - [2.14.2 `event` — several subscribers behind one name](02-types.md#2142-event--several-subscribers-behind-one-name)
- [2.15 Lambdas and closures](02-types.md#215-lambdas-and-closures)

### [3. Text](03-text.md)

`String`, how its bytes reach C, UTF-16 for platform APIs, `StringBuilder`, other encodings and interpolation.

- [3.1 Representation](03-text.md#31-representation)
- [3.2 Members](03-text.md#32-members)
- [3.3 Reaching C](03-text.md#33-reaching-c)
- [3.4 UTF-16 for platform APIs](03-text.md#34-utf-16-for-platform-apis)
- [3.5 StringBuilder](03-text.md#35-stringbuilder)
- [3.6 Other encodings](03-text.md#36-other-encodings)
- [3.7 Conversions](03-text.md#37-conversions)
- [3.8 Interpolation](03-text.md#38-interpolation)

### [4. Generics](04-generics.md)

Monomorphization, constraints, and what is and is not supported.

- [4.1 Monomorphization](04-generics.md#41-monomorphization)
- [4.2 Constraints](04-generics.md#42-constraints)
- [4.3 What a constraint does, and does not, do](04-generics.md#43-what-a-constraint-does-and-does-not-do)
- [4.4 What is and is not supported](04-generics.md#44-what-is-and-is-not-supported)
- [4.5 A worked example](04-generics.md#45-a-worked-example)

### [5. The standard library](05-standard-library.md)

What ships and how: threading, collections, environment, math, concurrency, I/O, processes, JSON and XML.

- [5.1 What ships, and how](05-standard-library.md#51-what-ships-and-how)
- [5.2 `Standard.Threading`](05-standard-library.md#52-standardthreading)
- [5.3 Interfaces are named with a leading I](05-standard-library.md#53-interfaces-are-named-with-a-leading-i)
- [5.4 `Standard.Collections`](05-standard-library.md#54-standardcollections)
- [5.5 Doing something to every element](05-standard-library.md#55-doing-something-to-every-element)
- [5.6 `Standard.Env`, `Standard.Time` and `Standard.Random`](05-standard-library.md#56-standardenv-standardtime-and-standardrandom)
- [5.7 `Standard.Math`](05-standard-library.md#57-standardmath)
- [5.8 `Standard.Concurrent`](05-standard-library.md#58-standardconcurrent)
- [5.9 `Standard.IO`, `File`, `Directory` and `Path`](05-standard-library.md#59-standardio-file-directory-and-path)
  - [5.9.1 `Standard.Process`](05-standard-library.md#591-standardprocess)
- [5.10 `Standard.Json` and `Standard.Xml`](05-standard-library.md#510-standardjson-and-standardxml)
- [5.11 Interfaces may extend interfaces](05-standard-library.md#511-interfaces-may-extend-interfaces)
- [5.12 `Standard.Drawing`](05-standard-library.md#512-standarddrawing)

### [6. Attributes and reflection](06-attributes-reflection.md)

`[Reflect]`, `typeof`, the tables that get emitted, and a serializer written once.

- [6.1 Attributes](06-attributes-reflection.md#61-attributes)
- [6.2 `[Reflect]` opts a type in](06-attributes-reflection.md#62-reflect-opts-a-type-in)
- [6.3 `typeof` and `Standard.Reflection`](06-attributes-reflection.md#63-typeof-and-standardreflection)
- [6.4 A serializer, written once](06-attributes-reflection.md#64-a-serializer-written-once)
  - [6.4.1 Properties, which are not fields](06-attributes-reflection.md#641-properties-which-are-not-fields)
  - [6.4.2 Finding a type by name](06-attributes-reflection.md#642-finding-a-type-by-name)
- [6.5 What is emitted](06-attributes-reflection.md#65-what-is-emitted)
- [6.6 Writing a field](06-attributes-reflection.md#66-writing-a-field)
- [6.7 What is not there yet](06-attributes-reflection.md#67-what-is-not-there-yet)

### [7. Functions and members](07-functions-members.md)

Functions, defaults, `ref`/`in`/`out`, named arguments, properties, operators, indexers and `static`.

- [7.1 Functions](07-functions-members.md#71-functions)
  - [7.1.1 `x.F(y)` is `F(x, y)`](07-functions-members.md#711-xfy-is-fx-y)
  - [7.1.2 A parameter with a default](07-functions-members.md#712-a-parameter-with-a-default)
- [7.2 `ref`, `in` and `out` parameters](07-functions-members.md#72-ref-in-and-out-parameters)
  - [7.2.1 `out`](07-functions-members.md#721-out)
  - [7.2.2 Named arguments](07-functions-members.md#722-named-arguments)
- [7.3 Properties](07-functions-members.md#73-properties)
- [7.4 Operators](07-functions-members.md#74-operators)
  - [7.4.1 `implicit` and `explicit operator`](07-functions-members.md#741-implicit-and-explicit-operator)
- [7.5 Indexers](07-functions-members.md#75-indexers)
- [7.6 `static` members](07-functions-members.md#76-static-members)

### [8. Interoperability and libraries](08-interop-libraries.md)

`extern`/`export`, C++ linkage, shared libraries, what crosses a boundary, COM, and linking a platform library.

- [8.1 C++ linkage](08-interop-libraries.md#81-c-linkage)
- [8.2 Building a shared library](08-interop-libraries.md#82-building-a-shared-library)
- [8.3 What may cross a library boundary](08-interop-libraries.md#83-what-may-cross-a-library-boundary)
- [8.4 A Stainless library consumed by Stainless](08-interop-libraries.md#84-a-stainless-library-consumed-by-stainless)
- [8.5 COM](08-interop-libraries.md#85-com)
- [8.6 Linking a platform library](08-interop-libraries.md#86-linking-a-platform-library)

### [9. Statements and expressions](09-statements-expressions.md)

`switch`, `parallel`, `const`, `foreach`, thread boundaries, `?.`, `default(T)`, `goto`, `nameof` and `checked`.

- [9.1 `switch`](09-statements-expressions.md#91-switch)
  - [9.1.1 Patterns](09-statements-expressions.md#911-patterns)
  - [9.1.2 `switch` as an expression](09-statements-expressions.md#912-switch-as-an-expression)
- [9.2 `parallel`, `spawn` and `parallel for`](09-statements-expressions.md#92-parallel-spawn-and-parallel-for)
- [9.3 `const` and `static`](09-statements-expressions.md#93-const-and-static)
- [9.4 `foreach`](09-statements-expressions.md#94-foreach)
- [9.5 What may cross a thread boundary](09-statements-expressions.md#95-what-may-cross-a-thread-boundary)
- [9.6 Stepping by one](09-statements-expressions.md#96-stepping-by-one)
- [9.7 `?.` and `??`](09-statements-expressions.md#97--and-)
- [9.8 `default(T)`](09-statements-expressions.md#98-defaultt)
- [9.9 `do`](09-statements-expressions.md#99-do)
- [9.10 `goto`](09-statements-expressions.md#910-goto)
- [9.11 `nameof`](09-statements-expressions.md#911-nameof)
- [9.12 `checked`](09-statements-expressions.md#912-checked)

### [10. Conditional compilation](10-conditional-compilation.md)

`#if` and its relatives: directives, not macros.

