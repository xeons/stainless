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

Not a prerequisite for anything, COM included: every pointer and `nint` in the
compiler is eight bytes and [abi.md](docs/abi.md) is written for x86-64, so
there is no 32-bit target for the distinction to matter on. It becomes real the
day one is added, and not before.

The struct classifier that used to share this entry is done: `--abi` now picks
Win64 or System V for argument passing as well as for mangling and bit-fields.
What is left here is only the conventions a *declaration* can name, which is a
different question and an x86-only one.

*Touches:* `Parser`, `TypeSystem`, `Mangler`, `LlvmEmitter.ClassifyParameter`.

### Deriving across a library boundary

A class from a referenced library can be held, called, tested with `is` and cast
back to — the base relation and every virtual slot already cross in the metadata
— but it cannot be derived from (SL0513).

What stands in the way is that the derived class's dispatch table is built by
*this* compilation from a layout compiled by *that* one, so the two have to agree
about the base's slot count and its destroy hook for ever after. The slots cross
already; what does not is a rule about which changes to a library are compatible.
One runtime is no longer the obstacle -- both sides share it -- so what is left
is versioning, which is the real question and a larger one.

---

## Interop, in the order writing the Win32 bindings wanted them

### An enum that crosses `extern "C"`

A `[Flags] enum : uint` will not pass to a `uint` parameter without a cast,
which is why [bindings/win32](bindings/win32) spells 460 constants as bare
`const uint` rather than as the typed sets they are. Letting an enum widen to
its underlying type in interop position would let a binding be typed without a
cast on every line.

### Portable COM activation

`com interface` and `com class` exist (spec §8.5) and `Win32.Com`,
`Win32.Ole32` and `Win32.ShellCom` bind Windows' activation over them, so
calling COM works on Windows and the binary contract works everywhere.

What does not exist anywhere but Windows is *how an object gets made*. The
piece worth building is small and deliberately not COM's: a table of factories
linked into the process, plus `dlopen`/`LoadLibrary` of a module exporting
`DllGetClassObject`, falling through to the real `CoCreateInstance` on Windows
so one source reaches the actual shell.

In-process and free-threaded only, stated as a limit rather than discovered as
one — no apartments, no marshalling, no proxies, no `IDispatch`. The value is
in the interface discipline, and XPCOM is what pretending otherwise looks
like.

The same work is what would let a Stainless `com class` be handed to another
process, which today it cannot be: it can be written and passed around inside
one program, and nothing can ask for it by CLSID.

*Touches:* `runtime/com.c`, `bindings/win32/Com.sl`.

### More Windows COM interfaces

A binding rather than a project, now that the language part is done and the
shell's half is written. In rough order of what a program actually wants:

- **WIC** — `IWICImagingFactory` and four interfaces under it, which is what
  loading a PNG or a JPEG takes. It pairs with `Win32.Drawing`, which can
  already put a bitmap on screen and has no way to read one from a file.
- **`IShellItem2` and the Property System** — the declaration is there for its
  IID and its first slots; the property methods are not.
- **`ITaskbarList3`** — progress in the taskbar button, which is thirty lines
  and very visible.
- **Direct2D and DirectWrite**, which are large and want a render loop, and are
  the real test of whether this scales.

*Touches:* `bindings/win32/api`, `bindings/win32`.

---

## Language

### An `as` operator

`as` produces a `C?` where a cast produces a `C` or ends the program. Now
worth having: flow narrowing arrived (§2.5), so the result of one is usable,
and `if (x is C) { var c = (C)x; }` is two tests where one would do.

*Touches:* `Parser`, `Binder.BindTypeTest`, `LlvmEmitter.EmitConversion`.

### Narrowing a field

`if (x != null)` narrows a local or a parameter and not `node.Next`, because a
field or a call result may be a different value by the time it is read — the
rule variants follow, stated once for both (SL0248, SL0285). A local is the
fix and usually what the code meant.

What would make it sound for a field is knowing that nothing between the check
and the use could have written it, which is a real analysis rather than a
lookup: any call, any `ref`, any store through a pointer takes the proof away.
Worth doing only if the local turns out to be a genuine irritation in practice.

*Touches:* `Binder.NarrowableSubject`, `Binder.InvalidateVariantFact`.

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
