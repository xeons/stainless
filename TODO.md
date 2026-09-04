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

### A variadic `export "C"` silently drops the `...`

```
generated header:  int32_t sl_log(uint8_t* format, ...);
generated IR:      define i32 @sl_log(ptr %arg.format)
```

The header promises a variadic function and the definition is not one. A caller
following that header uses the variadic convention — which on Win64 requires
floating-point arguments duplicated into the integer registers, and on SysV
requires `al` to carry the vector-register count. Integer and pointer arguments
survive; floats do not, silently.

There is no `va_list` to read them with anyway, so the fix is almost certainly
to **reject** `...` on an `export`, not to emit a variadic definition. Calling a
C variadic is fine and unaffected.

*Touches:* `Parser.ParseLinkageDeclaration`, `CHeaderWriter`.

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

### Class inheritance, the C# model

The one big piece. Single inheritance, `virtual` / `override` / `abstract` /
`sealed`, `base(...)` constructor chaining, `protected`, and a downcast that
checks.

The object model already makes the hard part easy: a class reference points at
the object header and fields follow it, so with **single** inheritance the base
subobject shares the derived object's address. An upcast is therefore free, and
`sl_retain` / `sl_release` keep taking the object pointer unchanged. That is
exactly the property multiple inheritance would destroy, and the reason not to
want it — see the note at the end of this file.

What it needs:

- a `vtable` pointer appended to `SlTypeInfo`, making a virtual call three
  loads and an indirect call — the same shape interface dispatch already has,
  and one load cheaper than it because there is no interface id to index
- a `base` pointer beside it, so a downcast can walk the chain
- derived fields laid out after base fields; `InstanceSize` accumulating
- destructors chaining, derived first
- interface tables inherited by a derived class
- `abstract` refused at `new`, `sealed` refused as a base
- module metadata carrying the base class, and the runtime struct change moving
  with it

*Touches:* `TypeSystem`, `Binder` passes 2–6, `LlvmEmitter`, `DebugInfo`
(`DW_TAG_inheritance`), `MetadataWriter`, `runtime/stainless.h`, `runtime/arc.c`.

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

---

## Interop, in the order writing the Win32 bindings wanted them

### Type aliases, and opaque struct types

There is no `using Handle = void*;`, so a binding spells `HANDLE`, `HWND`,
`HDC` and `HKEY` all as `void*` and nothing catches passing one where another
belongs. A weak alias would fix the readability; a **distinct** alias over an
opaque struct type — C's `struct HWND__;` — would make the compiler catch the
mix-up too, at no runtime cost. The two want doing together.

### An enum that crosses `extern "C"`

A `[Flags] enum : uint` will not pass to a `uint` parameter without a cast,
which is why [bindings/win32](bindings/win32) spells 460 constants as bare
`const uint` rather than as the typed sets they are. Letting an enum widen to
its underlying type in interop position would let a binding be typed without a
cast on every line.

### `->`

`(*state).Field` is every line of code that walks a struct pointer, and a
window procedure is nothing else. One token in the lexer and a desugar in the
parser.

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

This is the highest-value language item that is not inheritance.

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

- **Multiple inheritance.** With it a `Derived*` and a `Base2*` are different
  addresses, so an upcast becomes pointer arithmetic and reference identity
  stops being pointer identity. `sl_retain` takes the object pointer and
  interface references *are* object pointers; both assumptions would go.
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
