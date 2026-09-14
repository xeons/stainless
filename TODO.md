# TODO

What is coming next, and what is known to be wrong. Not a wishlist —
[docs/status.md's "What does not exist yet"](docs/status.md#what-does-not-exist-yet) is the
honest full inventory of edges, and this is the subset with an intention behind
it.

Each entry says what it is, why it matters, and what it touches. An entry with
no "why" is one that should be deleted rather than done.

---

## Documentation

The three entries that were here are done. What each turned out to be, since
none of them was quite what it looked like:

**Blocks on everything public.** 484 declarations had none. The bar held:
what a caller has to know before using it. Writing them found that
`String.ByteAt` reads the buffer unchecked where every other position on a
String clamps -- the class had to say which one does not rather than claim a
rule it does not keep.

**A generator.** `stainless doc`, and `docs/stdlib/` is its output, checked
in. The claim here that `///` blocks were in the syntax tree was wrong: the
lexer threw them away with every other comment. They are a token's
`Documentation` now, carried to the declaration and onto the symbol. It reads
syntax rather than a bound program, against what this entry assumed -- a
generic emits nothing until it is instantiated, so `List<T>` and
`Dictionary<K, V>` have no bound symbol to walk.

**Comments that say what the code does.** Smaller than it read. Splitting
`///` from `//` is what made it tractable: a block is documentation and keeps
the first entry's bar, and a note beside a line is describing that line. What
was left -- free-standing argument, history, and comparison with an absent
alternative -- came to about thirty comments across the tree, and every one of
them was a `//` block. There were no free-standing argumentative `//` blocks
at all: that prose lives in `///`, which is where it belongs.

---

## Next

### x86 and ARM64

Three of the four entries that were here are done. What each turned out to be:

**Linux x86 ran, and found two bugs a reading could not have.** `X86Abi`'s
i386 System V rule was right as written -- every struct returned through a
hidden pointer, whatever its size -- and the suite's four 32-bit cases pass on
Linux now as they did on Windows. What was wrong was underneath it. The
runtime's lock storage was counted in pointers, and glibc's i386
`pthread_cond_t` is 48 bytes on a machine whose pointer is four, so `thread.c`'s
own assertions refused to compile. And `Mangler` was decorating ELF: an i386
`__stdcall` gets the convention and the plain name on Linux, which is what gcc
has always done, so every `extern "C" __stdcall` went looking for a symbol
nobody had emitted. Both were link-time or compile-time failures rather than
wrong answers, which is the good kind.

`geekom-a7` runs the 32-bit cases directly now. It had `gcc-multilib` and
`libc6-dev-i386` all along; what it lacked was `libc6-dev:i386`, the
i386-architecture build that creates `/usr/include/i386-linux-gnu/` -- which is
where clang looks when it targets i386, and which the similarly named
`libc6-dev-i386` does not provide.
[tests/linux-x86.Dockerfile](tests/linux-x86.Dockerfile) is kept for a machine
that has neither, and is no longer on the path of an ordinary run.

**COM on x86 was where the convention is attached, and the byte counts answer
themselves.** A com interface's slots get `__stdcall` when the table is
numbered, beside the slot number, because both belong to the table rather than
to the declaration. The vtable's slot names carry no byte count and do not need
one: a decoration exists so a disagreement about argument size is a link error,
and a slot is reached by address. The three IUnknown slots are the exception,
being C functions -- `SL_COM_METHOD` in the runtime header puts the convention
on them and on the vtable's function pointers, and the emitter asks for the
decorated name. [tests/cases/com-native](tests/cases/com-native) declares a COM
vtable in C the way a COM header does and calls through it in both directions;
`x86-com` is the same program as a 32-bit binary, and it stops working the
moment the convention is removed.

**ARM64 is classified and has never run.** `Aapcs64Abi` answers for both
systems -- Microsoft's ARM64 ABI and ARM's agree about every shape asked -- and
every answer was read off clang, as the other three classifiers were. Two
things in it have no counterpart elsewhere: a homogeneous floating-point
aggregate travels in one SIMD register per member whatever its size, and the
registers may cover more of the value than exists, so a twelve-byte struct is
read out of a padded copy. A large struct is a pointer and deliberately not
`byval`, which LLVM lowers to the outgoing stack on every target.

There is no ARM64 machine here and no ARM64 C library to link against, so
`tests/cases/arm64-abi` stops at an object file: LLVM verifies the module and
lowers every instruction in it, and `ir.txt` pins each signature against
clang's. That is weaker than running a program and is meant to read that way.

What is **not** done:

**`stdcall` on a Stainless-defined function.** `export "C" __stdcall` parses and
emits, and nothing has called one from C across a real boundary. The COM work
above covers the shape of it -- an adjustor thunk is a Stainless-defined
`__stdcall` function that C calls through a vtable -- but not the decorated
symbol, which is what a named export turns on.

*Touches:* `Mangler`, `tests/cases/x86-conventions`.

---

### The GTK backend, which is done, and what is next for `forms/`

`forms/` has two backends now -- Win32 and GTK 3 -- and both samples pass their
whole self-test on each: 21 checks and 43. The entry that used to be here said
a seam with one implementation has quietly stopped being one, and that writing
the second was the only way to find out whether `IControlPeer` described a
control or an `HWND`.

**It described a control.** Thirty interfaces, forty-five methods on
`IWidgetSet`, and not one of them changed. The sharpest evidence is that a list
box, a checked list, a column header, a tree and a details list are five window
classes on Windows and five interfaces in the seam, and GTK answers all five
with one `GtkTreeView` over a model -- without either backend knowing.

**GTK 2 went with it.** It was behind `-D GTK2` and `Gtk.Api2`; two toolkits
behind one seam is two backends to keep honest, and no current distribution
ships the second.

It also settled an old failure, and that failure is now fixed. `common`'s "a
tree node reads back its text" failed on Win32 and passed on GTK, which said
the fault was on the Windows side. It was not in the tree peer at all: the
`TVI_ROOT` and `TVI_LAST` sentinels in `Win32.ComCtl32` were written as 32-bit
literals, and `commctrl.h` defines them as *negative* numbers that sign-extend
to `0xFFFFFFFFFFFF0000` on a 64-bit machine. Every insert was handed a parent
handle that named nothing, returned zero, and was never checked -- so the Win32
tree view had never held a single item, and only the peer's mirror list made
the other tree checks pass. Both samples now pass every check on Win32.

What is next there is in [forms/README.md](forms/README.md), which has the full
roadmap. The short version: **DPI awareness**, because both backends now turn
points into pixels at a hard-coded 96; **owner drawing**, which half a dozen
controls want and none has; and `grids.pas`, which is 14,000 lines that neither
platform has a widget for.

*Touches:* `forms/src/Platform/Gtk`, `bindings/gtk`.

---

## Interop, in the order writing the Win32 bindings wanted them

### An enum that crosses `extern "C"`

A `[Flags] enum : uint` will not pass to a `uint` parameter without a cast,
which is why [bindings/win32](bindings/win32) spells 460 constants as bare
`const uint` rather than as the typed sets they are. Letting an enum widen to
its underlying type in interop position would let a binding be typed without a
cast on every line.

### Portable COM activation

The server half is done. `[Guid]` on a `com class` is a CLSID, the compiler
collects every class carrying one into a factory table, and
`Com.GetClassObject` answers it with an `IClassFactory` — so a `--shared` build
exporting `DllGetClassObject` is a real in-process COM server, which
[samples/com](samples/com) is, called from C++ and checked by
[tests/cases/com-activation](tests/cases/com-activation).

What is still missing is the **client** half away from Windows: `Com.Create`,
taking a CLSID and reaching an object without the caller knowing where it came
from. That wants `dlopen`/`LoadLibrary` of a module exporting
`DllGetClassObject`, the in-process table first, and a fall-through to the real
`CoCreateInstance` on Windows so one source reaches the actual shell.

In-process and free-threaded only, stated as a limit rather than discovered as
one — no apartments, no marshalling, no proxies, no `IDispatch`. The value is
in the interface discipline, and XPCOM is what pretending otherwise looks
like.

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

### What resources left open

A `.rc` compiles into the binary on every target now, `Standard.Resources`
reads one anywhere, and `Bitmap.FromResource` works on both widget backends. Two
things around it are still open:

**A dialog built from its template.** `CreateDialogParamW`, `DialogBoxParamW`
and `EndDialog` are bound and an `RT_DIALOG` in a script works today through the
raw layer; what is missing is a `forms/` control that wraps one. It matters
because a dialog template is how every Windows program has laid out a dialog for
thirty years -- the layout is data, so it can be edited by a resource editor and
translated without recompiling, neither of which is true of the `SetBounds`
calls `forms/` uses now. Windows-only by nature: the template is a format the OS
itself interprets.

**Mach-O has no answer yet.** The blob goes in a section named `.rsrc`, which is
ELF's spelling. Mach-O wants `__SEGMENT,__section` and is not a target, so
nothing is wrong today -- but the `section` attribute in `ResourceBlob` is the
line that would have to learn about it.

*Touches:* `src/Stainless.Compiler/Emit`, `forms/src`.

---

## Language

### An `as` operator

`as` produces a `C?` where a cast produces a `C` or ends the program. Smaller
than it was: `if (x is C c)` now covers the branching case, so what is left is
wanting the answer as a value — passing it on, storing it, or a chain of them
where an `if` per step reads badly.

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

There is now a way to say it where the type can be named: `if (node.Payload is
Circle c)` for a variant's case, and `if (node.Next is Node n)` for a `C?`,
which asks about the null and the class at once. Both take the value once and
name what the test found, so the field is read exactly where it was checked.
What is still missing is the plain `if (node.Next != null)` reading as a
narrowing -- and that is the analysis above, not a shape.

*Touches:* `Binder.NarrowableSubject`, `Binder.InvalidateVariantFact`.

### Making an instance from a `Type`

Fields and properties can now be read *and* written through reflection, which is
what `Standard.Json` and `Standard.Xml` are built on. What is still missing is
the step before that: there is no way to ask a `Type` for a new instance, so
every reader fills an object the caller already made.

That is why `Populate<T>(T value, String text)` is the shape, and why there is no
`Deserialize<T>(String)` answering a fresh `T`. Two things would have to change.
A type argument cannot be written at a call (§4.4) — `<` in expression position
is ambiguous with less-than — so a function whose only mention of `T` is its
return type has nothing to infer from and could never be called. And the
metadata carries no constructor to call once the bytes are allocated.

Methods and interfaces carry no metadata either — fields and properties only.

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

### A reachability pass from `Main`

The standard library is compiled with every program and nothing prunes it. A
hello-world that calls `puts` and returns emits **every standard-library
function and reaches none of them**.

What saves the binary is the linker: every function goes in a section of its
own and the ones nothing reached are dropped. What nothing saves is the
compile, which pays for all of it — binding, emitting, and then handing clang
several times the text it needs.

Writing the library in Stainless is what made this worth doing rather than
worth noting. Every addition since — text, then sockets, then threading — has
grown what a program that uses none of it must compile, and the stripped binary
has come out the same size each time. The suite has roughly doubled in wall
time over those three. The linker's answer is free; the compiler's lack of one
is what the build is paying for.

It is also the honest explanation for a number that gets quoted about ARC:
counting `sl_retain`/`sl_release` in a module counts mostly calls in functions
nothing invokes. Fixing this shrinks that count without touching a single
instruction the program executes.

The walk is from `Main`, plus every `export "C"`, every static initializer, and
everything a dispatch table names — a virtual table, an interface table, a COM
vtable and the reflection metadata are all roots, and a pass that forgot one
would delete a method that is only ever called through a pointer. That last
part is the whole difficulty; the walk itself is a worklist.

*Touches:* a new pass between binding and emission, and `LlvmEmitter`'s
decision about what to write.

### Case mapping beyond ASCII

`ToUpperAscii` and `ToLowerAscii` say what they do. The real thing is a table
of several thousand entries with locale exceptions -- Turkish dotless i, German
sharp s uppercasing to two characters, Greek final sigma -- and none of it fits
in a runtime that is currently 3,000 lines of C. There is also no collation:
`CompareTo` orders by bytes, which orders by code point and resembles no
language's idea of alphabetical.

The honest options are to link ICU, to generate the tables from
UnicodeData.txt, or to keep saying `Ascii` in the name. The third is what is
happening.

### Cancellation that skips queued work

A cancelled `TaskScope` could drop the tasks it has not started. When a search
answers from the first chunk while ninety more sit in the queue, that is most of
the work saved — a flag on `SlScope` and one check in the worker loop. Reaching
it from inside a job is the harder half; see
[concurrency.md §9.3](docs/concurrency.md).

---

## Carried over from HANDOFF.md

That file was the running log of what each session found. Everything in it that
was still true and still wanted is below or above; the rest was the history of
finished work, and is in `git log` where history belongs.

### Method metadata, and invoke-by-name

Reflection describes types and fields and stops there. Methods are the last
piece before a form file can wire a handler -- `event` supplies the other half,
and what is missing is finding the method by name -- and the same work would let
a deserializer fill a `List<T>`, which is the one shape `Standard.Json` cannot
represent.

### A registry, or a decision not to have one

Package resolution unifies sources rather than searching versions, because a
path and a git tag each pin exactly one version and nothing can offer an
alternative. That is honest, and it is also why two packages needing
incompatible versions of a third is a hard error with no way out. The search
belongs in `PackageResolver.Visit` when there is something to search. Deciding
there will never be a registry is an equally good outcome; what is not good is
leaving the question open in a comment.

### Pin the test counts against the suites

`README.md` and `docs/internals.md` both state how many cases and unit tests
there are, and both drift on every commit that adds one. They were four audits
stale when that was last noticed, and adding two cases for `SL0218` and
`SL0222` made them stale again on the spot. A unit test asserting the numbers
against the two suites is an hour and ends it.

### The +0/+1 dataflow pass

Still the acknowledged performance item: retain/release pairs that cancel are
emitted and then executed. Nothing is wrong, and everything pays for it.

### `List<T>` has no `Remove(T)`

`IndexOf` wants `IEquatable<T>`, which a closure is not. Less pressing than it
was -- `RemoveWhere` takes a predicate for exactly this reason, and a list of
callbacks is usually an `event` now -- but it is still the obvious method that
is not there.

### `Standard.Collections` does not use the operators it could

`Money` in `samples/shop` still calls `Money.Add`. `Standard.Time` has had this
pass and reads better for it.

### Format specifiers in interpolation

`{n:x}` and `{n,8}` are not written. `:` and `,` inside a hole are already
reserved so that adding them is not a change of meaning, and
[§3](docs/spec/03-text.md) says so; `PadLeft` and `Convert.FromLong` are what
there is until then.

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
