# TODO

What is coming next, and what is known to be wrong. Not a wishlist —
[README's "What does not exist yet"](README.md#what-does-not-exist-yet) is the
honest full inventory of edges, and this is the subset with an intention behind
it.

Each entry says what it is, why it matters, and what it touches. An entry with
no "why" is one that should be deleted rather than done.

---

## Bugs

These are wrong rather than missing, and should go first.

### Nested type declarations are parsed and then discarded

```csharp
public struct Outer {
    public struct Inner { public int X; }    // accepted, then gone
    public Outer.Inner Value;                // error: type not found
}
```

The parser takes it and the binder never registers it, with no diagnostic —
the same shape of bug as the `public extern "C" { }` modifier that used to be
dropped. Either support nested types or refuse them, but not this.

*Touches:* `Parser.ParseTypeDeclaration`, `Binder` pass 2.

### `stainless run -- args` accepts arguments and drops them

`Main` takes no arguments yet, so everything after `--` is parsed into a list
that is then discarded. Accepting input and ignoring it is worse than refusing
it. Either give `Main` an `String[]` overload or reject `--`.

*Touches:* `Program.Build`.

---

## Next

### Calling conventions

`__stdcall`, `__fastcall`, `__vectorcall` on `extern` and `export`. Nearly a
no-op on x64 — one convention, and only `__vectorcall` differs — but it is the
whole story on x86, where `__stdcall` is what Win32 uses and the name is
decorated with the argument-byte count.

Worth doing *with* the SysV classifier rather than before it, since both are
"the calling convention is not a given" and the code that decides one should
decide the other.

*Touches:* `Parser`, `TypeSystem`, `Mangler`, `LlvmEmitter.ClassifyParameter`.

### The SysV struct classifier

`--abi itanium` reaches name mangling and bit-field packing and **not** how a
struct is passed in registers, which stays Win64. So passing a struct by value
to Linux C is not right yet, whatever `--abi` says. This is the only item on
this page that is a correctness gap rather than a missing feature.

*Touches:* a new classifier beside `Win64Abi`, and `LlvmEmitter`.

### Deriving across a library boundary

A class from a referenced library can be held, called, tested with `is` and cast
back to — the base relation and every virtual slot already cross in the metadata
— but it cannot be derived from (SL0513).

What stands in the way is that the derived class's dispatch table is built by
*this* compilation from a layout compiled by *that* one, so the two have to agree
about the base's slot count and its destroy hook for ever after. The slots cross
already; what does not is a rule about which changes to a library are compatible.
Worth doing after [shipping the runtime as a shared library](#ship-the-runtime-as-a-shared-library),
which is the other half of the same question.

---

## Interop, in the order writing the Win32 bindings wanted them

### An enum that crosses `extern "C"`

A `[Flags] enum : uint` will not pass to a `uint` parameter without a cast,
which is why [bindings/win32](bindings/win32) spells 460 constants as bare
`const uint` rather than as the typed sets they are. Letting an enum widen to
its underlying type in interop position would let a binding be typed without a
cast on every line.

### COM

Not the C++ object model — a COM interface is binary-identical to a pointer to
a vtable pointer, so this needs only a struct of `delegate`s and `IUnknown`
discipline. It is what stands between the bindings and `SHGetKnownFolderPath`,
Direct2D, WIC and the modern shell.

---

## Language

### Flow narrowing for `C?`

The compiler already tracks which case a variant is holding through `if`, `!`,
`&&`, `||`, a ternary, an early return and a `switch`. An optional wants the
same machinery, and does not have it: `if (x != null)` does not make `x` usable
as non-optional. It is why `LinkedList<T>` links by index — a structure that
walks `next` cannot be written at all.

This is the highest-value language item left. It is also what an `as`
operator is waiting on: `as` produces a `C?`, and until one can be narrowed
there is nothing to do with the result that `is` plus a cast does not do.

### Reflection that writes

Fields can be read from an instance and not set, so a deserializer cannot be
written; nor can an instance be made from a `Type`. Methods and interfaces carry
no metadata — fields only.

### Definition-site constraint checking

`where T : IShape` is checked where the generic is *used*, so an uninstantiated
template is never checked and a mistake inside one is reported against its use.
Doing it properly needs constraints on operators too.

### A borrowed slice

`T[:]` retains the array it came from, which is what makes it impossible to
dangle and also what makes it cost a reference count per copy and keep a large
array alive for a small view. A raw `(pointer, length)` view would do neither
and needs a lifetime story the language does not have.

---

## Runtime and libraries

### Ship the runtime as a shared library

The runtime is linked statically into every binary, so each side of a library
boundary has its own allocator and its own C stdio buffer. Two consequences,
both real: a managed object cannot safely cross a library boundary, and output
written inside a library does not interleave with its consumer's in the order it
was written. This closes both, and is the next thing worth doing about
libraries.

### `String` has a thin API

No `IndexOf`, `Split`, `Trim`, case mapping or formatting, and `Substring`
counts bytes rather than characters, so it can cut a multi-byte character in
half.

### Cancellation that skips queued work

A cancelled `TaskScope` could drop the tasks it has not started. When a search
answers from the first chunk while ninety more sit in the queue, that is most of
the work saved — a flag on `SlScope` and one check in the worker loop. Reaching
it from inside a job is the harder half; see
[concurrency.md §9.3](docs/concurrency.md).

---

## Deliberately not doing

Kept here so the reasoning does not have to be rediscovered.

- **Multiple inheritance.** Single inheritance is implemented and rests on the
  base subobject starting at the derived object's own address. With two bases a
  `Derived*` and a `Base2*` are different addresses, so an upcast becomes
  pointer arithmetic and reference identity stops being pointer identity.
  `sl_retain` takes the object pointer and interface references *are* object
  pointers; both assumptions would go.
  Virtual inheritance is worse again — base offsets resolved at run time, a
  hidden constructor parameter, and two ABIs that disagree completely about how.
  Interfaces already give multiple types without multiple state.
- **Exceptions.** Unwinding needs metadata on every frame and a personality
  routine, and a failure that travels invisibly through code that did not
  mention it is the thing `Result<T, E>` exists to refuse.
- **A C-style preprocessor.** `#if` and its relatives exist because choosing
  between two platforms is a real question. Macros and `#include` are not: a
  name always means itself.
- **Mutable globals.** Shared state that nothing synchronises. `static readonly`
  over a type that says how it is safe is the answer.
