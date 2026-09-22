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
`String.GetByteAt` reads the buffer unchecked where every other position on a
String clamps -- the class had to say which one does not rather than claim a
rule it does not keep.

**A generator.** `stainless doc`, and `docs/stdlib/` is its output, checked
in. The claim here that `///` blocks were in the syntax tree was wrong: the
lexer threw them away with every other comment. They are a token's
`Documentation` now, carried to the declaration and onto the symbol. It reads
syntax rather than a bound program, against what this entry assumed -- a
generic emits nothing until it is instantiated, so `List<T>` and
`Dictionary<TKey, TValue>` have no bound symbol to walk.

**Comments that say what the code does.** Smaller than it read. Splitting
`///` from `//` is what made it tractable: a block is documentation and keeps
the first entry's bar, and a note beside a line is describing that line. What
was left -- free-standing argument, history, and comparison with an absent
alternative -- came to about thirty comments across the tree, and every one of
them was a `//` block. There were no free-standing argumentative `//` blocks
at all: that prose lives in `///`, which is where it belongs.

---

## Next

### Bring the comments to §4

[docs/style.md](docs/style.md) §4 is new and most of the tree predates it.
Three things it now forbids are everywhere:

- **Narration.** Bold lead-ins, rhetorical questions, and paragraphs arguing a
  case that the declaration under them already makes.
- **History.** Comments describing a bug that was fixed, an earlier shape of
  the code, or how long something took to find. That belongs in `git log`,
  attached to the change, where nobody has to keep it true.
- **Obligations in plain words.** "must be called from the thread that
  attached" rather than "MUST be called from the thread that attached", which
  is the difference between a remark and a rule.

It wants reading rather than a script: deciding whether a comment earns its
place is the part a regular expression cannot do, and §4.1's own rule is that
a comment restating the code is worse than none. One module at a time, each
its own commit, so that a rewrite never travels with a change of behaviour.

`debug/`, `ide/src/Debug/`, `stdlib/Path.sl` and the `--debug-format` changes
are written to it already.

### What the debugger still wants from the compiler

`debug/` reads what `-g` emits. One thing it does not emit is measured rather
than guessed; [docs/dwarf.md](docs/dwarf.md) has the numbers.

- **`DW_AT_language` is `DW_LANG_C_plus_plus`.** We are not C++, and a consumer
  that demangles by language does the wrong thing with a `_SL` name.

One more, not in the emitter:

- **`--debug-format dwarf` on Windows does not rebuild the C runtime.** Its
  objects are compiled for the MSVC target and carry CodeView, so a DWARF PE
  describes the Stainless module alone and stepping into `sl_retain` there is
  not a thing that can be switched on.

*Touches:* `src/Stainless.Compiler/Emit/DebugInfo.cs`,
`src/Stainless.Compiler/Driver/Compilation.cs`. Each wants its own commit and a
`debug.txt` case.

### `stainless format`

[docs/style.md](docs/style.md) is the house style and there is nothing that
applies it. The C# half is partly enforced — `.editorconfig` plus
`EnforceCodeStyleInBuild`, so the build warns on a naming violation, though not
on brace placement or spacing — and the Stainless
half is enforced by review, which is the weaker half of a rule that exists
because review kept missing this.

The tree was brought to the standard by a throwaway script that masked strings
and comments, moved braces, and checked that nothing but layout had changed. A
real one belongs in the CLI next to `stainless doc`, reading the same syntax
tree rather than guessing at it with a regular expression. It wants: the brace
and one-statement-body rules (§3.1–3.3), `i++` (§3.4), the whitespace and
column-alignment rules (§3.5), and a `--check` mode a build can run.

**Why it matters**: the two halves of this repository disagreed about brace
style for months, and nothing said so. What a reviewer should be spending
attention on is §1.4 and §2.1 — whether a name promises the right thing, whether
a method should have been a property — and neither of those is mechanical.

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

### Cross-compiling to another operating system

`--target x64-linux` on a Windows box now does everything the compiler itself
controls: `#if WINDOWS` is off and `UNIX` is on, a project's `linux` overlay is
the one that applies, clang is told the triple, the runtime's objects are named
for the target rather than colliding with the host's, and the whole of a GTK
program compiles. It stops at `stdio.h`, because cross-compiling wants the
target's headers and libraries and this machine has none.

Four things had read "the target" as "the architecture" and were fixed getting
that far; **three more are still host-based and are the ones that name files**:

- `Toolchain.ExecutableExtension` and `SharedLibraryExtension`, which decide
  `.exe` against nothing and `.dll` against `.so`;
- `SharedLibraryFileName`, which decides the `lib` prefix;
- the runtime's own shared-library name, built from both.

They are not wrong today for any build that can complete, because a build that
would expose them cannot get past the sysroot. They are listed because the next
person to hit this will hit them immediately after, and because `ExecutableExtension`
is reached from `ProjectFile.OutputPath()` -- which has no target in scope, and
that is the actual work: threading one there, or moving the decision to where
the target is known.

**What would make any of it testable** is a sysroot: clang's `--sysroot` plus a
Linux `/usr/include` and `/usr/lib` copied onto the Windows box, or the reverse.
`geekom-a7` is the other half of that pair and can already build for Linux
natively, so the question this answers is narrower than it looks -- it is
whether one machine can produce both, not whether both platforms work.

*Touches:* `Toolchain`, `ProjectFile.OutputPath`.

---

### The GTK backend, and what is next for `forms/`

`forms/` has two backends now -- Win32 and GTK 3 -- and all five samples pass
their whole self-test on each: `demo`'s 21 checks, `common`'s 44 and `buttons`'
51.

**That sentence said "which is done" for months, and it was not.** Every one of
those checks passed while a control inside a container was one pixel wide, a
tab page was empty, and nothing a program drew reached the screen. A self-test
reads back what it set -- a caption, an index, a count -- and none of that
asks whether anything was drawn. Six faults were found the first time somebody
looked at a screenshot, and they are written up in
[forms/README.md](forms/README.md) under *What running it found*. The general
lesson is worth more than the six: a widgetset's tests prove the model, and
only a picture proves the view.

The entry that used to be here said
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
the other tree checks pass. Every sample now passes every check on Win32.

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

### Direct3D 12

`Win32.Dxgi`, `Win32.D3D11` and `Win32.D3DCompiler` are bound, and
`Windows.DirectX11` is the layer over them: a device and a swap chain on an
`HWND`, a depth buffer, meshes, materials, constant buffers, alpha blending,
and `SaveFrame` to read the back buffer out as a picture.
[samples/directx](samples/directx) renders a triangle and a lit, rotating,
shadow-casting cube with it.

**Direct3D 12 is not bound.** It is not more of the same: the device makes
nothing that draws, a command list is recorded and submitted to a queue, memory
is the program's to place and to keep alive across frames, and a fence is how
it knows when the GPU is finished. The binding is mechanical -- the generator
that read `ID3D11DeviceContext`'s hundred and eight slots out of the header's
own `Vtbl` structs reads `ID3D12GraphicsCommandList` just as well -- and the
*layer* is not, because a `Windows.DirectX12` that hid the queue and the fence
would be hiding the only two things D3D12 exists to expose.

**Why it matters**: nothing today needs it. D3D11 draws, and the machines that
require D3D12 are the ones a renderer would be written for rather than a
binding. What it would buy is the honest test of whether the COM story here
scales to an API whose resource lifetimes are not reference counts.

*Touches:* `bindings/win32/api`, a new `Windows.DirectX12`.

### What DirectX 11 does not cover yet

The layer is the six objects every program makes, and three things a second
program would want are missing:

- **Textures.** `CreateShaderResourceView` and `CreateSamplerState` are bound
  and nothing wraps them, so a mesh can have colours and not a picture. It is
  the smallest of the three and the most often wanted.
- **A shadow map.** [samples/directx/cube.sl](samples/directx/cube.sl)
  projects the cube onto the floor with a matrix, which is exact for a flat
  floor and wrong for anything else. A real one renders depth from the light
  into a texture and samples it, which needs render-to-texture -- and therefore
  the textures above.
- **Multisampling.** The swap chain is flip-discard, which takes none, so
  anti-aliasing means rendering to a multisampled target and resolving.
  `ResolveSubresource` is bound.

*Touches:* `bindings/win32/DirectX11.sl`.

### More Windows COM interfaces

A binding rather than a project, now that the language part is done and the
shell's half is written. In rough order of what a program actually wants:

- **WIC** — `IWICImagingFactory` and four interfaces under it. This was here
  because loading a PNG or a JPEG took it, and that is done: `Standard.Drawing`
  reads both through GDI+ on Windows and libgd elsewhere, so what is left for
  WIC is the things GDI+ is worse at — a decoder for a format GDI+ has none
  for, and frame-by-frame access to an animated one. Worth doing on its merits
  rather than because nothing else could read a file.
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

That is why `PopulateObject<T>(T value, String text)` is the shape, and why there is no
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

### Public-key cryptography

`Standard.Security.Cryptography` is the symmetric half and is complete: MD5,
SHA-1, SHA-256, SHA-384, SHA-512, HMAC over any of them, PBKDF2, HKDF, AES in
ECB, CBC, CFB and CTR, AES-GCM, the platform's entropy, and a constant-time
comparison. Every answer is pinned against a published vector by
`tests/cases/cryptography`.

**RSA, ECDsa, ECDiffieHellman and X.509 are not there, and none of them is the
work.** The work underneath all four is an arbitrary-precision integer:
addition, multiplication, modular exponentiation with a Montgomery ladder, and
an inverse -- in constant time, because the whole point of the exponent is that
it is secret. That is a module of its own, it is the thing a mistake in is
invisible, and half of it is worse than none.

The honest alternatives are to write it, to bind to a library that has
(bcrypt on Windows, OpenSSL elsewhere, and then two backends to keep honest),
or to say that this standard library does the symmetric half and expects a
program needing a signature to reach outside. **The third is what is happening
and it should be a decision rather than a gap.**

Two smaller things are also absent and are not blocked on any of that:
scrypt and Argon2, which is what PBKDF2's weakness against a GPU actually calls
for; and ChaCha20-Poly1305, which is AES-GCM's alternative on a machine with no
AES instructions.

### AES that does not leak through the cache

The AES here is byte-oriented with a table-driven S-box, which is the shape
that is known to leak a key to an attacker who can watch the data cache. It is
right for a file, a protocol and a password store, and it is not the thing to
put under a remote attacker who can time it.

The two answers are AES-NI, which is an intrinsic the language has no way to
spell, and a bitsliced fallback, which is a rewrite of the cipher that never
indexes a table by a secret. Both are real work; the doc block on the module
says plainly which one it is, which is the least that should be true.

### Case mapping beyond ASCII

`ToUpperAscii` and `ToLowerAscii` say what they do. The real thing is a table
of several thousand entries with locale exceptions -- Turkish dotless i, German
sharp s uppercasing to two characters, Greek final sigma -- and none of it fits
in a runtime that is currently 6,000 lines of C. There is also no collation:
`CompareTo` orders by bytes, which orders by code point and resembles no
language's idea of alphabetical.

The honest options are to link ICU, to generate the tables from
UnicodeData.txt, or to keep saying `Ascii` in the name. The third is what is
happening.

### Audio that is not PCM

`Standard.Media.Audio` plays and records interleaved PCM through WASAPI on
Windows and ALSA elsewhere, and reads and writes WAV. Three things around it
are open:

- **A decoder.** WAV is the only container, so a program with an MP3, an Ogg or
  a FLAC has nothing. Each is a real piece of work and a separate module;
  saying so is better than a half-written one.
- **Mixing.** One device, one stream: a second sound needs a second device,
  which the platform may refuse. `Win32.Sound` is the mixer on Windows, over
  XAudio2, and Linux has no equivalent here.
- **ALSA has been compiled and not run.** The Windows half has played and
  recorded on this machine; the ALSA half is written against the same seam and
  has never opened a device. `geekom-a7` is where that gets answered, and until
  it is, half of this module is a claim rather than a fact.

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
  mention it is the thing `Result<T, TError>` exists to refuse.
- **A C-style preprocessor.** `#if` and its relatives exist because choosing
  between two platforms is a real question. Macros and `#include` are not: a
  name always means itself.
